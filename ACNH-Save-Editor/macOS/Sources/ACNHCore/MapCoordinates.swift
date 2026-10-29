import Foundation

public struct MapCell: Equatable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public struct MapPoint: Equatable {
    public let x: Double
    public let y: Double
}

/// Converts canvas points to save coordinates without selecting cells outside a layer.
public enum MapCoordinates {
    /// NHSE's full map is 288×256 pixels, twice this canvas's 144×128 terrain grid.
    /// Building positions already include the ocean border; no terrain/item offset applies.
    public static func buildingPoint(_ position: BuildingPosition, zoom: Double) -> MapPoint {
        MapPoint(x: Double(position.x) * zoom / 2, y: Double(position.y) * zoom / 2)
    }

    public static func nearestBuilding(x: Double, y: Double, zoom: Double, buildings: [MapBuilding]) -> Int? {
        guard let point = worldPoint(x: x, y: y, zoom: zoom),
              (0..<144).contains(point.x), (0..<128).contains(point.y) else { return nil }
        var nearest: Int?
        var distance = Double.greatestFiniteMagnitude
        for building in buildings where building.kind != 0 && building.position.x < IslandLayout.buildingWidth && building.position.y < IslandLayout.buildingHeight {
            let location = buildingPoint(building.position, zoom: zoom)
            let dx = location.x - x, dy = location.y - y
            let candidate = dx * dx + dy * dy
            if candidate < distance { nearest = building.id; distance = candidate }
        }
        return nearest
    }

    public static func terrain(x: Double, y: Double, zoom: Double) -> MapCell? {
        guard let point = worldPoint(x: x, y: y, zoom: zoom),
              (16..<128).contains(point.x), (16..<112).contains(point.y) else { return nil }
        return MapCell(x: Int(floor(point.x)) - 16, y: Int(floor(point.y)) - 16)
    }

    public static func item(x: Double, y: Double, zoom: Double) -> MapCell? {
        guard let point = worldPoint(x: x, y: y, zoom: zoom),
              (0..<144).contains(point.x), (16..<112).contains(point.y) else { return nil }
        return MapCell(x: Int(floor(point.x * 2)), y: Int(floor((point.y - 16) * 2)))
    }

    private static func worldPoint(x: Double, y: Double, zoom: Double) -> (x: Double, y: Double)? {
        guard x.isFinite, y.isFinite, zoom.isFinite, zoom > 0 else { return nil }
        return (x / zoom, y / zoom)
    }
}
