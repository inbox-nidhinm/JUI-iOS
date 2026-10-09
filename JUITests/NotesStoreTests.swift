import XCTest
@testable import JUI

// The store is the one part of the app with logic worth pinning down in tests:
// everything else is judged by looking at it. Each test gets its own vault in a
// temporary directory and its own defaults suite, so nothing touches the real
// notes or settings.
final class NotesStoreTests: XCTestCase {
    private var vault: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("jui-tests-\(UUID().uuidString)", isDirectory: true)
        suite = "jui-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: vault)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeStore() -> NotesStore { NotesStore(directory: vault, defaults: defaults) }

    private func type(_ text: String, into store: NotesStore) {
        store.textChanged(NSAttributedString(string: text, attributes: Style.base))
        store.saveNow()
    }

    private func files(in folder: String? = nil) -> [String] {
        let dir = folder.map { vault.appendingPathComponent($0) } ?? vault!
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    // MARK: Titles

    func testTitleIsFirstNonEmptyLineTrimmedTo42() {
        XCTAssertEqual(NotesStore.title(for: "\n\n  hello there  \nsecond"), "hello there")
        XCTAssertEqual(NotesStore.title(for: ""), "Untitled")
        XCTAssertEqual(NotesStore.title(for: "   \n\t"), "Untitled")
        let long = String(repeating: "a", count: 60)
        XCTAssertEqual(NotesStore.title(for: long).count, 42)
    }

    // MARK: Saving

    func testBlankNoteIsNeverWritten() {
        let store = makeStore()
        store.newNote(in: nil)
        store.saveNow()
        XCTAssertTrue(files().isEmpty)
    }

    func testTypedNoteIsSavedAsRTFAndListed() {
        let store = makeStore()
        type("first line\nmore", into: store)
        XCTAssertEqual(files(), ["\(store.currentID).rtf"])
        XCTAssertEqual(store.notes.map(\.title), ["first line"])
        XCTAssertEqual(store.wordCount, 3)
    }

    func testReopeningRestoresTextAndRebuildsParagraphStyles() {
        let store = makeStore()
        let text = NSMutableAttributedString(string: "• one\nprose", attributes: Style.base)
        // Saved with the wrong style on purpose: the store must not trust it.
        text.addAttribute(.paragraphStyle, value: NSParagraphStyle(),
                          range: NSRange(location: 0, length: text.length))
        store.textChanged(text)
        store.saveNow()
        let id = store.currentID

        let reopened = makeStore()
        XCTAssertEqual(reopened.currentID, id)
        XCTAssertEqual(reopened.attr.string, "• one\nprose")
        let bullet = reopened.attr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let prose = reopened.attr.attribute(.paragraphStyle, at: 7, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(bullet?.headIndent ?? 0, 0)
        XCTAssertEqual(bullet?.paragraphSpacing, 0)
        XCTAssertEqual(prose?.headIndent, 0)
        XCTAssertEqual(prose?.paragraphSpacing, Style.linePitch)
    }

    func testItalicsSurviveARoundTrip() throws {
        let store = makeStore()
        let text = NSMutableAttributedString(string: "plain slanted", attributes: Style.base)
        text.addAttribute(.font, value: Style.italic(Style.baseFont, true),
                          range: NSRange(location: 6, length: 7))
        store.textChanged(text)
        store.saveNow()
        let reopened = makeStore()
        let font = try XCTUnwrap(reopened.attr.attribute(.font, at: 8, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(Style.isItalic(font))
        let upright = try XCTUnwrap(reopened.attr.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertFalse(Style.isItalic(upright))
    }

    // Reading a note is not editing it: opening, leaving and saving must not
    // rewrite the file, or the note jumps to the top of the list.
    func testOpeningAndLeavingANoteDoesNotRewriteIt() throws {
        let store = makeStore()
        type("older", into: store)
        let older = store.currentID
        store.newNote(in: nil)
        type("newer", into: store)
        let url = vault.appendingPathComponent("\(older).rtf")
        let before = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        Thread.sleep(forTimeInterval: 1.1) // file dates are to the second
        store.open(older)
        store.saveNow()
        store.newNote(in: nil)
        store.saveNow()
        let after = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        XCTAssertEqual(before, after)
        XCTAssertEqual(store.notes.map(\.title), ["newer", "older"])
    }

    // MARK: Stickies

    func testStickiesTrackEdits() {
        let store = makeStore()
        type("0123456789", into: store)
        store.addSticky(range: NSRange(location: 4, length: 3)) // "456"

        // insert before: shifts
        store.remapStickies(edit: NSRange(location: 0, length: 0), replacementLength: 2)
        XCTAssertEqual(store.stickies[0].start, 6)
        XCTAssertEqual(store.stickies[0].length, 3)

        // insert inside: grows
        store.remapStickies(edit: NSRange(location: 7, length: 0), replacementLength: 1)
        XCTAssertEqual(store.stickies[0].start, 6)
        XCTAssertEqual(store.stickies[0].length, 4)

        // delete across the whole anchor: collapses to the edit point, survives
        store.remapStickies(edit: NSRange(location: 5, length: 10), replacementLength: 0)
        XCTAssertEqual(store.stickies.count, 1)
        XCTAssertEqual(store.stickies[0].start, 5)
        XCTAssertEqual(store.stickies[0].length, 0)
    }

    func testEditAfterAnchorLeavesItAlone() {
        let store = makeStore()
        type("0123456789", into: store)
        store.addSticky(range: NSRange(location: 1, length: 2))
        store.remapStickies(edit: NSRange(location: 8, length: 1), replacementLength: 5)
        XCTAssertEqual(store.stickies[0].start, 1)
        XCTAssertEqual(store.stickies[0].length, 2)
    }

    func testEmptyStickyIsDiscardedOnClose() {
        let store = makeStore()
        type("words", into: store)
        let id = store.addSticky(range: NSRange(location: 0, length: 5))
        store.openStickyID = id
        store.closeSticky()
        XCTAssertTrue(store.stickies.isEmpty)
        XCTAssertNil(store.openStickyID)
    }

    func testWrittenStickyIsSavedBesideItsNote() throws {
        let store = makeStore()
        type("words", into: store)
        let id = store.addSticky(range: NSRange(location: 0, length: 5))
        store.updateStickyText(id, "a thought")
        store.openStickyID = id
        store.closeSticky()
        store.saveNow()
        XCTAssertTrue(files().contains("\(store.currentID).stickies.json"))
        let reopened = makeStore()
        XCTAssertEqual(reopened.stickies.map(\.text), ["a thought"])
    }

    // MARK: Folders

    func testCreateFolderUniquesNamesIgnoringCase() {
        let store = makeStore()
        XCTAssertEqual(store.createFolder("Poems"), "Poems")
        XCTAssertEqual(store.createFolder("poems"), "poems 2")
        XCTAssertEqual(store.createFolder("  a/b  "), "a-b")
        XCTAssertNil(store.createFolder("   "))
        XCTAssertEqual(store.folders, ["a-b", "Poems", "poems 2"])
    }

    func testRenameThatOnlyChangesCaseKeepsTheName() {
        let store = makeStore()
        store.createFolder("notes")
        XCTAssertEqual(store.renameFolder("notes", to: "Notes"), "Notes")
        XCTAssertEqual(store.folders, ["Notes"])
    }

    func testMovingANoteTakesItsStickiesAlong() {
        let store = makeStore()
        store.createFolder("poems")
        type("a poem", into: store)
        store.addSticky(range: NSRange(location: 0, length: 1))
        store.updateStickyText(store.stickies[0].id, "note")
        store.saveNow()
        let id = store.currentID

        store.moveNote(id, to: "poems")
        XCTAssertEqual(files(in: "poems"), ["\(id).rtf", "\(id).stickies.json"])
        XCTAssertEqual(store.notes.first?.folder, "poems")
        XCTAssertEqual(store.currentFolder, "poems")
    }

    func testDeletingAFolderDeletesItsNotesAndReopensSomethingElse() {
        let store = makeStore()
        type("unfiled", into: store)
        let keep = store.currentID
        store.createFolder("old")
        store.newNote(in: nil)
        type("doomed", into: store)
        store.moveNote(store.currentID, to: "old")

        store.deleteFolder("old")
        XCTAssertEqual(store.folders, [])
        XCTAssertEqual(store.notes.map(\.id), [keep])
        XCTAssertEqual(store.currentID, keep)
    }

    func testNewNoteLandsInTheFolderItWasMadeIn() {
        let store = makeStore()
        store.createFolder("drafts")
        store.newNote(in: "drafts")
        type("in drafts", into: store)
        XCTAssertEqual(store.notes.first?.folder, "drafts")
    }

    // MARK: Search

    func testSearchFindsTextInOtherNotesWithASnippet() {
        let store = makeStore()
        type("shopping\nbuy oranges", into: store)
        store.newNote(in: nil)
        type("a different note", into: store)
        store.openSearch()
        let hits = store.search("ORANGE")
        XCTAssertEqual(hits.map(\.title), ["shopping"])
        XCTAssertEqual(hits.first?.snippet, "buy oranges")
        XCTAssertEqual(store.search("").count, 2)
    }

    // MARK: Settings

    func testThemeAndNamePersist() {
        let store = makeStore()
        store.setTheme(Themes.lilac)
        store.setDisplayName("  Juilee ")
        XCTAssertEqual(defaults.string(forKey: "themeID"), "lilac")
        XCTAssertEqual(defaults.string(forKey: "displayName"), "Juilee")
        store.setTheme(Themes.cream) // leave the global as the other tests expect
    }
}
