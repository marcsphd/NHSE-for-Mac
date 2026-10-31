import Foundation

/// Placement-plot dimensions in full terrain tiles, not model collision bounds.
/// Sources and outstanding alignment checks: Design/Map/Building-Artwork-and-Spacing.md.
public struct BuildingFootprint: Equatable {
    public let width: Double
    public let depth: Double
    public let note: String

    public static func forBuilding(_ building: MapBuilding) -> BuildingFootprint? {
        let size: (Double, Double)
        switch building.kind {
        case 1...8: size = (5, 4)
        case 9...18, 25: size = (4, 4)
        case 19, 21: size = (7, 4)
        case 20: size = (6, 4)
        case 24: size = (5, 4)
        case 27:
            guard building.position.angle < 4 else { return nil }
            size = building.position.angle % 2 == 0 ? (2, 4) : (4, 2)
        case 26:
            guard building.position.angle < 4, let span = bridgeSpan(building.subtype) else { return nil }
            // Straight bridges include one bank tile at each end.
            size = building.position.angle % 2 == 0 ? (4, span + 2) : (span + 2, 4)
        default: return nil
        }
        return BuildingFootprint(width: size.0, depth: size.1,
            note: "Placement plot guide; alignment to the saved marker needs in-game verification.")
    }

    /// Water span from NHSE BridgeType's 03/04/05 model suffixes.
    /// Diagonal and unrecognized subtypes deliberately have no rectangular plot guide.
    public static func bridgeSpan(_ subtype: UInt16) -> Double? {
        switch subtype {
        case 0, 7, 14, 19, 26, 32, 39, 44, 49: return 3
        case 1, 6, 12, 13, 24, 25, 27, 37, 38: return 4
        case 2, 8, 15, 20, 28, 33, 40, 45, 52: return 5
        default: return nil
        }
    }

    public static func isDiagonalBridge(_ building: MapBuilding) -> Bool {
        building.kind == 26 && [UInt16(3),4,5,9,10,11,16,17,18,21,22,23,29,30,31,34,35,36,41,42,43,46,47,48,53,54,55].contains(building.subtype)
    }
}
