import XCTest
@testable import ACNHCore

final class MapCoordinatesTests: XCTestCase {
    func testBuildingMarkersMatchNHSEHalfTileGridAtEveryZoom() {
        // NHSE renders buildings directly on its 288×256 full map. Our terrain canvas
        // is 144×128, so the same positions must be divided by two, without an offset.
        let cases: [(UInt16, UInt16, Double, Double)] = [
            (124, 116, 62, 58), (140, 118, 70, 59),
            (192, 209, 96, 104.5), (177, 161, 88.5, 80.5),
            (217, 130, 108.5, 65), (205, 160, 102.5, 80),
            (0, 0, 0, 0), (287, 255, 143.5, 127.5)
        ]
        for zoom in 3...14 {
            for (x, y, expectedX, expectedY) in cases {
                let point = MapCoordinates.buildingPoint(BuildingPosition(x: x, y: y, angle: 0), zoom: Double(zoom))
                XCTAssertEqual(point.x, expectedX * Double(zoom))
                XCTAssertEqual(point.y, expectedY * Double(zoom))
            }
        }
    }

    func testBuildingSelectionUsesTheRenderedCoordinatesAtEveryZoom() {
        let positions: [(UInt16, UInt16)] = [(192,209), (177,161), (217,130), (124,116), (140,118), (205,160)]
        let buildings = positions.enumerated().map { MapBuilding(id: $0.offset, kind: 10, position: BuildingPosition(x: $0.element.0, y: $0.element.1, angle: 0)) }
        let absent = MapBuilding(id: 6, kind: 0, position: BuildingPosition(x: 124, y: 116, angle: 0))
        for zoom in 3...14 {
            let z = Double(zoom)
            for building in buildings {
                let point = MapCoordinates.buildingPoint(building.position, zoom: z)
                XCTAssertEqual(MapCoordinates.nearestBuilding(x: point.x, y: point.y, zoom: z, buildings: [absent] + buildings), building.id)
            }
            for point in [(-1.0, 60.0), (144.0, 60.0), (60.0, 128.0), (Double.nan, 0), (.infinity, 0)] {
                XCTAssertNil(MapCoordinates.nearestBuilding(x: point.0 * z, y: point.1 * z, zoom: z, buildings: buildings))
            }
        }
        XCTAssertNil(MapCoordinates.nearestBuilding(x: 30, y: 30, zoom: 3, buildings: []))
        XCTAssertNil(MapCoordinates.nearestBuilding(x: 30, y: 30, zoom: 0, buildings: buildings))
    }

    func testTerrainHitTestingAtEveryZoom() {
        for zoom in 3...14 {
            let z = Double(zoom)
            for (point, expected) in [
                ((16.0, 16.0), MapCell(x: 0, y: 0)),
                ((127.999, 111.999), MapCell(x: 111, y: 95)),
                ((56.75, 47.25), MapCell(x: 40, y: 31))
            ] {
                XCTAssertEqual(MapCoordinates.terrain(x: point.0 * z, y: point.1 * z, zoom: z), expected)
            }
            for point in [(15.999, 20.0), (20.0, 15.999), (128.0, 20.0), (20.0, 112.0), (-0.1, 20.0)] {
                XCTAssertNil(MapCoordinates.terrain(x: point.0 * z, y: point.1 * z, zoom: z))
            }
        }
    }

    func testItemHitTestingRejectsOceanAndOutsideCanvasAtEveryZoom() {
        for zoom in 3...14 {
            let z = Double(zoom)
            for (point, expected) in [
                ((0.0, 16.0), MapCell(x: 0, y: 0)),
                ((143.999, 111.999), MapCell(x: 287, y: 191)),
                ((56.25, 56.25), MapCell(x: 112, y: 80)),
                ((56.5, 56.5), MapCell(x: 113, y: 81))
            ] {
                XCTAssertEqual(MapCoordinates.item(x: point.0 * z, y: point.1 * z, zoom: z), expected)
            }
            for point in [(40.0, 0.0), (40.0, 15.999), (40.0, 112.0), (40.0, 127.9), (-0.001, 20.0), (144.0, 20.0)] {
                XCTAssertNil(MapCoordinates.item(x: point.0 * z, y: point.1 * z, zoom: z))
            }
        }
    }

    func testNonFiniteCoordinatesAndInvalidZoomAreIgnored() {
        for hit in [MapCoordinates.item, MapCoordinates.terrain] {
            for value in [Double.nan, .infinity, -.infinity] {
                XCTAssertNil(hit(value, 60, 3))
                XCTAssertNil(hit(60, value, 3))
            }
            for zoom in [0, -1, Double.nan, .infinity] { XCTAssertNil(hit(60, 60, zoom)) }
        }
    }
}
