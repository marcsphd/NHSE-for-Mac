import XCTest
@testable import ACNHCore

final class BuildingFootprintTests: XCTestCase {
    private func building(_ kind: UInt16, subtype: UInt16 = 0, angle: UInt8 = 0) -> MapBuilding {
        MapBuilding(id: 0, kind: kind, position: BuildingPosition(x: 124, y: 116, angle: angle), subtype: subtype)
    }
    func testMeasuredPlacementPlotsUseTerrainTiles() {
        for (kind, width, depth) in [(1,5,4),(8,5,4),(9,4,4),(18,4,4),(19,7,4),(20,6,4),(21,7,4),(24,5,4),(25,4,4)] {
            let plot = BuildingFootprint.forBuilding(building(UInt16(kind)))
            XCTAssertEqual(plot?.width, Double(width)); XCTAssertEqual(plot?.depth, Double(depth))
        }
        for kind in [0,22,23,28,29,42,65535] {
            XCTAssertNil(BuildingFootprint.forBuilding(building(UInt16(kind))), "Do not invent dimensions for unverified structures")
        }
    }
    func testBridgeSubtypeDeterminesWaterSpanAndBanks() {
        for (subtype, span) in [(0,3),(1,4),(2,5),(39,3),(25,4),(40,5),(49,3),(38,4),(52,5)] {
            let b = building(26, subtype: UInt16(subtype))
            XCTAssertEqual(BuildingFootprint.bridgeSpan(b.subtype), Double(span))
            XCTAssertEqual(BuildingFootprint.forBuilding(b)?.depth, Double(span + 2))
            XCTAssertEqual(BuildingFootprint.forBuilding(building(26, subtype: UInt16(subtype), angle: 1))?.width, Double(span + 2))
        }
        for subtype in [3,4,5,53,54,55,50,51,65535] {
            XCTAssertNil(BuildingFootprint.forBuilding(building(26, subtype: UInt16(subtype))))
        }
        XCTAssertTrue(BuildingFootprint.isDiagonalBridge(building(26, subtype: 54)))
        XCTAssertFalse(BuildingFootprint.isDiagonalBridge(building(26, subtype: 1)))
    }
    func testInclineDimensionsRotateAndUnknownAnglesHaveNoGuide() {
        for angle: UInt8 in 0..<4 {
            let plot = BuildingFootprint.forBuilding(building(27, angle: angle))
            XCTAssertEqual(plot?.width, angle % 2 == 0 ? 2 : 4)
            XCTAssertEqual(plot?.depth, angle % 2 == 0 ? 4 : 2)
        }
        XCTAssertNil(BuildingFootprint.forBuilding(building(27, angle: 8)))
    }
    func testGuideHitTestingUsesTheSameBoundsAndRejectsEmptyMap() {
        for zoom in 3...14 {
            let z = Double(zoom), b = building(21)
            let rect = MapCoordinates.buildingBounds(b, zoom: z)
            XCTAssertEqual(rect.width, 7 * z); XCTAssertEqual(rect.height, 4 * z)
            XCTAssertEqual(rect.midX, 62 * z); XCTAssertEqual(rect.midY, 58 * z)
            XCTAssertEqual(MapCoordinates.buildingAt(x: rect.minX + 0.1, y: rect.midY, zoom: z, buildings: [b]), b.id)
            XCTAssertNil(MapCoordinates.buildingAt(x: rect.maxX + z, y: rect.midY, zoom: z, buildings: [b]))
            XCTAssertNil(MapCoordinates.buildingAt(x: .nan, y: rect.midY, zoom: z, buildings: [b]))
        }
    }
    func testReadSubtypePreservesItWhenMovingBuilding() throws {
        var main = IslandSnapshot.preview().main
        let offset = IslandLayout.buildings
        main.put16(26, at: offset); main.put16(40, at: offset + 8)
        let world = IslandSnapshot(main: main)
        var edits = IslandEdits()
        edits.buildings[0] = BuildingPosition(x: 150, y: 100, angle: 1)
        let moved = world.building(0, edits: edits)
        XCTAssertEqual(moved.subtype, 40)
        XCTAssertEqual(BuildingFootprint.forBuilding(moved)?.width, 7)
        var changed = main
        try edits.applying(to: &changed)
        XCTAssertEqual(changed.u16(offset + 8), 40)
        XCTAssertEqual(IslandSnapshot(main: changed).building(0).position, moved.position)
        XCTAssertEqual(world.main, main)
    }
}
