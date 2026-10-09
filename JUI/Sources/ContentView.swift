import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Where you are: the home screen, a folder, or a note.
enum Route: Hashable {
    case folder(String)
    case note
}

struct ContentView: View {
    @ObservedObject var store: NotesStore
    @ObservedObject private var crumple = CrumpleDirector.shared
    @State private var path: [Route] = []
    @State private var nameDraft = ""
    @State private var keyboardShown = false
    @State private var choosingFolder = false
    @State private var searchHeight: CGFloat = 200

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NavigationStack(path: $path) {
                home(nil)
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .folder(let name): home(name)
                        case .note: NoteScreen(store: store)
                        }
                    }
            }
            // Everything recedes behind search and onboarding, so the card
            // reads as above the sheet rather than on it.
            .blur(radius: store.searchShown || store.onboardingShown ? 8 : 0)
            .animation(.timingCurve(0, 0, 0.35, 1, duration: 0.6), value: store.searchShown)
            .animation(.easeOut(duration: 0.25), value: store.onboardingShown)

            if store.hiddenShown {
                settingsPage
                    .transition(.opacity)
            }

            // One flourish over every screen, so it holds still in its corner
            // while pages slide past beneath it.
            cornerFlourish

            // The scrim and the card come and go separately: the page dims
            // with a plain fade while the sticky unfolds from its ball on the
            // stage above it, and the real card takes over once it lies flat
            // (Crumple.swift).
            if store.openStickyID != nil {
                stickyScrim
                    .transition(.opacity)
            }
            CrumpleStageView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if let id = crumple.cardID {
                stickyCard(id)
                    // Reduced motion: no fold, a fade.
                    .transition(prefersReducedMotion ? .opacity : .identity)
            }

            // first run: above everything, and nothing behind it is reachable
            // until it completes
            if store.onboardingShown {
                OnboardingView(store: store)
                    .transition(.opacity)
            }
        }
        // Search lives in an overlay rather than the stack, so its arrival
        // can't shift the layout beneath it.
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if store.searchShown {
                    sheetColor.opacity(0.55)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { store.searchShown = false }
                        .transition(.opacity)

                    // Slides down from above the screen and back up, solid
                    // all the way — a card arriving, not one fading in. It
                    // travels its own height plus the status bar and a margin
                    // for its shadow, so it is gone above the glass before it
                    // is removed; moved by its height alone, it was still
                    // showing under the status bar when it vanished.
                    SearchPalette(store: store) { path.append(.note) }
                        .padding(.top, 8)
                        .background(GeometryReader { geo in
                            Color.clear
                                .onAppear { searchHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, h in searchHeight = h }
                        })
                        .transition(.offset(y: -(searchHeight + Self.windowInsets.top + 24)))
                }
            }
            .animation(.timingCurve(0, 0, 0.35, 1, duration: 0.6), value: store.searchShown)
        }
        .tint(brownInk)
        .preferredColorScheme(.light)
        .animation(.easeOut(duration: 0.2), value: store.hiddenShown)
        .animation(.easeOut(duration: 0.2), value: store.openStickyID)
        .animation(.easeOut(duration: 0.15), value: keyboardShown)
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        .onChange(of: store.hiddenShown) { _, shown in
            // seed the field when settings opens, commit it when they leave
            if shown {
                nameDraft = store.displayName
            } else {
                store.setDisplayName(nameDraft)
                AppIcon.sync(to: Style.theme) // the mood they left on
            }
        }
        .onChange(of: store.onboardingShown) { _, shown in
            if !shown { AppIcon.sync(to: Style.theme) }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            // Catches a mood chosen just before the app was closed. Not while
            // a mood is still being chosen.
            if !store.hiddenShown, !store.onboardingShown { AppIcon.sync(to: Style.theme) }
        }
        .onChange(of: store.openStickyID) { old, new in
            if let old, old != new {
                crumple.close(old, text: store.stickies.first { $0.id == old }?.text)
            }
            if let new, new != old {
                // Opened to read, keyboard down: where the card will sit.
                let text = store.stickies.first { $0.id == new }?.text ?? ""
                let insets = Self.windowInsets
                let frame = StickyCard.stampFrame(
                    text: text, area: Self.windowSize,
                    safe: EdgeInsets(top: insets.top, leading: 0, bottom: insets.bottom, trailing: 0),
                    editing: false)
                crumple.open(new, text: text, frame: frame)
            }
        }
        .onChange(of: path) { old, new in
            // Leaving a note — by the arrow or the edge swipe — saves it.
            if old.last == .note, new.last != .note { store.saveNow() }
        }
    }

    private func home(_ location: String?) -> some View {
        HomeView(
            store: store,
            location: location,
            openNote: { id in
                store.open(id)
                path.append(.note)
            },
            openFolder: { path.append(.folder($0)) },
            newNote: { folder in
                store.newNote(in: folder)
                path.append(.note)
            })
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }
    private static var windowInsets: UIEdgeInsets { keyWindow?.safeAreaInsets ?? .zero }
    private static var windowHeight: CGFloat { windowSize.height }
    private static var windowSize: CGSize { keyWindow?.bounds.size ?? UIScreen.main.bounds.size }

    // MARK: The corner flourish

    // Decoration, and a way home. In a note or a folder it goes straight back
    // to the home screen; on home it opens the hidden page, and on the hidden
    // page it closes it again. Multiplied through the page, like every flourish in
    // the app; it deepens a step while pressed. It steps aside while the keyboard is up, when the foot of
    // the screen belongs to the text, and while a sticky is open.
    @ViewBuilder
    private var cornerFlourish: some View {
        if !AnimatedFlourish.frames(.corner).isEmpty, !store.onboardingShown,
           store.openStickyID == nil, !store.searchShown,
           !keyboardShown || store.hiddenShown {
            Button {
                hideKeyboard()
                if store.hiddenShown {
                    withAnimation(.easeOut(duration: 0.2)) { store.hiddenShown = false }
                } else if !path.isEmpty {
                    path.removeAll() // leaving a note saves it — see onChange(of: path)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { store.hiddenShown = true }
                }
            } label: {
                EmptyView()
            }
            .buttonStyle(FlourishStyle(replay: "corner-\(store.docVersion)"))
            .accessibilityLabel(store.hiddenShown ? "Close settings"
                                : path.isEmpty ? "Settings" : "Home")
            .padding(.leading, 12)
            .padding(.bottom, Style.cornerFlourishLift)
            .transition(.opacity)
        }
    }

    // It draws itself on each time a note is opened — `replay` carries the
    // document's load count, so every opening is a new key — and once per
    // opening only: it steps aside while the keyboard is up, and coming back
    // into view under the same note shows it finished rather than drawing it
    // again. The `.id` is what restarts it; the frames are held in view state,
    // which a new play mode alone would not reset.
    private struct FlourishStyle: ButtonStyle {
        var theme = Style.theme.id // redraw on a theme change — see Style.theme
        let replay: String
        static var height: CGFloat { Style.cornerFlourishHeight }

        func makeBody(configuration: Configuration) -> some View {
            AnimatedFlourish(
                tint: configuration.isPressed ? flourishPressed : flourishRest,
                play: .onceInSession(key: replay))
                .id(replay)
                .blendMode(.multiply)
                .frame(width: Self.height * AnimatedFlourish.aspect(.corner), height: Self.height)
                .contentShape(Rectangle())
        }
    }

    // MARK: The hidden page

    // Dedication, mood, and the app's few settings. Papered like the page it
    // covers, and closed by the same flourish that opened it.
    private var settingsPage: some View {
        ZStack {
            sheetColor
                .papered(.page)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { hideKeyboard() }
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 22) {
                    Text(store.displayName.isEmpty
                         ? "Juilee's personal writing pad <3"
                         : "\(store.displayName)'s personal writing pad <3")
                        .font(houseFont(16))
                        .foregroundStyle(brownInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    ThemePicker(store: store)
                }
                Spacer()
                settingsBlock
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110) // clear of the flourish
            }
        }
    }

    private var settingsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            // name — the same value onboarding collects; the hidden page reads it
            settingsRow("name") {
                HouseField(
                    text: $nameDraft, size: 13,
                    placeholder: "your name",
                    capitalization: .words,
                    onSubmit: {
                        store.setDisplayName(nameDraft)
                        hideKeyboard()
                    })
                    .frame(height: 20)
                    .settingsWell()
            }

            // Where the notes live — the app's own folder, or a folder in
            // iCloud Drive shared with the Mac. Tapping opens the Files
            // picker; the notes already here are copied into the new place.
            settingsRow("notes") {
                Button {
                    choosingFolder = true
                } label: {
                    HStack {
                        Text(store.vaultDisplay)
                            .font(houseFont(13))
                            .foregroundStyle(inkStrong)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(inkFaint)
                    }
                    .settingsWell()
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose the folder notes are kept in")
                .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                    if case .success(let folder) = result { store.useFolder(folder) }
                }
            }

            settingsRow("font") {
                Menu {
                    ForEach(Style.offeredFamilies, id: \.self) { family in
                        Button {
                            store.setFont(family)
                        } label: {
                            if family == store.fontFamily {
                                Label(family, systemImage: "checkmark")
                            } else {
                                Text(family)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(store.fontFamily)
                            .font(houseFont(13))
                            .foregroundStyle(inkStrong)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(inkFaint)
                    }
                    .settingsWell()
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    // A fixed-width label and a control filling the rest, on a card of the
    // page's own paper, a shade deeper — the same as the search cards.
    private func settingsRow<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(houseFont(12))
                .foregroundStyle(inkMuted)
                .frame(width: 44, alignment: .leading)
            content()
        }
        .padding(10)
        .background(
            PagePaper()
                .clipShape(RoundedRectangle(cornerRadius: 10))
        )
    }

    // MARK: An open sticky

    // Tap the dimmed page to put the sticky away.
    private var stickyScrim: some View {
        sheetColor.opacity(0.55)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                hideKeyboard()
                store.closeSticky()
            }
    }

    // The card centres itself and knows how tall it may grow, so a long note
    // scrolls inside the stamp rather than running off the screen.
    private func stickyCard(_ id: UUID) -> some View {
        // The whole screen down to the keyboard, so the card can centre
        // itself on the screen rather than on the safe area. A reader that
        // ignores the safe area also reports it as zero, so the status bar
        // and home indicator are read off the window instead — taking them
        // from the reader let a tall sticky climb under the clock.
        GeometryReader { geo in
            let window = Self.windowInsets
            // With the keyboard up the area already ends at its top, and the
            // home indicator is under the keyboard.
            let keyboardUp = geo.size.height < Self.windowHeight - 1
            StickyCard(store: store, id: id, area: geo.size,
                       safe: EdgeInsets(top: window.top, leading: 0,
                                        bottom: keyboardUp ? 0 : window.bottom, trailing: 0))
                .id(id)
        }
        .ignoresSafeArea(.container)
    }
}

// MARK: - A note

// The page and nothing else on it but the word count. The way back is the
// edge swipe, or the corner flourish, which goes straight home.
struct NoteScreen: View {
    @ObservedObject var store: NotesStore
    @State private var keyboardShown = false

    var body: some View {
        ZStack {
            // The paper, pinned to the screen. Grain is not something the eye
            // tracks, so a sheet that stays put while the words move over it
            // reads as a page being written on; the ruling, which the eye does
            // track, is drawn by the text view and travels with the text.
            sheetColor
                .papered(.page)
                .ignoresSafeArea()

            RichTextEditor(store: store)
                .ignoresSafeArea()
                .blur(radius: store.openStickyID != nil ? 8 : 0)
                .animation(.easeOut(duration: 0.25), value: store.openStickyID)

            if store.openStickyID == nil, !store.hiddenShown {
                Text("\(store.wordCount)")
                    .font(houseFont(14))
                    .foregroundStyle(inkFaint)
                    .accessibilityLabel("\(store.wordCount) words")
                    .padding(.trailing, 22)
                    .padding(.bottom, keyboardShown ? 14 : 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
    }
}

// The navigation bar is hidden on every screen, which by default also turns
// off the swipe from the left edge that takes you back. This turns it on
// again, everywhere but the root, where there is nowhere to go back to.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: - Icon buttons

// The page's buttons: a faint glyph on bare sheet at rest, firming up on a
// papered tile while pressed or while whatever it opens is open. 44 across
// with a 10 radius, the Mac's own size — which is also a finger's.
struct IconButton: View {
    var theme = Style.theme.id // redraw on a theme change — see Style.theme
    let systemName: String
    let label: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(IconStyle(active: active))
        .accessibilityLabel(label)
    }

    private struct IconStyle: ButtonStyle {
        var theme = Style.theme.id // redraw on a theme change — see Style.theme
        let active: Bool

        func makeBody(configuration: Configuration) -> some View {
            let raised = active || configuration.isPressed
            configuration.label
                .foregroundStyle(raised ? inkStrong : inkFaint)
                .background {
                    if raised {
                        panelColor.papered(.button)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
        }
    }
}

extension View {
    // The recessed well a settings control sits in. Deliberately not papered:
    // it is a hole in the card rather than another surface on top of it.
    func settingsWell() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(sheetColor))
    }
}
