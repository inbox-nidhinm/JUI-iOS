# JUI for iPhone

The iPhone port of **re-JUI**, the macOS writing pad built as a gift for Juilee —
a cream sheet, Courier, a ruled page and no chrome. How it *feels* matters more
than feature count.

**The macOS app is the source of truth, and it lives somewhere else.** It is at
`~/Documents/Claude Code/JUI` (branch `re-JUI`) and is worked on by a different
Claude Code session. Never write to that folder. `mac-reference/` holds a
read-only snapshot of its sources and notes (see `mac-reference/SNAPSHOT.txt`
for exactly which version); its `CLAUDE.md` and `CHANGELOG.md` explain *why*
almost every number and oddity exists. Read the relevant part before changing
anything that was ported from it.

## Decisions for this port

- **iPhone only**, portrait, iOS 17+, light appearance only.
- **Notes live in a folder the reader picks — in practice `iCloud Drive/JUI
  Notes`, shared with the Mac's re-JUI** (whose `vaultPath` points at the same
  folder), so the two apps read the same files and iCloud syncs them. Free
  signing allows no app iCloud container, so this is a plain iCloud Drive
  folder chosen once in settings (`fileImporter`) and reopened from a
  security-scoped bookmark (`Vault.swift`). Reads and writes are coordinated
  (`NSFileCoordinator`); not-yet-downloaded notes (`.name.icloud`) are
  requested and listed as they arrive; `VaultWatcher` refreshes on changes
  from elsewhere, and the open note reloads unless it has unsaved edits (ours
  win). Until a folder is picked, notes are in the app's Documents
  (On My iPhone › JUI); picking one copies them in, never overwriting.
  Same on-disk format as the Mac.
- **Free Apple ID signing** for now: installs from Xcode last 7 days.
- **A home screen, not a panel.** The app opens on home: the notes and
  folders, on the page's own paper (not the panel's), with search and a new
  note at the foot. A note is a screen of its own with nothing on it but the
  word count; there are no back arrows anywhere — the way back is the edge
  swipe, or the corner flourish, which goes straight home. A folder opens as
  the same home screen standing inside it, its name as the heading. Navigation is a
  `NavigationStack` with its bar hidden; `UINavigationController`'s edge-swipe
  is switched back on in `ContentView.swift`.
- **The corner flourish is drawn once, over every screen.** In a note or a
  folder it goes straight back to the home screen; on home it opens the
  hidden settings page, and on that page it closes it again. Folder tiles carry no
  flourish.
- **A sticky put away is a crumpled ball in the line, right after its words**
  (Crumple.swift, from `prototypes/crumpled-sticky/`, its "fluid" motion at
  crease depth 0.8): the words, one space, the 24pt ball, and the sentence
  running on after it. The room is made in layout only (`BallRoom`, the
  layout manager's delegate, lays the space after the words out wide) — the
  stored text never changes, as the Mac reads the same file. Tapped, it lifts,
  comes to the card's place and opens out flat; put away, it crushes back and
  drops into its place in the line (deleted or unwritten: it crumples to
  nothing). The fold is a SceneKit sheet textured with a picture of the card;
  the real card appears only once the sheet lies flat, so its flourish draws
  itself after the unfold. `StickyCard.stampFrame` is the one place the card's
  position is worked out — the sheet unfolds into it, so keep them one.
- **A sticky's words carry a wash** of
  the sticky colour (`StickyWashView`, drawn beneath the text — never a
  storage attribute, which would be written into the RTF). Tapping a ball
  opens the card: sized to its text, keyboard down until the text is tapped;
  a sticky just made opens straight to writing. Its text is 14pt at 140%
  leading, and the card's flourish is smaller than the Mac's, with a clear gap
  above it. No pinning.
- **The app icon follows the mood.** Six icons from Figma (node 331:539),
  cream primary, the rest alternate icons (`AppIcon.swift`). Rebuild them with
  `Art/AppIcons/build-icons.sh` from the SVGs beside it. iOS keeps the chosen
  icon across quits on its own, and always shows an alert when it changes —
  so the icon switches once, on leaving settings or onboarding, plus on every
  activation to catch a change made just before quitting; never per tap.
- **The sticky's delete and done are the Figma marks** (node 330:433), bare —
  no tile — tinted `inkMuted`, and shown only while the sticky is being edited.
- **Search lives on home** (the Mac's ⌘K). ⌘K and ⌘N work there with a
  hardware keyboard.
- **New notes open with the keyboard up; existing ones open to read**, at the
  end of what was written, keyboard down until the page is tapped.
- **Onboarding has no vault step** — there is nothing to choose.
- **Paragraphs are left-aligned**, not justified: at ~35 monospaced characters a
  line, justification opens rivers between words.
- **Courier Prime is the default font**, bundled in the app (the Figma system's
  face). Courier and the rest stay in the settings list.
- **Autocorrect stays on** (it is a phone keyboard); smart quotes and dashes
  stay off, as on the Mac.

## Shape of the project

The Xcode project is generated by XcodeGen from `project.yml` and is not
committed. After adding or removing a file, or changing `project.yml`:

```bash
xcodegen generate
```

| File | Contents |
|---|---|
| `JUI/Sources/Style.swift` | Colour tokens, `houseFont`, `Style` (fonts, ruled-grid metrics, paragraph styles), `AnimatedFlourish` |
| `JUI/Sources/Theme.swift` | The six palettes, `ThemePicker` |
| `JUI/Sources/Texture.swift` | Paper: stock, strength and fit per surface; `.papered(_:)`; `PagePaper`, the page's own paper with the panel colour multiplied in — search, settings rows and the onboarding letter |
| `JUI/Sources/NotesStore.swift` | The single source of truth: files, folders, stickies, search, settings |
| `JUI/Sources/Caret.swift` | `SmoothCaret`, `CaretTextView` — the gliding ink caret |
| `JUI/Sources/Editor.swift` | `RuledTextView` (UITextView, TextKit 1), ruling, caret/selection sizing, bullets, italics, sticky marks, `RichTextEditor` bridge |
| `JUI/Sources/AppIcon.swift` | Switching the home-screen icon with the theme |
| `JUI/Sources/Fields.swift` | `HouseField`, `StickyTextView`, the content-sized sticky card |
| `JUI/Sources/Crumple.swift` | The crumpled-ball sticky: the sheet, its SceneKit scene, the card's picture, the ball's image, `CrumpleDirector` |
| `JUI/Sources/HomeView.swift` | The home screen: folders, notes, search and new-note buttons |
| `JUI/Sources/SearchPalette.swift` | Search, with the hidden command rows |
| `JUI/Sources/Onboarding.swift` | The envelope flow |
| `JUI/Sources/ContentView.swift` | Navigation, the note screen, corner flourish, settings page, overlays |
| `JUI/Resources/` | Textures and flourish frames — **copied from the Mac build's output** (`.texcache`, `.animcache`), not regenerated here |
| `JUI/Resources/Fonts/` | Courier Prime, four faces, with its SIL OFL licence (registered via `UIAppFonts`) |
| `JUITests/` | Store tests (files, folders, sticky remapping, search, settings) |
| `JUIUITests/` | A walkthrough that saves a screenshot at each stop |

## Build, test, look

```bash
xcodegen generate
xcodebuild -project JUI.xcodeproj -scheme JUI \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -derivedDataPath build/DerivedData -only-testing:JUITests test
```

To see every screen, run the walkthrough on a fresh install (it starts at
onboarding) and look at the images it writes:

```bash
xcrun simctl uninstall booted com.nidhin.jui.ios
TEST_RUNNER_SHOTS_DIR=/path/to/shots xcodebuild ... -only-testing:JUIUITests test
```

When changing anything visual, look at it. Passing tests say nothing about
whether the page still looks like paper.

## Invariants carried over from the Mac

These are the Mac's rules, restated for UIKit. The Mac's `CLAUDE.md` has the
history behind each one.

- **TextKit 1, assembled by hand** in `makeUIView` (storage → layout manager →
  container). The ruling, caret and selection are all measured against that
  layout manager's line fragments. Don't move to TextKit 2.
- **`docVersion` is the load signal.** It increments only when a different
  document is loaded, never on typing. Bump it on a keystroke and you wipe the
  undo stack and fight the caret.
- **The ruled grid: pitch is the constant** (48 = 3 × the 16pt type) and
  leading is derived from it per font, so every family lands on the same rules.
  Paragraph spacing is exactly one pitch; bullet spacing exactly zero. Any gap
  that isn't a whole number of pitches walks the type off the ruling.
- **The ruling is anchored to the text container's top**, never to a line
  fragment, and drawn as black at 10% — the same arithmetic as the system's
  10% multiply, which is why it can live in its own layer.
- **Caret and selection are sized off the ink box**, never off the rect UIKit
  reports, whose height varies by line. `caretRect(for:)` and
  `selectionRects(for:)` do this; the selection band is centred in the ruled
  band (`Style.ruledCentre`), and one reported rect can cover several lines.
- **The caret is the house's own, and it glides** (`Caret.swift`). The system
  caret is replaced, not tinted away: since iOS 17 it is the `cursorView` of the
  text view's `UITextSelectionDisplayInteraction`, and `SmoothCaret` swaps in a
  `SilentCursorView` that draws nothing, then draws a 2pt ink `CALayer` at
  `caretRect(for:)` — gliding 0.10s ease-out between positions, solid while
  moving, blinking only when idle. Tinting the view clear would also hide the
  selection and its handles. Every editor is a `CaretTextView` (the note and
  the sticky); a new multi-line text view should be one too. Caret moves arrive
  three ways and all three are hooked: the delegate (user), and the
  `selectedRange` and `selectedTextRange` setters (code), which UIKit does not
  route through each other. `SmoothCaretTests` fails if a future iOS stops
  exposing the interaction — the app then falls back to the system caret
  rather than drawing two.
- **Paragraph styles are rebuilt on load** (`NotesStore.restyled`), classified
  by the line's own text (does it start with `• `), never trusted from the file.
- **Bullets are literal `"• "` text** plus `Style.bulletParagraph`.
  `normalizeFonts` identifies them by `headIndent > 0`.
- **Sticky anchors are character ranges, remapped on every edit** — here in the
  text storage's delegate, the one place every edit passes (typing, autocorrect,
  dictation, undo, the bullet rewrites). Loading a document must not remap.
- **Never write attributes from inside an enumeration.** Collect, then apply.
- **`applyTheme` defers its store update by one hop**, because it runs inside a
  SwiftUI update pass.
- **Theme changes recolour in place** and do not bump `docVersion`; font changes
  restyle the stored text and do.
- **Anything that draws a colour token without observing the store carries
  `var theme = Style.theme.id`** — every ButtonStyle, `IconButton`,
  `StampButton`, `HouseField`, `StickyTextView`, `OnboardingPill`. SwiftUI
  can't see the global theme, and redraws a piece only when its inputs
  change; without this line it keeps the old mood until something touches it.
- **Fields end on a tap outside them** (`HouseField`), and `onEndEditing` is
  where a name is committed or dropped: an unnamed new folder disappears, a
  named one is made. Return only ends editing, so it happens in one place.
- **Never write a colour literal outside `Theme.swift`**, and never a fresh
  opacity of the ink — use `brownInk`/`inkStrong`/`inkMuted`/`inkFaint`. Tones
  (black at a fraction) are the exception, because they are right in all six
  themes.
- **Type goes through `houseFont`/`Style.font`**, so the family picked in
  settings reaches everything. 16 is the largest size in the app.
- **Every raised surface takes paper**: colour, then `.papered(...)`, then clip.
- **The save happens whenever the app leaves the foreground** (iOS may kill it
  without a quit), plus the 300ms debounce while typing. A never-typed note is
  never written.

## Installing on an iPhone (free signing)

1. Open `JUI.xcodeproj` in Xcode → Settings → Accounts → add an Apple ID.
2. Select the JUI target → Signing & Capabilities → choose the personal team.
   If the bundle id `com.nidhin.jui.ios` is taken, change it in `project.yml`.
3. Plug in the phone, enable Developer Mode on it (Settings → Privacy &
   Security), pick it as the run destination, and Run.
4. On the phone: Settings → General → VPN & Device Management → trust the
   developer.

A free-signed install stops opening after 7 days; running from Xcode again
renews it, and the notes survive.
