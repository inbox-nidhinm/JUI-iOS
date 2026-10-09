import SceneKit
import SwiftUI
import UIKit

// A sticky, put away, is a sheet crumpled into a ball in the line, right
// after its words (the room is made by `BallRoom`, Editor.swift). Tapped,
// the ball lifts, comes to the middle of the screen and opens out flat into
// the card; put away again, the card crushes back into a ball and drops back
// into its place in the line. The prototype this came from is
// `prototypes/crumpled-sticky/index.html` (the "fluid" motion, crease depth
// 0.8) — every number here is carried over from it.
//
// The card itself is SwiftUI and can't fold, so the fold is a stand-in: a
// sheet of a few thousand points drawn by SceneKit, textured with a picture of
// the card, bent between a crumpled ball and flat. The real card appears only
// once the sheet has landed flat in exactly its place — which is also why the
// card's flourish only starts drawing itself after the unfold — and on the
// way out the sheet takes over from the card the same way round.

// MARK: - Creases

// Perlin noise, seeded as the prototype's, so the ball has the same creases.
enum Crease {
    private static let perm: [Int] = {
        var p = Array(0..<256)
        var seed = 7
        for i in stride(from: 255, to: 0, by: -1) {
            seed = (seed * 16807) % 2147483647
            p.swapAt(i, seed % (i + 1))
        }
        return p + p
    }()

    private static func fade(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }
    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    private static func grad(_ h: Int, _ x: Float, _ y: Float, _ z: Float) -> Float {
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) != 0 ? -u : u) + ((h & 2) != 0 ? -v : v)
    }

    static func noise(_ x: Float, _ y: Float, _ z: Float) -> Float {
        let X = Int(x.rounded(.down)) & 255, Y = Int(y.rounded(.down)) & 255, Z = Int(z.rounded(.down)) & 255
        let x = x - x.rounded(.down), y = y - y.rounded(.down), z = z - z.rounded(.down)
        let u = fade(x), v = fade(y), w = fade(z)
        let A = perm[X] + Y, AA = perm[A] + Z, AB = perm[A + 1] + Z
        let B = perm[X + 1] + Y, BA = perm[B] + Z, BB = perm[B + 1] + Z
        return lerp(lerp(lerp(grad(perm[AA] & 15, x, y, z), grad(perm[BA] & 15, x - 1, y, z), u),
                         lerp(grad(perm[AB] & 15, x, y - 1, z), grad(perm[BB] & 15, x - 1, y - 1, z), u), v),
                    lerp(lerp(grad(perm[AA + 1] & 15, x, y, z - 1), grad(perm[BA + 1] & 15, x - 1, y, z - 1), u),
                         lerp(grad(perm[AB + 1] & 15, x, y - 1, z - 1), grad(perm[BB + 1] & 15, x - 1, y - 1, z - 1), u), v), w)
    }

    /// Sharp lines where the noise crosses zero: fold lines.
    static func ridge(_ x: Float, _ y: Float, _ z: Float) -> Float {
        let n = 1 - abs(noise(x, y, z))
        return n * n
    }
}

// MARK: - The sheet

/// One sticky's sheet: every point of it laid flat (the card) and crumpled
/// (the ball), and when each starts to open. Points are in the card's own
/// points, centred, y up.
struct CrumpleSheet {
    /// How crinkled the ball is, 0…1 — the prototype's slider, settled at 0.8.
    static let depth: Float = 0.8
    /// The ball in the line, across — a little over the type's height.
    static let ballDiameter: Float = 24
    /// The centre of the sheet opens first and the edges last, by this much
    /// of the unfold.
    static let delaySpread: Float = 0.32

    let size: CGSize
    let columns: Int
    let rows: Int
    /// The ball's radius before it is scaled down to the line — sized to
    /// the sheet's area, so a tall sticky makes a ball as round as a square one.
    let radius: Float
    private(set) var flat: [SIMD3<Float>] = []
    private(set) var ball: [SIMD3<Float>] = []
    private(set) var delay: [Float] = []
    private(set) var wrinkle: [Float] = []

    init(size: CGSize, depth: Float = CrumpleSheet.depth) {
        self.size = size
        let w = Float(max(size.width, 1)), h = Float(max(size.height, 1))
        columns = 56
        rows = min(140, max(8, Int((56 * h / w).rounded())))
        radius = 58 * (w * h).squareRoot() / 280
        for row in 0...rows {
            for column in 0...columns {
                let x: Float = (Float(column) / Float(columns) - 0.5) * w
                let y: Float = (0.5 - Float(row) / Float(rows)) * h
                flat.append(SIMD3<Float>(x, y, 0))
                let u: Float = x / (w / 2), v: Float = y / (h / 2)
                let r: Float = min(1, (u * u + v * v).squareRoot() / Float(2).squareRoot())
                // Gathered like a handkerchief: the middle of the sheet faces
                // out, the edges are drawn round to the back, with a twist as
                // they go.
                let theta: Float = atan2(v, u) + r * 1.4
                let alpha: Float = r * .pi * 0.93
                let d = SIMD3<Float>(sin(alpha) * cos(theta), sin(alpha) * sin(theta), cos(alpha))
                let lump: Float = 1 + 0.14 * Crease.noise(d.x * 1.6 + 3.1, d.y * 1.6, d.z * 1.6)
                let coarse: Float = Crease.ridge(d.x * 2.6, d.y * 2.6, d.z * 2.6)
                let fine: Float = Crease.ridge(d.x * 5.3 + 9, d.y * 5.3, d.z * 5.3)
                let crease: Float = coarse * 0.62 + fine * 0.38 - 0.5
                let reach: Float = radius * (lump + crease * 0.42 * depth)
                ball.append(d * reach)
                delay.append(r * Self.delaySpread)
                // Creases left in the paper as it flattens, gone once it's flat.
                let broad: Float = Crease.ridge(u * 2.2 + 4, v * 2.2, 1.7)
                let small: Float = Crease.ridge(u * 4.4, v * 4.4 + 2, 5.1)
                let left: Float = (broad * 0.7 + small * 0.3 - 0.45) * 26 * depth
                wrinkle.append(left)
            }
        }
    }

    var count: Int { flat.count }

    /// Texture coordinates, the image's top left at (0, 0).
    var uvs: [CGPoint] {
        var out: [CGPoint] = []
        out.reserveCapacity(count)
        for row in 0...rows {
            for column in 0...columns {
                out.append(CGPoint(x: Double(column) / Double(columns), y: Double(row) / Double(rows)))
            }
        }
        return out
    }

    /// Two triangles a cell, wound so the card's face is the front.
    var indices: [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(columns * rows * 6)
        let stride = UInt32(columns + 1)
        for row in 0..<UInt32(rows) {
            for column in 0..<UInt32(columns) {
                let a = column + stride * row, b = column + stride * (row + 1)
                let c = column + 1 + stride * (row + 1), d = column + 1 + stride * row
                out += [a, b, d, b, c, d]
            }
        }
        return out
    }

    /// Every point, `unfold` of the way from the ball to flat (0…1).
    func positions(unfold: Float, into out: inout [SCNVector3]) {
        if out.count != count { out = Array(repeating: SCNVector3Zero, count: count) }
        let span = 1 - Self.delaySpread
        for i in 0..<count {
            let p = Ease.inOutCubic(Ease.clamp((unfold - delay[i]) / span))
            let settle = 4 * p * (1 - p) // creases linger mid-way
            let at = ball[i] + (flat[i] - ball[i]) * p
            out[i] = SCNVector3(at.x, at.y, at.z + wrinkle[i] * settle)
        }
    }
}

enum Ease {
    static func clamp(_ t: Float) -> Float { min(1, max(0, t)) }
    static func outCubic(_ t: Float) -> Float { 1 - pow(1 - t, 3) }
    static func inOutCubic(_ t: Float) -> Float { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
}

// MARK: - The scene

/// The sheet, its shadow, the light and an orthographic camera measured in
/// screen points — rendered by the stage over the app, or offscreen for the
/// ball in the line.
final class CrumpleScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let sheetNode = SCNNode()
    private let shadowNode = SCNNode()
    private var sheet: CrumpleSheet?
    private var buffer: [SCNVector3] = []
    private var normals: SCNGeometrySource?
    private var uvs: SCNGeometrySource?
    private var element: SCNGeometryElement?
    private let front = CrumpleScene.paper(cull: .back)
    private let back = CrumpleScene.paper(cull: .front)
    private(set) var viewport = CGSize(width: 1, height: 1)

    init() {
        scene.background.contents = UIColor.clear
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 1
        camera.zFar = 4000
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 1000)
        scene.rootNode.addChildNode(cameraNode)

        // Lit so that the sheet, lying flat, comes out the colour of the card
        // it hands over to: ambient plus the sun's share facing it is 1.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 600
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 500
        sun.position = SCNVector3(-400, 600, 1000)
        sun.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(sun)

        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.writesToDepthBuffer = false
        shadowNode.geometry = SCNPlane(width: 1, height: 1)
        shadowNode.geometry?.materials = [shadowMaterial]
        scene.rootNode.addChildNode(shadowNode)
        scene.rootNode.addChildNode(sheetNode)
        rest()
    }

    // Paper is lit as matte facets — the normals come from the facets
    // themselves, so every crease catches the light — and the stamp's
    // perforations are cut out of it.
    private static func paper(cull: SCNCullMode) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.cullMode = cull
        m.transparencyMode = .aOne
        m.diffuse.mipFilter = .linear
        m.shaderModifiers = [
            .surface: """
            #pragma body
            _surface.normal = normalize(cross(dfdy(_surface.position), dfdx(_surface.position)));
            """,
            .fragment: """
            #pragma body
            if (_output.color.a < 0.5) { discard_fragment(); }
            """,
        ]
        return m
    }

    func setViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewport = size
        cameraNode.camera?.orthographicScale = Double(size.height / 2)
    }

    /// A new sheet the size of the card, with the card's two faces.
    func load(size: CGSize, front frontImage: UIImage, back backImage: UIImage) {
        if sheet?.size != size {
            let sheet = CrumpleSheet(size: size)
            self.sheet = sheet
            normals = SCNGeometrySource(normals: Array(repeating: SCNVector3(0, 0, 1), count: sheet.count))
            uvs = SCNGeometrySource(textureCoordinates: sheet.uvs)
            element = SCNGeometryElement(indices: sheet.indices, primitiveType: .triangles)
        }
        front.diffuse.contents = frontImage
        back.diffuse.contents = backImage
        let shadow = CrumpleArt.shadow(for: size)
        shadowNode.geometry?.firstMaterial?.diffuse.contents = shadow
        (shadowNode.geometry as? SCNPlane)?.width = shadow.size.width
        (shadowNode.geometry as? SCNPlane)?.height = shadow.size.height
    }

    /// The face, swapped once its words are drawn.
    func setFront(_ image: UIImage) {
        front.diffuse.contents = image
    }

    /// Nothing to show: the sheet put away.
    func rest() {
        sheetNode.isHidden = true
        shadowNode.isHidden = true
    }

    /// The sheet at `t` of the way from the ball at `mark` (0) to flat over
    /// `card` (1), both in screen points. No mark: it crumples to nothing
    /// where it is — a sticky deleted, rather than put away.
    func pose(_ t: Float, mark: CGPoint?, card: CGRect, elapsed: Float) {
        guard let sheet, let normals, let uvs, let element else { return }
        let travel = Ease.outCubic(Ease.clamp(t / 0.42))
        let unfold = Ease.clamp((t - 0.26) / 0.74)
        sheet.positions(unfold: unfold, into: &buffer)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: buffer), normals, uvs],
                                   elements: [element, element])
        geometry.materials = [front, back]
        sheetNode.geometry = geometry

        let end = scenePoint(CGPoint(x: card.midX, y: card.midY))
        let start = mark.map(scenePoint) ?? end
        let lift = sin(travel * .pi) * 46 // an arc on the way
        sheetNode.position = SCNVector3(start.x + (end.x - start.x) * travel,
                                        start.y + (end.y - start.y) * travel + lift, 0)
        let closed = mark == nil ? 0.001 : CrumpleSheet.ballDiameter / (2 * sheet.radius)
        let scale = closed + (1 - closed) * travel
        sheetNode.scale = SCNVector3(scale, scale, scale)
        let tumble = 1 - unfold
        sheetNode.eulerAngles = SCNVector3(
            tumble * 0.55 + (1 - travel) * 0.2 * sin(elapsed * 1.2),
            tumble * (0.9 + (1 - travel) * 1.6),
            tumble * -0.5)
        shadowNode.position = SCNVector3(end.x, end.y, -900)
        // Only as the sheet comes down flat, once it covers the card's
        // footprint — earlier, the clear middle showed as a pale outline.
        shadowNode.opacity = CGFloat(Ease.clamp((unfold - 0.8) / 0.2))
        sheetNode.isHidden = false
        shadowNode.isHidden = false
    }

    private func scenePoint(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(p.x - viewport.width / 2), Float(viewport.height / 2 - p.y))
    }
}

// MARK: - Pictures of the card

/// What the card is drawn with, read on the main thread — the mood, the
/// typeface and the artwork — so the picture itself can be drawn anywhere.
struct StampLook {
    let sticky: UIColor
    let panel: UIColor
    let attributes: [NSAttributedString.Key: Any]
    let flourish: UIImage?
    let key: String

    static var current: StampLook {
        _ = Surface.sticky.paper.image // loaded here, so other threads only read it
        return StampLook(sticky: Style.theme.sticky, panel: Style.theme.panel,
                         attributes: StickyTextView.attributes,
                         flourish: AnimatedFlourish.frames(.sticky).last,
                         key: "\(Style.theme.id)-\(Style.fontFamily)")
    }
}

enum CrumpleArt {
    // Twice the card's points: the sheet is only ever this sharp while it is
    // moving, and lies flat for a twentieth of a second before the card takes
    // over — 3x drew 2.25 times the pixels for nothing anyone sees.
    private static let scale: CGFloat = 2

    /// The card as it looks: sticky colour, sticky paper, the flourish (when
    /// it has drawn itself) and the words, cut to the stamp. Drawn the way
    /// `StickyCard` lays itself out, so the hand-over can't be seen. Safe off
    /// the main thread, given a `look` read on it.
    static func stamp(size: CGSize, text: String?, flourish: Bool,
                      look: StampLook = .current) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            let outline = StampOutline.path(in: rect)
            outline.usesEvenOddFillRule = true
            outline.addClip()
            look.sticky.setFill()
            UIRectFill(rect)
            Surface.sticky.draw(in: rect)
            if flourish, let last = look.flourish {
                let width = StickyCard.side * StickyCard.flourishWidth
                let frame = CGRect(x: StickyCard.side * (StickyCard.flourishRight - StickyCard.flourishWidth),
                                   y: size.height - StickyCard.flourishOnStamp,
                                   width: width, height: StickyCard.flourishHeight)
                tinted(last, look.panel, size: frame.size)
                    .draw(in: frame, blendMode: .multiply, alpha: 1)
            }
            if let text, !text.isEmpty {
                words(text, cardHeight: size.height, attributes: look.attributes)
                    .draw(at: CGPoint(x: StickyCard.textSides, y: StickyCard.textTop))
            }
        }
    }

    /// The back of the card, and the face before its words are drawn: just
    /// the paper. The same for every sticky of a size, so kept.
    static func blank(size: CGSize, look: StampLook = .current) -> UIImage {
        let key = "\(look.key)-\(Int(size.width))x\(Int(size.height))"
        if let hit = blanks[key] { return hit }
        let image = stamp(size: size, text: nil, flourish: false, look: look)
        if blanks.count > 8 { blanks.removeAll() }
        blanks[key] = image
        return image
    }

    private static var blanks: [String: UIImage] = [:]

    /// The words in the card's text box, laid out by TextKit 1 exactly as the
    /// card's text view lays them out — and, when they run on past the box,
    /// faded at its foot as the text view's `EdgeFade` fades them.
    private static func words(_ text: String, cardHeight: CGFloat,
                              attributes: [NSAttributedString.Key: Any]) -> UIImage {
        let inset = StickyTextView.inset
        let box = CGSize(width: StickyCard.textWidth,
                         height: max(1, StickyCard.textHeight(cardHeight: cardHeight)))
        let storage = NSTextStorage(string: text, attributes: attributes)
        let lm = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: box.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(lm)
        lm.addTextContainer(container)
        lm.ensureLayout(for: container)
        let extra = lm.extraLineFragmentRect
        let used = max(lm.usedRect(for: container).maxY, extra.isEmpty ? 0 : extra.maxY)
        let below = max(0, ceil(used) + inset.top + inset.bottom - box.height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: box, format: format).image { context in
            let cg = context.cgContext
            let shown = lm.glyphRange(forBoundingRect: CGRect(x: 0, y: 0, width: box.width, height: box.height),
                                      in: container)
            lm.drawGlyphs(forGlyphRange: shown, at: CGPoint(x: 0, y: inset.top))
            let band = StickyCaretTextView.fadeBand
            let fade = min(1, below / band)
            guard fade > 0 else { return }
            // Erase towards the foot: nothing at the top of the band, `fade`
            // of the ink at the bottom.
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceGray(),
                colors: [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: fade).cgColor] as CFArray,
                locations: [0, 1])!
            cg.setBlendMode(.destinationOut)
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: box.height - band),
                                  end: CGPoint(x: 0, y: box.height),
                                  options: [.drawsAfterEndLocation])
        }
    }

    private static func tinted(_ image: UIImage, _ color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            image.draw(in: rect)
            color.setFill()
            UIRectFillUsingBlendMode(rect, .sourceIn)
        }
    }

    /// The card's soft shadow, for while the sheet lies flat — with the card's
    /// own footprint left clear, so it never shows through a lifting corner.
    static func shadow(for size: CGSize) -> UIImage {
        let pad: CGFloat = 30
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let canvas = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let cg = context.cgContext
            let card = CGRect(x: pad, y: pad, width: size.width, height: size.height)
            cg.setShadow(offset: .zero, blur: 20, color: UIColor.black.withAlphaComponent(0.08).cgColor)
            UIColor.black.setFill()
            cg.fill(card)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.clear(card)
        }
    }

    /// The ball in the line, in the current mood: a blank card, crumpled,
    /// at rest. Rendered once per mood.
    static func marginBall() -> UIImage? {
        let key = Style.theme.id
        if let hit = balls[key] { return hit }
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let side = CGFloat(CrumpleSheet.ballDiameter) + 6, scale = min(3, UIScreen.main.scale)
        let crumple = CrumpleScene()
        crumple.setViewport(CGSize(width: side, height: side))
        let paper = blank(size: CGSize(width: StickyCard.side, height: StickyCard.side))
        crumple.load(size: paper.size, front: paper, back: paper)
        let centre = CGPoint(x: side / 2, y: side / 2)
        crumple.pose(0, mark: centre, card: CGRect(origin: centre, size: .zero).insetBy(dx: -1, dy: -1), elapsed: 0)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = crumple.scene
        renderer.pointOfView = crumple.cameraNode
        let shot = renderer.snapshot(atTime: 0, with: CGSize(width: side * scale, height: side * scale),
                                     antialiasingMode: .multisampling4X)
        guard let cg = shot.cgImage else { return nil }
        let image = UIImage(cgImage: cg, scale: scale, orientation: .up)
        balls[key] = image
        return image
    }

    private static var balls: [String: UIImage] = [:]
}

// MARK: - Running it

/// Runs the fold, and decides when the real card is on screen. One for the
/// app: the page asks it where a ball is, the card tells it where the card is.
final class CrumpleDirector: ObservableObject {
    static let shared = CrumpleDirector()

    /// The sticky whose real card is showing — set once its sheet has landed
    /// flat, cleared once a sheet has taken its place on the way out.
    @Published private(set) var cardID: UUID?
    /// Where the open card is, in screen points — kept up to date by the card.
    var cardFrame: CGRect = .zero
    /// The note page, which knows where each sticky's ball sits.
    weak var page: RuledTextView?
    /// The sticky whose ball has left its place in the line.
    private(set) var flyingID: UUID? {
        didSet { if flyingID != oldValue { page?.showFlight() } }
    }

    let stage = CrumpleScene()
    weak var view: SCNView?

    static let openSeconds: Float = 1.15
    static let closeSeconds: Float = 0.95
    // How long a hand-over keeps both the card and the sheet on screen, so
    // neither leaves before the other has drawn.
    private static let handOver: TimeInterval = 0.05

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var t: Float = 0
    private var target: Float = 0
    private var elapsed: Float = 0
    private var id: UUID?
    private var mark: CGPoint?
    private var card: CGRect = .zero
    // Counts sheets loaded, so a face drawn in the background for one is
    // never put on a later one.
    private var generation = 0
    // The open sticky's words, and the face it will be put away with —
    // drawn in the background while it is open, so putting it away doesn't
    // stop to draw. Redrawn on the spot if the words have changed since.
    private var openText = ""
    private var closingFace: (text: String, size: CGSize, key: String, image: UIImage)?

    func open(_ id: UUID, text: String, frame: CGRect) {
        if prefersReducedMotion {
            withAnimation(.easeOut(duration: 0.2)) { cardID = id }
            flyingID = id
            return
        }
        if self.id == id, link != nil { // put away and taken out again mid-way
            target = 1
            return
        }
        stop()
        self.id = id
        card = frame
        openText = text
        closingFace = nil
        mark = page?.markCentre(for: id)
        // Off at once with plain paper; the words are drawn in the background
        // and pressed on while the ball is still too small to read them.
        let look = StampLook.current
        let paper = CrumpleArt.blank(size: frame.size, look: look)
        stage.load(size: frame.size, front: paper, back: paper)
        generation += 1
        if !text.isEmpty {
            let generation = self.generation, size = frame.size
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let face = CrumpleArt.stamp(size: size, text: text, flourish: false, look: look)
                DispatchQueue.main.async {
                    if self?.generation == generation { self?.stage.setFront(face) }
                }
            }
        }
        t = 0
        target = 1
        run()
        // The ball in the scene is drawing now; the one in the line can go.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOver) { [weak self] in
            if self?.id == id { self?.flyingID = id }
        }
    }

    /// `text` is nil when the sticky is gone — deleted, or put away unwritten.
    func close(_ id: UUID, text: String?) {
        if prefersReducedMotion {
            withAnimation(.easeOut(duration: 0.2)) { cardID = nil }
            flyingID = nil
            return
        }
        let gone = text == nil
        if self.id == id, link != nil, target == 1 { // still opening: turn back
            target = 0
            if gone { mark = nil }
            return
        }
        stop()
        self.id = id
        if cardFrame.width > 0 { card = cardFrame }
        mark = gone ? nil : page?.markCentre(for: id)
        let look = StampLook.current
        let face: UIImage
        if let ready = closingFace, ready.size == card.size, ready.key == look.key,
           gone || ready.text == text {
            face = ready.image
        } else {
            face = CrumpleArt.stamp(size: card.size, text: text ?? openText, flourish: true, look: look)
        }
        closingFace = nil
        stage.load(size: card.size, front: face, back: CrumpleArt.blank(size: card.size, look: look))
        generation += 1
        t = 1
        target = 0
        flyingID = id
        run()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOver) { [weak self] in
            if self?.cardID == id { self?.cardID = nil }
        }
    }

    private func run() {
        if let view { stage.setViewport(view.bounds.size) }
        elapsed = 0
        last = CACurrentMediaTime()
        stage.pose(t, mark: mark, card: card, elapsed: elapsed)
        view?.rendersContinuously = true
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stop() {
        link?.invalidate()
        link = nil
        if cardID != nil, cardID != id { cardID = nil }
        flyingID = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = min(0.05, Float(now - last))
        last = now
        elapsed += dt
        if t != target {
            let step = dt / (target > t ? Self.openSeconds : Self.closeSeconds)
            t = target > t ? min(target, t + step) : max(target, t - step)
        }
        stage.pose(t, mark: mark, card: card, elapsed: elapsed)
        if t == target { landed() }
    }

    /// Kept up to date by the card as it is written in; the face it will be
    /// put away with is redrawn once the typing pauses.
    func textChanged(_ text: String) {
        guard text != openText else { return }
        openText = text
        redraw?.cancel()
        let id = self.id
        let work = DispatchWorkItem { [weak self] in self?.prepareClosingFace(for: id) }
        redraw = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private var redraw: DispatchWorkItem?

    private func prepareClosingFace(for id: UUID?) {
        guard id != nil, self.id == id, cardID == id, link == nil, cardFrame.width > 0 else { return }
        let text = openText, size = cardFrame.size, look = StampLook.current
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = CrumpleArt.stamp(size: size, text: text, flourish: true, look: look)
            DispatchQueue.main.async {
                guard let self, self.id == id, self.cardID == id else { return }
                self.closingFace = (text, size, look.key, image)
            }
        }
    }

    private func landed() {
        link?.invalidate()
        link = nil
        let id = self.id
        if target == 1 {
            cardID = id // the real card, flat where the sheet is; its flourish starts now
            // Once the card has said where it is, draw the face it will be
            // put away with.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.prepareClosingFace(for: id)
            }
        } else {
            flyingID = nil // the ball is back in the line
            self.id = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOver) { [weak self] in
            guard let self, self.link == nil else { return }
            self.stage.rest()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.link == nil { self.view?.rendersContinuously = false }
            }
        }
    }
}

/// The stage the sheet is drawn on, over everything, never touched.
struct CrumpleStageView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let director = CrumpleDirector.shared
        let view = SCNView(frame: .zero, options: nil)
        view.scene = director.stage.scene
        view.pointOfView = director.stage.cameraNode
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = false
        view.rendersContinuously = false
        director.view = view
        // Compile the paper's shaders now, not on the first tap.
        let paper = CrumpleArt.blank(size: CGSize(width: 40, height: 40))
        director.stage.load(size: paper.size, front: paper, back: paper)
        director.stage.setViewport(UIScreen.main.bounds.size)
        director.stage.pose(1, mark: nil, card: CGRect(x: -100, y: -100, width: 40, height: 40), elapsed: 0)
        view.prepare([director.stage.scene]) { _ in
            DispatchQueue.main.async { if director.view?.rendersContinuously == false { director.stage.rest() } }
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
