import Foundation

/// An outdoor object's root and owned extension cells, relative to its root.
/// No terrain, buildings, resident identities, or absolute save offsets are copied.
public struct MapItemClipboard: Codable, Equatable {
    public struct Cell: Codable, Equatable {
        public let x: Int
        public let y: Int
        public let item: PocketItem
    }
    public let cells: [Cell]
    public var rootItem: PocketItem? { cells.first?.item }

    public func validate() throws {
        guard !cells.isEmpty, cells.count <= 4096, cells.allSatisfy({ $0.item.raw.count == 8 }),
              let root = cells.first, root.x == 0, root.y == 0,
              root.item.id > 0, root.item.id < 0xFFFD else { throw SaveError("The clipboard does not contain a valid outdoor object.") }
        var seen = Set<Int>()
        for (offset, cell) in cells.enumerated() {
            guard (0..<288).contains(cell.x), (0..<192).contains(cell.y),
                  seen.insert(cell.x * 192 + cell.y).inserted else { throw SaveError("The copied object's footprint is invalid.") }
            if offset != 0 {
                guard cell.item.id == 0xFFFD, cell.item.raw.u16(4) == root.item.id,
                      Int(cell.item.raw[6]) == cell.x, Int(cell.item.raw[7]) == cell.y else {
                    throw SaveError("A copied footprint cell does not belong to its object.")
                }
            }
        }
    }
}

extension IslandSnapshot {
    public func copyingItem(at index: Int, edits: IslandEdits) throws -> MapItemClipboard {
        let root = try rootIndex(for: index, edits: edits)
        let item = fieldItem(root, edits: edits)
        guard !item.isEmpty else { throw SaveError("Select an outdoor object to copy.") }
        let layer = root / IslandLayout.fieldCount, local = root % IslandLayout.fieldCount
        let x = local / 192, y = local % 192
        var cells = [MapItemClipboard.Cell(x: 0, y: 0, item: item)]
        for i in 0..<IslandLayout.fieldCount where i != local {
            let candidate = fieldItem(layer * IslandLayout.fieldCount + i, edits: edits)
            if candidate.id == 0xFFFD, candidate.raw.u16(4) == item.id,
               i / 192 - Int(candidate.raw[6]) == x, i % 192 - Int(candidate.raw[7]) == y {
                cells.append(.init(x: i / 192 - x, y: i % 192 - y, item: candidate))
            }
        }
        let result = MapItemClipboard(cells: cells)
        try result.validate()
        return result
    }

    public func pastingItem(_ copied: MapItemClipboard, at index: Int, edits: IslandEdits) throws -> IslandEdits {
        try copied.validate()
        guard (0..<(IslandLayout.fieldCount * 2)).contains(index) else { throw SaveError("Invalid item coordinates.") }
        let layer = index / IslandLayout.fieldCount, local = index % IslandLayout.fieldCount
        let x = local / 192, y = local % 192
        var result = edits
        for cell in copied.cells {
            let key = try IslandLayout.fieldIndex(x: x + cell.x, y: y + cell.y, layer: layer)
            guard fieldItem(key, edits: edits).isEmpty else {
                throw SaveError("The copied object needs empty space for its whole footprint. Delete the existing object first, or select another cell.")
            }
            result.fieldItems[key] = cell.item
        }
        return result
    }
}
