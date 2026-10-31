import XCTest
@testable import ACNHCore

final class MapItemSnapTests: XCTestCase {
    func testOneArrowUpClearsATypicalCopiedFootprint() throws {
        let world = IslandSnapshot.preview()
        let item = try PocketItem.make(id:0x9C9,quantity:1,maxStack:30)
        let sourceCell = MapCell(x:40,y:40)
        let source = try IslandLayout.fieldIndex(x:40,y:40,layer:0)
        let edits = try world.dropping(item,at:source,edits:.init())
        let copied = try world.copyingItem(at:source,edits:edits)
        let next = MapCoordinates.movingItemCell(sourceCell,dx:0,dy:-1,snapped:true)
        XCTAssertEqual(next,MapCell(x:40,y:38))
        let target = try IslandLayout.fieldIndex(x:next.x,y:next.y,layer:0)
        let pasted = try world.pastingItem(copied,at:target,edits:edits)
        XCTAssertEqual(pasted.fieldItems.count,8)
        let fine = MapCoordinates.movingItemCell(sourceCell,dx:0,dy:-1,snapped:false)
        XCTAssertEqual(fine,MapCell(x:40,y:39))
        XCTAssertThrowsError(try world.pastingItem(copied,at:IslandLayout.fieldIndex(x:fine.x,y:fine.y,layer:0),edits:edits))
    }
    func testSnappedClicksAndEdgeMovementStayAligned() {
        XCTAssertEqual(MapCoordinates.snappedItemCell(MapCell(x:113,y:81)),MapCell(x:112,y:80))
        XCTAssertEqual(MapCoordinates.snappedItemCell(MapCell(x:287,y:191)),MapCell(x:286,y:190))
        XCTAssertEqual(MapCoordinates.movingItemCell(MapCell(x:286,y:190),dx:1,dy:1,snapped:true),MapCell(x:286,y:190))
        XCTAssertEqual(MapCoordinates.movingItemCell(MapCell(x:0,y:0),dx:-1,dy:-1,snapped:true),MapCell(x:0,y:0))
    }
    func testExistingOddRootsKeepTheirPhaseAndFineModeCanReachEveryCell() {
        XCTAssertEqual(MapCoordinates.movingItemCell(MapCell(x:113,y:81),dx:0,dy:-1,snapped:true),MapCell(x:113,y:79))
        XCTAssertEqual(MapCoordinates.movingItemCell(MapCell(x:1,y:1),dx:-1,dy:-1,snapped:true),MapCell(x:1,y:1))
        XCTAssertEqual(MapCoordinates.movingItemCell(MapCell(x:286,y:190),dx:1,dy:1,snapped:false),MapCell(x:287,y:191))
    }
}
