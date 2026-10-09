import SceneKit
import XCTest
@testable import JUI

// The crumpled sticky's sheet: that it really is the card at one end and a
// ball at the other, and that lying flat it renders the card's own colour —
// the hand-over to the real card is invisible only if it does.
final class CrumpleTests: XCTestCase {
    func testSheetIsTheCardWhenFlatAndABallWhenCrumpled() {
        let sheet = CrumpleSheet(size: CGSize(width: 280, height: 360))
        var out: [SCNVector3] = []
        sheet.positions(unfold: 1, into: &out)
        for (p, f) in zip(out, sheet.flat) {
            XCTAssertEqual(p.x, f.x, accuracy: 0.001)
            XCTAssertEqual(p.y, f.y, accuracy: 0.001)
            XCTAssertEqual(p.z, 0, accuracy: 0.001)
        }
        sheet.positions(unfold: 0, into: &out)
        let reach = out.map { ($0.x * $0.x + $0.y * $0.y + $0.z * $0.z).squareRoot() }
        XCTAssertLessThan(reach.max()!, sheet.radius * 1.6)
    }

    func testFlatSheetRendersTheCardsColour() throws {
        let viewport = CGSize(width: 390, height: 844)
        let card = CGRect(x: 55, y: 282, width: 280, height: 280)
        let mark = CGPoint(x: 368, y: 52 + 48 * 7 + 24)
        let text = "remember to buy more of\nthe good paper — the heavy\ncream one from the shop\nby the station."
        let front = CrumpleArt.stamp(size: card.size, text: text, flourish: false)
        let back = CrumpleArt.stamp(size: card.size, text: nil, flourish: false)
        let crumple = CrumpleScene()
        crumple.setViewport(viewport)
        crumple.load(size: card.size, front: front, back: back)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = crumple.scene
        renderer.pointOfView = crumple.cameraNode

        let dir = ProcessInfo.processInfo.environment["CRUMPLE_SHOTS"]
        var flat: UIImage?
        for t: Float in [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1] {
            crumple.pose(t, mark: mark, card: card, elapsed: t)
            let shot = renderer.snapshot(atTime: 0, with: CGSize(width: viewport.width * 2, height: viewport.height * 2),
                                         antialiasingMode: .multisampling4X)
            if t == 1 { flat = shot }
            if let dir {
                try shot.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("crumple-\(Int(t * 100)).png"))
            }
        }
        if let dir {
            try front.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("crumple-texture.png"))
            try CrumpleArt.marginBall()?.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("crumple-ball.png"))
            // A sticky longer than the screen allows: its words fade at the foot.
            let long = (1...30).map { "line \($0) of a long sticky" }.joined(separator: "\n")
            try CrumpleArt.stamp(size: CGSize(width: 280, height: 520), text: long, flourish: true)
                .pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("crumple-long.png"))
        }

        // A spot clear of the words, in the rendered sheet and in the picture.
        let spot = CGPoint(x: 140, y: 230)
        let rendered = try XCTUnwrap(flat).pixel(at: CGPoint(x: (card.minX + spot.x) * 2, y: (card.minY + spot.y) * 2))
        let painted = front.pixel(at: CGPoint(x: spot.x * front.scale, y: spot.y * front.scale))
        for (r, p) in zip(rendered, painted) { XCTAssertEqual(r, p, accuracy: 0.06) }
    }
}

private extension UIImage {
    /// RGBA, 0…1, at a pixel position.
    func pixel(at p: CGPoint) -> [CGFloat] {
        guard let cg = cgImage else { return [] }
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -p.x, y: -(CGFloat(cg.height) - p.y - 1),
                                width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return data.map { CGFloat($0) / 255 }
    }
}
