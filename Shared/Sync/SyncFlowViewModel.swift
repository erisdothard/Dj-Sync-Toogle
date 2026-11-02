import Foundation
import SetlistCore

/// Drives one share: detect → match → (review) → save. Used by the share extension and the in-app tester.
@MainActor
final class SyncFlowViewModel: ObservableObject, Identifiable {
    enum Phase: Equatable {
        case loading
        case noSetlist(String)
        case alreadySynced(SyncRecord)
        case matching(done: Int, total: Int)
        case review
        case saving
        case done(SavedPlaylist, saved: Int, unmatched: [SetlistEntry])
        case failed(String)
    }

    let id = UUID()

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var setlist: Setlist?
    @Published private(set) var matches: [TrackMatch] = []
    @Published var selected: Set<UUID> = []
    @Published var playlistName = ""

    /// Mirrors `SyncSettings.autoSyncEnabled`; flipping it in the share sheet persists for next time.
    @Published var autoSync: Bool {
        didSet { settings.autoSyncEnabled = autoSync }
    }

    @Published var service: MusicService {
        didSet { settings.service = service }
    }

    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?

    private let settings: SyncSettings
    private let history: SyncHistoryStore
    private let extractor = SetlistExtractor()
    private let engine = SyncEngine()
    private var share: LoadedShare?
    private var ignoreDuplicate = false

    init(settings: SyncSettings = .shared, history: SyncHistoryStore = .shared) {
        self.settings = settings
        self.history = history
        autoSync = settings.autoSyncEnabled
        service = settings.service
    }

    var canReview: Bool { !matches.isEmpty }

    var selectedCount: Int { matches.filter { selected.contains($0.id) }.count }

    var unidentifiedEntries: [SetlistEntry] { setlist?.entries.filter(\.isUnidentified) ?? [] }

    // MARK: - Entry points

    func start(items: [NSExtensionItem]) async {
        guard let share = await ExtensionInputLoader.load(from: items) else {
            phase = .noSetlist("Nothing usable was shared. Share a link, text, or a screenshot.")
            return
        }
        await start(with: share)
    }

    func start(with share: LoadedShare) async {
        self.share = share
        await run()
    }

    func continueAfterDuplicate() async {
        ignoreDuplicate = true
        await matchAndMaybeSave()
    }

    func rematch() async {
        guard setlist != nil else { return }
        await matchAndMaybeSave(forceReview: true)
    }

    func toggle(_ match: TrackMatch) {
        guard match.candidate != nil else { return }
        if selected.contains(match.id) {
            selected.remove(match.id)
        } else {
            selected.insert(match.id)
        }
    }

    func backToReview() {
        phase = .review
    }

    // MARK: - Pipeline

    private func run() async {
        guard let share else { return }
        phase = .loading
        do {
            let found = try await extractor.extract(from: share.input, titleHint: share.titleHint)
            guard found.isLikelySetlist else {
                let count = found.searchableEntries.count
                phase = .noSetlist(count == 0
                    ? "No tracklist was found. Try sharing the text of the tracklist or a screenshot of it."
                    : "Only \(count) track line\(count == 1 ? "" : "s") found, which is not enough to call this a set.")
                return
            }
            setlist = found
            playlistName = settings.playlistName(for: found)
            if !ignoreDuplicate, let url = found.sourceURL, let previous = history.record(forSource: url) {
                phase = .alreadySynced(previous)
                return
            }
            await matchAndMaybeSave()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func matchAndMaybeSave(forceReview: Bool = false) async {
        guard let setlist else { return }
        let client = MusicServiceFactory.client(for: service)
        guard await client.isAuthorized() else {
            phase = .failed(MusicServiceError.notAuthorized(service).localizedDescription)
            return
        }

        let total = setlist.searchableEntries.count
        phase = .matching(done: 0, total: total)
        let results = await engine.match(setlist, using: client) { [weak self] done, total in
            Task { @MainActor in
                if case .matching = self?.phase {
                    self?.phase = .matching(done: done, total: total)
                }
            }
        }
        matches = results
        let includeLowConfidence = settings.includeLowConfidence
        selected = Set(results.filter { $0.isConfident || (includeLowConfidence && $0.candidate != nil) }.map(\.id))

        if autoSync && !forceReview {
            await save()
        } else {
            phase = .review
        }
    }

    func save() async {
        guard let setlist else { return }
        phase = .saving
        let client = MusicServiceFactory.client(for: service)
        do {
            let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedName.isEmpty ? settings.playlistName(for: setlist) : trimmedName
            let playlist = try await engine.save(matches: matches, selected: selected, setlist: setlist, playlistName: name, using: client)

            let savedIDs = Set(matches.filter { selected.contains($0.id) && $0.candidate != nil }.map(\.id))
            let unmatched = setlist.entries.filter { !savedIDs.contains($0.id) }
            history.add(SyncRecord(
                date: Date(),
                setTitle: SetlistDetector.cleanTitle(setlist.title) ?? "DJ Set",
                sourceURL: setlist.sourceURL,
                sourceKey: setlist.sourceURL.map(SyncHistoryStore.sourceKey(for:)),
                service: service,
                playlistName: playlist.name,
                playlistURL: playlist.url,
                savedCount: savedIDs.count,
                totalCount: setlist.entries.count,
                unmatched: unmatched.map(\.displayText)
            ))
            phase = .done(playlist, saved: savedIDs.count, unmatched: unmatched)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
