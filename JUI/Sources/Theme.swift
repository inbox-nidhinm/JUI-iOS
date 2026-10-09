import SwiftUI
import UIKit

// A theme is a complete recolour of the app. Every colour the app draws comes
// from the active one, so switching swaps the whole surface at once — sheet,
// panel, ink, stickies, rules, the flourish, the onboarding envelope.
//
// Ported from the macOS re-JUI unchanged in value: the five alternates hold the
// cream original's lightness and saturation and rotate only hue, so hierarchy
// and contrast survive in all six. See mac-reference/Theme.swift for the
// derivation.
//
// Held as UIColor because UIKit needs them (text storage, caret tint, sticky
// marks) and SwiftUI can always borrow one via Color(uiColor:), so each value
// exists exactly once.
struct Theme: Identifiable, Equatable {
    let id: String
    let label: String

    let sheet: UIColor          // the page
    let panel: UIColor          // panels, palette, settings cards
    let folderBase: UIColor     // folder card at rest
    let envelope: UIColor       // onboarding envelope
    let letterSheet: UIColor    // onboarding letter
    let ink: UIColor            // every word in the app
    let sticky: UIColor         // sticky notes — the anchor tone
    let openDot: UIColor        // the dot marking the open note; the picker's ring
    let flourish: UIColor       // onboarding's flourish

    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id }
}

private func rgb(_ hex: UInt32) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

enum Themes {
    static let cream = Theme(
        id: "cream", label: "cream",
        sheet: rgb(0xFDF0D9), panel: rgb(0xECDBBE), folderBase: rgb(0xF3E4CA),
        envelope: rgb(0xEBCEA3), letterSheet: rgb(0xFFFAF3),
        ink: rgb(0x71390D), sticky: rgb(0xF7C82D), openDot: rgb(0xA88D34),
        flourish: rgb(0xF2E3C9))

    static let mint = Theme(
        id: "mint", label: "mint",
        sheet: rgb(0xDDF9EF), panel: rgb(0xC3E7DA), folderBase: rgb(0xCEEFE3),
        envelope: rgb(0xAAE4CE), letterSheet: rgb(0xF4FEFA),
        ink: rgb(0x176742), sticky: rgb(0x61E7C1), openDot: rgb(0x409C82),
        flourish: rgb(0xCDEEE2))

    static let sky = Theme(
        id: "sky", label: "sky",
        sheet: rgb(0xD9F1FD), panel: rgb(0xBEDCEC), folderBase: rgb(0xCAE5F3),
        envelope: rgb(0xA3D4EB), letterSheet: rgb(0xF3FBFF),
        ink: rgb(0x0D5A71), sticky: rgb(0x65BFFF), openDot: rgb(0x3478A8),
        flourish: rgb(0xC9E4F2))

    static let coral = Theme(
        id: "coral", label: "coral",
        sheet: rgb(0xFDE3D9), panel: rgb(0xECCBBE), folderBase: rgb(0xF3D6CA),
        envelope: rgb(0xEBB6A3), letterSheet: rgb(0xFFF6F3),
        ink: rgb(0x711F0D), sticky: rgb(0xFF985E), openDot: rgb(0xA85E34),
        flourish: rgb(0xF2D5C9))

    static let lilac = Theme(
        id: "lilac", label: "lilac",
        sheet: rgb(0xE6D9FD), panel: rgb(0xCFBEEC), folderBase: rgb(0xD9CAF3),
        envelope: rgb(0xBCA3EB), letterSheet: rgb(0xF7F3FF),
        ink: rgb(0x270D71), sticky: rgb(0xC18FFF), openDot: rgb(0x6834A8),
        flourish: rgb(0xD8C9F2))

    static let orchid = Theme(
        id: "orchid", label: "orchid",
        sheet: rgb(0xFDD9F8), panel: rgb(0xECBEE6), folderBase: rgb(0xF3CAED),
        envelope: rgb(0xEBA3E2), letterSheet: rgb(0xFFF3FE),
        ink: rgb(0x710D6E), sticky: rgb(0xFF87E5), openDot: rgb(0xA8348F),
        flourish: rgb(0xF2C9EC))

    // order is the order of the dots, in both onboarding and settings
    static let all: [Theme] = [cream, mint, sky, coral, lilac, orchid]

    static func named(_ id: String?) -> Theme {
        all.first { $0.id == id } ?? cream
    }
}

// The row of mood dots. Each dot is its theme's sticky colour, edged in that
// theme's open-note dot — a shade darker than the fill, so every dot has a
// definite edge against the paper, the pale ones especially. The active one is
// drawn larger rather than ringed. Tapping applies the theme immediately —
// there is no confirm step.
//
// The tap target is wider and taller than the dot: a 24pt circle is well under
// the 44pt a finger needs. The spacing is folded into each target rather than
// laid between them, so the dots sit exactly as far apart as on the Mac.
struct ThemePicker: View {
    @ObservedObject var store: NotesStore
    var diameter: CGFloat = 24
    var spacing: CGFloat = 18

    // The chosen mood, grown in place: its neighbours don't move, and at the
    // default size and spacing it still clears them by 8pt either side.
    static let selectedScale: CGFloat = 1.4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Themes.all) { theme in
                Button {
                    store.setTheme(theme)
                } label: {
                    Circle()
                        .fill(Color(uiColor: theme.sticky))
                        .overlay(
                            Circle()
                                .strokeBorder(Color(uiColor: theme.openDot),
                                              lineWidth: max(1, diameter * 0.05))
                        )
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(store.themeID == theme.id ? Self.selectedScale : 1)
                        .frame(width: diameter + spacing,
                               height: max(44, diameter * Self.selectedScale))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.label)
                .accessibilityAddTraits(store.themeID == theme.id ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.themeID)
    }
}
