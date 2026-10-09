import SwiftUI
import UIKit

struct NoteMeta: Identifiable, Equatable {
    let id: String
    var title: String
    var modified: Date
    var folder: String? // nil = unfiled (vault root)
}

struct SearchHit: Identifiable {
    let id: String
    let title: String
    let snippet: String
    let folder: String?
}

// An annotation anchored to a character range of the note, not to pixels.
// Same file format as the Mac app, so a vault copied between the two keeps its
// stickies. The phone shows every sticky as a mark in the margin and never
// pins one, but it keeps pinX/pinY/rotation/left as it found them.
struct Sticky: Identifiable, Codable, Equatable {
    let id: UUID
    var start: Int
    var length: Int
    var text: String
    var pinX: Double?
    var pinY: Double?
    var rotation: Double?
    var left: Bool?
}

// The single source of truth for everything. Every view takes `store`
// directly; there is no other model layer.
//
// Persistence is plain files in the vault, the same layout the Mac uses:
//
//   <vault>/<uuid>.rtf             a note (RTF so italics survive)
//   <vault>/<uuid>.stickies.json   its sticky annotations, if any
//   <vault>/<folder>/              a real subdirectory, one level only
//
// On the phone the vault is the app's Documents folder, which the Files app
// shows as On My iPhone › JUI.
final class NotesStore: ObservableObject {
    @Published var notes: [NoteMeta] = []
    @Published var currentID: String = UUID().uuidString
    // Bumped only when a different document is loaded into the editor, never
    // on typing — the text view watches this to know when to reset. Bumping it
    // on keystrokes wipes the undo stack and fights the caret.
    @Published private(set) var docVersion = 0
    // Set by `newNote` so the editor opens with the keyboard up; the editor
    // clears it once it has taken focus. Opening an existing note leaves the
    // keyboard down until the page is tapped.
    var focusOnOpen = false

    private(set) var attr = NSAttributedString()
    private var saveWork: DispatchWorkItem?
    // Whether the open note has been edited since it was last written. A note
    // is written only when it has: opening, reading and leaving one must not
    // touch its file, because the file's modification date is what orders the
    // home screen — rewriting on every visit sent whatever was last *read* to
    // the top. Every edit goes through `scheduleSave`, which sets this.
    private var unsaved = false
    @Published private(set) var dir: URL
    private let defaults: UserDefaults
    @Published private(set) var fontFamily: String = Style.fontFamily

    // MARK: Folders (real subdirectories of the vault, one level deep)

    @Published private(set) var folders: [String] = []
    private(set) var currentFolder: String?

    func baseDir(_ folder: String?) -> URL {
        guard let folder, !folder.isEmpty else { return dir }
        return dir.appendingPathComponent(folder, isDirectory: true)
    }

    func folderOf(_ id: String) -> String? {
        if id == currentID { return currentFolder }
        return notes.first(where: { $0.id == id })?.folder
    }

    static var defaultVaultDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Where the notes are, as the Files app would name it.
    var vaultDisplay: String {
        if dir.standardizedFileURL == Self.defaultVaultDir.standardizedFileURL {
            return "On My iPhone › JUI"
        }
        return (Vault.isICloud(dir) ? "iCloud Drive › " : "") + dir.lastPathComponent
    }

    private let watcher = VaultWatcher()
    // The open note's file date when it was last read or written here, so a
    // newer one can be recognised as an edit made elsewhere.
    private var lastSeenModified: Date?
    private var downloadChecks = 0

    // MARK: First run & display name

    @Published var displayName: String
    @Published var onboardingShown: Bool

    // typing is suspended while a full-screen overlay is up
    var editorBlocked: Bool { hiddenShown || onboardingShown || openStickyID != nil }

    func setDisplayName(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != displayName else { return }
        displayName = clean
        defaults.set(clean, forKey: "displayName")
    }

    func completeOnboarding() {
        defaults.set(true, forKey: "onboardingCompleted")
        onboardingShown = false
    }

    // Replays the first-run flow on demand — the hidden "onboard again" row in
    // search. Deliberately leaves onboardingCompleted alone: the only way out of
    // onboarding is to finish it, so abandoning a replay by quitting must not
    // re-trigger it on next launch.
    func replayOnboarding() {
        searchShown = false
        hiddenShown = false
        saveNow()
        onboardingShown = true
    }

    private var observers: [NSObjectProtocol] = []

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A folder the reader chose (iCloud Drive) if there is one and it can
        // still be reached; otherwise the app's own folder.
        dir = directory ?? Vault.savedFolder(defaults) ?? Self.defaultVaultDir
        displayName = defaults.string(forKey: "displayName") ?? ""
        onboardingShown = !defaults.bool(forKey: "onboardingCompleted")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        watcher.onChange = { [weak self] in self?.refreshFromDisk() }
        if directory == nil { watcher.watch(dir) }
        refreshList()
        if let latest = notes.first { open(latest.id) }
        // Back in the foreground: pick up whatever changed meanwhile.
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshFromDisk() })
        // iOS can suspend and then kill the app without warning, so the save
        // that the Mac makes on quit happens here every time it leaves the
        // foreground instead.
        for name in [UIApplication.willResignActiveNotification,
                     UIApplication.didEnterBackgroundNotification,
                     UIApplication.willTerminateNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.saveNow() })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    @Published private(set) var wordCount = 0

    private func updateWordCount() {
        // The bullet is furniture, not a word.
        let tokens = attr.string.split { $0.isWhitespace || $0.isNewline }
        wordCount = tokens.filter { $0 != "•" }.count
    }

    func textChanged(_ new: NSAttributedString) {
        attr = NSAttributedString(attributedString: new)
        updateWordCount()
        scheduleSave()
    }

    /// The same text in a new ink, after a theme change. Not an edit: the ink
    /// is re-applied whenever a note is loaded, so nothing needs writing.
    func textRecoloured(_ new: NSAttributedString) {
        attr = NSAttributedString(attributedString: new)
    }

    // The hidden page — dedication and settings — toggled by the corner
    // flourish; while it's up the editor underneath is frozen.
    @Published var hiddenShown = false

    // MARK: Sticky annotations

    @Published var stickies: [Sticky] = []
    // The sticky whose card is open over the page, if any.
    @Published var openStickyID: UUID?

    private func stickiesURL(_ id: String, in folder: String?) -> URL {
        baseDir(folder).appendingPathComponent("\(id).stickies.json")
    }

    private func loadStickies(_ id: String, in folder: String?) -> [Sticky] {
        let url = stickiesURL(id, in: folder)
        guard Vault.exists(url), let data = Vault.read(url) else { return [] }
        return (try? JSONDecoder().decode([Sticky].self, from: data)) ?? []
    }

    @discardableResult
    func addSticky(range: NSRange) -> UUID {
        let sticky = Sticky(id: UUID(), start: range.location, length: range.length, text: "")
        stickies.append(sticky)
        scheduleSave()
        return sticky.id
    }

    func updateStickyText(_ id: UUID, _ text: String) {
        guard let i = stickies.firstIndex(where: { $0.id == id }), stickies[i].text != text else { return }
        stickies[i].text = text
        scheduleSave()
    }

    func removeSticky(_ id: UUID) {
        stickies.removeAll { $0.id == id }
        if openStickyID == id { openStickyID = nil }
        scheduleSave()
    }

    /// Closes the open sticky card. A sticky that was never written in goes
    /// with it, as an untouched one does on the Mac when clicked away from.
    func closeSticky() {
        guard let id = openStickyID else { return }
        openStickyID = nil
        if let sticky = stickies.first(where: { $0.id == id }),
           sticky.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            removeSticky(id)
        }
    }

    // Shift anchors through a text edit so they keep tracking their text.
    // Anchors inside a deleted range collapse to the edit point but survive.
    func remapStickies(edit: NSRange, replacementLength: Int) {
        guard !stickies.isEmpty else { return }
        let delta = replacementLength - edit.length
        let editEnd = edit.location + edit.length
        var changed = false
        func map(_ position: Int) -> Int {
            if position <= edit.location { return position }
            if position >= editEnd { return position + delta }
            return edit.location
        }
        var updated = stickies
        for i in updated.indices {
            let start = updated[i].start
            let end = start + updated[i].length
            let newStart = map(start)
            let newEnd = max(map(end), newStart)
            if newStart != start || newEnd - newStart != updated[i].length {
                updated[i].start = newStart
                updated[i].length = newEnd - newStart
                changed = true
            }
        }
        if changed {
            stickies = updated
            scheduleSave()
        }
    }

    // MARK: Search

    @Published var searchShown = false {
        didSet {
            guard !searchShown, oldValue else { return }
            // Dropped a beat after the palette closes, so the rows keep their
            // snippets while they fade out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, !self.searchShown else { return }
                self.searchCache.removeAll()
            }
        }
    }
    var pendingReveal: NSRange? // consumed by the text view after a reveal()
    private var searchCache: [String: String] = [:]

    func openSearch() {
        hiddenShown = false
        openStickyID = nil
        searchCache = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, plainTextForNote($0.id)) })
        searchShown = true
    }

    func search(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var hits: [SearchHit] = []
        for meta in notes {
            let text = meta.id == currentID ? attr.string : (searchCache[meta.id] ?? "")
            if q.isEmpty {
                hits.append(SearchHit(id: meta.id, title: meta.title, snippet: "", folder: meta.folder))
                continue
            }
            if let r = text.range(of: q, options: .caseInsensitive) {
                let line = text[text.lineRange(for: r)]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                hits.append(SearchHit(
                    id: meta.id, title: meta.title,
                    snippet: String(line.prefix(64)), folder: meta.folder))
            } else if meta.title.range(of: q, options: .caseInsensitive) != nil {
                hits.append(SearchHit(id: meta.id, title: meta.title, snippet: "", folder: meta.folder))
            }
        }
        return hits
    }

    // open a note from search and remember where to scroll/flash
    func reveal(_ id: String, query: String) {
        searchShown = false
        saveNow()
        load(id, in: notes.first(where: { $0.id == id })?.folder, revealing: query)
    }

    private func plainTextForNote(_ id: String) -> String {
        let folder = folderOf(id)
        let rtf = rtfURL(id, in: folder)
        if FileManager.default.fileExists(atPath: rtf.path) { return plainText(of: rtf) }
        return plainText(of: txtURL(id, in: folder))
    }

    // MARK: Folder management

    // iOS volumes are case-sensitive where the Mac's are not, so "Poems" and
    // "poems" could both be made here and then collide the moment the vault
    // met a Mac. Folder names are compared without case, as the Mac's
    // filesystem would.
    private func folderExists(_ name: String, except: String? = nil) -> Bool {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return items.contains { item in
            guard item.lowercased() == name.lowercased(),
                  item.lowercased() != except?.lowercased() else { return false }
            return true
        }
    }

    @discardableResult
    func createFolder(_ name: String) -> String? {
        let clean = sanitizeFolderName(name)
        guard !clean.isEmpty else { return nil }
        var candidate = clean
        var counter = 2
        while folderExists(candidate) {
            candidate = "\(clean) \(counter)"
            counter += 1
        }
        do {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(candidate, isDirectory: true),
                withIntermediateDirectories: true)
        } catch { return nil }
        refreshList()
        return candidate
    }

    @discardableResult
    func renameFolder(_ name: String, to newName: String) -> String? {
        let clean = sanitizeFolderName(newName)
        guard !clean.isEmpty, clean != name else { return name }
        // A rename that only changes case is not a collision with itself.
        var candidate = clean
        var counter = 2
        while folderExists(candidate, except: name) {
            candidate = "\(clean) \(counter)"
            counter += 1
        }
        do {
            try FileManager.default.moveItem(
                at: dir.appendingPathComponent(name),
                to: dir.appendingPathComponent(candidate))
        } catch { return nil }
        if currentFolder == name { currentFolder = candidate }
        refreshList()
        return candidate
    }

    // Deleting a folder deletes what is in it — no trash, no undo, the same
    // deal `delete(_:)` offers for one note. The whole directory goes, so a
    // stray file of another kind can't leave a ghost folder behind.
    func deleteFolder(_ name: String) {
        let folderURL = dir.appendingPathComponent(name, isDirectory: true)
        // Cancel the open note's pending save first if it is one of the ones
        // going, or the debounce writes it straight back into a directory that
        // no longer exists.
        let losingCurrent = folderOf(currentID) == name
        if losingCurrent { saveWork?.cancel() }
        try? FileManager.default.removeItem(at: folderURL)
        if currentFolder == name { currentFolder = nil }
        refreshList()
        if losingCurrent { openMostRecentOrBlank() }
    }

    func moveNote(_ id: String, to folder: String?) {
        let from = folderOf(id)
        guard from != folder else { return }
        if id == currentID { saveNow() } // files must exist at the old location
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDir(folder), withIntermediateDirectories: true)
        for ext in ["rtf", "txt"] {
            let src = baseDir(from).appendingPathComponent(id).appendingPathExtension(ext)
            guard fm.fileExists(atPath: src.path) else { continue }
            try? fm.moveItem(
                at: src, to: baseDir(folder).appendingPathComponent(id).appendingPathExtension(ext))
        }
        let stickySrc = baseDir(from).appendingPathComponent("\(id).stickies.json")
        if fm.fileExists(atPath: stickySrc.path) {
            try? fm.moveItem(
                at: stickySrc, to: baseDir(folder).appendingPathComponent("\(id).stickies.json"))
        }
        if id == currentID { currentFolder = folder }
        refreshList()
    }

    private func sanitizeFolderName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    // MARK: Settings

    func setFont(_ family: String) {
        guard family != fontFamily else { return }
        fontFamily = family
        Style.fontFamily = family
        defaults.set(family, forKey: "fontFamily")
        // Re-run the paragraph styles too: leading is derived from the pitch
        // and the family's own line height, so it changes with the family.
        attr = Self.restyled(attr)
        docVersion += 1
        // Not saved: the family is re-applied to every note on load, so a
        // font change is not an edit and must not reorder the notes.
    }

    @Published private(set) var themeID: String = Style.theme.id

    // Deliberately does NOT bump docVersion the way setFont does: a theme
    // change recolours the text view's storage in place, so selection, scroll
    // position and undo all survive.
    func setTheme(_ theme: Theme) {
        guard theme.id != themeID else { return }
        Style.theme = theme
        themeID = theme.id
        defaults.set(theme.id, forKey: "themeID")
    }

    // MARK: The note list

    // Titles are cached against the modification date they were read at.
    // `saveNow` ends in `refreshList`, and saves fire on every pause in typing,
    // so without this every pause re-parsed every note in the vault.
    private var titleCache: [String: (modified: Date, title: String)] = [:]

    func refreshList() {
        let fm = FileManager.default
        var seen = Set<String>()
        var metas: [NoteMeta] = []
        var folderNames: [String] = []
        var freshTitles: [String: (modified: Date, title: String)] = [:]

        func scanFiles(in directory: URL, folder: String?) {
            let files = (try? fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            // rtf first so a leftover legacy .txt with the same id is ignored
            for url in files.sorted(by: { $0.pathExtension < $1.pathExtension }) {
                guard ["rtf", "txt"].contains(url.pathExtension) else { continue }
                let id = url.deletingPathExtension().lastPathComponent
                guard seen.insert(id).inserted else { continue }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let title: String
                if let hit = titleCache[url.path], hit.modified == modified {
                    title = hit.title
                } else {
                    title = Self.title(for: plainText(of: url))
                }
                freshTitles[url.path] = (modified, title)
                metas.append(NoteMeta(id: id, title: title, modified: modified, folder: folder))
            }
        }

        let rootItems = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for item in rootItems {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            // ".Trash" and other hidden folders iOS may create are not folders
            // of notes.
            if isDir, !item.lastPathComponent.hasPrefix(".") {
                folderNames.append(item.lastPathComponent)
                scanFiles(in: item, folder: item.lastPathComponent)
            }
        }
        scanFiles(in: dir, folder: nil)

        // Notes iCloud hasn't brought down yet: ask for them, and look again
        // in a moment. Bounded, so a file that never arrives (offline) can't
        // keep this going.
        var waiting = Vault.requestDownloads(in: dir)
        for name in folderNames {
            waiting = Vault.requestDownloads(in: dir.appendingPathComponent(name)) || waiting
        }
        if waiting, downloadChecks < 40 {
            downloadChecks += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refreshList() }
        } else if !waiting {
            downloadChecks = 0
        }

        titleCache = freshTitles
        folders = folderNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        notes = metas.sorted { $0.modified > $1.modified }
    }

    private func plainText(of url: URL) -> String {
        guard let data = Vault.read(url) else { return "" }
        if url.pathExtension == "rtf", let parsed = Self.readRTF(data) { return parsed.string }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func title(for text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        if firstLine.isEmpty { return "Untitled" }
        return String(firstLine.prefix(42))
    }

    // MARK: RTF

    static func readRTF(_ data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil)
    }

    static func writeRTF(_ text: NSAttributedString) -> Data? {
        try? text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    /// Paragraph styles, ink and fonts rebuilt rather than trusted from the
    /// file. A stale paragraph spacing walks the type off the ruling, and every
    /// note written before the grid existed carries one.
    ///
    /// Per line, and classified by the line's own text (does it start with the
    /// bullet), not by its headIndent — that is the attribute being rebuilt.
    static func restyled(_ source: NSAttributedString) -> NSAttributedString {
        let restyled = NSMutableAttributedString(attributedString: source)
        let lines = restyled.string as NSString
        var cursor = 0
        while cursor < lines.length {
            let lineRange = lines.lineRange(for: NSRange(location: cursor, length: 0))
            let isBullet = lines.substring(with: lineRange).hasPrefix(Style.bulletPrefix)
            restyled.addAttribute(
                .paragraphStyle,
                value: isBullet ? Style.bulletParagraph : Style.paragraph,
                range: lineRange)
            cursor = NSMaxRange(lineRange)
        }
        restyled.addAttribute(
            .foregroundColor, value: Style.ink,
            range: NSRange(location: 0, length: restyled.length))
        Style.applyFont(to: restyled)
        return restyled
    }

    private func loadAttr(_ id: String, in folder: String?) -> NSAttributedString {
        if Vault.exists(rtfURL(id, in: folder)),
           let data = Vault.read(rtfURL(id, in: folder)),
           let parsed = Self.readRTF(data) {
            let restyled = NSMutableAttributedString(attributedString: Self.restyled(parsed))
            // migrate old fixed-width "───…" rules to the blank-line marker
            let ns = restyled.string as NSString
            var hrRanges: [NSRange] = []
            var lineStart = 0
            while lineStart < ns.length {
                let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
                let content = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
                if content.count >= 3, content.allSatisfy({ $0 == "─" }) {
                    hrRanges.append(NSRange(
                        location: lineRange.location, length: (content as NSString).length))
                }
                lineStart = NSMaxRange(lineRange)
            }
            for range in hrRanges.reversed() {
                restyled.replaceCharacters(
                    in: range,
                    with: NSAttributedString(string: Style.hrMarker, attributes: Style.base))
            }
            return restyled
        }
        if Vault.exists(txtURL(id, in: folder)),
           let data = Vault.read(txtURL(id, in: folder)),
           let legacy = String(data: data, encoding: .utf8) {
            return NSAttributedString(string: legacy, attributes: Style.base)
        }
        return NSAttributedString()
    }

    // MARK: Getting a document into the editor
    //
    // Every route in goes through `load` or `loadBlank`, so none can forget a
    // step. `docVersion` is bumped last, after `pendingReveal` is set, or the
    // text view reloads before it can read it.

    private func load(_ id: String, in folder: String?, revealing query: String? = nil) {
        openStickyID = nil
        unsaved = false
        currentID = id
        currentFolder = folder
        attr = loadAttr(id, in: folder)
        stickies = loadStickies(id, in: folder)
        lastSeenModified = modificationDate(of: rtfURL(id, in: folder))
        updateWordCount()
        if let query {
            let q = query.trimmingCharacters(in: .whitespaces)
            let range = (attr.string as NSString).range(of: q, options: .caseInsensitive)
            pendingReveal = (!q.isEmpty && range.location != NSNotFound) ? range : nil
        }
        docVersion += 1
    }

    /// A blank page. Nothing reaches disk until something is typed into it.
    private func loadBlank(in folder: String?) {
        openStickyID = nil
        unsaved = false
        currentID = UUID().uuidString
        currentFolder = folder
        attr = NSAttributedString()
        stickies = []
        updateWordCount()
        docVersion += 1
    }

    private func openMostRecentOrBlank() {
        if let latest = notes.first {
            load(latest.id, in: latest.folder)
        } else {
            loadBlank(in: nil)
        }
    }

    func open(_ id: String) {
        saveNow()
        load(id, in: notes.first(where: { $0.id == id })?.folder)
    }

    func delete(_ id: String) {
        let losingCurrent = id == currentID
        if losingCurrent { saveWork?.cancel() } // a pending save would resurrect the file
        let folder = folderOf(id)
        Vault.remove(rtfURL(id, in: folder))
        Vault.remove(txtURL(id, in: folder))
        Vault.remove(stickiesURL(id, in: folder))
        refreshList()
        if losingCurrent { openMostRecentOrBlank() }
    }

    /// A blank page in `folder` (nil = unfiled) — wherever the home screen
    /// is standing when the plus is pressed. It opens with the keyboard up.
    func newNote(in folder: String?) {
        hiddenShown = false
        saveNow()
        loadBlank(in: folder)
        focusOnOpen = true
    }

    private func rtfURL(_ id: String, in folder: String?) -> URL {
        baseDir(folder).appendingPathComponent(id).appendingPathExtension("rtf")
    }

    private func txtURL(_ id: String, in folder: String?) -> URL {
        baseDir(folder).appendingPathComponent(id).appendingPathExtension("txt")
    }

    private func scheduleSave() {
        unsaved = true
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        guard unsaved else { return } // nothing edited: leave the file, and its date, alone
        unsaved = false
        let fm = FileManager.default
        let url = rtfURL(currentID, in: currentFolder)
        let hadFile = Vault.exists(url) || Vault.exists(txtURL(currentID, in: currentFolder))
        // Don't create a file for a note that was never typed into.
        if attr.length == 0 && !hadFile { return }
        try? fm.createDirectory(at: baseDir(currentFolder), withIntermediateDirectories: true)
        guard let data = Self.writeRTF(attr) else { return }
        Vault.write(data, to: url)
        Vault.remove(txtURL(currentID, in: currentFolder)) // legacy plain text
        let sURL = stickiesURL(currentID, in: currentFolder)
        if stickies.isEmpty {
            Vault.remove(sURL)
        } else if let stickyData = try? JSONEncoder().encode(stickies) {
            Vault.write(stickyData, to: sURL)
        }
        lastSeenModified = modificationDate(of: url)
        refreshList()
    }

    // MARK: Where the notes live

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Re-reads the folder after a change made elsewhere — the Mac, through
    /// iCloud — or on coming back to the foreground. The open note is
    /// reloaded if its file is newer than the one read here, unless it has
    /// edits not yet saved (those win, and overwrite it on the next save) or
    /// a sticky is open on it.
    func refreshFromDisk() {
        refreshList()
        guard !unsaved, openStickyID == nil,
              let current = modificationDate(of: rtfURL(currentID, in: currentFolder)),
              let seen = lastSeenModified, current > seen else { return }
        load(currentID, in: currentFolder)
    }

    /// Makes `folder` — picked in the Files app, usually in iCloud Drive —
    /// where the notes live from now on. The notes already here are copied
    /// into it, never over a file of the same name; the originals stay where
    /// they were.
    func useFolder(_ folder: URL) {
        let accessing = folder.startAccessingSecurityScopedResource()
        do {
            try Vault.remember(folder, in: defaults)
        } catch {
            if accessing { folder.stopAccessingSecurityScopedResource() }
            return
        }
        saveNow()
        copyNotes(from: dir, to: folder)
        if dir != Self.defaultVaultDir { dir.stopAccessingSecurityScopedResource() }
        dir = folder
        watcher.watch(folder)
        downloadChecks = 0
        refreshList()
        openMostRecentOrBlank()
    }

    // Notes, their stickies and their folders, one level deep, as the vault
    // holds them. Never overwrites; skips the destination itself if it is
    // inside the source.
    private func copyNotes(from source: URL, to destination: URL) {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        let fm = FileManager.default
        let isNoteFile: (URL) -> Bool = { ["rtf", "txt", "json"].contains($0.pathExtension) }
        let items = (try? fm.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for item in items where !item.lastPathComponent.hasPrefix(".") {
            if destination.standardizedFileURL.path.hasPrefix(item.standardizedFileURL.path) { continue }
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let target = destination.appendingPathComponent(item.lastPathComponent, isDirectory: isDir)
            if isDir {
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                let inner = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
                for file in inner where isNoteFile(file) {
                    let fileTarget = target.appendingPathComponent(file.lastPathComponent)
                    if !Vault.exists(fileTarget) { Vault.copy(file, to: fileTarget) }
                }
            } else if isNoteFile(item), !Vault.exists(target) {
                Vault.copy(item, to: target)
            }
        }
    }
}
