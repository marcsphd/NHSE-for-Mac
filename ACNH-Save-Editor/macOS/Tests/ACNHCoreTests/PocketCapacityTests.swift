import XCTest
@testable import ACNHCore

final class PocketCapacityTests: XCTestCase {
    var root: URL!
    var folder: URL { root.appendingPathComponent("Island") }
    let header = SaveEngineTests.fixtureFiles["Villager0/personalHeader.dat"]!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ACNHPockets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Villager0"), withIntermediateDirectories: true)
        for (path, data) in SaveEngineTests.fixtureFiles { try data.write(to: folder.appendingPathComponent(path)) }
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func setCapacity(first: UInt32 = 20, extra: UInt32) throws {
        let path = folder.appendingPathComponent("Villager0/personal.dat")
        var data = try SaveCodec.crypt(Data(contentsOf: path), header: header)
        data.put32(first, at: 0x37D48); data.put32(extra, at: 0x37C90)
        for i in 0..<20 {
            let a = try PocketItem.make(id: UInt16(100 + i), quantity: 1, maxStack: 1)
            let b = try PocketItem.make(id: UInt16(200 + i), quantity: 1, maxStack: 1)
            data.replaceSubrange((0x37CA8 + i * 8)..<(0x37CB0 + i * 8), with: a.raw)
            data.replaceSubrange((0x37BF0 + i * 8)..<(0x37BF8 + i * 8), with: b.raw)
        }
        SaveLayout.rehash(&data, regions: SaveLayout.personalRegions)
        try SaveCodec.crypt(data, header: header).write(to: path)
    }
    func testTwentyThirtyFortyPocketsLoadInGameOrderAndNoOpIsIdentical() throws {
        XCTAssertEqual(SaveLayout.pocketCount, 0x37D48)
        XCTAssertEqual(SaveLayout.extraPocketCount, 0x37C90)
        for extra: UInt32 in [0, 10, 20] {
            try setCapacity(extra: extra)
            let session = try SaveSession(folder: folder)
            XCTAssertEqual(session.initial.pockets.count, 20 + Int(extra))
            XCTAssertEqual(session.initial.pockets.prefix(20).map(\.id), (100..<120).map(UInt16.init))
            XCTAssertEqual(session.initial.pockets.dropFirst(20).map(\.id), (200..<(200 + Int(extra))).map(UInt16.init))
            let destination = root.appendingPathComponent("Noop\(extra)")
            try session.export(session.initial, to: destination)
            XCTAssertEqual(try VerifiedFiles.digests(folder), try VerifiedFiles.digests(destination))
        }
    }
    func testPocketTwentyTwentyOneAndFinalSlotExportOnlySelectedBytes() throws {
        for extra: UInt32 in [10, 20] {
            try setCapacity(extra: extra)
            let session = try SaveSession(folder: folder)
            var draft = session.initial
            draft.pockets[19] = .empty
            draft.pockets[20] = try PocketItem.make(id: 0x16DB, quantity: 10, maxStack: 10)
            draft.pockets[draft.pockets.count - 1] = try PocketItem.make(id: 0x09C9, quantity: 1, maxStack: 1)
            let destination = root.appendingPathComponent("Edited\(extra)")
            try session.export(draft, to: destination)
            let reopened = try SaveSession(folder: destination)
            XCTAssertEqual(reopened.initial, draft)
            var expected = session.personal
            expected.replaceSubrange(0x37D40..<0x37D48, with: PocketItem.empty.raw)
            expected.replaceSubrange(0x37BF0..<0x37BF8, with: draft.pockets[20].raw)
            let lastOffset = 0x37BF0 + (Int(extra) - 1) * 8
            expected.replaceSubrange(lastOffset..<(lastOffset + 8), with: draft.pockets.last!.raw)
            SaveLayout.rehash(&expected, regions: SaveLayout.personalRegions)
            XCTAssertEqual(reopened.personal, expected, "Locked slots, capacity counters, and all unrelated bytes must be preserved")
            XCTAssertEqual(reopened.main, session.main)
            XCTAssertEqual(reopened.originals["Villager0/personalHeader.dat"], session.originals["Villager0/personalHeader.dat"])
            try session.ensureUnchanged()
        }
    }
    func testEachBlockUsesItsOwnUnlockedCountAndCannotExpandTheDraft() throws {
        try setCapacity(first: 10, extra: 10)
        let session = try SaveSession(folder: folder)
        XCTAssertEqual(session.initial.pockets.count, 20)
        XCTAssertEqual(session.initial.pockets[9].id, 109)
        XCTAssertEqual(session.initial.pockets[10].id, 200)
        var draft = session.initial
        draft.pockets.append(.empty)
        XCTAssertThrowsError(try session.encoded(draft))
        draft = session.initial; draft.pockets.removeLast()
        XCTAssertThrowsError(try session.encoded(draft))
        for (first, extra): (UInt32, UInt32) in [(21, 0), (20, 21), (UInt32.max, UInt32.max), (0, 0)] {
            try setCapacity(first: first, extra: extra)
            XCTAssertThrowsError(try SaveSession(folder: folder))
        }
    }
    func testExtraPocketEditsSaveAndRestoreWithCapacityUnchanged() throws {
        try setCapacity(extra: 10)
        let session = try SaveSession(folder: folder), before = try VerifiedFiles.digests(folder)
        var draft = session.initial
        draft.pockets[29] = .empty
        let backups = root.appendingPathComponent("Backups")
        let backup = try session.save(draft, backupRoot: backups)
        let saved = try SaveSession(folder: folder)
        XCTAssertEqual(saved.initial.pockets.count, 30)
        XCTAssertEqual(saved.initial.pockets[29], .empty)
        _ = try saved.restore(backup, backupRoot: backups)
        XCTAssertEqual(try VerifiedFiles.digests(folder), before)
    }
    func testLegacyAndExpandedLoadoutsPreserveRemainingSlots() throws {
        let item = try PocketItem.make(id: 0x09C9, quantity: 1, maxStack: 1)
        let legacy = PocketLoadout(schema: 1, name: "Old loadout", pockets: Array(repeating: .empty, count: 20))
        let decoded = try JSONDecoder().decode(PocketLoadout.self, from: JSONEncoder().encode(legacy))
        XCTAssertTrue(decoded.isValid)
        for capacity in [20, 30, 40] {
            let existing = Array(repeating: item, count: capacity)
            let result = try decoded.applying(to: existing)
            XCTAssertEqual(result.count, capacity)
            XCTAssertTrue(result.prefix(20).allSatisfy(\.isEmpty))
            XCTAssertEqual(Array(result.dropFirst(20)), Array(existing.dropFirst(20)))
        }
        for capacity in [30, 40] {
            let loadout = PocketLoadout(name: "Expanded", pockets: Array(repeating: item, count: capacity))
            let decoded = try JSONDecoder().decode(PocketLoadout.self, from: JSONEncoder().encode(loadout))
            XCTAssertEqual(try decoded.applying(to: Array(repeating: .empty, count: capacity)), loadout.pockets)
            XCTAssertThrowsError(try decoded.applying(to: Array(repeating: .empty, count: capacity - 10)))
        }
        let thirty = PocketLoadout(name: "Thirty", pockets: Array(repeating: .empty, count: 30))
        let forty = try thirty.applying(to: Array(repeating: item, count: 40))
        XCTAssertEqual(Array(forty.suffix(10)), Array(repeating: item, count: 10))
        for bad in [PocketLoadout(schema: 1, name: "Bad", pockets: Array(repeating: .empty, count: 30)),
                    PocketLoadout(schema: 3, name: "Bad", pockets: Array(repeating: .empty, count: 20)),
                    PocketLoadout(name: "Bad", pockets: [PocketItem(raw: Data([1]))])] {
            XCTAssertFalse(bad.isValid)
            XCTAssertThrowsError(try bad.applying(to: Array(repeating: .empty, count: 40)))
        }
    }
}
