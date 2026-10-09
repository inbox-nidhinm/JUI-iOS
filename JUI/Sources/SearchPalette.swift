import SwiftUI

// Search — the Mac's ⌘K palette, opened from the home screen's search button
// (or ⌘K on a hardware keyboard). Results *and* commands share one list; Return fires the
// first row, a tap fires any row.
//
// Two cards, not one divided card, as in the frames: the field is what you act
// on, the results are what happens because of it, and separating them lets the
// results grow and shrink without the field appearing to resize.
struct SearchPalette: View {
    @ObservedObject var store: NotesStore
    /// Takes you to the note a hit was found in, once the store has loaded it.
    var onReveal: () -> Void = {}
    @State private var query = ""
    @State private var focused = false

    private var hits: [SearchHit] { store.search(query) }

    private struct Command: Identifiable {
        let id: String
        let title: String
        let run: () -> Void
    }

    private var commands: [Command] {
        var out: [Command] = []
        if showOnboardAgain {
            out.append(Command(id: "onboard", title: "onboard again") {
                store.replayOnboarding()
            })
        }
        return out
    }

    var body: some View {
        let results = hits
        let cmds = commands
        VStack(spacing: 10) {
            queryCard(results, cmds)
            resultsCard(results, cmds)
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, 16)
        .onAppear { focused = true }
    }

    private func queryCard(_ results: [SearchHit], _ cmds: [Command]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(inkFaint)
            HouseField(
                text: $query,
                size: 14,
                placeholder: "search",
                placeholderAlpha: 0.55, // inkMuted — the prompt is a step firmer here
                focused: focused,
                returnKey: .go,
                capitalization: .none,
                onSubmit: { activate(results, cmds) })
                .frame(height: 22)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Papered on the background rather than over the whole view: an overlay
        // would multiply the rows and their ink into the card too.
        .background(Self.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // The search cards are the page's own paper, a shade deeper.
    private static var card: some View { PagePaper() }

    @ViewBuilder
    private func resultsCard(_ results: [SearchHit], _ cmds: [Command]) -> some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                Text(store.notes.isEmpty ? "no notes yet" : "no matches")
                    .font(houseFont(12))
                    .foregroundStyle(inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, hit in
                            resultRow(hit, first: index == 0)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: listHeight(results))
                .scrollDismissesKeyboard(.immediately)
                .scrollIndicators(.hidden)
            }

            // The one command left, "onboard again", is properly hidden and
            // has to be typed for. (The Mac's hide/show sticky notes row is
            // not here: on the phone a sticky is a small stamp in the margin,
            // and hiding them had nothing to clear out of the way.)
            if !cmds.isEmpty {
                Rectangle()
                    .fill(panelDividerColor)
                    .frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(cmds) { cmd in
                        commandRow(cmd.title, action: cmd.run)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Self.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // The first row carries the highlight box, because it is what Return opens.
    private func resultRow(_ hit: SearchHit, first: Bool) -> some View {
        Button {
            reveal(hit.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let folder = hit.folder {
                        Text("\(folder)/")
                            .font(houseFont(13))
                            .foregroundStyle(inkMuted)
                            .lineLimit(1)
                    }
                    Text(hit.title)
                        .font(houseFont(13))
                        .foregroundStyle(brownInk)
                        .lineLimit(1)
                }
                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(houseFont(11))
                        .foregroundStyle(inkMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(first && !query.isEmpty ? sheetColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedRowStyle())
        .padding(.horizontal, 8)
    }

    // Needs three characters and a real prefix of "onboard", so it can't
    // surface by accident while someone is searching their notes.
    private var showOnboardAgain: Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 3 else { return false }
        return "onboard again".hasPrefix(q) || q.hasPrefix("onboard")
    }

    private func commandRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(houseFont(12))
                    .foregroundStyle(inkMuted)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedRowStyle())
        .padding(.horizontal, 8)
    }

    // hug the results instead of reserving empty space
    private func listHeight(_ results: [SearchHit]) -> CGFloat {
        let rows = results.reduce(CGFloat(0)) { $0 + ($1.snippet.isEmpty ? 48 : 64) }
        return min(rows + 16, 300)
    }

    private func reveal(_ id: String) {
        hideKeyboard()
        store.reveal(id, query: query)
        onReveal()
    }

    // Return opens the top match, or runs the only command if nothing matched.
    private func activate(_ results: [SearchHit], _ cmds: [Command]) {
        if let first = results.first, !query.isEmpty {
            reveal(first.id)
        } else if results.isEmpty, let only = cmds.first {
            only.run()
        }
    }
}

// A row's press state: the sheet-toned box the Mac shows under the pointer,
// shown here under the finger instead.
struct PressedRowStyle: ButtonStyle {
    var theme = Style.theme.id // redraw on a theme change — see Style.theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? sheetColor : Color.clear)
                    .padding(.horizontal, 0)
            )
    }
}
