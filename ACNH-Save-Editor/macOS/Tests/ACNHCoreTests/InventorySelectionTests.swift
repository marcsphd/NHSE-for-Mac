import XCTest
@testable import ACNHCore

final class InventorySelectionTests: XCTestCase {
    func testClickToggleAndRangeFollowVisibleOrder() {
        var selection = InventorySelection(0)
        let visible = [0, 3, 6, 9, 12]
        selection.click(3, visible: visible)
        XCTAssertEqual(selection.indices, [3])
        selection.click(9, visible: visible, command: true)
        XCTAssertEqual(selection.indices, [3, 9])
        selection.click(3, visible: visible, command: true)
        XCTAssertEqual(selection.indices, [9])
        selection.click(12, visible: visible, shift: true)
        XCTAssertEqual(selection.indices, [3, 6, 9, 12])
        selection.click(6, visible: visible, command: true)
        XCTAssertEqual(selection.indices, [3, 9, 12])
        selection.click(1, visible: visible)
        XCTAssertEqual(selection.indices, [3, 9, 12], "A filtered-out slot cannot become selected")
    }

    func testPagingFilteringAndEmptySelections() {
        var selection = InventorySelection()
        selection.replace(with: Array(0..<50))
        selection.retain(Array(50..<80))
        XCTAssertTrue(selection.indices.isEmpty)
        XCTAssertNil(selection.anchor)
        selection.click(79, visible: Array(50..<80), shift: true)
        XCTAssertEqual(selection.single, 79)
        selection.replace(with: [50, 60, 79])
        selection.retain([60, 79])
        XCTAssertEqual(selection.indices, [60, 79])
        selection.replace(with: [])
        XCTAssertNil(selection.single)
    }

    func testBatchAssignmentIsAtomicAndConfinedToChosenSlots() throws {
        let original = try PocketItem.make(id: 0x09C9, quantity: 10, maxStack: 30)
        let replacement = try PocketItem.make(id: 0x08A5, quantity: 3, maxStack: 10)
        var draft = SaveDraft(economy: [0, 0, 0, 0], pockets: Array(repeating: original, count: 30))
        draft.storage = Array(repeating: original, count: 9_000)
        let initial = draft
        try draft.assign(replacement, to: [0, 19, 20, 29], in: .pockets)
        try draft.assign(replacement, to: [0, 49, 50, 8_999], in: .storage)
        for index in draft.pockets.indices { XCTAssertEqual(draft.pockets[index], [0, 19, 20, 29].contains(index) ? replacement : original) }
        for index in draft.storage.indices { XCTAssertEqual(draft.storage[index], [0, 49, 50, 8_999].contains(index) ? replacement : original) }
        let edited = draft
        for destination in [InventoryDestination.pockets, .storage] {
            for invalid: Set<Int> in [[], [-1, 0], [0, 9_000]] {
                XCTAssertThrowsError(try draft.assign(replacement, to: invalid, in: destination))
                XCTAssertEqual(draft, edited)
            }
        }
        XCTAssertThrowsError(try draft.assign(PocketItem(raw: Data([0])), to: [0], in: .storage))
        XCTAssertEqual(draft, edited)
        try draft.assign(.empty, to: [19, 20], in: .pockets)
        XCTAssertTrue(draft.pockets[19].isEmpty)
        XCTAssertTrue(draft.pockets[20].isEmpty)
        XCTAssertEqual(draft.pockets[0], replacement)
        XCTAssertEqual(draft.economy, initial.economy)
        XCTAssertEqual(draft.storage, edited.storage)
    }
}
