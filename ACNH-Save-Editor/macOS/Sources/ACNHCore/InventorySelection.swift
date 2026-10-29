import Foundation

/// Selection is limited to the slots currently shown by an inventory view.
public struct InventorySelection: Equatable {
    public private(set) var indices: Set<Int> = []
    public private(set) var anchor: Int?
    public var single: Int? { indices.count == 1 ? indices.first : nil }

    public init(_ index: Int? = nil) { replace(with: index.map { [$0] } ?? []) }

    public mutating func replace(with slots: [Int]) {
        indices = Set(slots); anchor = slots.first
    }
    public mutating func retain(_ visible: [Int]) {
        indices.formIntersection(visible)
        if let anchor, !visible.contains(anchor) { self.anchor = nil }
    }
    public mutating func click(_ index: Int, visible: [Int], command: Bool = false, shift: Bool = false) {
        guard visible.contains(index) else { return }
        retain(visible)
        if shift, let anchor, let start = visible.firstIndex(of: anchor), let end = visible.firstIndex(of: index) {
            let range = Set(visible[min(start, end)...max(start, end)])
            indices = command ? indices.union(range) : range
        } else if command {
            if !indices.insert(index).inserted { indices.remove(index) }
            anchor = index
        } else { replace(with: [index]) }
    }
}

public enum InventoryDestination { case pockets, storage }

extension SaveDraft {
    /// Validate every destination before changing any record; the UI records one undo step.
    public mutating func assign(_ item: PocketItem, to slots: Set<Int>, in destination: InventoryDestination) throws {
        let count = destination == .pockets ? pockets.count : storage.count
        guard !slots.isEmpty, slots.allSatisfy({ (0..<count).contains($0) }),
              item.raw.count == 8, item.isEmpty || item.id < 0xFFFD else {
            throw SaveError("Choose unlocked inventory slots and a valid item before placing it.")
        }
        for index in slots {
            switch destination {
            case .pockets: pockets[index] = item
            case .storage: storage[index] = item
            }
        }
    }
}
