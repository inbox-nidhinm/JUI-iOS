import SwiftUI
import UIKit

// Paper.
//
// Three photographed stocks — the page, the sticky notes, the panels — applied
// as *blend layers over themed colour*, never as pictures in their own right.
// They are measurably neutral (R = G = B), so the colour comes from the theme
// underneath and only the tone comes from the paper: one file serves all six
// palettes. A texture is always a multiply at a fraction, never drawn opaque.
//
// Every number here (strength, fit) is carried over from the macOS app, where
// each was recovered from the Figma system — see mac-reference/Texture.swift
// for how, before changing any of them.
enum Paper: String {
    case sheet  // the page itself
    case sticky // sticky notes
    case ui     // panels, the search palette, folder cards

    enum Fit {
        /// The whole photograph across the surface.
        case cover
        /// Drawn at a fixed multiple of the photograph's own size and cropped
        /// to the surface. Lower numbers mean bigger grain.
        case window(CGFloat)
    }

    var image: UIImage? {
        if let hit = Paper.cache[rawValue] { return hit }
        guard let url = Bundle.main.resourceURL?
                .appendingPathComponent("Textures/\(rawValue).jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        Paper.cache[rawValue] = image
        return image
    }

    private static var cache: [String: UIImage] = [:]

    // Aspect-fill, for the views UIKit draws by hand. Must be drawn into the
    // same context as the colour it textures — a multiply only sees what is
    // already in its own context.
    func draw(in rect: CGRect, fit: Fit, strength: CGFloat) {
        guard let image, rect.width > 0, rect.height > 0 else { return }
        let scale = fit.scale(covering: rect.size, image: image.size)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2,
                              y: rect.midY - size.height / 2,
                              width: size.width, height: size.height),
                   blendMode: .multiply, alpha: strength)
    }
}

extension Paper.Fit {
    // Shared by both halves so a UIKit surface and a SwiftUI one can never
    // drift into showing the same stock at two different grains.
    func scale(covering surface: CGSize, image: CGSize) -> CGFloat {
        let cover = max(surface.width / image.width, surface.height / image.height)
        switch self {
        case .cover: return cover
        case .window(let k): return max(k, cover)
        }
    }
}

// How hard each surface takes its paper. Strength sets the tone and fit sets
// the grain size; both belong to the surface, not the stock.
enum Surface {
    case page        // sheet
    case sticky      // sticky
    case folderPanel // panel — the pane the tiles sit on, settings cards
    case folderTile  // folderBase — the tiles themselves
    case pageCard    // sheet — cards of the page's own paper (`PagePaper`)
    case button      // panel — a raised icon button
    case envelope    // envelope — onboarding
    case letter      // letterSheet — onboarding

    var paper: Paper {
        switch self {
        case .page, .pageCard: return .sheet
        case .sticky: return .sticky
        case .folderPanel, .folderTile, .button,
             .envelope, .letter: return .ui
        }
    }

    var strength: CGFloat {
        switch self {
        case .page: return 0.50
        case .sticky: return 0.46
        case .folderPanel: return 0.93
        case .folderTile: return 0.49
        case .pageCard: return 0.50 // as the page
        case .button: return 0.75
        case .envelope: return 0.85
        case .letter: return 0.40
        }
    }

    var fit: Paper.Fit {
        switch self {
        case .page, .folderPanel, .folderTile, .button,
             .envelope, .letter: return .cover
        // 0.5 puts one image pixel on one Retina pixel — on a 3x phone that is
        // slightly coarser grain than on the Mac's 2x, which reads as the same
        // paper held a little closer rather than a different stock.
        case .sticky: return .window(0.5)
        // The page's paper at the page's own grain: the scale the photograph
        // is drawn at to cover the screen, held for a card a fraction of its
        // size — covering just the card would blow the grain up.
        case .pageCard:
            guard let image = Paper.sheet.image else { return .cover }
            return .window(Paper.Fit.cover.scale(covering: UIScreen.main.bounds.size, image: image.size))
        }
    }

    func draw(in rect: CGRect) { paper.draw(in: rect, fit: fit, strength: strength) }
}

// Cards made of the page's own paper, a shade deeper: the sheet with the
// page's grain, and the mood's panel colour multiplied into it — a multiply
// darkens the grain along with the paper, where a plain layer of colour laid
// over it washed the grain out. Search and the settings rows take it at 0.7;
// the onboarding letter, which should read as fresh paper, only faintly.
struct PagePaper: View {
    var theme = Style.theme.id // redraw on a theme change — see Style.theme
    /// How much of the panel colour is multiplied in, 0…1.
    var tint: Double = 0.7

    var body: some View {
        let shade: Color = panelColor.opacity(tint)
        sheetColor
            .papered(.pageCard)
            .overlay(Rectangle().fill(shade).blendMode(.multiply))
            .compositingGroup() // multiplied into the card, not what is behind it
    }
}

// The SwiftUI half. `.papered(.ui)` presses paper into whatever it is applied
// to. `compositingGroup` is load-bearing: without it the multiply blends
// against everything behind the view instead of the colour it textures.
//
// Order at a call site is colour, then paper, then clip — or the grain squares
// off behind the corner radius.
extension View {
    func papered(_ surface: Surface) -> some View {
        overlay(PaperOverlay(surface: surface)).compositingGroup()
    }
}

private struct PaperOverlay: View {
    let surface: Surface
    private var paper: Paper { surface.paper }

    var body: some View {
        GeometryReader { geo in
            if let image = paper.image {
                let scale = surface.fit.scale(covering: geo.size, image: image.size)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: image.size.width * scale,
                           height: image.size.height * scale)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blendMode(.multiply)
                    .opacity(surface.strength)
            }
        }
        .allowsHitTesting(false)
    }
}
