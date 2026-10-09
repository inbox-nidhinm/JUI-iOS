import SwiftUI
import UIKit

// MARK: - House text field

// The app's only single-line field: onboarding name, settings name, search,
// folder name, folder rename. A UITextField rather than SwiftUI's TextField so
// it can take the house font through the same resolution as everything else,
// keep typewriter input (no smart quotes or dashes), and carry submit and
// end-of-editing callbacks.
//
// A tap anywhere outside the field ends its editing, as tapping away from a
// field does on the Mac. UIKit doesn't do this by itself — a tap on bare
// paper changes no responder — which is how an unnamed folder field used to
// sit there through opening a note and coming back.
//
// Its caret, selection and handles follow `tintColor`, which is the ink — the
// one element that never stops moving stays in palette, as on the Mac.
struct HouseField: UIViewRepresentable {
    var theme = Style.theme.id // redraw on a theme change — see Style.theme
    @Binding var text: String
    var size: CGFloat = 13
    var alpha: CGFloat = 1 // which step of the ink ladder the text sits at
    var centered = false
    var placeholder = ""
    // Which step of the ink ladder the placeholder sits at: inkFaint for every
    // field but search, whose prompt is the muted step.
    var placeholderAlpha: CGFloat = 0.4
    var focused = false
    var returnKey: UIReturnKeyType = .done
    var capitalization: UITextAutocapitalizationType = .sentences
    var onSubmit: () -> Void = {}
    /// Editing has ended, however it ended: Return, a tap elsewhere, or the
    /// field leaving the screen. Called with the text as it stands.
    var onEndEditing: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.delegate = context.coordinator
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.autocorrectionType = .no
        field.text = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        let font = Style.font(size)
        field.font = font
        field.textColor = Style.ink.withAlphaComponent(alpha)
        field.tintColor = Style.ink
        field.textAlignment = centered ? .center : .natural
        field.returnKeyType = returnKey
        field.autocapitalizationType = capitalization
        field.attributedPlaceholder = placeholder.isEmpty ? nil
            : NSAttributedString(string: placeholder, attributes: [
                .font: font,
                .foregroundColor: Style.ink.withAlphaComponent(placeholderAlpha),
            ])
        // Only on the false → true transition, so an update pass can't steal
        // focus back after someone has tapped away.
        if focused != context.coordinator.wantsFocus {
            context.coordinator.wantsFocus = focused
            if focused {
                DispatchQueue.main.async { field.becomeFirstResponder() }
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate, UIGestureRecognizerDelegate {
        var parent: HouseField
        var wantsFocus = false
        private weak var field: UITextField?
        private var outsideTap: UITapGestureRecognizer?

        init(_ parent: HouseField) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        // While the field is being edited, the window listens for a tap
        // outside it. The tap still goes through to whatever was tapped
        // (`cancelsTouchesInView` is off), so tapping a note both ends the
        // naming and opens the note.
        func textFieldDidBeginEditing(_ textField: UITextField) {
            field = textField
            guard outsideTap == nil, let window = textField.window else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tappedOutside))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            outsideTap = tap
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if let outsideTap { outsideTap.view?.removeGestureRecognizer(outsideTap) }
            outsideTap = nil
            // A hop later: editing can end because SwiftUI is taking the
            // field away mid-update, and the callback changes state.
            let text = textField.text ?? ""
            let end = parent.onEndEditing
            DispatchQueue.main.async { end(text) }
        }

        @objc private func tappedOutside() { field?.resignFirstResponder() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            guard let field, let view = touch.view else { return true }
            return !view.isDescendant(of: field)
        }

        // Alongside every other recogniser — it only listens.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

// MARK: - Sticky text


// The sticky card's writing surface: plain text in the house family, set a
// step below the page at 140% leading, with typewriter input and the house
// caret. The card sizes itself to the text, so this only scrolls when the
// text is longer than the screen can show.
struct StickyTextView: UIViewRepresentable {
    var theme = Style.theme.id // redraw on a theme change — see Style.theme
    @Binding var text: String
    /// True while the text is being edited — the keyboard is up for it.
    @Binding var isEditing: Bool
    var focused: Bool
    var scrolls: Bool

    static let textSize: CGFloat = 14
    static let leading: CGFloat = 1.4 // line height as a multiple of the type size
    static let inset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

    static var attributes: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        let line = (textSize * leading).rounded()
        p.minimumLineHeight = line
        p.maximumLineHeight = line
        let font = Style.font(textSize)
        return [
            .font: font, .foregroundColor: Style.ink, .paragraphStyle: p,
            // A fixed line puts its extra height above the glyphs; this
            // centres the type in its line instead.
            .baselineOffset: (line - font.lineHeight) / 2,
        ]
    }

    /// How tall `text` sets at `width`, insets included — what the card
    /// measures to size itself.
    ///
    /// Laid out by the same engine the view uses (TextKit 1, no fragment
    /// padding), not by `boundingRect`: that ignores the fixed line height
    /// and came out a fifth short, which left the card square while the text
    /// ran on below it.
    static func height(of text: String, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(string: text, attributes: attributes)
        let lm = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(lm)
        lm.addTextContainer(container)
        lm.ensureLayout(for: container)
        // The extra fragment is the empty line after a trailing newline, or
        // the only line of an empty sticky — a line to write on either way.
        let extra = lm.extraLineFragmentRect
        let height = max(lm.usedRect(for: container).maxY, extra.isEmpty ? 0 : extra.maxY)
        return ceil(height) + inset.top + inset.bottom
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> StickyCaretTextView {
        // TextKit 1, so it lays out exactly as `height(of:width:)` measures —
        // assembled by hand, as the note editor's is. Not through UIKit's
        // `init(usingTextLayoutManager:)`, which skips a Swift subclass's
        // property setup: the fade mask was never made, and the first layout
        // crashed on it.
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(lm)
        lm.addTextContainer(container)
        let tv = StickyCaretTextView(frame: .zero, textContainer: container)
        tv.retainedStorage = storage
        tv.accessibilityIdentifier = "sticky-text"
        tv.showsVerticalScrollIndicator = false
        tv.backgroundColor = .clear
        tv.isOpaque = false
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.textContainerInset = Self.inset
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.attributedText = NSAttributedString(string: text, attributes: Self.attributes)
        tv.typingAttributes = Self.attributes
        return tv
    }

    // Exactly the size it is offered. Without this SwiftUI sizes the view
    // from its intrinsic size, which for a text view that doesn't scroll is
    // one unbroken line — the text ran straight out of both sides of the stamp.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StickyCaretTextView,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: proposal.height ?? 120)
    }

    func updateUIView(_ tv: StickyCaretTextView, context: Context) {
        context.coordinator.parent = self
        let attrs = Self.attributes
        if tv.text != text || context.coordinator.themeID != Style.theme.id
            || context.coordinator.family != Style.fontFamily {
            context.coordinator.themeID = Style.theme.id
            context.coordinator.family = Style.fontFamily
            let selection = tv.selectedRange
            tv.attributedText = NSAttributedString(string: text, attributes: attrs)
            tv.selectedRange = selection
        }
        tv.typingAttributes = attrs
        tv.tintColor = Style.ink
        tv.smoothCaret.applyTheme()
        tv.isScrollEnabled = scrolls
        if scrolls, tv.isFirstResponder {
            tv.scrollRangeToVisible(tv.selectedRange)
        }
        if focused, !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StickyTextView
        var didFocus = false
        var themeID = Style.theme.id
        var family = Style.fontFamily
        init(_ parent: StickyTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            (textView as? CaretTextView)?.caretMoved()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? CaretTextView)?.caretMoved()
        }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.isEditing = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.isEditing = false }
    }
}

/// The sticky's text view: the house caret, and soft edges when a note too
/// long for the screen scrolls inside its stamp.
final class StickyCaretTextView: CaretTextView {
    var retainedStorage: NSTextStorage? // manual TextKit 1 setup: keep the storage alive
    private let fade = EdgeFade()
    static let fadeBand: CGFloat = 20

    // Not while it is being written in: a line fading out under the caret
    // reads as the words disappearing as they are typed.
    override func layoutSubviews() {
        super.layoutSubviews()
        if isFirstResponder {
            if layer.mask != nil { layer.mask = nil }
        } else {
            if layer.mask !== fade.layer { layer.mask = fade.layer }
            fade.update(in: self, band: Self.fadeBand)
        }
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        setNeedsLayout()
        return ok
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        setNeedsLayout()
        return ok
    }
}

// MARK: - The sticky card

/// The postage stamp, as a SwiftUI shape: fill it with `eoFill` so the
/// perforations are punched out.
struct StampShape: Shape {
    var radius: CGFloat = 4
    var pitch: CGFloat = 15
    var cornerGap: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        Path(StampOutline.path(in: rect, radius: radius, pitch: pitch, cornerGap: cornerGap).cgPath)
    }
}

// An open sticky: the Mac's margin stamp, brought to the middle of the page
// because a phone has no margin to hold it. Sticky colour, sticky paper, the
// flourish pressed into the bottom-right corner and run off its edge.
//
// It is square at least, and grows to show everything written on it — opened
// to be read, it shows the whole note without a keyboard. The keyboard comes
// up when the text is tapped, or straight away for a sticky just made, which
// has nothing to read yet. Taller than the screen allows, it stops growing
// and its text scrolls instead.
struct StickyCard: View {
    @ObservedObject var store: NotesStore
    let id: UUID
    /// The whole screen above the keyboard, safe areas included, and those
    /// safe areas — the card places itself in it.
    var area: CGSize
    var safe: EdgeInsets
    @State private var draft: String
    @State private var startsEditing = false
    @State private var editing = false

    // The words are there from the card's very first frame. Read in on
    // appearing, the card's first frame was an empty square that then grew
    // to its text — a jolt right where the crumpled sheet hands over to it.
    init(store: NotesStore, id: UUID, area: CGSize, safe: EdgeInsets) {
        self.store = store
        self.id = id
        self.area = area
        self.safe = safe
        _draft = State(initialValue: store.stickies.first(where: { $0.id == id })?.text ?? "")
    }

    static let side: CGFloat = 280
    static let textTop: CGFloat = 18
    static let textSides: CGFloat = 20

    // The flourish, as fractions of the stamp's *width*. Smaller than the
    // Mac's 0.40 — at that size its blooms reached up into the last lines of
    // writing — and kept to the same right-hand overhang.
    static let flourishWidth: CGFloat = 0.30
    static let flourishRight: CGFloat = 1.0315 // where its right edge lands
    static let flourishOverhang: CGFloat = 0.0575 // past the foot
    // Clear paper between the last line and the top of the flourish.
    static let flourishGap: CGFloat = 18

    static var flourishHeight: CGFloat {
        side * flourishWidth / max(AnimatedFlourish.aspect(.sticky), 0.01)
    }

    // The part of the flourish that sits on the stamp; the rest runs off it.
    static var flourishOnStamp: CGFloat {
        flourishHeight - side * flourishOverhang
    }

    static var textWidth: CGFloat { side - textSides * 2 }

    static func textHeight(cardHeight: CGFloat) -> CGFloat {
        cardHeight - textTop - flourishGap - flourishOnStamp
    }

    private var side: CGFloat { Self.side }
    private var textWidth: CGFloat { Self.textWidth }

    // MARK: Placing the stamp
    //
    // The stamp is centred on the screen — the screen, not the safe area,
    // whose top is a good deal deeper than its foot, and not the stamp and its
    // buttons together, which sat it a row too high. The buttons hang below
    // it. It moves off centre only as far as it must: below the status bar,
    // and high enough over a keyboard for the buttons to fit under it.
    // Clear air between the stamp and the status bar (and the keyboard, and
    // the home indicator) — enough that a tall stamp never reads as tucked
    // under the camera.
    private static let margin: CGFloat = 20
    // Opened to read, a stamp that fits is dead centre on the screen, and a
    // tall one keeps well clear of the top — `readingTopClearance` more than
    // the margin — growing down from there instead. While it is written in it
    // sits a little below centre in the room the keyboard leaves, and keeps
    // that place.
    private static let readingDrop: CGFloat = 0
    private static let editingDrop: CGFloat = 24
    private static let readingTopClearance: CGFloat = 60
    private static let buttonGap: CGFloat = 14
    private static var buttonsBand: CGFloat { buttonGap + StampButton.side }

    /// Where the stamp sits for `text` — worked out here rather than in the
    /// body so the crumpled sheet can open out into exactly its place before
    /// the card is there (see Crumple.swift).
    static func stampFrame(text: String, area: CGSize, safe: EdgeInsets, editing: Bool) -> CGRect {
        let minTop = safe.top + margin + (editing ? 0 : readingTopClearance)
        let maxBottom = area.height - safe.bottom - margin
        let wanted = textTop + StickyTextView.height(of: text, width: textWidth) + flourishGap + flourishOnStamp
        let tallest = maxBottom - minTop - buttonsBand
        let height = min(max(side, wanted), max(side * 0.6, tallest))
        let centred = (area.height - height) / 2 + (editing ? editingDrop : readingDrop)
        let top = min(max(centred, minTop), maxBottom - buttonsBand - height)
        return CGRect(x: (area.width - side) / 2, y: top, width: side, height: height)
    }

    private var textHeight: CGFloat { Self.textHeight(cardHeight: stampFrame.height) }

    private var stampFrame: CGRect {
        Self.stampFrame(text: draft, area: area, safe: safe, editing: editing)
    }

    var body: some View {
        let frame = stampFrame
        let height = frame.height
        let scrolls = StickyTextView.height(of: draft, width: textWidth) > textHeight + 0.5
        let top = frame.minY
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                stickyColor
                    .papered(.sticky)
                    .overlay(alignment: .topLeading) {
                        // Draws itself on every time the stamp is opened. The
                        // card is made fresh for each opening — only once the
                        // crumpled sheet has opened out flat, so the drawing
                        // starts after the unfold — and stays the same view
                        // while it is open, so typing, growing and the
                        // keyboard don't restart it.
                        AnimatedFlourish(set: .sticky, tint: panelColor, play: .always)
                            .frame(width: side * Self.flourishWidth, height: Self.flourishHeight)
                            .offset(x: side * (Self.flourishRight - Self.flourishWidth),
                                    y: height - Self.flourishOnStamp)
                            // drawn *through* the gold, not onto it
                            .blendMode(.multiply)
                    }
                    .compositingGroup()
                    .clipShape(StampShape(), style: FillStyle(eoFill: true))
                    .frame(width: side, height: height)

                StickyTextView(text: $draft, isEditing: $editing,
                               focused: startsEditing, scrolls: scrolls)
                    .frame(width: textWidth, height: textHeight)
                    .offset(x: Self.textSides, y: Self.textTop)
            }
            .frame(width: side, height: height)
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .offset(x: (area.width - side) / 2, y: top)

            // Only while writing. A sticky opened to be read is just the
            // stamp; tapping the page around it puts it away. While hidden the
            // buttons are gone, not merely transparent — VoiceOver would still
            // find invisible buttons. They hang below the stamp rather than
            // being laid out with it, so they don't move it.
            ZStack {
                if editing {
                    HStack(spacing: StampButton.gap) {
                        StampButton(kind: .delete) { store.removeSticky(id) }
                        StampButton(kind: .done) { commitAndClose() }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: area.width, height: StampButton.side)
            .offset(y: top + height + Self.buttonGap)
            .animation(.easeOut(duration: 0.15), value: editing)
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
        // Grows with the text and steps up for the keyboard, smoothly.
        .animation(.easeOut(duration: 0.2), value: height)
        .animation(.easeOut(duration: 0.25), value: editing) // reading ↔ writing place
        .animation(.easeOut(duration: 0.25), value: area.height)
        // The sheet that takes over from the card when it is put away starts
        // from wherever the card last was.
        .onChange(of: frame, initial: true) { _, frame in CrumpleDirector.shared.cardFrame = frame }
        .onAppear {
            draft = store.stickies.first(where: { $0.id == id })?.text ?? ""
            // A sticky with nothing on it was just made: straight to writing.
            startsEditing = draft.isEmpty
        }
        .onChange(of: draft) { _, new in
            store.updateStickyText(id, new)
            CrumpleDirector.shared.textChanged(new)
        }
    }

    private func commitAndClose() {
        hideKeyboard()
        store.updateStickyText(id, draft)
        store.closeSticky()
    }
}

// MARK: - The stamp's buttons

// Delete and done: the hand-drawn marks from the Figma system (node 330:433),
// on a faint tile — the system draws them on a papered panel tile, which was
// too heavy beside the stamp, so this is a tone instead. The marks ship as the system's own
// vectors, in pieces placed exactly where the frame places them, and are
// tinted at draw time — the design draws them in #967654, which is the ink's
// muted step (see mac-reference/CLAUDE.md, "Where the system and the ink
// ladder disagree"), so they follow every theme as the ink does.
//
// The system's tile is 60, and the app scales the system by 16/22 — the Mac's
// own icon buttons are 44 for the same reason — so the marks are laid out in
// the system's units and multiplied by `scale`.
struct StampButton: View {
    var theme = Style.theme.id // redraw on a theme change — see Style.theme
    enum Kind { case delete, done }

    let kind: Kind
    let action: () -> Void

    static let side: CGFloat = 44
    static var scale: CGFloat { side / 60 }
    // Wider than the system's 17 (scaled to 12.5), so the two marks read as
    // two choices rather than a pair.
    static let gap: CGFloat = 28

    /// One piece of a mark: its asset and where its frame sits in the
    /// system's 60 × 60 tile — the frame being the SVG's own box, which runs
    /// past the stroke it carries.
    private struct Piece {
        let asset: String
        let frame: CGRect
    }

    private var pieces: [Piece] {
        switch kind {
        case .delete:
            return [
                Piece(asset: "StickyTrashRim", frame: CGRect(x: 15.754, y: 18.548, width: 29.1716, height: 4.52117)),
                Piece(asset: "StickyTrashHandle", frame: CGRect(x: 23.573, y: 14.173, width: 13.9999, height: 7.36518)),
                Piece(asset: "StickyTrashBody", frame: CGRect(x: 17.911, y: 19.511, width: 23.4676, height: 25.6018)),
                Piece(asset: "StickyTrashLineLeft", frame: CGRect(x: 25.158, y: 26.295, width: 4.73735, height: 11.6757)),
                Piece(asset: "StickyTrashLineRight", frame: CGRect(x: 30.979, y: 25.355, width: 4.22164, height: 12.0327)),
            ]
        case .done:
            return [
                Piece(asset: "StickyCheck", frame: CGRect(x: 14.977, y: 15.205, width: 29.9354, height: 27.8646)),
            ]
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                ForEach(pieces, id: \.asset) { piece in
                    Image(piece.asset)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: piece.frame.width * Self.scale,
                               height: piece.frame.height * Self.scale)
                        .offset(x: piece.frame.minX * Self.scale,
                                y: piece.frame.minY * Self.scale)
                }
            }
            .foregroundStyle(inkMuted)
            .frame(width: Self.side, height: Self.side, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 14 * Self.scale))
        }
        .buttonStyle(Press())
        .accessibilityLabel(kind == .delete ? "Delete sticky note" : "Done")
    }

    // A faint tile behind each mark: a tone, not a colour — black at 6% is a
    // multiply by 0.94, so it is a soft step down from whatever it sits on in
    // every theme, much lighter than the system's papered panel tile. Under
    // the finger the mark settles a little.
    static let tileTone = Color.black.opacity(0.06)

    private struct Press: ButtonStyle {
        var theme = Style.theme.id // redraw on a theme change — see Style.theme
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 14 * StampButton.scale)
                        .fill(StampButton.tileTone))
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
