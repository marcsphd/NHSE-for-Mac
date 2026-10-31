import XCTest
@testable import ACNHCore

final class MapZoomTests: XCTestCase {
    func testFiveStopsUseTheExisting100PercentTileScale() {
        XCTAssertEqual(Array(MapZoom.stops), [1,2,3,4,5])
        XCTAssertEqual(MapZoom.pointsPerTile, 5)
        for scale in MapZoom.stops { XCTAssertEqual(MapZoom.clamped(Double(scale)), Double(scale)) }
    }
    func testPinchUsesTheGestureStartWithoutCompoundingEachUpdate() {
        XCTAssertEqual(MapZoom.magnified(start: 2, magnification: 1.2), 2.4, accuracy: 0.0001)
        XCTAssertEqual(MapZoom.magnified(start: 2, magnification: 1.5), 3)
        XCTAssertEqual(MapZoom.magnified(start: 4, magnification: 0.5), 2)
        XCTAssertEqual(MapZoom.magnified(start: 1, magnification: 0.5), 1)
        XCTAssertEqual(MapZoom.magnified(start: 4, magnification: 2), 5)
    }
    func testPinchPreservesFractionalZoomAndRejectsInvalidInput() {
        XCTAssertEqual(MapZoom.clamped(1.49), 1.49)
        XCTAssertEqual(MapZoom.clamped(1.5), 1.5)
        XCTAssertEqual(MapZoom.clamped(4.7), 4.7)
        XCTAssertEqual(MapZoom.clamped(100), 5)
        let firstPinch = MapZoom.clamped(MapZoom.magnified(start: 1, magnification: 1.37))
        let secondPinch = MapZoom.clamped(MapZoom.magnified(start: firstPinch, magnification: 1.2))
        XCTAssertEqual(firstPinch, 1.37, accuracy: 0.0001)
        XCTAssertEqual(secondPinch, 1.644, accuracy: 0.0001)
        for value in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertEqual(MapZoom.magnified(start: 3, magnification: value), 3)
        }
    }
    func testHitTestingTracksPresetsAndFractionalPinchZoom() {
        for scale in [1.0, 1.37, 2, 2.65, 3, 3.82, 4, 4.7, 5] {
            let z = scale * MapZoom.pointsPerTile
            XCTAssertEqual(MapCoordinates.terrain(x: 56.5 * z, y: 56.5 * z, zoom: z), MapCell(x:40,y:40))
            XCTAssertEqual(MapCoordinates.item(x: 56.5 * z, y: 56.5 * z, zoom: z), MapCell(x:113,y:81))
            let b = MapBuilding(id:0, kind:19, position:BuildingPosition(x:124,y:116,angle:0))
            XCTAssertEqual(MapCoordinates.buildingAt(x:62*z,y:58*z,zoom:z,buildings:[b]),0)
        }
    }
}
