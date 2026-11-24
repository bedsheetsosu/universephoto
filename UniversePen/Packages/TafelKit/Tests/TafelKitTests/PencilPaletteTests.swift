import XCTest
@testable import TafelKit

final class PencilPaletteTests: XCTestCase {
    func testDefaultItemsGetSymbolsAndGroups() {
        let d = InputSettings.defaultRadialMenu
        XCTAssertTrue(d.allSatisfy { $0.paletteSymbol != nil }, "every default item has an icon")
        XCTAssertEqual(d.first?.paletteSymbol, "arrow.uturn.backward")
        XCTAssertEqual(d.first?.paletteGroup, 0)
        XCTAssertEqual(d[1].paletteGroup, 1)
    }

    func testSeparatorsWhereTheKindChanges() {
        let undo = ShortcutButton(title: "Undo", shortcut: Shortcut("z", .command))
        let brush = ShortcutButton(title: "B", shortcut: Shortcut("b"))
        let ruler = ShortcutButton(title: "Lineal", shortcut: Shortcut("a"), tool: .ruler)
        XCTAssertEqual(ShortcutButton.paletteSeparators([undo, brush, brush, ruler]), [0, 2])
        XCTAssertEqual(ShortcutButton.paletteSeparators([brush]), [])
        XCTAssertNil(ShortcutButton(title: "x", shortcut: Shortcut("q", .control)).paletteSymbol)
    }

    func testArcOpensUpLeftAndStaysOnScreen() {
        let f = RadialMenuLayout.facing(x: 600, y: 500, width: 1180, height: 820, count: 8)
        XCTAssertLessThan(f, RadialMenuLayout.up)          // leans left
        for n in 2...12 {
            let c = RadialMenuLayout.offset(of: n / 2, count: n, facing: f)
            XCTAssertEqual(RadialMenuLayout.item(dx: c.x, dy: c.y, count: n, facing: f), n / 2)
        }
    }

    func testScrollingArcShowsAWindow() {
        XCTAssertEqual(RadialMenuLayout.visible(count: 12), 7)
        XCTAssertEqual(RadialMenuLayout.maxScroll(count: 12), 5)
        XCTAssertEqual(RadialMenuLayout.maxScroll(count: 5), 0)
        let f = RadialMenuLayout.up, r = RadialMenuLayout.radius(count: 7)
        // Scrolled by 3: the item at the left end is item 3.
        let a = RadialMenuLayout.angle(of: 3, count: 12, facing: f, scroll: 3)
        XCTAssertEqual(RadialMenuLayout.item(dx: r * cos(a), dy: r * sin(a), count: 12, facing: f, scroll: 3), 3)
        XCTAssertEqual(RadialMenuLayout.opacity(of: 3, count: 12, scroll: 3), 1)
        XCTAssertEqual(RadialMenuLayout.opacity(of: 2, count: 12, scroll: 2.5), 1 - 0.5 / 0.7, accuracy: 1e-9)
        XCTAssertEqual(RadialMenuLayout.opacity(of: 0, count: 12, scroll: 3), 0)
        // Moving the finger one step clockwise scrolls back by one item.
        let st = RadialMenuLayout.step(count: 7)
        XCTAssertEqual(RadialMenuLayout.scrollDelta(from: 0, to: st, count: 12), -1, accuracy: 1e-9)
    }

    func testToolSwitchesAreChoices() {
        let d = InputSettings.defaultRadialMenu
        XCTAssertEqual(d.map(\.isToolSwitch), [false, true, true, true, true, false])
        XCTAssertFalse(ShortcutButton(title: "Lineal", shortcut: Shortcut("a"), tool: .ruler).isToolSwitch)
        XCTAssertFalse(ShortcutButton(title: "⇧", shortcut: Shortcut("a"), hold: .shift).isToolSwitch)
    }
}

final class ClientCommandTests: XCTestCase {
    func testFindPencilRoundTrip() throws {
        XCTAssertEqual(MessageType.clientCommand.rawValue, 0x25)
        XCTAssertEqual(try JSONWire.decode(ClientCommand.self, JSONWire.encode(ClientCommand.findPencil)), .findPencil)
    }
}
