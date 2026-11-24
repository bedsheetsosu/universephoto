import Foundation

/// How a button looks on the Pencil palette (the arc that squeeze opens, 1.1).
extension ShortcutButton {
    /// Buttons of one kind sit together; a thin line separates the kinds on the arc.
    /// 0 = undo/redo, 1 = Mac shortcuts, 2 = plugin actions, 3 = iPad tools.
    public var paletteGroup: Int {
        if tool != nil { return 3 }
        if pluginAction != nil { return 2 }
        if hold == nil, shortcut.key == "z", shortcut.modifiers.contains(.command) { return 0 }
        return 1
    }

    /// An SF Symbol for common shortcuts (undo, brush, eraser, …), nil when the title is shown
    /// instead. iPad tools bring their own symbol.
    public var paletteSymbol: String? {
        guard tool == nil, pluginAction == nil, hold == nil else { return nil }
        let m = shortcut.modifiers
        switch (shortcut.key, m) {
        case ("z", [.command]): return "arrow.uturn.backward"
        case ("z", [.command, .shift]): return "arrow.uturn.forward"
        case ("b", []): return "paintbrush.pointed"
        case ("e", []): return "eraser"
        case ("i", []): return "eyedropper"
        case ("h", []), ("space", []): return "hand.raised"
        case ("v", []): return "cursorarrow"
        case ("l", []): return "lasso"
        case ("t", []): return "textformat"
        case ("g", []): return "drop"
        case ("m", []): return "rectangle.dashed"
        case ("p", []): return "pencil"
        case ("s", [.command]): return "square.and.arrow.down"
        case ("c", [.command]): return "doc.on.doc"
        case ("v", [.command]): return "doc.on.clipboard"
        case ("+", [.command]), ("=", [.command]): return "plus.magnifyingglass"
        case ("-", [.command]): return "minus.magnifyingglass"
        default: return nil
        }
    }

    /// A plain one-key shortcut such as B (brush) or E (eraser): picking it switches the Mac app's
    /// tool, so the palette marks it as the current choice until another one is picked. Undo,
    /// shortcuts with modifiers, held keys, plugins and iPad tools are not choices.
    public var isToolSwitch: Bool {
        tool == nil && pluginAction == nil && hold == nil && shortcut.modifiers.isEmpty
            && (shortcut.key.count == 1 || shortcut.key == "space")
    }

    /// Indices after which the arc draws a separator (where the kind changes).
    public static func paletteSeparators(_ items: [ShortcutButton]) -> [Int] {
        guard items.count > 1 else { return [] }
        return (0..<(items.count - 1)).filter { items[$0].paletteGroup != items[$0 + 1].paletteGroup }
    }
}
