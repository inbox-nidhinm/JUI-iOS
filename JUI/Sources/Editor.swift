import SwiftUI
import UIKit

// MARK: - The ruling

// The ruled page, drawn as hairlines in a layer that sits beneath the text and
// covers only what is on screen. It is re-pathed on every scroll tick, which
// costs a couple of dozen line segments; covering the whole document instead
// would mean a backing store as tall as the note.
//
// The grid is anchored to the top of the text container and to nothing else —
// never to a line fragment, whose height is not the pitch and which moves as
// you type. Derived from the container, every repaint agrees with every other.
final class RulingView: UIView {
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shape.fillColor = nil
        shape.lineWidth = 1
        shape.strokeColor = Style.ruleTone.cgColor
        layer.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    /// `visible` is the text view's bounds — the on-screen slice of the
    /// document, in document coordinates — and this view is placed over it.
    func update(visible: CGRect, anchor: CGFloat, left: CGFloat, right: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = visible
        shape.frame = bounds
        let pitch = Style.linePitch
        let path = CGMutablePath()
        if pitch > 1, right > left {
            // Start at the first rule at or above the visible slice.
            let steps = max(0, ((visible.minY - anchor) / pitch).rounded(.down))
            var y = anchor + steps * pitch
            while y <= visible.maxY + 1 {
                if y >= visible.minY - 1 {
                    let py = Style.ruleY(y) - visible.minY
                    path.move(to: CGPoint(x: left, y: py))
                    path.addLine(to: CGPoint(x: right, y: py))
                }
                y += pitch
            }
        }
        shape.path = path
        CATransaction.commit()
    }
}

// MARK: - The sticky wash

// Words with a sticky attached carry a faint wash of the sticky's colour, like
// a highlighter run over them — the margin stamp says *that* there is a note,
// the wash says *which words* it is about.
//
// Drawn in its own layer beneath the text, never as a background attribute in
// the storage: an attribute would be written into the RTF, and the storage's
// safety net strips background colours anyway. Bands are sized and placed
// exactly as the selection's are — the ink box plus air, centred in the ruled
// band — so a wash and a selection over the same words are the same shape.
final class StickyWashView: UIView {
    private let shape = CAShapeLayer()

    // A tint, not a fill: at a quarter the sticky colour is unmistakably the
    // sticky's, and the ink and the ruling read straight through it.
    static let alpha: CGFloat = 0.26

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    /// `bands` are in document coordinates; `visible` is the on-screen slice.
    func update(visible: CGRect, bands: [CGRect]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = visible
        shape.frame = bounds
        shape.fillColor = Style.theme.sticky.withAlphaComponent(Self.alpha).cgColor
        let path = CGMutablePath()
        for band in bands where band.intersects(visible) {
            path.addRoundedRect(
                in: band.offsetBy(dx: 0, dy: -visible.minY),
                cornerWidth: 3, cornerHeight: 3)
        }
        shape.path = path
        CATransaction.commit()
    }
}

// MARK: - Sticky marks

// A sticky, on the phone, is a small crumpled ball of sticky paper tucked
// into the line right after the words it is about, with the sentence running
// on after it. There is no room for the Mac's 172pt margin notes; the ball is
// the sticky put away, and tapping it opens it out into the card
// (Crumple.swift). The room it sits in is made by `BallRoom`.
//
// The view is larger than the ball it draws, so a finger can find it.
final class StickyMarkView: UIView {
    let stickyID: UUID
    var onTap: (() -> Void)?

    static let hitSize = CGSize(width: 30, height: 40)

    init(id: UUID) {
        stickyID = id
        super.init(frame: CGRect(origin: .zero, size: Self.hitSize))
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "Sticky note"
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    @objc private func tapped() { onTap?() }

    func applyTheme() { setNeedsDisplay() }

    // The same crumpled sheet the opening starts from, rendered once per mood.
    override func draw(_ rect: CGRect) {
        guard let ball = CrumpleArt.marginBall() else { return }
        ball.draw(in: CGRect(x: (bounds.width - ball.size.width) / 2,
                             y: (bounds.height - ball.size.height) / 2,
                             width: ball.size.width, height: ball.size.height))
    }
}

// The room for each ball in the line. The note's text can't change — it is
// the file the Mac reads too — so the room is made in layout alone: the space
// after a sticky's words is laid out wide, as one space, the ball's slot and
// one more space, and the ball is drawn in it. The layout manager's delegate
// does this by treating that one space as a control glyph of its own width.
//
// Where the words end a line or the note, with no space after them to widen,
// the ball sits just past them and nothing moves.
final class BallRoom: NSObject, NSLayoutManagerDelegate {
    /// Widened spaces: character index → how many balls sit in it.
    var slots: [Int: Int] = [:]

    /// The ball's slot in the line, a little wider than the 24pt ball.
    static let slot: CGFloat = 30

    static var space: CGFloat {
        (" " as NSString).size(withAttributes: [.font: Style.baseFont]).width
    }

    static func width(for balls: Int) -> CGFloat { space * 2 + slot * CGFloat(balls) }

    /// Where a sticky's ball goes: the first whitespace at or after the end
    /// of its words (trailing spaces in the anchor don't count, and a
    /// half-selected word is finished first) — or the end of the text.
    static func spot(for sticky: Sticky, in text: NSString) -> Int {
        let length = text.length
        var end = min(max(sticky.start + sticky.length, 0), length)
        let start = min(max(sticky.start, 0), length)
        while end > start, isBlank(text.character(at: end - 1)) { end -= 1 }
        while end < length, !isBlank(text.character(at: end)) { end += 1 }
        return end
    }

    /// A space that can be widened to hold the ball.
    static func widens(_ c: unichar) -> Bool { c == 0x20 || c == 0xA0 }

    private static func isBlank(_ c: unichar) -> Bool {
        c == 0x20 || c == 0xA0 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
    }

    /// Moves the slots through an edit, as the anchors move, so the glyphs
    /// laid out for the edit agree with them. Slots inside the edit go: their
    /// text is laid out afresh, and the page works out the new ones after.
    func shift(edit: NSRange, replacementLength: Int) {
        let delta = replacementLength - edit.length
        var moved: [Int: Int] = [:]
        for (c, n) in slots {
            if c >= edit.location + edit.length { moved[c + delta] = n }
            else if c < edit.location { moved[c] = n }
        }
        slots = moved
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>, font aFont: UIFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !slots.isEmpty,
              (0..<glyphRange.length).contains(where: { slots[charIndexes[$0]] != nil })
        else { return 0 }
        let marked = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: glyphRange.length)
        defer { marked.deallocate() }
        for i in 0..<glyphRange.length {
            marked[i] = slots[charIndexes[i]] != nil ? .controlCharacter : props[i]
        }
        layoutManager.setGlyphs(glyphs, properties: marked, characterIndexes: charIndexes,
                                font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        slots[charIndex] != nil ? .whitespace : action
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer, proposedLineFragment proposedRect: CGRect,
        glyphPosition: CGPoint, characterIndex charIndex: Int
    ) -> CGRect {
        CGRect(x: glyphPosition.x, y: 0,
               width: Self.width(for: slots[charIndex] ?? 1), height: proposedRect.height)
    }
}

/// The postage-stamp outline shared by the margin mark and the card: the
/// rectangle with semicircular perforations, evenly distributed for whatever
/// size it is. Fill it even-odd, clipped to `rect`.
enum StampOutline {
    static func path(in rect: CGRect, radius: CGFloat = 4, pitch: CGFloat = 15,
                     cornerGap: CGFloat = 6) -> UIBezierPath {
        let path = UIBezierPath(rect: rect)
        func punch(along length: CGFloat, _ point: (CGFloat) -> CGPoint) {
            let usable = length - cornerGap * 2
            guard usable >= pitch else { return }
            let count = max(1, Int((usable / pitch).rounded()))
            let step = usable / CGFloat(count)
            for i in 0..<count {
                let c = point(cornerGap + (CGFloat(i) + 0.5) * step)
                path.append(UIBezierPath(ovalIn: CGRect(
                    x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)))
            }
        }
        punch(along: rect.width) { CGPoint(x: rect.minX + $0, y: rect.minY) }
        punch(along: rect.width) { CGPoint(x: rect.minX + $0, y: rect.maxY) }
        punch(along: rect.height) { CGPoint(x: rect.minX, y: rect.minY + $0) }
        punch(along: rect.height) { CGPoint(x: rect.maxX, y: rect.minY + $0) }
        return path
    }
}

// MARK: - Selection rects sized off the ink

// UIKit draws the selection and its handles from the rects the text view
// reports, so the ink-box sizing the Mac does in its layout manager is done
// here, by reporting different rects.
final class InkSelectionRect: UITextSelectionRect {
    private let base: UITextSelectionRect
    private let inkRect: CGRect
    private let start: Bool
    private let end: Bool

    init(base: UITextSelectionRect, rect: CGRect, start: Bool, end: Bool) {
        self.base = base
        self.inkRect = rect
        self.start = start
        self.end = end
        super.init()
    }

    override var rect: CGRect { inkRect }
    override var writingDirection: NSWritingDirection { base.writingDirection }
    override var containsStart: Bool { start }
    override var containsEnd: Bool { end }
    override var isVertical: Bool { base.isVertical }
}

// MARK: - The text view

final class RuledTextView: CaretTextView {
    weak var notesStore: NotesStore?
    var retainedStorage: NSTextStorage? // manual TextKit 1 setup: keep the storage alive

    private let ruling = RulingView()
    private let wash = StickyWashView()
    private var stickyMarks: [UUID: StickyMarkView] = [:]
    /// The layout manager's delegate: room in the line for each ball.
    let ballRoom = BallRoom()

    // The page runs under the status bar, and the words must not: they fade
    // out as they reach it, and are gone beneath the clock. At the foot they
    // fade too, at the screen's edge or the keyboard's, whenever there is
    // more note below. See EdgeFade.
    private let fade = EdgeFade()
    static let fadeBand: CGFloat = 56

    // Bottom clearance for whatever floats over the page's foot: the controls
    // and the corner flourish at rest, the controls alone above a keyboard.
    var keyboardOverlap: CGFloat = 0 { didSet { if keyboardOverlap != oldValue { updateInsets() } } }
    // Enough that the end of a note stops above where the fade begins: the
    // flourish, plus its lift, plus the clear band above it.
    static var restingClearance: CGFloat {
        Style.cornerFlourishLift + Style.cornerFlourishHeight + Style.cornerFlourishClearance + 12
    }
    static let keyboardClearance: CGFloat = 64

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        insertSubview(wash, at: 0)
        insertSubview(ruling, at: 0)
        layer.mask = fade.layer
        showsVerticalScrollIndicator = false
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Kept beneath whatever UIKit adds for the text itself: the ruling at
        // the bottom, the wash on it, the words over both.
        if subviews.count < 2 || subviews[0] !== ruling || subviews[1] !== wash {
            sendSubviewToBack(wash)
            sendSubviewToBack(ruling)
        }
        let anchor = textContainerInset.top - Style.lineSpacing / 2
        let padding = textContainer.lineFragmentPadding
        ruling.update(
            visible: bounds, anchor: anchor,
            left: textContainerInset.left + padding - Style.ruleOverhang,
            right: bounds.width - textContainerInset.right - padding + Style.ruleOverhang)
        // Words are gone by the bottom of the status bar and fully back a
        // little below the clear band under it, so nothing scrolls up under it
        // at full strength.
        // At the foot, with the keyboard up, the words are gone by its top,
        // when there is more note below. Without it they are always gone by
        // the top of the corner flourish, starting to fade a clear band above
        // it — wherever the note is scrolled to, text running over the
        // flourish read as a mistake.
        let flourishTop = bounds.height - screenInsets.bottom
            - Style.cornerFlourishLift - Style.cornerFlourishHeight
        let foot = keyboardOverlap > 0 ? bounds.height - keyboardOverlap : flourishTop
        let footBand = keyboardOverlap > 0 ? Self.fadeBand : Style.cornerFlourishClearance
        fade.update(in: self,
                    hiddenTop: screenInsets.top + Style.backBand - Self.fadeBand,
                    bottomEdge: foot,
                    band: Self.fadeBand,
                    bottomBand: footBand,
                    bottomAlways: keyboardOverlap == 0)
        syncStickies()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateInsets()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateInsets()
    }

    /// The status bar and home indicator, read off the window. Not the view's
    /// own safe area: while a sticky is open SwiftUI blurs the page, and the
    /// blur hosts it somewhere that reports no safe area at all — the top
    /// inset fell to zero, and the words jumped up a band under the sticky
    /// and back down as it closed.
    private var screenInsets: UIEdgeInsets { window?.safeAreaInsets ?? safeAreaInsets }

    // The page runs under the status bar and the home indicator, so the insets
    // are worked out here rather than left to automatic adjustment, which
    // would count the home indicator twice once the keyboard is up.
    func updateInsets() {
        let bottom = keyboardOverlap > 0
            ? keyboardOverlap + Self.keyboardClearance
            : screenInsets.bottom + Self.restingClearance
        let insets = UIEdgeInsets(top: screenInsets.top, left: 0, bottom: bottom, right: 0)
        if contentInset != insets {
            contentInset = insets
            verticalScrollIndicatorInsets = UIEdgeInsets(
                top: screenInsets.top, left: 0,
                bottom: keyboardOverlap > 0 ? keyboardOverlap : screenInsets.bottom, right: 0)
        }
    }

    // MARK: Where lines are

    /// The top of the line fragment holding `point`, in view coordinates.
    private func lineTop(near point: CGPoint) -> CGFloat? {
        let lm = layoutManager
        let local = CGPoint(x: max(point.x - textContainerInset.left, 0),
                            y: point.y - textContainerInset.top)
        let extra = lm.extraLineFragmentRect
        if !extra.isEmpty, local.y >= extra.minY - 0.5 {
            return extra.minY + textContainerInset.top
        }
        guard lm.numberOfGlyphs > 0 else {
            return extra.isEmpty ? nil : extra.minY + textContainerInset.top
        }
        let glyph = lm.glyphIndex(for: local, in: textContainer)
        return lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            + textContainerInset.top
    }

    /// The top of the line holding character `index`, in view coordinates.
    func lineTop(forCharacterAt index: Int) -> CGFloat {
        let lm = layoutManager
        let length = textStorage.length
        let extra = lm.extraLineFragmentRect
        if length == 0 || lm.numberOfGlyphs == 0 {
            return (extra.isEmpty ? 0 : extra.minY) + textContainerInset.top
        }
        if index >= length,
           (textStorage.string as NSString).character(at: length - 1) == 0x0A,
           !extra.isEmpty {
            return extra.minY + textContainerInset.top
        }
        let glyph = lm.glyphIndexForCharacter(at: min(max(index, 0), length - 1))
        return lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            + textContainerInset.top
    }

    // MARK: Caret and selection, sized off the ink box

    // The caret is the ink's height plus a little overshoot, wherever it is.
    // UIKit's own rect is the line's; on a 48pt band most of that is leading,
    // and the caret would hang below the letters toward the next line.
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard rect.height > 0, !rect.isInfinite, !rect.isNull,
              let top = lineTop(near: CGPoint(x: rect.minX, y: rect.midY)) else { return rect }
        rect.origin.y = top + Style.inkOffset - Style.caretOvershoot
        rect.size.height = Style.inkHeight + Style.caretOvershoot * 2
        return rect
    }

    // One band per line, centred in the ruled band rather than on the ink —
    // the ruling centres the font's line height, which is not symmetric about
    // its ink. And one rect is not one line: a rect UIKit reports may cover
    // several, so the lines inside it are asked of the layout manager rather
    // than assumed. Horizontal extent still comes from UIKit.
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        let rects = super.selectionRects(for: range)
        guard !rects.isEmpty else { return rects }
        let lm = layoutManager
        let start = offset(from: beginningOfDocument, to: range.start)
        let end = offset(from: beginningOfDocument, to: range.end)
        guard end > start else { return rects }
        let glyphs = lm.glyphRange(
            forCharacterRange: NSRange(location: start, length: end - start),
            actualCharacterRange: nil)
        var lineTops: [CGFloat] = []
        lm.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in
            lineTops.append(fragment.minY + self.textContainerInset.top)
        }
        let height = Style.inkHeight + Style.selectionPadding * 2
        var out: [UITextSelectionRect] = []
        for base in rects {
            let r = base.rect
            guard r.width > 0 || base.containsStart || base.containsEnd else { continue }
            let covered = lineTops.filter { $0 >= r.minY - 1 && $0 < r.maxY - 1 }
            let tops = covered.isEmpty ? [lineTop(near: CGPoint(x: r.minX, y: r.midY)) ?? r.minY] : covered
            for (i, top) in tops.enumerated() {
                let band = CGRect(x: r.minX, y: Style.ruledCentre(forLineTop: top) - height / 2,
                                  width: r.width, height: height)
                out.append(InkSelectionRect(
                    base: base, rect: band,
                    start: base.containsStart && i == 0,
                    end: base.containsEnd && i == tops.count - 1))
            }
        }
        return out
    }

    // MARK: Italics

    // Bold and underline are not part of this page; italics are, as on the
    // Mac. The system's Format menu is off (allowsEditingTextAttributes is
    // false, which also makes every paste plain), so italics arrive through
    // the edit menu and ⌘I on a hardware keyboard.
    override var keyCommands: [UIKeyCommand]? {
        let italic = UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(italicize(_:)))
        italic.discoverabilityTitle = "Italic"
        return (super.keyCommands ?? []) + [italic]
    }

    @objc func italicize(_ sender: Any?) {
        let range = selectedRange
        if range.length == 0 {
            var attrs = typingAttributes
            let font = (attrs[.font] as? UIFont) ?? Style.baseFont
            attrs[.font] = Style.italic(font, !Style.isItalic(font))
            typingAttributes = attrs
            return
        }
        var allItalic = true
        var before: [(UIFont, NSRange)] = []
        textStorage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? UIFont) ?? Style.baseFont
            before.append((font, sub))
            if !Style.isItalic(font) { allItalic = false }
        }
        setFonts(before.map { (Style.italic($0.0, !allItalic), $0.1) }, undoing: before)
    }

    private func setFonts(_ fonts: [(UIFont, NSRange)], undoing previous: [(UIFont, NSRange)]) {
        undoManager?.registerUndo(withTarget: self) { tv in
            tv.setFonts(previous, undoing: fonts)
        }
        undoManager?.setActionName("Italic")
        // Applied after the walk, inside one edit — writing from inside an
        // enumeration can merge runs and reshape the ranges being walked.
        textStorage.beginEditing()
        for (font, range) in fonts { textStorage.addAttribute(.font, value: font, range: range) }
        textStorage.endEditing()
        delegate?.textViewDidChange?(self)
    }

    // MARK: Theme and font

    // Recolour everything UIKit owns, in place. The ink is baked into the
    // storage's attributes, so it is rewritten — as an attribute-only edit that
    // leaves the selection, scroll position and undo stack alone.
    func applyTheme() {
        if textStorage.length > 0 {
            textStorage.beginEditing()
            textStorage.addAttribute(
                .foregroundColor, value: Style.ink,
                range: NSRange(location: 0, length: textStorage.length))
            textStorage.endEditing()
            // Hand the store the recoloured text — not as an edit, so the
            // note isn't rewritten and doesn't move up the list — and not on
            // this turn: we are inside a SwiftUI update pass.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.notesStore?.textRecoloured(self.attributedText)
            }
        }
        var attrs = typingAttributes
        attrs[.foregroundColor] = Style.ink
        typingAttributes = attrs
        tintColor = Style.ink // selection and handles
        smoothCaret.applyTheme()
        stickyMarks.values.forEach { $0.applyTheme() }
    }

    // MARK: Stickies

    func syncStickies() {
        guard let store = notesStore else { return }
        let list = store.stickies
        for (id, view) in stickyMarks where !list.contains(where: { $0.id == id }) {
            view.removeFromSuperview()
            stickyMarks[id] = nil
        }
        let length = textStorage.length
        let size = StickyMarkView.hitSize
        let text = textStorage.string as NSString
        let sorted = list.sorted(by: { $0.start < $1.start })

        // Make room in the line for each ball: the spaces to widen, and how
        // many balls each holds. Only what changed is laid out again.
        var spots: [UUID: Int] = [:]
        var room: [Int: Int] = [:]
        for sticky in sorted {
            let at = BallRoom.spot(for: sticky, in: text)
            spots[sticky.id] = at
            if at < length, BallRoom.widens(text.character(at: at)) { room[at, default: 0] += 1 }
        }
        if room != ballRoom.slots {
            let changed = Set(room.keys).union(ballRoom.slots.keys).filter { $0 < length }
            ballRoom.slots = room
            for c in changed {
                let r = NSRange(location: c, length: 1)
                layoutManager.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
                layoutManager.invalidateLayout(forCharacterRange: r, actualCharacterRange: nil)
            }
            setNeedsDisplay()
        }

        var perSpot: [Int: Int] = [:]
        var bands: [CGRect] = []
        for sticky in sorted {
            let mark = stickyMarks[sticky.id] ?? {
                let m = StickyMarkView(id: sticky.id)
                m.onTap = { [weak self] in
                    self?.resignFirstResponder()
                    self?.notesStore?.openStickyID = sticky.id
                }
                addSubview(m)
                stickyMarks[sticky.id] = m
                return m
            }()
            bands += washBands(for: sticky, length: length)
            // In the room after the words: one space in, then each ball of
            // the stickies that end here in its own slot.
            let at = spots[sticky.id] ?? length
            let nth = perSpot[at, default: 0]
            perSpot[at] = nth + 1
            let (edge, top) = ballEdge(at: at)
            let centreX = min(edge + BallRoom.space + BallRoom.slot * (CGFloat(nth) + 0.5),
                              bounds.width - CGFloat(CrumpleSheet.ballDiameter) / 2 - 4)
            let centreY = Style.ruledCentre(forLineTop: top)
            mark.frame = CGRect(x: centreX - size.width / 2, y: centreY - size.height / 2,
                                width: size.width, height: size.height)
        }
        wash.update(visible: bounds, bands: bands)
        showFlight()
    }

    /// Where the room for a ball starts — the left edge of the widened space,
    /// or just past the words where there is none — and its line's top, in
    /// view coordinates.
    private func ballEdge(at index: Int) -> (CGFloat, CGFloat) {
        let lm = layoutManager
        let length = textStorage.length
        guard length > 0, lm.numberOfGlyphs > 0 else {
            return (textContainerInset.left, lineTop(forCharacterAt: 0))
        }
        if index < length {
            let glyph = lm.glyphIndexForCharacter(at: index)
            let line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let x = line.minX + lm.location(forGlyphAt: glyph).x
            return (textContainerInset.left + x, line.minY + textContainerInset.top)
        }
        let last = lm.numberOfGlyphs - 1
        let line = lm.lineFragmentRect(forGlyphAt: last, effectiveRange: nil)
        let box = lm.boundingRect(forGlyphRange: NSRange(location: last, length: 1), in: textContainer)
        return (textContainerInset.left + box.maxX, line.minY + textContainerInset.top)
    }

    /// The ball of the sticky that is out — opening, open, or on its way
    /// back — is the one in the air, not the one in the margin.
    func showFlight() {
        let flying = CrumpleDirector.shared.flyingID
        for (id, mark) in stickyMarks { mark.isHidden = id == flying }
    }

    /// Where `id`'s ball sits, in screen points.
    func markCentre(for id: UUID) -> CGPoint? {
        syncStickies() // a sticky just made has no ball yet
        guard let mark = stickyMarks[id], window != nil else { return nil }
        return mark.convert(CGPoint(x: mark.bounds.midX, y: mark.bounds.midY), to: nil)
    }

    /// One band per line the sticky's words cover, in document coordinates.
    /// Horizontal extent is the words' own on that line; height and placement
    /// are the selection's. A sticky whose words were all deleted has nothing
    /// left to wash.
    private func washBands(for sticky: Sticky, length: Int) -> [CGRect] {
        let start = min(max(sticky.start, 0), length)
        let end = min(start + max(sticky.length, 0), length)
        guard end > start else { return [] }
        let lm = layoutManager
        let glyphs = lm.glyphRange(
            forCharacterRange: NSRange(location: start, length: end - start),
            actualCharacterRange: nil)
        let height = Style.inkHeight + Style.selectionPadding * 2
        let origin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)
        var bands: [CGRect] = []
        lm.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, container, lineGlyphs, _ in
            let covered = NSIntersectionRange(lineGlyphs, glyphs)
            guard covered.length > 0 else { return }
            // Trailing spaces and the line's newline carry no ink to mark.
            var trimmed = covered
            let text = self.textStorage.string as NSString
            while trimmed.length > 0 {
                let ch = lm.characterIndexForGlyph(at: NSMaxRange(trimmed) - 1)
                guard ch < text.length,
                      let scalar = Unicode.Scalar(text.character(at: ch)),
                      CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
                trimmed.length -= 1
            }
            guard trimmed.length > 0 else { return }
            let ink = lm.boundingRect(forGlyphRange: trimmed, in: container)
            let top = fragment.minY + origin.y
            bands.append(CGRect(
                x: ink.minX + origin.x - 2,
                y: Style.ruledCentre(forLineTop: top) - height / 2,
                width: ink.width + 4, height: height))
        }
        return bands
    }
}

// MARK: - The SwiftUI bridge

struct RichTextEditor: UIViewRepresentable {
    @ObservedObject var store: NotesStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> RuledTextView {
        // TextKit 1, assembled by hand, as on the Mac: the ruling, the caret
        // and the selection are all measured against this layout manager's
        // line fragments.
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(lm)
        lm.addTextContainer(container)
        let tv = RuledTextView(frame: .zero, textContainer: container)
        tv.retainedStorage = storage
        lm.delegate = tv.ballRoom
        context.coordinator.ballRoom = tv.ballRoom
        storage.delegate = context.coordinator
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear // the paper is behind, pinned to the screen
        tv.allowsEditingTextAttributes = false
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.contentInsetAdjustmentBehavior = .never
        // typewriter input: dashes and quotes stay exactly as typed
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.smartInsertDeleteType = .no
        tv.textContainerInset = UIEdgeInsets(
            top: Style.topInset, left: Style.sideMargin,
            bottom: Style.topInset, right: Style.sideMargin)
        tv.tintColor = Style.ink

        context.coordinator.loading = true
        storage.setAttributedString(store.attr)
        context.coordinator.loading = false
        tv.typingAttributes = Style.base
        tv.notesStore = store
        CrumpleDirector.shared.page = tv
        context.coordinator.loadedVersion = store.docVersion
        context.coordinator.observeKeyboard(for: tv)
        // The page is made fresh each time a note is opened from home, so
        // this is where a note arrives: at a search hit if it came from
        // search, with the keyboard up if it is new, and otherwise at the end
        // of what was written with the keyboard down — reading first, until
        // the page is tapped.
        let reveal = store.pendingReveal
        store.pendingReveal = nil
        let focus = store.focusOnOpen
        store.focusOnOpen = false
        DispatchQueue.main.async {
            if let reveal {
                tv.becomeFirstResponder()
                tv.selectedRange = reveal
                tv.scrollRangeToVisible(reveal)
            } else {
                tv.selectedRange = NSRange(location: storage.length, length: 0)
                tv.scrollRangeToVisible(tv.selectedRange)
                if focus { tv.becomeFirstResponder() }
            }
        }
        return tv
    }

    func updateUIView(_ tv: RuledTextView, context: Context) {
        let c = context.coordinator
        if c.wasBlocked != store.editorBlocked {
            c.wasBlocked = store.editorBlocked
            tv.isEditable = !store.editorBlocked
            if store.editorBlocked { tv.resignFirstResponder() }
        }
        if c.themeID != store.themeID {
            c.themeID = store.themeID
            tv.applyTheme()
        }
        if c.loadedVersion != store.docVersion {
            c.loading = true
            tv.ballRoom.slots = [:] // a different note: its balls are worked out afresh
            tv.textStorage.setAttributedString(store.attr)
            c.loading = false
            tv.typingAttributes = Style.base
            tv.undoManager?.removeAllActions()
            if let reveal = store.pendingReveal {
                store.pendingReveal = nil
                DispatchQueue.main.async {
                    tv.becomeFirstResponder()
                    tv.selectedRange = reveal
                    tv.scrollRangeToVisible(reveal)
                }
            } else {
                let end = NSRange(location: tv.textStorage.length, length: 0)
                tv.selectedRange = end
                DispatchQueue.main.async { tv.scrollRangeToVisible(end) }
            }
            c.loadedVersion = store.docVersion
            tv.setNeedsLayout()
        }
        tv.syncStickies()
    }

    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
        let store: NotesStore
        var loadedVersion = -1
        var wasBlocked = false
        var themeID = Style.theme.id
        var loading = false
        weak var ballRoom: BallRoom?
        private var normalizing = false
        private var applyingEdit = false
        private var keyboardObservers: [NSObjectProtocol] = []

        init(store: NotesStore) { self.store = store }

        deinit { keyboardObservers.forEach(NotificationCenter.default.removeObserver) }

        // MARK: Keyboard

        func observeKeyboard(for tv: RuledTextView) {
            let change = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main
            ) { [weak tv] note in
                guard let tv, let window = tv.window,
                      let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }
                let keyboard = window.convert(end, from: nil)
                let mine = tv.convert(tv.bounds, to: window)
                // The bounds' origin is the scroll offset; only height matters.
                let viewBottom = mine.minY + tv.bounds.height
                tv.keyboardOverlap = max(0, viewBottom - keyboard.minY)
                if tv.isFirstResponder {
                    DispatchQueue.main.async { tv.scrollRangeToVisible(tv.selectedRange) }
                }
            }
            let hide = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
            ) { [weak tv] _ in tv?.keyboardOverlap = 0 }
            keyboardObservers = [change, hide]
        }

        // MARK: Text

        func textViewDidChange(_ textView: UITextView) {
            guard !normalizing else { return }
            normalizing = true
            normalizeFonts(textView)
            normalizing = false
            store.textChanged(textView.attributedText)
            (textView as? CaretTextView)?.caretMoved()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? CaretTextView)?.caretMoved()
        }

        // Keep sticky anchors tracking their text through every edit. Done at
        // the storage rather than in shouldChangeTextIn, because that is the
        // one place every edit passes — typing, autocorrect, dictation, undo,
        // the bullet rewrites below — and it reports what actually changed.
        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard !loading, editedMask.contains(.editedCharacters) else { return }
            let edit = NSRange(location: editedRange.location, length: editedRange.length - delta)
            store.remapStickies(edit: edit, replacementLength: editedRange.length)
            ballRoom?.shift(edit: edit, replacementLength: editedRange.length)
        }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            guard !applyingEdit, range.length == 0 else { return true }
            if text == " " { return !makeBullet(textView, at: range.location) }
            if text == "\n" { return !continueBullet(textView, at: range.location) }
            return true
        }

        // Replaces through UITextInput so the edit is undoable, and with a
        // guard so a delegate callback made by the replace itself passes.
        private func replace(_ tv: UITextView, _ range: NSRange, with text: String) {
            guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                  let end = tv.position(from: start, offset: range.length),
                  let textRange = tv.textRange(from: start, to: end) else { return }
            applyingEdit = true
            tv.replace(textRange, withText: text)
            applyingEdit = false
        }

        private func setParagraph(_ tv: UITextView, _ style: NSParagraphStyle, line: NSRange) {
            guard line.length > 0, NSMaxRange(line) <= tv.textStorage.length else { return }
            tv.textStorage.addAttribute(.paragraphStyle, value: style, range: line)
        }

        // Typing "- " at the start of a line turns it into a bullet.
        private func makeBullet(_ tv: UITextView, at location: Int) -> Bool {
            let ns = tv.textStorage.string as NSString
            guard location > 0, location <= ns.length else { return false }
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            guard location - line.location == 1,
                  ns.character(at: line.location) == 0x2D else { return false } // "-"
            var attrs = tv.typingAttributes
            attrs[.paragraphStyle] = Style.bulletParagraph
            tv.typingAttributes = attrs
            replace(tv, NSRange(location: line.location, length: 1), with: Style.bulletPrefix)
            let para = (tv.textStorage.string as NSString)
                .lineRange(for: NSRange(location: line.location, length: 0))
            setParagraph(tv, Style.bulletParagraph, line: para)
            tv.typingAttributes = attrs
            tv.selectedRange = NSRange(
                location: line.location + (Style.bulletPrefix as NSString).length, length: 0)
            textViewDidChange(tv)
            return true
        }

        // Return continues a list; Return on an empty bullet leaves it.
        private func continueBullet(_ tv: UITextView, at location: Int) -> Bool {
            let ns = tv.textStorage.string as NSString
            guard location <= ns.length else { return false }
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
            if line.trimmingCharacters(in: .whitespaces) == "•" {
                // empty bullet → remove it and drop back to prose
                replace(tv, NSRange(location: lineRange.location, length: (line as NSString).length), with: "")
                let now = (tv.textStorage.string as NSString)
                    .lineRange(for: NSRange(location: lineRange.location, length: 0))
                setParagraph(tv, Style.paragraph, line: now)
                var attrs = tv.typingAttributes
                attrs[.paragraphStyle] = Style.paragraph
                tv.typingAttributes = attrs
                tv.selectedRange = NSRange(location: lineRange.location, length: 0)
                textViewDidChange(tv)
                return true
            }
            guard line.hasPrefix(Style.bulletPrefix) else { return false }
            replace(tv, NSRange(location: location, length: 0), with: "\n" + Style.bulletPrefix)
            // Say what both paragraphs are rather than hoping typing attributes
            // carried it: a bullet wearing the prose style silently grows a
            // blank rule after it, and nothing visible can be deleted to fix it.
            let text = tv.textStorage.string as NSString
            let caret = min(tv.selectedRange.location, text.length)
            let current = text.lineRange(for: NSRange(location: caret, length: 0))
            setParagraph(tv, Style.bulletParagraph, line: current)
            if current.location > 0 {
                setParagraph(tv, Style.bulletParagraph,
                             line: text.lineRange(for: NSRange(location: current.location - 1, length: 0)))
            }
            var attrs = tv.typingAttributes
            attrs[.paragraphStyle] = Style.bulletParagraph
            tv.typingAttributes = attrs
            textViewDidChange(tv)
            return true
        }

        // The edit menu: a selection can become a sticky, or go italic.
        func textView(
            _ textView: UITextView, editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0, let tv = textView as? RuledTextView else { return nil }
            let sticky = UIAction(title: "Sticky Note", image: UIImage(systemName: "note.text")) { [weak self] _ in
                guard let self else { return }
                let id = self.store.addSticky(range: range)
                tv.resignFirstResponder()
                self.store.openStickyID = id
            }
            let italic = UIAction(title: "Italic", image: UIImage(systemName: "italic")) { _ in
                tv.italicize(nil)
            }
            return UIMenu(children: [sticky, italic] + suggestedActions)
        }

        // Safety net for anything that slips in styled: force the house family
        // and size, the house paragraph styles and the ink, and strip every
        // decoration, keeping only italic/bold. Fixes are collected and applied
        // after the walk. Skipped while text is marked (a keyboard mid-
        // composition owns its own underline).
        private func normalizeFonts(_ tv: UITextView) {
            guard tv.markedTextRange == nil else { return }
            let storage = tv.textStorage
            let full = NSRange(location: 0, length: storage.length)
            let banned: [NSAttributedString.Key] = [
                .underlineStyle, .strikethroughStyle, .backgroundColor,
                .link, .shadow, .strokeWidth, .baselineOffset,
            ]
            let family = Style.baseFont.familyName
            let ink = Style.ink
            var fixes: [() -> Void] = []
            storage.enumerateAttributes(in: full) { attrs, range, _ in
                let font = attrs[.font] as? UIFont
                if font?.familyName != family || font?.pointSize != Style.baseSize {
                    let fixed = Style.restyle(font)
                    fixes.append { storage.addAttribute(.font, value: fixed, range: range) }
                }
                let para = attrs[.paragraphStyle] as? NSParagraphStyle
                // indented paragraphs are bullet items and keep their own style
                let target = (para?.headIndent ?? 0) > 0 ? Style.bulletParagraph : Style.paragraph
                if para == nil || para?.isEqual(target) == false {
                    fixes.append { storage.addAttribute(.paragraphStyle, value: target, range: range) }
                }
                if (attrs[.foregroundColor] as? UIColor) != ink {
                    fixes.append { storage.addAttribute(.foregroundColor, value: ink, range: range) }
                }
                for key in banned where attrs[key] != nil {
                    fixes.append { storage.removeAttribute(key, range: range) }
                }
            }
            guard !fixes.isEmpty else { return }
            let selection = tv.selectedRange
            storage.beginEditing()
            fixes.forEach { $0() }
            storage.endEditing()
            tv.selectedRange = selection
        }
    }
}
