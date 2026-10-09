import Foundation

// Where the notes live, when that is a folder the reader chose — in practice
// a folder in iCloud Drive that the Mac's re-JUI also uses, so the two apps
// read and write the same files and iCloud carries them between devices.
//
// Free signing gives the app no iCloud container of its own (that needs the
// paid developer account), so this goes through the Files app instead: the
// reader picks the folder once, and the app keeps a security-scoped bookmark
// to it, which reopens it on every launch without asking again.
//
// Three things follow from the folder being shared and synced:
// - Reads and writes are *coordinated*, so iCloud never uploads a half-written
//   note and the app never reads one mid-download. A coordinated read of a
//   note that hasn't come down to the phone yet downloads it first.
// - Notes iCloud hasn't fetched yet are listed as hidden placeholders
//   (".<name>.icloud"); `Vault.requestDownloads` asks for them, and the list
//   fills in as they arrive.
// - The folder is watched, so a note edited on the Mac shows up here without
//   reopening the app.
enum Vault {
    static let bookmarkKey = "vaultBookmark"

    /// The folder chosen earlier, reopened from its bookmark — or nil if
    /// none was chosen, or it can no longer be found.
    static func savedFolder(_ defaults: UserDefaults) -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        // Held for the life of the app: the store reads and writes here
        // until a different folder is chosen.
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData() { defaults.set(fresh, forKey: bookmarkKey) }
        return url
    }

    /// Remembers `url` as the notes folder. Call with access already started.
    static func remember(_ url: URL, in defaults: UserDefaults) throws {
        defaults.set(try url.bookmarkData(), forKey: bookmarkKey)
    }

    static func forget(in defaults: UserDefaults) {
        defaults.removeObject(forKey: bookmarkKey)
    }

    /// Whether `url` is in iCloud Drive.
    static func isICloud(_ url: URL) -> Bool {
        url.path.contains("/Mobile Documents/")
    }

    // MARK: Coordinated file access

    /// The presenter whose own writes shouldn't be reported back to it.
    static weak var presenter: NSFilePresenter?

    private static var coordinator: NSFileCoordinator { NSFileCoordinator(filePresenter: presenter) }

    static func read(_ url: URL) -> Data? {
        var data: Data?
        var error: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { url in
            data = try? Data(contentsOf: url)
        }
        return data
    }

    static func write(_ data: Data, to url: URL) {
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { url in
            try? data.write(to: url, options: .atomic)
        }
    }

    static func remove(_ url: URL) {
        guard exists(url) else { return }
        var error: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &error) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func copy(_ source: URL, to destination: URL) {
        var error: NSError?
        coordinator.coordinate(readingItemAt: source, options: [],
                               writingItemAt: destination, options: .forReplacing,
                               error: &error) { from, to in
            try? FileManager.default.copyItem(at: from, to: to)
        }
    }

    /// A file that is here, or in iCloud and not yet downloaded.
    static func exists(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.path) || fm.fileExists(atPath: placeholder(for: url).path)
    }

    // MARK: Files not downloaded yet

    /// iCloud's stand-in for a file that hasn't come down: ".<name>.icloud".
    static func placeholder(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    /// The real file a placeholder stands in for, if `url` is one.
    static func realFile(forPlaceholder url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let real = String(name.dropFirst().dropLast(".icloud".count))
        return url.deletingLastPathComponent().appendingPathComponent(real)
    }

    /// Asks iCloud for every placeholder in `directory`; true if any were
    /// found, so the caller knows to look again shortly.
    @discardableResult
    static func requestDownloads(in directory: URL) -> Bool {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var pending = false
        for item in items {
            guard let real = realFile(forPlaceholder: item) else { continue }
            try? fm.startDownloadingUbiquitousItem(at: real)
            pending = true
        }
        return pending
    }
}

// Watches the notes folder for changes made elsewhere — the Mac, through
// iCloud — and reports them, a beat after the last one, so a burst of
// arriving files is one refresh rather than twenty.
final class VaultWatcher: NSObject, NSFilePresenter {
    private(set) var presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    var onChange: () -> Void = {}
    private var pending: DispatchWorkItem?

    func watch(_ url: URL) {
        if presentedItemURL != nil { NSFileCoordinator.removeFilePresenter(self) }
        presentedItemURL = url
        NSFileCoordinator.addFilePresenter(self)
        Vault.presenter = self
    }

    func stop() {
        guard presentedItemURL != nil else { return }
        NSFileCoordinator.removeFilePresenter(self)
        presentedItemURL = nil
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func presentedItemDidChange() { changed() }
    func presentedSubitemDidChange(at url: URL) { changed() }
    func presentedSubitemDidAppear(at url: URL) { changed() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed() }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        changed()
        completionHandler(nil)
    }
}
