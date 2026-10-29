import Foundation

public struct PocketLoadout: Codable {
    public let schema: Int
    public let name: String
    public let pockets: [PocketItem]
    public init(schema: Int = 2, name: String, pockets: [PocketItem]) {
        self.schema = schema; self.name = name; self.pockets = pockets
    }
    public var isValid: Bool {
        ((schema == 1 && pockets.count == 20) || (schema == 2 && (1...40).contains(pockets.count))) && pockets.allSatisfy { $0.raw.count == 8 }
    }
    public func applying(to existing: [PocketItem]) throws -> [PocketItem] {
        guard isValid, (1...40).contains(existing.count), existing.allSatisfy({ $0.raw.count == 8 }) else {
            throw SaveError("This loadout contains an invalid pocket layout.")
        }
        guard pockets.count <= existing.count else {
            throw SaveError("This loadout needs \(pockets.count) unlocked pockets, but this resident has \(existing.count). Open a save with enough pocket space.")
        }
        var result = existing
        result.replaceSubrange(0..<pockets.count, with: pockets)
        return result
    }
}
