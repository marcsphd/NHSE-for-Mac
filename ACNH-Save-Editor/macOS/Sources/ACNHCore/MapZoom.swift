import Foundation

/// Zoom factors relative to the map's 100% scale (five points per terrain tile).
public enum MapZoom {
    public static let stops = 1...5
    public static let pointsPerTile = 5.0

    public static func clamped(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1 }
        return min(5, max(1, scale))
    }

    public static func magnified(start: Double, magnification: Double) -> Double {
        guard magnification.isFinite, magnification > 0 else { return clamped(start) }
        return clamped(clamped(start) * magnification)
    }

}
