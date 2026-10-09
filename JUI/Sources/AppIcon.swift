import UIKit

// The home-screen icon follows the mood, as the Mac's Dock icon does on the
// main branch: six icons from the Figma system (node 331:539), each drawn in
// its theme's own sticky and open-dot colours. Cream is the primary icon; the
// other five are alternate icons, built from Art/AppIcons by build-icons.sh.
//
// iOS keeps an alternate icon across quits and restarts by itself — nothing
// here has to persist it. What iOS also does, and offers no public way to
// stop, is show a small alert each time an app changes its icon. So the icon
// is not switched on every tap of a mood dot, which would mean an alert per
// tap while someone browses the moods; it is brought into step once, when
// they leave the page they choose on (settings or onboarding), and again
// whenever the app becomes active, which catches a change made just before
// the app was closed.
enum AppIcon {
    /// The alternate icon for a theme, or nil for the primary (cream) one.
    static func name(for theme: Theme) -> String? {
        theme.id == Themes.cream.id ? nil : "AppIcon-\(theme.id)"
    }

    /// Switches the icon to match `theme`, if it doesn't already. Only an
    /// active app may change its icon, so this does nothing otherwise and
    /// relies on the next activation to try again.
    static func sync(to theme: Theme) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active else { return }
        let wanted = name(for: theme)
        guard app.alternateIconName != wanted else { return }
        app.setAlternateIconName(wanted) { error in
            if let error { print("JUI: icon change to \(wanted ?? "primary") failed: \(error)") }
        }
    }
}
