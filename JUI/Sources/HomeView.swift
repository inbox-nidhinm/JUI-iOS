import SwiftUI

// The home screen: every note and folder, on the same paper as the page.
// It replaces the Mac's past-notes popover — on a phone the list is where you
// start, and a note is somewhere you go.
//
// At the root, folders sit two-per-row above the notes, with an add tile
// flowing after them. A folder opens as the same screen standing inside it.
// Long-press for the Mac's right-click menus; drag a note onto a folder to
// file it, or onto the back row to unfile it.
//
// Search and a new note sit at the foot, where the Mac keeps its controls;
// the corner flourish (drawn by ContentView, over every screen) opens the
// hidden page, as it does on a note.
struct HomeView: View {
    @ObservedObject var store: NotesStore
    /// nil = the root, else the folder this screen stands in.
    let location: String?
    let openNote: (String) -> Void
    let openFolder: (String) -> Void
    let newNote: (String?) -> Void

    @State private var renamingFolder: String?
    @State private var creatingFolder = false
    @State private var folderDraft = ""
    @State private var confirmingDelete: String?
    @State private var dropTarget: String??

    // Pull down to search. `pull` is how far the list is drawn past its top;
    // the search opens once it passes `pullToSearch`, once per pull — it
    // re-arms only when the list has settled back.
    @State private var pull: CGFloat = 0
    @State private var pullArmed = true
    private static let pullToSearch: CGFloat = 70

    private var visibleNotes: [NoteMeta] {
        store.notes.filter { $0.folder == location }
    }

    private enum FolderItem: Hashable {
        case folder(String)
        case add
    }

    private var folderRows: [[FolderItem]] {
        let items = store.folders.map { FolderItem.folder($0) } + [.add]
        return stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            sheetColor
                .papered(.page)
                .ignoresSafeArea()

            // Revealed above the list as it is pulled down, firming up as the
            // pull nears the point where search opens.
            pullHint
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if location == nil {
                        if creatingFolder { folderNameField }
                        folderGrid
                        if !visibleNotes.isEmpty {
                            Rectangle()
                                .fill(panelDividerColor)
                                .frame(height: 1)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 14)
                        }
                    }
                    if visibleNotes.isEmpty, location != nil || store.folders.isEmpty {
                        Text("no notes yet")
                            .font(houseFont(13))
                            .foregroundStyle(inkFaint)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 32)
                    }
                    ForEach(Array(noteDays.enumerated()), id: \.element.day) { index, group in
                        if index > 0 { daySeparator }
                        dayTitle(group.day)
                        ForEach(group.notes) { noteRow($0) }
                    }
                }
                // Full width, from the left. A scroll view sizes its content
                // to fit and then places it, so a screen with nothing wide on
                // it — an empty folder, just a back row and "no notes yet" —
                // was laid out narrow and set off to the side. At the root
                // the folder grid stretched it and hid the problem.
                .frame(maxWidth: .infinity, alignment: .leading)
                // clear of the flourish and the controls at the foot
                .padding(.bottom, 150)
                .background(GeometryReader { geo in
                    Color.clear.preference(
                        key: PullOffsetKey.self,
                        value: geo.frame(in: .named(Self.scrollSpace)).minY)
                })
            }
            .coordinateSpace(name: Self.scrollSpace)
            .modifier(PullTracking(onPull: pulled(to:)))
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .mask(listMask)

            controls
                .padding(.trailing, 10)
                .padding(.bottom, 2)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            // Belt and braces for the end-of-editing path: whatever happens,
            // coming back never finds a half-named folder waiting.
            if creatingFolder { finishCreatingFolder(folderDraft) }
            if let folder = renamingFolder { finishRenaming(folder, to: folderDraft) }
        }
        .animation(.easeOut(duration: 0.15), value: store.notes)
        .animation(.easeOut(duration: 0.15), value: store.folders)
        .confirmationDialog(
            confirmingDelete.map { "Delete \u{201C}\($0)\u{201D} and the notes in it?" } ?? "",
            isPresented: Binding(get: { confirmingDelete != nil },
                                 set: { if !$0 { confirmingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let name = confirmingDelete { store.deleteFolder(name) }
                confirmingDelete = nil
            }
        } message: {
            Text("There is no trash — this can't be undone.")
        }
    }

    // MARK: Soft edges
    //
    // The same edges a note has. The list fades out as it scrolls up under
    // the status bar; at the foot it is always faded out by the top of the
    // corner flourish, starting a clear band above it, so nothing scrolls
    // over the flourish or the controls beside it. At rest nothing is faded:
    // the heading starts where the top fade ends, and the list's foot padding
    // lets its last row rise clear of the bottom one.
    //
    // A mask on the scroll view is pinned to the screen, not to the list.
    private static let topFade: CGFloat = 20

    private var listMask: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let flourishTop = h - Style.cornerFlourishLift - Style.cornerFlourishHeight
            let fadeStart = flourishTop - Style.cornerFlourishClearance
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: Self.topFade / h),
                    .init(color: .black, location: max(Self.topFade, fadeStart) / h),
                    .init(color: .clear, location: max(Self.topFade, flourishTop) / h),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Pull to search

    private static let scrollSpace = "homeScroll"

    private var pullProgress: CGFloat { min(1, pull / Self.pullToSearch) }

    private var pullHint: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(inkFaint)
            .scaleEffect(0.7 + 0.3 * pullProgress)
            .opacity(Double(pullProgress))
            .padding(.top, 10)
            .accessibilityHidden(true)
    }

    private func pulled(to offset: CGFloat) {
        pull = max(0, offset)
        if offset <= 4 {
            pullArmed = true
        } else if pullArmed, offset >= Self.pullToSearch, !store.searchShown {
            pullArmed = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            hideKeyboard()
            store.openSearch()
        }
    }

    // MARK: Header

    // At the root, whose writing pad this is; in a folder, the folder's name,
    // which is also where a note can be dragged to unfile it. The way back out
    // is the edge swipe, or the corner flourish, which goes straight home.
    @ViewBuilder
    private var header: some View {
        if let location {
            Text(location)
                .font(houseFont(16))
                .foregroundStyle(inkStrong)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(dropTarget == .some(nil) ? panelColor : Color.clear))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16) // the name lines up with the root's heading
            .padding(.top, Self.topFade) // just clear of the top fade
            .padding(.bottom, 12)
            .dropDestination(for: String.self) { ids, _ in
                ids.forEach { store.moveNote($0, to: nil) }
                return !ids.isEmpty
            } isTargeted: { dropTarget = $0 ? .some(nil) : nil }
        } else {
            Text(store.displayName.isEmpty ? "notes" : "\(store.displayName)'s notes")
                .font(houseFont(16))
                .foregroundStyle(brownInk)
                .padding(.horizontal, 26)
                .padding(.top, Self.topFade) // just clear of the top fade
                .padding(.bottom, 20)
        }
    }

    // MARK: Controls

    // Search and a new note — the new note lands in this folder, or unfiled
    // at the root. ⌘K and ⌘N work with a hardware keyboard.
    private var controls: some View {
        HStack(spacing: 4) {
            IconButton(systemName: "magnifyingglass", label: "Search") {
                store.openSearch()
            }
            .keyboardShortcut("k", modifiers: .command)
            IconButton(systemName: "plus",
                       label: location.map { "New note in \($0)" } ?? "New note") {
                newNote(location)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    // MARK: Folders

    private var folderGrid: some View {
        VStack(spacing: 8) {
            ForEach(Array(folderRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        switch item {
                        case .folder(let name): folderCell(name)
                        case .add: addFolderCell
                        }
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity) // keep a lone tile half-width
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var addFolderCell: some View {
        Button {
            folderDraft = ""
            creatingFolder = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(inkFaint)
                .frame(maxWidth: .infinity,
                       minHeight: folderCellHeight - folderCellPadding * 2,
                       maxHeight: folderCellHeight - folderCellPadding * 2)
                .padding(.vertical, folderCellPadding)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(TileStyle(highlighted: false))
        .accessibilityLabel("New folder")
    }

    private func folderCell(_ folder: String) -> some View {
        Button {
            guard renamingFolder != folder else { return }
            openFolder(folder)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(width: folderMarkWidth, height: folderMarkHeight)
                Spacer(minLength: folderMarkGap)
                HStack(spacing: 6) {
                    if renamingFolder == folder {
                        HouseField(
                            text: $folderDraft, size: 13, alpha: 0.85,
                            focused: true,
                            onSubmit: hideKeyboard,
                            onEndEditing: { finishRenaming(folder, to: $0) })
                            .frame(height: 18)
                    } else {
                        Text(folder)
                            .font(houseFont(13))
                            .foregroundStyle(inkStrong)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Circle()
                            .fill(store.currentFolder == folder ? openDotColor : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity,
                   minHeight: folderCellHeight - folderCellPadding * 2,
                   maxHeight: folderCellHeight - folderCellPadding * 2,
                   alignment: .leading)
            .padding(.vertical, folderCellPadding)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileStyle(highlighted: dropTarget == .some(folder)))
        .contextMenu {
            Button {
                folderDraft = folder
                renamingFolder = folder
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) {
                let holdsNotes = store.notes.contains { $0.folder == folder }
                if holdsNotes { confirmingDelete = folder } else { store.deleteFolder(folder) }
            } label: { Label("Delete Folder", systemImage: "trash") }
        }
        .dropDestination(for: String.self) { ids, _ in
            ids.forEach { store.moveNote($0, to: folder) }
            return !ids.isEmpty
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) {
                if targeted { dropTarget = .some(folder) } else if dropTarget == .some(folder) { dropTarget = nil }
            }
        }
    }

    private var folderNameField: some View {
        HouseField(
            text: $folderDraft, size: 13, alpha: 0.85,
            placeholder: "folder name",
            focused: true,
            onSubmit: hideKeyboard,
            onEndEditing: finishCreatingFolder)
            .frame(height: 20)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                folderBaseColor.papered(.folderTile)
                    .clipShape(RoundedRectangle(cornerRadius: 6)))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    // Naming ends however editing ends — Return, a tap anywhere else, or
    // leaving the screen — and it ends one way: a name makes the folder, no
    // name means it was never made. Return only ends the editing, so the
    // folder is made in exactly one place.
    private func finishCreatingFolder(_ name: String) {
        guard creatingFolder else { return }
        creatingFolder = false
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.createFolder(name)
        }
        folderDraft = ""
    }

    // A rename left empty, or unchanged, keeps the old name.
    private func finishRenaming(_ folder: String, to name: String) {
        guard renamingFolder == folder else { return }
        renamingFolder = nil
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != folder { _ = store.renameFolder(folder, to: clean) }
        folderDraft = ""
    }

    // MARK: Notes

    // Notes are gathered under the day they were last written in — made that
    // day, or edited then — newest day first, with a hairline between days.
    // Reading a note doesn't move it: only an edit changes its date.
    private var noteDays: [(day: Date, notes: [NoteMeta])] {
        let calendar = Calendar.current
        var days: [(day: Date, notes: [NoteMeta])] = []
        for note in visibleNotes { // already newest first
            let day = calendar.startOfDay(for: note.modified)
            if let last = days.indices.last, days[last].day == day {
                days[last].notes.append(note)
            } else {
                days.append((day, [note]))
            }
        }
        return days
    }

    private func dayTitle(_ day: Date) -> some View {
        Text(Self.dayName(day))
            .font(houseFont(12))
            .foregroundStyle(inkMuted)
            .padding(.horizontal, 26)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var daySeparator: some View {
        Rectangle()
            .fill(panelDividerColor)
            .frame(height: 1)
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
    }

    // "today", "yesterday", the weekday within the last week, then the date —
    // with the year only when it isn't this one. Lowercase, like the rest of
    // the app's own words.
    private static func dayName(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "today" }
        if calendar.isDateInYesterday(day) { return "yesterday" }
        let today = calendar.startOfDay(for: .now)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        let name: String
        if (2...6).contains(daysAgo) {
            name = day.formatted(.dateTime.weekday(.wide))
        } else if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            name = day.formatted(.dateTime.day().month(.wide))
        } else {
            name = day.formatted(.dateTime.day().month(.wide).year())
        }
        return name.lowercased()
    }

    // The title; the day is in the heading above it. The note last open keeps
    // its dot, as in the Mac's panel; the panel-toned box comes up only under
    // the finger.
    private func noteRow(_ note: NoteMeta) -> some View {
        Button {
            openNote(note.id)
        } label: {
            HStack(spacing: 10) {
                Text(note.title)
                    .font(houseFont(14))
                    .foregroundStyle(inkStrong)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Circle()
                    .fill(note.id == store.currentID ? openDotColor : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(NoteRowStyle())
        .padding(.horizontal, 14)
        .draggable(note.id) {
            Text(note.title)
                .font(houseFont(13))
                .foregroundStyle(inkStrong)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(sheetColor))
        }
        .contextMenu {
            Menu {
                if note.folder != nil {
                    Button("Unfiled") { store.moveNote(note.id, to: nil) }
                }
                ForEach(store.folders.filter { $0 != note.folder }, id: \.self) { folder in
                    Button(folder) { store.moveNote(note.id, to: folder) }
                }
            } label: { Label("Move to", systemImage: "folder") }
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.15)) { store.delete(note.id) }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// A note row: the panel-toned box under the finger.
private struct NoteRowStyle: ButtonStyle {
    var theme = Style.theme.id // redraw on a theme change — see Style.theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? panelColor : Color.clear))
    }
}

// A folder tile: folderBase on its own paper, stepping down to panel when it
// is a drop target or under the finger. The tiles carry no flourish; the one
// flourish on this screen is the corner's.
private struct TileStyle: ButtonStyle {
    var theme = Style.theme.id // redraw on a theme change — see Style.theme
    let highlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                (highlighted || configuration.isPressed ? panelColor : folderBaseColor)
                    .papered(.folderTile)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// How far the home list's top sits below the top of its scroll view — past
// zero only while it is being pulled down.
private struct PullOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// Reports how far the list is pulled down past its top.
//
// On iOS 18 and later this asks the scroll view directly. Measuring the
// content's frame from inside the scroll view — the iOS 17 way, kept as the
// fallback below — isn't reported while the list is being dragged on current
// iOS, so on a phone the pull was never seen and search never opened.
private struct PullTracking: ViewModifier {
    let onPull: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                // Offset is negative while pulled past the top, measured from
                // where the content rests (its top inset).
                -(geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, pulled in
                onPull(pulled)
            }
        } else {
            content.onPreferenceChange(PullOffsetKey.self) { onPull($0) }
        }
    }
}
