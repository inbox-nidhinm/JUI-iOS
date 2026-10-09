import UIKit

// MARK: - Smooth caret (MS Word 2013-style glide)
//
// Ported from the Mac's SmoothCaret. The caret glides to its new position
// instead of jumping, stays solid while moving or typing, and blinks only when
// idle. It is drawn in the house ink — the one thing on the page that never
// stops moving has to be in palette.
//
// The Mac suppresses AppKit's caret three ways at once and draws a CALayer of
// its own. iOS offers a cleaner seam: since iOS 17 a text view's caret is the
// `cursorView` of its UITextSelectionDisplayInteraction, and that view can be
// replaced. Replacing it with one that draws nothing removes the system caret
// without touching the tint, so the selection highlight and its handles —
// which the tint also colours — are left exactly as they were.
//
// Where the caret goes is asked of the text view's own `caretRect(for:)`, so
// the note editor's ink-box sizing (RuledTextView) carries over for free and
// a plain text view (a sticky) gets the system's rect.

/// Stands in for the system caret and draws nothing.
final class SilentCursorView: UIView, UITextCursorView {
    var isBlinking = false
    func resetBlinkAnimation() {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("unused") }
}

final class SmoothCaret {
    private weak var view: UITextView?
    let layer = CALayer()
    private var visible = false

    // How long a move takes, and how long the caret stays solid after one
    // before it starts to blink — both the Mac's.
    static let glide: CFTimeInterval = 0.10
    static let holdBeforeBlink: CFTimeInterval = 0.45

    init(view: UITextView) {
        self.view = view
        layer.cornerRadius = 1
        layer.backgroundColor = Style.ink.cgColor
        layer.zPosition = 10 // above the text and anything added after it
        layer.isHidden = true
        // Opacity and visibility are driven explicitly; only position glides.
        layer.actions = ["opacity": NSNull(), "hidden": NSNull(), "backgroundColor": NSNull()]
    }

    /// The system's display interaction, once the text view has made one. It
    /// can appear late (on first focus), so this is asked on every update.
    private var display: UITextSelectionDisplayInteraction? {
        view?.interactions.lazy.compactMap { $0 as? UITextSelectionDisplayInteraction }.first
    }

    /// True once the system caret has been swapped out. Until then — if a
    /// future iOS stops exposing the interaction — the system caret is left
    /// alone and this one stays hidden, rather than drawing two.
    var isActive: Bool { display?.cursorView is SilentCursorView }

    private func silenceSystemCaret() {
        guard let display, !(display.cursorView is SilentCursorView) else { return }
        display.cursorView = SilentCursorView()
    }

    func applyTheme() {
        layer.backgroundColor = Style.ink.cgColor
    }

    func update(animated: Bool) {
        guard let view else { return }
        if layer.superlayer !== view.layer { view.layer.addSublayer(layer) }
        silenceSystemCaret()
        guard isActive, view.isFirstResponder, view.isEditable,
              let range = view.selectedTextRange, range.isEmpty else {
            hide()
            return
        }
        var rect = view.caretRect(for: range.end)
        guard rect.height > 0, rect.minX.isFinite, rect.minY.isFinite else {
            hide()
            return
        }
        rect.size.width = 2
        // Glide only from somewhere the caret already was; appearing (focus,
        // a document load) is a cut, as on the Mac. Reduced motion is a cut
        // too.
        let glide = animated && visible && !prefersReducedMotion
        CATransaction.begin()
        if glide {
            CATransaction.setAnimationDuration(Self.glide)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        layer.frame = rect
        layer.isHidden = false
        CATransaction.commit()
        visible = true
        restartBlink()
    }

    private func hide() {
        visible = false
        layer.isHidden = true
        layer.removeAnimation(forKey: "blink")
    }

    // Solid while moving or typing; blinks only once it has been still.
    private func restartBlink() {
        layer.removeAnimation(forKey: "blink")
        layer.opacity = 1
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 1, 0, 0, 1]
        blink.keyTimes = [0, 0.45, 0.55, 0.95, 1]
        blink.duration = 1.1
        blink.beginTime = CACurrentMediaTime() + Self.holdBeforeBlink
        blink.repeatCount = .infinity
        layer.add(blink, forKey: "blink")
    }
}

/// A UITextView that draws the house caret. The note editor and the sticky's
/// editor both are one, so the caret behaves the same everywhere — as on the
/// Mac, where any new text view was meant to use SmoothCaret too.
class CaretTextView: UITextView {
    private(set) lazy var smoothCaret = SmoothCaret(view: self)
    private var lastSize: CGSize = .zero

    override func didMoveToWindow() {
        super.didMoveToWindow()
        smoothCaret.update(animated: false)
    }

    // Programmatic selection changes come through these two — UIKit does not
    // route one setter through the other, and does not tell the delegate. The
    // user's changes come through the delegate, which calls `caretMoved()`.
    override var selectedTextRange: UITextRange? {
        didSet { smoothCaret.update(animated: true) }
    }

    override var selectedRange: NSRange {
        didSet { smoothCaret.update(animated: true) }
    }

    override var isEditable: Bool {
        didSet { smoothCaret.update(animated: false) }
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.smoothCaret.update(animated: false) }
        return ok
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.smoothCaret.update(animated: false) }
        return ok
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A new width rewraps the text under the caret: follow it without a
        // glide. Scrolling also lands here and must not restart the blink.
        if bounds.size != lastSize {
            lastSize = bounds.size
            smoothCaret.update(animated: false)
        }
    }

    /// The caret moved because of typing or a tap — glide to it.
    func caretMoved() { smoothCaret.update(animated: true) }
}
