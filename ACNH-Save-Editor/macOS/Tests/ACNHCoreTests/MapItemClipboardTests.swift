import XCTest
@testable import ACNHCore

final class MapItemClipboardTests: XCTestCase {
    func testCopyFromExtensionPreservesEveryRecordAndCrossLayerPaste() throws {
        let world = IslandSnapshot.preview()
        let pocket = try PocketItem.make(id: 0x9C9, quantity: 10, maxStack: 30)
        for sourceLayer in 0...1 {
            let source = try IslandLayout.fieldIndex(x: 20, y: 20, layer: sourceLayer)
            var edits = try world.dropping(pocket, at: source, edits: .init())
            edits.fieldItems[source]!.raw[2] = 0x04 // placed/oriented root flags must survive
            edits.fieldItems[source]!.raw[3] = 7
            edits.fieldItems[source]!.raw[7] = 13 // variation data must survive
            let extensionCell = try IslandLayout.fieldIndex(x:21,y:21,layer:sourceLayer)
            let copied = try world.copyingItem(at: extensionCell, edits: edits)
            XCTAssertEqual(copied.cells.count, 4)
            XCTAssertEqual(copied.rootItem, edits.fieldItems[source])
            let roundTrip = try JSONDecoder().decode(MapItemClipboard.self, from: JSONEncoder().encode(copied))
            let target = try IslandLayout.fieldIndex(x:40,y:40,layer:1-sourceLayer)
            let pasted = try world.pastingItem(roundTrip, at: target, edits: edits)
            XCTAssertEqual(pasted.fieldItems.count, 8)
            for cell in copied.cells {
                let key = try IslandLayout.fieldIndex(x:40+cell.x,y:40+cell.y,layer:1-sourceLayer)
                XCTAssertEqual(world.fieldItem(key, edits:pasted), cell.item)
                XCTAssertEqual(try world.rootIndex(for:key,edits:pasted),target)
            }
            var main = world.main
            try pasted.applying(to: &main)
            let reopened = IslandSnapshot(main: main)
            XCTAssertEqual(reopened.fieldItem(target), copied.rootItem)
            XCTAssertEqual(try reopened.rootIndex(for: target+193, edits:.init()),target)
            XCTAssertEqual(world.fieldItem(source), .empty)
        }
    }
    func testPlantedFlowerCopyAndDeletionDoNotTouchNearbyObjects() throws {
        let world = IslandSnapshot.preview()
        let root = try IslandLayout.fieldIndex(x:30,y:30,layer:0)
        var raw = Data([0x6C,0xEB,0x00,0x01,0x03,0x04,0x05,0x06]) // field rose ID > 60000
        raw.put16(60268,at:0)
        var edits = IslandEdits(); edits.fieldItems[root] = PocketItem(raw:raw)
        edits.fieldItems[root+192] = PocketItem(raw:raw)
        let copied = try world.copyingItem(at:root,edits:edits)
        XCTAssertEqual(copied.cells.count,1)
        let pasted = try world.pastingItem(copied,at:root+384,edits:edits)
        let cleared = try world.removingItem(at:root+384,edits:pasted)
        XCTAssertTrue(world.fieldItem(root+384,edits:cleared).isEmpty)
        XCTAssertEqual(world.fieldItem(root,edits:cleared).raw,raw)
        XCTAssertEqual(world.fieldItem(root+192,edits:cleared).raw,raw)
    }
    func testPasteRejectsOccupiedFootprintsAndEdgesWithoutPartialEdits() throws {
        let world = IslandSnapshot.preview()
        let item = try PocketItem.make(id: 0x9C9, quantity: 3, maxStack: 30)
        let source = try IslandLayout.fieldIndex(x:20,y:20,layer:0)
        let edits = try world.dropping(item,at:source,edits:.init())
        let copied = try world.copyingItem(at:source,edits:edits)
        XCTAssertThrowsError(try world.pastingItem(copied,at:source,edits:edits))
        XCTAssertThrowsError(try world.pastingItem(copied,at:IslandLayout.fieldIndex(x:287,y:191,layer:1),edits:edits))
        XCTAssertThrowsError(try world.pastingItem(copied,at:-1,edits:edits))
        XCTAssertThrowsError(try world.copyingItem(at:IslandLayout.fieldIndex(x:0,y:0,layer:0),edits:edits))
        XCTAssertEqual(edits.fieldItems.count,4)
        XCTAssertEqual(world.fieldItem(source), .empty)
    }
    func testDeletingPastedExtensionRemovesOnlyItsOwnFootprint() throws {
        let world = IslandSnapshot.preview()
        let item = try PocketItem.make(id: 0x9C9, quantity: 2, maxStack: 30)
        let source = try IslandLayout.fieldIndex(x:20,y:20,layer:0)
        let edits = try world.dropping(item,at:source,edits:.init())
        let copied = try world.copyingItem(at:source,edits:edits)
        let target = try IslandLayout.fieldIndex(x:24,y:20,layer:0)
        let pasted = try world.pastingItem(copied,at:target,edits:edits)
        let cleared = try world.removingItem(at:target+193,edits:pasted)
        for cell in copied.cells {
            XCTAssertTrue(world.fieldItem(target+cell.x*192+cell.y,edits:cleared).isEmpty)
            XCTAssertEqual(world.fieldItem(source+cell.x*192+cell.y,edits:cleared),edits.fieldItems[source+cell.x*192+cell.y])
        }
    }
    func testRealIslandObjectCopySurvivesEncryptionWithoutChangingTerrainOrBuildings() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/ACNHMac/ExampleSave/Save")
        let session = try SaveSession(folder: folder), world = IslandSnapshot(main: session.main)
        let source = try XCTUnwrap((0..<IslandLayout.fieldCount).first {
            let item = world.fieldItem($0)
            return item.id > 0 && item.id < 0xFFFD
        })
        let copied = try world.copyingItem(at: source, edits: .init())
        let target = try IslandLayout.fieldIndex(x: 0, y: 0, layer: 1)
        var draft = session.initial
        draft.island = try world.pastingItem(copied, at: target, edits: draft.island)
        let encoded = try session.encoded(draft)
        let main = try SaveCodec.crypt(XCTUnwrap(encoded["main.dat"]), header: XCTUnwrap(session.originals["mainHeader.dat"]))
        try SaveLayout.verify(main, regions: SaveLayout.mainRegions, name: "copied island")
        let reopened = IslandSnapshot(main: main)
        XCTAssertEqual(try reopened.copyingItem(at: target, edits: .init()), copied)
        XCTAssertEqual(try reopened.copyingItem(at: source, edits: .init()), copied)
        let terrain = IslandLayout.terrain..<(IslandLayout.terrain + 112 * 96 * 14)
        let buildings = IslandLayout.buildings..<(IslandLayout.buildings + IslandLayout.buildingCount * 20)
        XCTAssertEqual(main.subdata(in: terrain), session.main.subdata(in: terrain))
        XCTAssertEqual(main.subdata(in: buildings), session.main.subdata(in: buildings))
        XCTAssertEqual(encoded["Villager0/personal.dat"], session.originals["Villager0/personal.dat"])
        try session.ensureUnchanged()
    }
    func testMalformedClipboardCannotCreateRootlessOrForeignExtensionCells() throws {
        let root = try PocketItem.make(id:0x9C9,quantity:1,maxStack:30)
        let valid = MapItemClipboard.Cell(x:0,y:0,item:root)
        for cells in [[MapItemClipboard.Cell](), [.init(x:0,y:0,item:PocketItem(raw:Data()))],
                      [valid, valid], [valid,.init(x:1,y:0,item:root)],
                      [.init(x:-1,y:0,item:root)], [.init(x:0,y:0,item:.empty)]] {
            XCTAssertThrowsError(try MapItemClipboard(cells:cells).validate())
        }
        var raw = Data([0xFD,0xFF,0,0,0,0,1,1]); raw.put16(0x9C5,at:4)
        XCTAssertThrowsError(try MapItemClipboard(cells:[valid,.init(x:1,y:1,item:PocketItem(raw:raw))]).validate())
    }
}
