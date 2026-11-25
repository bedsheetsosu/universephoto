import SwiftUI

/// Help → Keyboard shortcuts (⌘/): every tool key and the menu shortcuts in one searchable list.
struct ShortcutsSheet: View {
    @EnvironmentObject private var s: Studio
    @Environment(\.photoTheme) private var theme
    @State private var query = ""

    /// Menu commands with their keys (titles are the menu's own, so they share its translation).
    static let commands: [(section: String, items: [(String, String)])] = [
        ("File", [("New document…", "⇧⌘O"), ("Save", "⌘S"), ("Save as…", "⇧⌘S")]),
        ("Edit", [("Undo", "⌘Z"), ("Redo", "⇧⌘Z"), ("Cut", "⌘X"), ("Copy", "⌘C"), ("Copy merged", "⇧⌘C"), ("Paste", "⌘V"),
                  ("Fill selection", "⌥⌫"), ("Content-aware fill", "⇧⌫"), ("Command search", "⇧⌘P")]),
        ("Tools", [("Increase brush size", "]"), ("Decrease brush size", "["), ("Increase opacity", "."), ("Decrease opacity", ","),
                   ("Swap colors", "X"), ("Next color", "⇧X")]),
        ("Selection", [("Select all", "⌘A"), ("Deselect", "⌘D"), ("Invert selection", "⇧⌘I"), ("Edit in quick mask", "⇧Q")]),
        ("Image", [("Image size…", "⌥⌘I"), ("Canvas size…", "⌥⌘C")]),
        ("Layers", [("New layer", "⇧⌘N"), ("New adjustment layer", "⌥⌘J"), ("Layer via copy", "⌘J"), ("Layer via cut", "⇧⌘J"),
                    ("Free transform", "⌘T"), ("Distort", "⌥⌘T"), ("Group layers", "⌘G"), ("Ungroup", "⇧⌘G"), ("Clipping mask", "⌥⌘G"),
                    ("Merge down", "⌘E"), ("Merge visible", "⇧⌘E"), ("Stamp visible", "⌥⇧⌘E"), ("Delete layer", "⇧⌘⌫"), ("Visibility", "⌥H")]),
        ("View", [("Fit canvas", "⌘0"), ("Zoom in", "⌘+"), ("Zoom out", "⌘−"), ("Mirror canvas", "⇧H")]),
        ("Animation", [("Play / Pause", "Space"), ("Duplicate frame", "⇧F"), ("Previous frame", "⌥←"), ("Next frame", "⌥→"), ("Onion Skin", "⌥O"), ("First frame", "⌥⇧←"), ("Last frame", "⌥⇧→"), ("Hold frame longer", "⌥↑"), ("Hold frame shorter", "⌥↓"), ("Move frame earlier", "⌥⌘←"), ("Move frame later", "⌥⌘→"), ("Delete frame", "⌥⌘⌫")]),
        ("Canvas", [("Pan", "Scroll"), ("Zoom", "⌘ Scroll"), ("Deselect", "Esc")]),
    ]

    private var sections: [(String, [(String, String)])] {
        let tools = Tool.allCases.map { (L($0.english), $0.key.uppercased()) }
        let all = [(L("Tools") + " · " + L("Keys"), tools)] + Self.commands.map { (L($0.section), $0.items.map { (L($0.0), $0.1) }) }
        guard !query.isEmpty else { return all }
        return all.map { ($0.0, $0.1.filter { $0.0.localizedCaseInsensitiveContains(query) || $0.1.localizedCaseInsensitiveContains(query) }) }.filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("Keyboard shortcuts")).font(.system(size: 23, weight: .bold, design: .rounded))
                Spacer()
                TextField(L("Search"), text: $query).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(section.0.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(theme.secondary)
                            ForEach(section.1, id: \.0) { item in
                                HStack {
                                    Text(item.0).font(.system(size: 11)).lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text(item.1).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                                        .padding(.horizontal, 6).padding(.vertical, 2).background(theme.deep.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                                }
                            }
                        }.padding(10).background(theme.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.frame(height: 440)
            HStack { Spacer(); Button(L("Close")) { s.showShortcuts = false }.keyboardShortcut(.cancelAction) }
        }.padding(26).frame(width: 640).background(PhotoAmbient())
    }
}
