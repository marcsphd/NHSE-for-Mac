// NHSE PersonalOffsets30.ItemChest and Personal.ItemChestCount; see notices.
import Foundation

public enum StorageLayout {
    public static let base = 0x37BE0 + 0x18C
    public static let maximumSlots = 9_000
    public static let capacityOffset = base + maximumSlots * 8

    public static func read(from personal: Data) throws -> [PocketItem] {
        guard personal.count == SaveLayout.personalSize else { throw SaveError("Unexpected personal save size while reading home storage.") }
        let count = personal.u32(capacityOffset)
        guard count <= UInt32(maximumSlots) else { throw SaveError("The saved home storage capacity is invalid. This save format supports at most 9,000 slots.") }
        return (0..<Int(count)).map { index in
            let offset = base + index * 8
            return PocketItem(raw: personal.subdata(in: offset..<(offset + 8)))
        }
    }

    static func apply(_ items: [PocketItem], original: [PocketItem], to personal: inout Data) throws {
        guard personal.count == SaveLayout.personalSize, items.count == original.count,
              items.count <= maximumSlots, items.allSatisfy({ $0.raw.count == 8 }) else {
            throw SaveError("The storage edit has an invalid layout. Keep the saved capacity and eight-byte item records intact.")
        }
        for index in items.indices where items[index] != original[index] {
            guard items[index].isEmpty || items[index].id < 0xFFFD else { throw SaveError("This item record cannot be placed in home storage.") }
            let offset = base + index * 8
            personal.replaceSubrange(offset..<(offset + 8), with: items[index].raw)
        }
    }
}

extension PocketItem {
    public func changingQuantity(to quantity: Int, maxStack: Int) throws -> PocketItem {
        guard raw.count == 8, !isEmpty, id < 0xFFFD, maxStack > 1, maxStack <= 99,
              (1...maxStack).contains(quantity) else { throw SaveError("Choose a valid quantity for a stackable item.") }
        var item = self
        item.raw.put16(UInt16(quantity - 1), at: 4)
        return item
    }
}
