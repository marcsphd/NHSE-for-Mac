import XCTest
@testable import ACNHCore
import SaveCrypto

final class SaveEngineTests: XCTestCase {
    var root: URL!
    var folder: URL { root.appendingPathComponent("Island") }
    var backupRoot: URL { root.appendingPathComponent("Backups") }
    static let fixtureFiles: [String: Data] = {
        var header = Data(repeating: 0, count: 0x300)
        header.put32(0xA0002, at: 0); header.put32(0xA0028, at: 4)
        header.put16(2, at: 8); header.put16(2, at: 12); header.put16(34, at: 14)
        for i in 0..<128 { header.put32(UInt32(i * 0x12345 + 0x89), at: 0x100 + i * 4) }
        var personal = Data(repeating: 0, count: SaveLayout.personalSize)
        var main = Data(repeating: 0, count: SaveLayout.mainSize)
        personal.replaceSubrange(0..<16, with: header.prefix(16)); main.replaceSubrange(0..<16, with: header.prefix(16))
        for (offset, value) in [(SaveLayout.wallet, UInt32(1234)), (SaveLayout.bank, 750_000), (SaveLayout.miles, 12_000)] {
            personal.put16(0xA123, at: offset + 4); personal[offset + 6] = 17
            SaveCodec.writeMoney(value, to: &personal, at: offset)
        }
        main.put16(0x9BCD, at: SaveLayout.loan + 4); main[SaveLayout.loan + 6] = 29
        SaveCodec.writeMoney(548_000, to: &main, at: SaveLayout.loan)
        for i in 0..<20 { personal.replaceSubrange((SaveLayout.pocketBase + i * 8)..<(SaveLayout.pocketBase + i * 8 + 8), with: PocketItem.empty.raw) }
        personal.put32(20, at: SaveLayout.pocketCount)
        personal[0x20000] = 0xA5; main[0x5B3D50] = 0xDE; main[0x900000] = 0xB6
        SaveLayout.rehash(&personal, regions: SaveLayout.personalRegions); SaveLayout.rehash(&main, regions: SaveLayout.mainRegions)
        return ["mainHeader.dat": header, "Villager0/personalHeader.dat": header,
                "main.dat": try! SaveCodec.crypt(main, header: header),
                "Villager0/personal.dat": try! SaveCodec.crypt(personal, header: header)]
    }()
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ACNHTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Villager0"), withIntermediateDirectories: true)
        for (path, data) in Self.fixtureFiles { try data.write(to: folder.appendingPathComponent(path)) }
        try Data("untouched sibling file".utf8).write(to: folder.appendingPathComponent("postbox.dat"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testAESNISTKnownAnswer() {
        let key = Array(UInt8(0)...UInt8(15))
        let plain: [UInt8] = [0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF]
        var output = [UInt8](repeating: 0, count: 16)
        acnh_aes_block(key, plain, &output)
        XCTAssertEqual(Data(output).hex, "69c4e0d86a7b0430d8cdb78070b4c55a")
    }
    func testCryptoAgainstIndependentOpenSSLVector() throws {
        let input = Data((0..<48).map(UInt8.init))
        let header = Self.fixtureFiles["mainHeader.dat"]!
        // Independently generated with Python XorShift128 and OpenSSL AES-128-CTR.
        let encrypted = try SaveCodec.crypt(input, header: header)
        XCTAssertEqual(encrypted.hex, "604fe28b9f2793143f0835d9d5745503c8c9e3f48de756a812882fb4c363168a4f938ea8f9ff5a7af7752eb355432391")
        XCTAssertEqual(try SaveCodec.crypt(encrypted, header: header), input)
    }
    func testMurmurKnownAnswer() {
        let input = Data("abcd".utf8)
        XCTAssertEqual(SaveCodec.hash(input, start: 0, length: 4), 0x43ED676A)
    }
    func testMoneyRotationAndChecksumForEveryShift() throws {
        for shift in 0...255 {
            var data = Data(repeating: 0, count: 8)
            data.put16(0xF123, at: 4); data[6] = UInt8(shift)
            for value: UInt32 in [0, 99_999, 999_999_999, UInt32.max] {
                SaveCodec.writeMoney(value, to: &data, at: 0)
                XCTAssertEqual(try SaveCodec.readMoney(data, at: 0), value)
                XCTAssertEqual(data.u16(4), 0xF123); XCTAssertEqual(data[6], UInt8(shift))
            }
        }
    }
    func testOpenAndNoOpAreByteIdentical() throws {
        let session = try SaveSession(folder: folder)
        XCTAssertEqual(session.version, "3.0.3")
        XCTAssertEqual(session.initial.economy, [1234, 750_000, 12_000, 548_000])
        let output = try session.encoded(session.initial)
        for (path, data) in output { XCTAssertEqual(data, Self.fixtureFiles[path]) }
        if let destination = ProcessInfo.processInfo.environment["ACNH_TEST_FIXTURE_OUTPUT"] {
            try FileManager.default.copyItem(at: folder, to: URL(fileURLWithPath: destination))
        }
    }
    func testAllMoneyAndMultiplePocketsExportWithValidHashes() throws {
        let session = try SaveSession(folder: folder)
        var draft = session.initial
        draft.economy = [99_999, 999_999_999, 9_999_999, 0]
        draft.pockets[0] = try PocketItem.make(id: 0x16DB, quantity: 10, maxStack: 10)
        draft.pockets[19] = try PocketItem.make(id: 0x09C9, quantity: 1, maxStack: 1)
        let destination = root.appendingPathComponent("Edited")
        try session.export(draft, to: destination)
        let reopened = try SaveSession(folder: destination)
        XCTAssertEqual(reopened.initial, draft)
        XCTAssertEqual(reopened.personal[0x20000], 0xA5)
        XCTAssertEqual(reopened.main[0x5B3D50], 0xDE, "Must not inherit upstream blanket corruption-repair writes")
        XCTAssertEqual(reopened.main[0x900000], 0xB6)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("postbox.dat")), Data("untouched sibling file".utf8))
        try session.ensureUnchanged()
        // Apart from chosen fields, pocket records and checksum words, every decrypted byte is preserved.
        let pAllowed = Set([SaveLayout.wallet, SaveLayout.bank, SaveLayout.miles].flatMap { Array($0..<($0 + 4)) + [$0 + 7] }
            + Array(SaveLayout.pocketBase..<(SaveLayout.pocketBase + 8))
            + Array((SaveLayout.pocketBase + 19 * 8)..<(SaveLayout.pocketBase + 20 * 8))
            + SaveLayout.personalRegions.flatMap { Array($0.offset..<($0.offset + 4)) })
        for i in 0..<session.personal.count where !pAllowed.contains(i) { XCTAssertEqual(session.personal[i], reopened.personal[i]) }
        let mAllowed = Set(Array(SaveLayout.loan..<(SaveLayout.loan + 4)) + [SaveLayout.loan + 7] + SaveLayout.mainRegions.flatMap { Array($0.offset..<($0.offset + 4)) })
        for i in 0..<session.main.count where !mAllowed.contains(i) { XCTAssertEqual(session.main[i], reopened.main[i]) }
    }
    func testBackupSaveRestoreAndTamperDetection() throws {
        let session = try SaveSession(folder: folder)
        var draft = session.initial; draft.economy[0] = 42
        let backup = try session.save(draft, backupRoot: backupRoot)
        try backup.verify()
        XCTAssertEqual(try Data(contentsOf: backup.saveFolder.appendingPathComponent("main.dat")), Self.fixtureFiles["main.dat"])
        let changed = try SaveSession(folder: folder)
        XCTAssertEqual(changed.initial.economy[0], 42)
        let recovery = try changed.restore(backup, backupRoot: backupRoot)
        try recovery.verify()
        XCTAssertEqual(try SaveSession(folder: folder).initial, session.initial)
        XCTAssertEqual(BackupRecord.list(root: backupRoot).count, 2)
        try Data("tampered".utf8).write(to: backup.saveFolder.appendingPathComponent("postbox.dat"))
        XCTAssertThrowsError(try backup.verify())
    }
    func testConcurrentModificationBlocksExportAndSave() throws {
        let session = try SaveSession(folder: folder)
        var changed = session.originals["main.dat"]!; changed[0] ^= 1
        try changed.write(to: folder.appendingPathComponent("main.dat"))
        XCTAssertThrowsError(try session.export(session.initial, to: root.appendingPathComponent("Edited")))
        XCTAssertThrowsError(try session.save(session.initial, backupRoot: backupRoot))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupRoot.path))
    }
    func testRejectsBadVersionsHeadersAndSizes() throws {
        var header = Self.fixtureFiles["mainHeader.dat"]!; header.put16(35, at: 14)
        try header.write(to: folder.appendingPathComponent("mainHeader.dat"))
        XCTAssertThrowsError(try SaveSession(folder: folder))
        try Data(repeating: 0, count: 30).write(to: folder.appendingPathComponent("mainHeader.dat"))
        XCTAssertThrowsError(try SaveSession(folder: folder))
        try Self.fixtureFiles["mainHeader.dat"]!.write(to: folder.appendingPathComponent("mainHeader.dat"))
        try Data(repeating: 0, count: 80).write(to: folder.appendingPathComponent("main.dat"))
        XCTAssertThrowsError(try SaveSession(folder: folder))
    }
    func testRejectsCorruptionAndInterruptedWrites() throws {
        var data = Self.fixtureFiles["Villager0/personal.dat"]!; data[0x20000] ^= 1
        try data.write(to: folder.appendingPathComponent("Villager0/personal.dat"))
        XCTAssertThrowsError(try SaveSession(folder: folder))
        try Self.fixtureFiles["Villager0/personal.dat"]!.write(to: folder.appendingPathComponent("Villager0/personal.dat"))
        try Data("unfinished".utf8).write(to: folder.appendingPathComponent(".acnh-write-in-progress"))
        XCTAssertThrowsError(try SaveSession(folder: folder))
    }
    func testRejectsInvalidDraftsAndStackCounts() throws {
        let session = try SaveSession(folder: folder)
        var draft = session.initial; draft.economy[0] = 100_000
        XCTAssertThrowsError(try session.encoded(draft))
        draft = session.initial; draft.pockets.removeLast()
        XCTAssertThrowsError(try session.encoded(draft))
        XCTAssertThrowsError(try PocketItem.make(id: 0xFFFF, quantity: 1, maxStack: 1))
        XCTAssertThrowsError(try PocketItem.make(id: 1, quantity: 31, maxStack: 30))
        XCTAssertEqual(try PocketItem.make(id: 1, quantity: 30, maxStack: 30).storedCount, 29)
    }
    func testCannotOverwriteOrExportInsideOriginalOrCopySymlinks() throws {
        let session = try SaveSession(folder: folder)
        XCTAssertThrowsError(try session.export(session.initial, to: folder))
        XCTAssertThrowsError(try session.export(session.initial, to: folder.appendingPathComponent("Child")))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: folder.appendingPathComponent("main.dat"))
        XCTAssertThrowsError(try session.export(session.initial, to: root.appendingPathComponent("Edited")))
    }
    func testPartialWriteFailureRollsBackBothFiles() throws {
        let session = try SaveSession(folder: folder)
        let backup = try BackupRecord.create(session: session, root: backupRoot)
        var draft = session.initial; draft.economy[0] = 42; draft.economy[3] = 0
        let output = try session.encoded(draft)
        var calls = 0
        XCTAssertThrowsError(try session.replace(output, backup: backup) { data, url in
            calls += 1
            if calls == 2 { throw SaveError("Simulated disk error") }
            try data.write(to: url, options: .atomic)
        })
        try session.ensureUnchanged()
        try backup.verify()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".acnh-write-in-progress").path))
    }
    func testFailedRollbackLeavesRecoveryMarkerAndVerifiedBackup() throws {
        let session = try SaveSession(folder: folder)
        let backup = try BackupRecord.create(session: session, root: backupRoot)
        var draft = session.initial; draft.economy[3] = 0
        var calls = 0
        XCTAssertThrowsError(try session.replace(session.encoded(draft), backup: backup) { data, url in
            calls += 1
            if calls >= 2 { throw SaveError("Simulated disconnected disk") }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".acnh-write-in-progress").path))
        XCTAssertThrowsError(try SaveSession(folder: folder))
        try backup.verify()
        XCTAssertEqual(try SaveSession(folder: backup.saveFolder).initial, session.initial)
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
