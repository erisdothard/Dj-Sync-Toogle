import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: SyncHistoryStore

    var body: some View {
        List {
            if history.records.isEmpty {
                ContentUnavailableView("No syncs yet", systemImage: "music.note.list",
                                       description: Text("Sets you share will show up here."))
            }
            ForEach(history.records) { record in
                DisclosureGroup {
                    if let url = record.playlistURL {
                        Link("Open in \(record.service.displayName)", destination: url)
                    }
                    if let source = record.sourceURL {
                        Link("Open source", destination: source)
                    }
                    if !record.unmatched.isEmpty {
                        Text("Not saved").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(record.unmatched, id: \.self) { line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.playlistName).font(.subheadline.weight(.medium))
                        Text("\(record.service.displayName) · \(record.savedCount)/\(record.totalCount) tracks · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { history.records[$0] }.forEach(history.remove)
            }
        }
        .navigationTitle("History")
    }
}
