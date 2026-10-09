import UIKit

// The soft edges of a scrolling page.
//
// Text that runs on past the edge of what is showing fades out as it reaches
// that edge, so the eye reads "there is more" rather than "the words are cut".
// A fade only appears while there is something beyond it, and comes in with
// the first few points of hidden text rather than switching on — at the very
// top or bottom of a note the edge is crisp, and scrolling away from it lets
// the fade grow in.
//
// A mask on the text view itself, so the words fade and the paper behind them
// does not. Scroll bars are off everywhere these are, too: on paper the fade
// says what a scroll bar would.
final class EdgeFade {
    let layer = CAGradientLayer()

    init() {
        layer.colors = Array(repeating: UIColor.black.cgColor, count: 6)
    }

    /// Updates the mask for `view`'s current scroll position. Call on every
    /// layout pass; a scroll view lays out on every scroll tick.
    ///
    /// - Parameters:
    ///   - hiddenTop: a band at the top that is always faded, whatever the
    ///     scroll — the note's runs under the status bar and the clear band below it.
    ///   - bottomEdge: where the visible text ends, in the view's own height —
    ///     the bottom of the view, or the top of the keyboard over it.
    ///   - band: how deep a fade is.
    ///   - bottomBand: how deep the foot's fade is, if not `band`.
    ///   - bottomAlways: fade the foot whatever the scroll — for an edge that
    ///     guards something drawn over the page (the corner flourish), not
    ///     one that says there is more below.
    func update(in view: UIScrollView, hiddenTop: CGFloat = 0,
                bottomEdge: CGFloat? = nil, band: CGFloat, bottomBand: CGFloat? = nil,
                bottomAlways: Bool = false) {
        let footBand = bottomBand ?? band
        let height = max(view.bounds.height, 1)
        let bottom = min(bottomEdge ?? height, height)
        let offset = view.contentOffset.y + view.adjustedContentInset.top
        let maxOffset = view.contentSize.height + view.adjustedContentInset.top
            + view.adjustedContentInset.bottom - view.bounds.height
        let above = max(0, offset)
        let below = max(0, maxOffset - offset)

        // How strongly each end fades: nothing at the end of the text, fully
        // once a whole band of it is out of sight.
        let topFade = hiddenTop > 0 ? 1 : min(1, above / band)
        let bottomFade = bottomAlways ? 1 : min(1, below / footBand)

        let topClear = hiddenTop > 0 ? hiddenTop : 0
        let topSolid = topClear + band
        let bottomSolid = bottom - footBand

        func alpha(_ fade: CGFloat) -> CGColor { UIColor(white: 0, alpha: 1 - fade).cgColor }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = view.bounds // pinned to the visible slice, not the document
        layer.colors = [alpha(topFade), alpha(topFade), UIColor.black.cgColor,
                        UIColor.black.cgColor, alpha(bottomFade), alpha(bottomFade)]
        layer.locations = [0, topClear, topSolid, max(topSolid, bottomSolid), bottom, height]
            .map { NSNumber(value: Double(min(max($0 / height, 0), 1))) }
        CATransaction.commit()
    }
}
