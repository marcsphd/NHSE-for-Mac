import XCTest
@testable import ACNHCore

final class StorageTests: XCTestCase {
    var root: URL!
    var folder: URL { root.appendingPathComponent("Island") }
    let header = SaveEngineTests.fixtureFiles["Villager0/personalHeader.dat"]!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ACNHStorage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Villager0"), withIntermediateDirectories: true)
        for (path, data) in SaveEngineTests.fixtureFiles { try data.write(to: folder.appendingPathComponent(path)) }
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func setStorage(capacity: UInt32) throws {
        let url = folder.appendingPathComponent("Villager0/personal.dat")
        var p = try SaveCodec.crypt(Data(contentsOf: url), header: header)
        p.put32(capacity, at: 0x496AC)
        for index in 0..<9_000 {
            let offset = 0x37D6C + index * 8
            p.replaceSubrange(offset..<(offset + 8), with: PocketItem.empty.raw)
        }
        // A stack with unrelated saved flags that a quantity-only edit must retain.
        p.replaceSubrange(0x37D6C..<0x37D74, with: Data([0xC9, 0x09, 0x20, 0x55, 9, 0, 0xA6, 0xB7]))
        let axe = try PocketItem.make(id: 0x2591, quantity: 1, maxStack: 1)
        p.replaceSubrange(0x37D74..<0x37D7C, with: axe.raw)
        // A non-default variation at the last physical record must survive when locked.
        p.replaceSubrange(0x496A4..<0x496AC, with: Data([0xA5, 0x08, 0x22, 0x33, 0x12, 0x01, 0x44, 0x55]))
        SaveLayout.rehash(&p, regions: SaveLayout.personalRegions)
        try SaveCodec.crypt(p, header: header).write(to: url)
    }
    func testLiteralNHSELayoutAllCapacitiesAndNoOpByteIdentity() throws {
        XCTAssertEqual(StorageLayout.base, 0x37D6C)
        XCTAssertEqual(StorageLayout.capacityOffset, 0x496AC)
        XCTAssertEqual(StorageLayout.maximumSlots, 9_000)
        for capacity: UInt32 in [0, 80, 5_000, 9_000] {
            try setStorage(capacity: capacity)
            let session = try SaveSession(folder: folder)
            XCTAssertEqual(session.initial.storage.count, Int(capacity))
            if capacity > 0 { XCTAssertEqual(session.initial.storage[0].id, 0x09C9); XCTAssertEqual(session.initial.storage[0].storedCount, 9) }
            let destination = root.appendingPathComponent("Noop\(capacity)")
            try session.export(session.initial, to: destination)
            XCTAssertEqual(try VerifiedFiles.digests(folder), try VerifiedFiles.digests(destination))
            if capacity == 80, let output = ProcessInfo.processInfo.environment["ACNH_STORAGE_FIXTURE_OUTPUT"] {
                try FileManager.default.copyItem(at: folder, to: URL(fileURLWithPath: output))
            }
        }
    }
    func testBatchPocketAndStorageExportChangesOnlySelectedRecords() throws {
        try setStorage(capacity: 80)
        let url = folder.appendingPathComponent("Villager0/personal.dat")
        var plain = try SaveCodec.crypt(Data(contentsOf: url), header: header)
        plain.put32(20, at: 0x37D48); plain.put32(10, at: 0x37C90)
        SaveLayout.rehash(&plain, regions: SaveLayout.personalRegions)
        try SaveCodec.crypt(plain, header: header).write(to: url)
        let session = try SaveSession(folder: folder)
        var draft = session.initial
        let item = try PocketItem.make(id: 0x09C9, quantity: 30, maxStack: 30)
        try draft.assign(item, to: [0, 19, 20, 29], in: .pockets)
        try draft.assign(item, to: [0, 1, 49, 50, 79], in: .storage)
        let destination = root.appendingPathComponent("Batch")
        try session.export(draft, to: destination)
        let reopened = try SaveSession(folder: destination)
        XCTAssertEqual(reopened.initial, draft)
        var expected = session.personal
        for offset in [0x37CA8, 0x37D40, 0x37BF0, 0x37C38] {
            expected.replaceSubrange(offset..<(offset + 8), with: item.raw)
        }
        for index in [0, 1, 49, 50, 79] {
            let offset = 0x37D6C + index * 8
            expected.replaceSubrange(offset..<(offset + 8), with: item.raw)
        }
        SaveLayout.rehash(&expected, regions: SaveLayout.personalRegions)
        XCTAssertEqual(reopened.personal, expected, "Batch placement preserves unselected and locked slots, capacity, and unrelated data")
        XCTAssertEqual(reopened.main, session.main)
        try session.ensureUnchanged()
    }
    func testAddReplaceRemoveAndQuantityExportPreservesOtherBytes() throws {
        try setStorage(capacity: 80)
        let session = try SaveSession(folder: folder)
        var draft = session.initial
        draft.storage[0] = try draft.storage[0].changingQuantity(to: 30, maxStack: 30)
        draft.storage[1] = .empty
        draft.storage[49] = try PocketItem.make(id: 2213, quantity: 10, maxStack: 10)
        draft.storage[79] = try PocketItem.make(id: 0x2591, quantity: 1, maxStack: 1)
        let output = root.appendingPathComponent("Edited")
        try session.export(draft, to: output)
        let reopened = try SaveSession(folder: output)
        XCTAssertEqual(reopened.initial, draft)
        var expected = session.personal
        expected.put16(29, at: 0x37D70)
        expected.replaceSubrange(0x37D74..<0x37D7C, with: PocketItem.empty.raw)
        for index in [49, 79] {
            let offset = 0x37D6C + index * 8
            expected.replaceSubrange(offset..<(offset + 8), with: draft.storage[index].raw)
        }
        SaveLayout.rehash(&expected, regions: SaveLayout.personalRegions)
        XCTAssertEqual(reopened.personal, expected, "Only requested storage bytes and required hashes may change")
        XCTAssertEqual(reopened.main, session.main)
        XCTAssertEqual(reopened.initial.pockets, session.initial.pockets)
        XCTAssertEqual(reopened.personal.u32(0x496AC), 80)
        XCTAssertEqual(reopened.personal.subdata(in: 0x496A4..<0x496AC), session.personal.subdata(in: 0x496A4..<0x496AC))
        try session.ensureUnchanged()
    }
    func testLastOfNineThousandSlotsAndQuantityDetailsRoundTrip() throws {
        try setStorage(capacity: 9_000)
        let session = try SaveSession(folder: folder)
        var draft = session.initial
        draft.storage[8_999] = try PocketItem.make(id: 2213, quantity: 3, maxStack: 10)
        let output = try session.encoded(draft)
        let plain = try SaveCodec.crypt(output["Villager0/personal.dat"]!, header: header)
        XCTAssertEqual(plain.subdata(in: 0x496A4..<0x496AC), draft.storage[8_999].raw)
        XCTAssertEqual(try StorageLayout.read(from: plain).last, draft.storage.last)
        XCTAssertEqual(plain.u32(0x496AC), 9_000)
        var expected = session.personal
        expected.replaceSubrange(0x496A4..<0x496AC, with: draft.storage[8_999].raw)
        SaveLayout.rehash(&expected, regions: SaveLayout.personalRegions)
        XCTAssertEqual(plain, expected)
        let original = session.initial.storage[0]
        for quantity in [1, 30] {
            let edited = try original.changingQuantity(to: quantity, maxStack: 30)
            XCTAssertEqual(edited.storedCount + 1, quantity)
            for i in [0, 1, 2, 3, 6, 7] { XCTAssertEqual(edited.raw[i], original.raw[i]) }
        }
        for quantity in [0, 31] { XCTAssertThrowsError(try original.changingQuantity(to: quantity, maxStack: 30)) }
        XCTAssertThrowsError(try original.changingQuantity(to: 1, maxStack: 1))
        XCTAssertThrowsError(try PocketItem.empty.changingQuantity(to: 1, maxStack: 30))
        XCTAssertThrowsError(try PocketItem(raw: Data([0])).changingQuantity(to: 1, maxStack: 30))
    }
    func testInvalidStorageDraftsCannotWriteOrCreateExports() throws {
        try setStorage(capacity: 80)
        let session = try SaveSession(folder: folder)
        var bad = session.initial; bad.storage.append(.empty)
        XCTAssertThrowsError(try session.encoded(bad))
        bad = session.initial; bad.storage.removeLast()
        XCTAssertThrowsError(try session.encoded(bad))
        for raw in [Data([1, 2]), Data(repeating: 0, count: 9), Data([0xFD, 0xFF, 0, 0, 0, 0, 0, 0])] {
            bad = session.initial; bad.storage[0] = PocketItem(raw: raw)
            XCTAssertThrowsError(try session.export(bad, to: root.appendingPathComponent("Invalid")))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Invalid").path))
        }
        try session.ensureUnchanged()
        for count: UInt32 in [9_001, UInt32.max] {
            try setStorage(capacity: count)
            XCTAssertThrowsError(try SaveSession(folder: folder))
        }
        try setStorage(capacity: 0)
        let locked = try SaveSession(folder: folder)
        bad = locked.initial; bad.storage = [.empty]
        XCTAssertThrowsError(try locked.encoded(bad))
        XCTAssertThrowsError(try StorageLayout.read(from: Data(repeating: 0, count: 32)))
    }
    func testStorageSaveBackupRestoreAndWriteFailureRollback() throws {
        try setStorage(capacity: 80)
        let session = try SaveSession(folder: folder), original = try VerifiedFiles.digests(folder)
        var draft = session.initial; draft.storage[79] = try PocketItem.make(id: 0x2591, quantity: 1, maxStack: 1)
        draft.economy[0] = 42; draft.pockets[0] = .empty
        let backupRoot = root.appendingPathComponent("Backups")
        let backup = try session.save(draft, backupRoot: backupRoot)
        try backup.verify()
        let saved = try SaveSession(folder: folder)
        XCTAssertEqual(saved.initial, draft)
        _ = try saved.restore(backup, backupRoot: backupRoot)
        XCTAssertEqual(try VerifiedFiles.digests(folder), original)
        let fresh = try SaveSession(folder: folder)
        var calls = 0
        XCTAssertThrowsError(try fresh.replace(fresh.encoded(draft), backup: backup) { data, url in
            calls += 1
            if calls == 2 { throw SaveError("Simulated storage write failure") }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertEqual(try VerifiedFiles.digests(folder), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".acnh-write-in-progress").path))
    }
}
