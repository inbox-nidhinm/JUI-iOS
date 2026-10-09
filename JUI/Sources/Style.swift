import SwiftUI
import UIKit

// MARK: - Colour tokens
//
// Every colour token reads through the active theme, so changing theme repaints
// the whole app without a single call site knowing about it. Never write a
// colour literal outside Theme.swift; the tones below (black at a fraction) are
// the only exceptions, because a tone is right in all six themes at once.

var sheetColor: Color { Color(uiColor: Style.theme.sheet) }
var panelColor: Color { Color(uiColor: Style.theme.panel) }
var openDotColor: Color { Color(uiColor: Style.theme.openDot) }
var flourishColor: Color { Color(uiColor: Style.theme.flourish) }
var folderBaseColor: Color { Color(uiColor: Style.theme.folderBase) }
var stickyColor: Color { Color(uiColor: Style.theme.sticky) }
var envelopeColor: Color { Color(uiColor: Style.theme.envelope) }
var letterColor: Color { Color(uiColor: Style.theme.letterSheet) }

// The corner flourish is panel drawn *through* the page (multiplied), and
// deepens a step toward the ink while pressed — the phone's stand-in for the
// Mac's hover.
var flourishRest: Color { panelColor }
var flourishPressed: Color { Color(uiColor: Style.theme.panel.blended(0.22, toward: Style.theme.ink)) }

var brownInk: Color { Color(uiColor: Style.theme.ink) }

// The ink ladder — four steps, and only these four. Pick the step that matches
// the role; never reach for a fresh opacity.
var inkStrong: Color { brownInk.opacity(0.85) } // panel rows, settings values, folder names
var inkMuted: Color { brownInk.opacity(0.55) }  // labels, snippets, secondary rows
var inkFaint: Color { brownInk.opacity(0.4) }   // placeholders, empty states, icons, disabled

// The hairline inside a papered surface: black at 12% is a multiply by 0.88,
// so it darkens whatever it lands on and cannot invert.
var panelDividerColor: Color { Color.black.opacity(0.12) }

// Type, handled the way colour is: one function every call site reads through,
// so the family chosen in settings reaches the chrome and not only the page.
// The scale is 10 / 11 / 12 / 13 / 14 / 16; 16 is the largest text in the app.
func houseFont(_ size: CGFloat) -> Font { Font(Style.font(size) as CTFont) }

extension UIColor {
    /// This colour moved `fraction` of the way toward `other`, in sRGB.
    func blended(_ fraction: CGFloat, toward other: UIColor) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        let t = min(max(fraction, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

// MARK: - Style

enum Style {
    // The one piece of mutable global state the colours hang off. Set on launch
    // from UserDefaults and by NotesStore.setTheme thereafter.
    //
    // SwiftUI cannot see a global. A view that observes the store redraws when
    // `themeID` publishes, but a view or style built *inside* it is redrawn
    // only if its own inputs changed — and a ButtonStyle, an icon button or a
    // representable whose inputs are the same as last time keeps its old
    // colours until something else touches it. That is how the corner
    // flourish and the folder tiles came to stay in the old mood until
    // tapped. So every such piece carries `var theme = Style.theme.id`, read
    // when it is built: a new theme makes it a different input, and SwiftUI
    // redraws it. Any new style or small view that draws a token needs the
    // same line.
    static var theme: Theme = Themes.named(UserDefaults.standard.string(forKey: "themeID"))

    static var ink: UIColor { theme.ink }
    static var sheet: UIColor { theme.sheet }

    // user-selectable on the settings page. Courier Prime by default — the
    // face the Figma system is set in, bundled with the app; the Mac uses the
    // system Courier. A family that isn't there falls back to Courier.
    static let defaultFontFamily = "Courier Prime"
    static var fontFamily: String =
        UserDefaults.standard.string(forKey: "fontFamily") ?? defaultFontFamily

    // The body size, and the top of the type scale.
    static let baseSize: CGFloat = 16

    static var baseFont: UIFont { font(baseSize) }

    /// The chosen family at a given size, regular face, with the same fallback
    /// chain everywhere. Resolved by *family* through a descriptor, because
    /// `UIFont(name:)` wants a face's PostScript name and the two only coincide
    /// for some families.
    static func font(_ size: CGFloat, family: String? = nil) -> UIFont {
        let family = family ?? fontFamily
        if let face = UIFont.fontNames(forFamilyName: family).first(where: isRegularFace)
            ?? UIFont.fontNames(forFamilyName: family).first,
           let font = UIFont(name: face, size: size) {
            return font
        }
        return UIFont(name: "Courier", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // The upright, book-weight face of a family, picked from its face names.
    // Family descriptors on iOS resolve to whichever face the system lists
    // first, which for some families is a bold or an italic.
    private static func isRegularFace(_ name: String) -> Bool {
        guard let f = UIFont(name: name, size: 12) else { return false }
        let traits = f.fontDescriptor.symbolicTraits
        return !traits.contains(.traitItalic) && !traits.contains(.traitBold)
            && !name.lowercased().contains("light") && !name.lowercased().contains("medium")
    }

    /// `font` restyled into the current family and body size, keeping only its
    /// italic and bold traits.
    static func restyle(_ font: UIFont?) -> UIFont {
        let traits = (font?.fontDescriptor.symbolicTraits ?? [])
            .intersection([.traitItalic, .traitBold])
        let base = baseFont
        guard !traits.isEmpty,
              let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: baseSize)
    }

    static func isItalic(_ font: UIFont?) -> Bool {
        font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false
    }

    /// The same face with italic switched on or off. Falls back to the font
    /// unchanged when the family has no italic.
    static func italic(_ font: UIFont, _ on: Bool) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if on { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    // Force every font run to the chosen family/size, keeping italic/bold.
    // Collected first and applied after — writing from inside the walk can
    // merge runs and reshape the ranges being enumerated.
    static func applyFont(to text: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: text.length)
        var fixes: [(UIFont, NSRange)] = []
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            let font = value as? UIFont
            guard font?.familyName != baseFont.familyName || font?.pointSize != baseSize else { return }
            fixes.append((restyle(font), range))
        }
        guard !fixes.isEmpty else { return }
        text.beginEditing()
        for (font, range) in fixes { text.addAttribute(.font, value: font, range: range) }
        text.endEditing()
    }

    // MARK: The page column
    //
    // The Mac's 200pt margins are a third of an iPhone. The column here is set
    // by what a phone can hold — about 35 characters of Courier 16 — and the
    // ruling's overhang past the text shrinks with it, so the rules still run
    // wider than the words and stop short of the glass.
    static let sideMargin: CGFloat = 30
    static let ruleOverhang: CGFloat = 18
    // The Mac's own 52. On the phone the first `backBand` points under the
    // status bar are left clear (they once held a back arrow) and the text
    // fades out through them as it scrolls up.
    static let topInset: CGFloat = 52
    static let backBand: CGFloat = 44

    // MARK: The corner flourish
    //
    // Its size and its distance up from the home indicator. The note page
    // reads these too, to fade its words out before they reach it.
    static let cornerFlourishHeight: CGFloat = 92
    static let cornerFlourishLift: CGFloat = 4
    // Clear paper between the last visible words and the flourish's top.
    static let cornerFlourishClearance: CGFloat = 20

    // MARK: Ruled paper
    //
    // Three times the type size — the rule the Figma system is built on (22 on
    // a 66pt line there, 16 on 48 here). Held as the *pitch*, with the leading
    // derived from it, so the grid survives the font picker: a family with a
    // different natural line height gets different leading and still lands on
    // the same rules.
    static let linePitch: CGFloat = 48

    /// What TextKit actually does with the chosen font, measured off a real
    /// layout rather than taken from the font's own numbers. TextKit on iOS has
    /// no `defaultLineHeight(for:)`, and a font's `lineHeight` is not always
    /// the fragment height it lays out at.
    struct Metrics {
        let lineHeight: CGFloat     // a fragment's height with no spacing
        let baselineOffset: CGFloat // baseline, down from the fragment's top
        let ascender: CGFloat
        let descender: CGFloat
    }

    private static var metricsCache: (key: String, value: Metrics)?

    static var metrics: Metrics {
        let font = baseFont
        let key = "\(font.fontName)-\(font.pointSize)"
        if let hit = metricsCache, hit.key == key { return hit.value }
        let storage = NSTextStorage(string: "Hg", attributes: [.font: font])
        let lm = NSLayoutManager()
        let tc = NSTextContainer(size: CGSize(width: 1000, height: 1000))
        tc.lineFragmentPadding = 0
        storage.addLayoutManager(lm)
        lm.addTextContainer(tc)
        lm.ensureLayout(for: tc)
        let fragment = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let baseline = lm.location(forGlyphAt: 0).y
        let value = Metrics(
            lineHeight: fragment.height > 0 ? fragment.height : font.lineHeight,
            baselineOffset: baseline > 0 ? baseline : font.ascender,
            ascender: font.ascender, descender: font.descender)
        metricsCache = (key, value)
        return value
    }

    static var lineSpacing: CGFloat { max(0, linePitch - metrics.lineHeight) }

    // MARK: The ink box
    //
    // Where the glyphs sit inside a line fragment. Anything that marks the
    // *words* rather than the line — the selection, the caret — measures from
    // here, never from the rect UIKit hands it: that rect's height is the
    // fragment's, which is the line on the last line of a note, the line plus
    // leading elsewhere, and plus a whole pitch at the end of a paragraph.
    static var inkOffset: CGFloat { metrics.baselineOffset - metrics.ascender }
    static var inkHeight: CGFloat { metrics.ascender - metrics.descender }

    /// Where a rule actually lands, given the y it would ideally sit at —
    /// snapped so a hairline doesn't smear across two pixels. Anything placed
    /// against the ruling snaps the same way.
    static func ruleY(_ y: CGFloat) -> CGFloat { y.rounded() + 0.5 }

    /// The midpoint between the two rules bracketing a line, as drawn.
    static func ruledCentre(forLineTop top: CGFloat) -> CGFloat {
        let above = ruleY(top - lineSpacing / 2)
        return (above + ruleY(top - lineSpacing / 2 + linePitch)) / 2
    }

    // How far a selection reaches past the ink it covers, top and bottom.
    static let selectionPadding: CGFloat = 5

    // How far the caret reaches past the type, top and bottom.
    static let caretOvershoot: CGFloat = 2

    // Black at 10% over a colour is the same arithmetic as multiplying it by
    // 0.9 — so the ruling is drawn as plain black at 10%, which is exactly the
    // multiply the system specifies, without needing the page in the same
    // drawing context. One value, right in all six themes and over the grain.
    static let ruleTone = UIColor(white: 0, alpha: 0.10)

    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        // A whole pitch, so a paragraph break is exactly one blank rule. Any
        // gap that isn't a whole number of pitches walks type off the ruling.
        p.paragraphSpacing = linePitch
        // Left, not justified as on the Mac. At ~35 monospaced characters a
        // line, justification opens rivers of space between words on most
        // lines; the Mac's column is long enough to hide them.
        p.alignment = .natural
        return p
    }

    static var base: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: ink, .paragraphStyle: paragraph]
    }

    // Horizontal rules are gone; the marker survives only so a note that
    // already contains one opens as a blank line.
    static let hrMarker = "\u{00A0}"
    static let bulletPrefix = "• "
    static var bulletIndent: CGFloat {
        (bulletPrefix as NSString).size(withAttributes: [.font: baseFont]).width
    }

    // Hanging indent so wrapped lines align after the bullet; zero spacing so
    // list items take consecutive rules.
    static var bulletParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.paragraphSpacing = 0
        p.headIndent = bulletIndent
        p.alignment = .natural
        return p
    }

    /// The families offered in settings — the ones a phone actually carries
    /// that suit a writing pad, filtered to what is installed. The Mac lists
    /// every family on the system; on a phone that list is mostly UI faces and
    /// scripts nobody would write a letter in.
    static var offeredFamilies: [String] {
        let wanted = [
            // Courier Prime ships inside the app (Resources/Fonts): the face
            // the Figma system is set in, redrawn from Courier for screens.
            "Courier", "Courier Prime", "Courier New", "American Typewriter", "Menlo",
            "Georgia", "Baskerville", "Palatino", "Hoefler Text", "Iowan Old Style",
            "Charter", "Times New Roman", "Didot", "Optima", "Gill Sans",
            "Avenir Next", "Futura", "Helvetica Neue", "Noteworthy", "Snell Roundhand",
        ]
        let installed = Set(UIFont.familyNames)
        return wanted.filter { installed.contains($0) }
    }
}

var prefersReducedMotion: Bool { UIAccessibility.isReduceMotionEnabled }

// MARK: - Folder tile metrics
//
// The air a folder tile keeps above its name: the old sprig's metrics, kept
// because the tile height — and so the grid — is computed from them.
let folderMarkHeight: CGFloat = 32
let folderMarkWidth: CGFloat = 32 * (181.0 / 271.0)
let folderMarkGap: CGFloat = 14
let folderTitleHeight: CGFloat = 16
let folderCellPadding: CGFloat = 9
let folderCellHeight: CGFloat =
    folderMarkHeight + folderMarkGap + folderTitleHeight + folderCellPadding * 2

// MARK: - The flourish

// Three sets ship: the same drawing at the three angles the artwork uses —
// upright for the page corner, rotated for folder tiles and for stickies.
// Frames are white silhouettes tinted at draw time, so one set serves all six
// themes.
enum FlourishSet: String {
    case corner, folder, sticky
}

struct AnimatedFlourish: View {
    // When a flourish draws itself is the caller's decision, not the view's.
    enum Play {
        /// Already there. Show the finished drawing and never animate.
        case never
        /// Draws itself the first time this key appears, then holds.
        case onceInSession(key: String)
        /// Draws itself every time it appears.
        case always
    }

    let set: FlourishSet
    let tint: Color
    let play: Play
    @State private var index: Int

    init(set: FlourishSet = .corner, tint: Color, play: Play) {
        self.set = set
        self.tint = tint
        self.play = play
        _index = State(initialValue: Self.startIndex(set: set, play: play))
    }

    private static func startIndex(set: FlourishSet, play: Play) -> Int {
        let last = max(0, frames(set).count - 1)
        switch play {
        case .never: return last
        case .always: return 0
        case .onceInSession(let key): return played.contains(key) ? last : 0
        }
    }

    private static var cache: [String: [UIImage]] = [:]
    private static var played: Set<String> = []

    // Counted off what actually shipped, sorted by the number in the name (not
    // the string), so a re-export of a different length just works.
    static func frames(_ set: FlourishSet) -> [UIImage] {
        if let hit = cache[set.rawValue] { return hit }
        let urls = Bundle.main.urls(
            forResourcesWithExtension: "png",
            subdirectory: "FlourishFrames/" + set.rawValue) ?? []
        let loaded = urls
            .map { ($0, Int($0.deletingPathExtension().lastPathComponent
                .drop { !$0.isNumber }) ?? 0) }
            .sorted { $0.1 < $1.1 }
            .compactMap { UIImage(contentsOfFile: $0.0.path) }
        cache[set.rawValue] = loaded
        return loaded
    }

    /// Width over height, taken from the artwork rather than written down.
    static func aspect(_ set: FlourishSet) -> CGFloat {
        guard let first = frames(set).first, first.size.height > 0 else { return 1 }
        return first.size.width / first.size.height
    }

    // 30 frames over 2.5s in the source, which is 12fps.
    static let frameDuration = 1.0 / 12.0

    /// How long the sequence takes, derived from the frames actually shipped.
    static var duration: TimeInterval { Double(frames(.corner).count) * frameDuration }

    var body: some View {
        let all = Self.frames(set)
        return Group {
            if all.indices.contains(index) {
                Image(uiImage: all[index]).resizable().renderingMode(.template)
            } else {
                Color.clear // no frames shipped: draw nothing rather than a box
            }
        }
        .foregroundStyle(tint)
        .accessibilityHidden(true)
        .onAppear(perform: start)
    }

    private func start() {
        let all = Self.frames(set)
        guard all.count > 1 else { return }
        switch play {
        case .never: return
        case .onceInSession(let key):
            guard !Self.played.contains(key) else { return }
            Self.played.insert(key)
        case .always: break
        }
        if prefersReducedMotion {
            index = all.count - 1
            return
        }
        index = 0
        // Stepped by a repeating timer rather than animated: stop-motion is
        // discrete, and interpolating between frames would take the character
        // out of it. Common mode keeps it drawing while the page scrolls.
        let timer = Timer(timeInterval: Self.frameDuration, repeats: true) { t in
            if index < all.count - 1 { index += 1 } else { t.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
