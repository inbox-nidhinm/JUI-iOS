import SwiftUI
import UIKit

// First run, as drawn in Figma (node 243:120): a letter tucked into an
// envelope. The title shows through the flap's V; after the flourish draws
// itself the letter slides up out of the envelope to reveal the controls, and
// the remaining steps swap the letter's contents.
//
// The envelope's geometry is the design's own, in its own units (see `D`),
// multiplied by one scale factor so the composition keeps its proportions.
//
// Two changes from the Mac, both because of the phone:
// - The letter's contents are stacked rather than placed at the design's
//   offsets. At phone scale the envelope is about 0.4 of the design, but the
//   controls stay at a size a finger can use, so the design's positions put
//   one button on top of the next.
// - There is no vault step. Notes live in the app's own folder, shown in the
//   Files app, so there is nothing to choose.

private enum D {
    static let envW: CGFloat = 915
    static let envH: CGFloat = 593
    static let notch: CGFloat = 250 // depth of the flap's V, apex on centre

    static let letterW: CGFloat = 882
    static let letterH: CGFloat = 777
    static let letterX: CGFloat = 16
    static let letterTucked: CGFloat = -184 // Screen One
    static let letterRaised: CGFloat = -465 // Screens Two–Four

    static let contentY: CGFloat = 200
    static let contentW: CGFloat = 640

    static let sprigW: CGFloat = 105.877
    static let sprigH: CGFloat = 158.092
    static let sprigGrowth: CGFloat = 1.25
    static let sprigCX: CGFloat = 458
    static let sprigCY: CGFloat = 427

    // tallest the composition ever gets: raised letter above the envelope
    static var assemblyH: CGFloat { -letterRaised + envH }
}

// Fixed point sizes from the app's own scale, held regardless of how small
// the envelope is drawn — a phone's envelope is far smaller than a Mac
// window's, and scaling type with it would make the title unreadable.
private enum T {
    static let title: CGFloat = 16
    static let control: CGFloat = 14
    static let back: CGFloat = 12
    static let controlH: CGFloat = 40
    static let controlRadius: CGFloat = 10
    static let controlPadH: CGFloat = 20
}

// The envelope's front: a rectangle with a triangular notch taken out of the
// top, so the letter behind shows through the opening.
struct EnvelopeFront: Shape {
    let notchDepth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + notchDepth))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct OnboardingView: View {
    @ObservedObject var store: NotesStore

    // name (who) → mood (how it looks)
    private enum Step { case welcome, name, mood }

    @State private var step: Step = .welcome
    @State private var presented = false
    @State private var letterRaised = false
    @State private var finishing = false
    @State private var closing = false
    @State private var sceneOpacity: Double = 0
    @State private var name = ""
    @State private var nameFocused = false

    var body: some View {
        GeometryReader { geo in
            let s = scale(for: geo.size)
            ZStack {
                // It also swallows every tap, so nothing behind can be reached
                // until this is finished.
                sheetColor.opacity(0.8)
                    .contentShape(Rectangle())
                    .onTapGesture { hideKeyboard() }

                ZStack {
                    envelope(s)
                        .offset(y: envelopeOffset(s))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                // While the name is being typed the keyboard takes the bottom
                // of the screen; the envelope steps up out of its way.
                .offset(y: step == .name && nameFocused ? -geo.size.height * 0.12 : 0)
                .scaleEffect(sceneScale)
                .offset(y: sceneTravel(geo.size.height))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .compositingGroup()
            .opacity(sceneOpacity)
            .allowsHitTesting(!finishing)
        }
        .ignoresSafeArea()
        .onAppear(perform: runIntro)
    }

    private var sceneScale: CGFloat {
        if closing { return 0.5 }
        return presented ? 1 : 0.5
    }

    private func sceneTravel(_ height: CGFloat) -> CGFloat {
        if closing { return height * 0.55 }
        return presented ? 0 : height * 0.55
    }

    // MARK: Composition

    private func envelope(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // the envelope's inside, visible once the letter has risen past it
            envelopeColor
                .papered(.envelope)
                .frame(width: D.envW * s, height: D.envH * s)
                .allowsHitTesting(false)

            letter(s)
                .offset(x: D.letterX * s, y: letterOffset * s)

            // Papered then clipped: the paper has to stop at the flap's V.
            // Scenery, so it takes no taps — clipShape clips drawing, not hit
            // testing, and the V is exactly where the letter's controls sit.
            envelopeColor
                .papered(.envelope)
                .frame(width: D.envW * s, height: D.envH * s)
                .clipShape(EnvelopeFront(notchDepth: D.notch * s))
                .allowsHitTesting(false)

            if !AnimatedFlourish.frames(.corner).isEmpty {
                AnimatedFlourish(tint: flourishColor, play: .always)
                    .frame(width: D.sprigH * D.sprigGrowth * AnimatedFlourish.aspect(.corner) * s,
                           height: D.sprigH * D.sprigGrowth * s)
                    .offset(
                        x: (D.sprigCX - D.sprigW / 2) * s,
                        y: (D.sprigCY - D.sprigH / 2) * s)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: D.envW * s, height: D.envH * s, alignment: .topLeading)
    }

    private func letter(_ s: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // The notes' own paper, faintly tinted: the letter is the first
            // sheet of the pad.
            PagePaper(tint: 0.3)
                .frame(width: D.letterW * s, height: D.letterH * s)

            // On the way out the letter goes back in blank, like it's being
            // put away.
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case .welcome:
                        title("a calm place\nto write")
                    case .name:
                        VStack(spacing: 16) {
                            title("let’s start\nwith your name,")
                            nameField(s)
                        }
                    case .mood:
                        VStack(spacing: 12) {
                            title("pick your\nmood")
                            ThemePicker(store: store, diameter: 24, spacing: 14)
                        }
                    }
                }
                .transition(.opacity)

                primaryButton
                    .padding(.top, step == .welcome ? 34 : 20)

                if step != .welcome {
                    backButton
                }
            }
            .frame(width: D.contentW * s)
            .padding(.top, D.contentY * s)
            .opacity(finishing ? 0 : 1)
        }
        .frame(width: D.letterW * s, height: D.letterH * s, alignment: .top)
    }

    // MARK: Pieces

    private func title(_ text: String) -> some View {
        Text(text)
            .font(houseFont(T.title))
            .foregroundStyle(brownInk)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func nameField(_ s: CGFloat) -> some View {
        HouseField(
            text: $name,
            size: T.control,
            centered: true,
            placeholder: "your name",
            focused: nameFocused,
            returnKey: .next,
            capitalization: .words,
            onSubmit: { if canAdvance { advance() } })
            .frame(height: T.control + 6)
            .padding(.horizontal, T.controlPadH)
            .frame(width: D.contentW * s, height: T.controlH)
            .background(RoundedRectangle(cornerRadius: T.controlRadius).fill(sheetColor))
    }

    private var primaryButton: some View {
        OnboardingPill(
            title: step == .welcome ? "begin" : "next",
            enabled: canAdvance,
            action: advance)
    }

    private var backButton: some View {
        Button(action: goBack) {
            Text("back")
                .font(houseFont(T.back))
                .foregroundStyle(inkMuted)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Layout maths

    // One factor for the whole scene, so the design's proportions survive.
    // On a phone it is width that binds, and the envelope is allowed nearly the
    // full width of the screen.
    private func scale(for size: CGSize) -> CGFloat {
        let byWidth = (size.width * 0.94) / D.envW
        let byHeight = (size.height * 0.84) / D.assemblyH
        return max(min(byWidth, byHeight), 0.2)
    }

    private var letterOffset: CGFloat {
        letterRaised ? D.letterRaised : D.letterTucked
    }

    // Keeps the letter-plus-envelope composition centred, which is why the
    // envelope drifts down as the letter rises (exactly as the frames do).
    private func envelopeOffset(_ s: CGFloat) -> CGFloat {
        -letterOffset * s / 2
    }

    // MARK: State

    private var canAdvance: Bool {
        switch step {
        case .welcome, .mood: return true
        case .name: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: Behaviour

    private func runIntro() {
        // On a replay the name is already known; seeding it means tapping
        // straight through changes nothing.
        if name.isEmpty { name = store.displayName }
        if prefersReducedMotion {
            presented = true
            letterRaised = true
            sceneOpacity = 1
            return
        }
        withAnimation(.easeOut(duration: 0.55)) {
            presented = true
            sceneOpacity = 1
        }
        // The letter waits for the flourish to finish drawing, timed off the
        // sequence's own length.
        let afterFlourish = AnimatedFlourish.duration + 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + afterFlourish) {
            withAnimation(.easeInOut(duration: 0.75)) { letterRaised = true }
        }
    }

    private func advance() {
        guard canAdvance else { return }
        switch step {
        case .welcome:
            transition(to: .name)
        case .name:
            store.setDisplayName(name)
            transition(to: .mood)
        case .mood:
            finish()
        }
    }

    private func goBack() {
        switch step {
        case .welcome: break
        case .name: transition(to: .welcome)
        case .mood: transition(to: .name)
        }
    }

    private func transition(to next: Step) {
        if next != .name { hideKeyboard() }
        if prefersReducedMotion {
            step = next
            nameFocused = next == .name
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                step = next
                nameFocused = next == .name
            }
        }
    }

    // The flow closes the way it opened, in reverse: the letter slides back
    // into the envelope, then the envelope sinks away and shrinks as it fades.
    private func finish() {
        guard !finishing else { return }
        store.setDisplayName(name)
        hideKeyboard()
        guard !prefersReducedMotion else {
            store.completeOnboarding()
            return
        }
        finishing = true
        nameFocused = false
        withAnimation(.easeInOut(duration: 0.7)) { letterRaised = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeIn(duration: 0.5)) {
                closing = true
                sceneOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                store.completeOnboarding()
            }
        }
    }
}

// The design's pill button: folderBase at rest, lifting to sheet when pressed.
struct OnboardingPill: View {
    var theme = Style.theme.id // redraw on a theme change — see Style.theme
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(houseFont(T.control))
                .foregroundStyle(enabled ? brownInk : inkFaint)
                .padding(.horizontal, T.controlPadH + 8)
                .frame(height: T.controlH)
                .contentShape(RoundedRectangle(cornerRadius: T.controlRadius))
        }
        .buttonStyle(PillStyle(enabled: enabled))
        .disabled(!enabled)
    }

    // The mood's own colour — the one its dot shows — on the sticky paper,
    // so the button follows the mood as it is picked. A step deeper while
    // pressed; faded while there is nothing to go on with.
    private struct PillStyle: ButtonStyle {
        var theme = Style.theme.id // redraw on a theme change — see Style.theme
        let enabled: Bool
        func makeBody(configuration: Configuration) -> some View {
            let fill = configuration.isPressed
                ? Color(uiColor: Style.theme.sticky.blended(0.15, toward: Style.theme.ink))
                : stickyColor
            configuration.label
                .background(
                    fill
                        .papered(.sticky)
                        .clipShape(RoundedRectangle(cornerRadius: T.controlRadius))
                        .opacity(enabled ? 1 : 0.45))
        }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
