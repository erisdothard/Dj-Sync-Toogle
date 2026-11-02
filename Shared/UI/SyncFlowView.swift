import SwiftUI
import SetlistCore

/// The whole share-sheet experience. Also shown inside the app for the "Try it" tester.
struct SyncFlowView: View {
    @ObservedObject var model: SyncFlowViewModel
    /// `Link` only works in the app; extensions cannot open URLs.
    var showsOpenLink = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.service) { _, _ in
            if case .review = model.phase {
                Task { await model.rematch() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $model.autoSync) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-sync").font(.headline)
                    Text(model.autoSync ? "Shared sets are saved without asking." : "You review the matches before saving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.green)

            Picker("Save to", selection: $model.service) {
                ForEach(MusicService.allCases) { service in
                    Text(service.displayName).tag(service)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isBusy)
        }
        .padding()
    }

    private var isBusy: Bool {
        switch model.phase {
        case .loading, .matching, .saving: return true
        default: return false
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            statusView(systemImage: "text.magnifyingglass", title: "Looking for a tracklist…", showsProgress: true)
        case .noSetlist(let message):
            statusView(systemImage: "questionmark.circle", title: "No tracklist found", message: message) {
                Button("Close") { model.onCancel?() }
            }
        case .alreadySynced(let record):
            statusView(systemImage: "checkmark.circle", title: "Already synced",
                       message: "Saved as “\(record.playlistName)” on \(record.date.formatted(date: .abbreviated, time: .shortened)).") {
                Button("Sync again") { Task { await model.continueAfterDuplicate() } }
                    .buttonStyle(.borderedProminent)
                Button("Close") { model.onCancel?() }
            }
        case .matching(let done, let total):
            VStack(spacing: 16) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .padding(.horizontal)
                Text("Matching \(done) of \(total) tracks on \(model.service.displayName)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        case .review:
            reviewView
        case .saving:
            statusView(systemImage: "square.and.arrow.down", title: "Saving playlist…", showsProgress: true)
        case .done(let playlist, let saved, let unmatched):
            doneView(playlist: playlist, saved: saved, unmatched: unmatched)
        case .failed(let message):
            statusView(systemImage: "exclamationmark.triangle", title: "Something went wrong", message: message) {
                if model.canReview {
                    Button("Review matches") { model.backToReview() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Close") { model.onCancel?() }
            }
        }
    }

    private func statusView(
        systemImage: String,
        title: String,
        message: String? = nil,
        showsProgress: Bool = false
    ) -> some View {
        statusView(systemImage: systemImage, title: title, message: message, showsProgress: showsProgress) { EmptyView() }
    }

    private func statusView<Actions: View>(
        systemImage: String,
        title: String,
        message: String? = nil,
        showsProgress: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if showsProgress {
                ProgressView()
            }
            actions()
        }
        .padding(24)
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    TextField("Playlist name", text: $model.playlistName)
                }
                Section("\(model.selectedCount) of \(model.matches.count) tracks selected") {
                    ForEach(model.matches) { match in
                        MatchRow(match: match, isSelected: model.selected.contains(match.id))
                            .contentShape(Rectangle())
                            .onTapGesture { model.toggle(match) }
                    }
                }
                if !model.unidentifiedEntries.isEmpty {
                    Section("Unreleased / ID tracks (cannot be searched)") {
                        ForEach(model.unidentifiedEntries) { entry in
                            Text(entry.rawLine).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            Button {
                Task { await model.save() }
            } label: {
                Text("Save \(model.selectedCount) tracks to \(model.service.displayName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedCount == 0)
            .padding()
        }
    }

    // MARK: - Done

    private func doneView(playlist: SavedPlaylist, saved: Int, unmatched: [SetlistEntry]) -> some View {
        VStack(spacing: 0) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Saved to \(playlist.service.displayName)", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text(playlist.name).font(.subheadline)
                        Text("\(saved) of \(saved + unmatched.count) tracks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    if let url = playlist.url {
                        if showsOpenLink {
                            Link("Open playlist", destination: url)
                        }
                        Button("Copy playlist link") {
                            UIPasteboard.general.url = url
                        }
                    }
                }
                if !unmatched.isEmpty {
                    Section("Not saved (\(unmatched.count))") {
                        ForEach(unmatched) { entry in
                            Text(entry.displayText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            Button {
                model.onFinish?()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}

struct MatchRow: View {
    let match: TrackMatch
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(match.candidate == nil ? Color.secondary.opacity(0.4) : (isSelected ? Color.green : Color.secondary))
                .font(.title3)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(match.entry.displayText)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let candidate = match.candidate {
                    Text("\(candidate.title) · \(candidate.artistLine)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("No match found")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 8)

            if match.candidate != nil {
                Text(match.isConfident ? "Match" : "Unsure")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((match.isConfident ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(match.isConfident ? Color.green : Color.orange)
            }
        }
        .padding(.vertical, 2)
    }
}
