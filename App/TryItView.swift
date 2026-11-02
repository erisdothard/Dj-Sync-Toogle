import SwiftUI

/// Runs the exact share-sheet flow on pasted text or a link, so the pipeline can be tested without sharing.
struct TryItView: View {
    @State private var text = ""
    @State private var model: SyncFlowViewModel?

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minHeight: 220)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste a tracklist, or a YouTube / SoundCloud / Mixcloud link")
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                let flow = SyncFlowViewModel()
                model = flow
            } label: {
                Text("Detect and sync").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
        .navigationTitle("Try it")
        .sheet(item: $model) { flow in
            NavigationStack {
                SyncFlowView(model: flow, showsOpenLink: true)
                    .navigationTitle("DJ Sync")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { model = nil }
                        }
                    }
                    .task {
                        flow.onFinish = { model = nil }
                        flow.onCancel = { model = nil }
                        await flow.start(with: LoadedShare(input: .text(text), titleHint: nil))
                    }
            }
        }
    }
}
