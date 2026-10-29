import XCTest
@testable import ACNHCore

final class SettingsTests: XCTestCase {
    var root: URL!
    var folder: URL { root.appendingPathComponent("Island") }
    var backups: URL { root.appendingPathComponent("Backups") }
    let playerID: UInt32 = 0x12345678
    let islandID: UInt32 = 0x87654321
    let header = SaveEngineTests.fixtureFiles["mainHeader.dat"]!

    func identity(id: UInt32, name: String) throws -> Data {
        var result = Data(repeating: 0, count: 24)
        result.put32(id, at: 0); result.replaceSubrange(4..<24, with: try SettingsLayout.nameBytes(name))
        return result
    }
    func writePair(_ path: String, plain: Data, regions: [HashRegion]) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = plain
        data.replaceSubrange(0..<16, with: header.prefix(16))
        SaveLayout.rehash(&data, regions: regions)
        try SaveCodec.crypt(data, header: header).write(to: url)
        let headerURL = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "Header.dat")
        try header.write(to: headerURL)
    }
    func plain(_ path: String, in directory: URL) throws -> Data {
        let url = directory.appendingPathComponent(path)
        let headerURL = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + "Header.dat")
        return try SaveCodec.crypt(Data(contentsOf: url), header: Data(contentsOf: headerURL))
    }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ACNHSettings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Villager0"), withIntermediateDirectories: true)
        for (path, data) in SaveEngineTests.fixtureFiles { try data.write(to: folder.appendingPathComponent(path)) }
        var p = try plain("Villager0/personal.dat", in: folder)
        let town = try identity(id: islandID, name: "Palm Bay"), player = try identity(id: playerID, name: "Marina")
        p.replaceSubrange(SettingsLayout.personalID..<(SettingsLayout.personalID + 24), with: town)
        p.replaceSubrange((SettingsLayout.personalID + 0x1C)..<(SettingsLayout.personalID + 0x34), with: player)
        p[SettingsLayout.birthday] = 6; p[SettingsLayout.birthday + 1] = 15
        p[SettingsLayout.profileBirthday] = 6; p[SettingsLayout.profileBirthday + 1] = 15
        p.put16(2213, at: SettingsLayout.profileFruit)
        try writePair("Villager0/personal.dat", plain: p, regions: SaveLayout.personalRegions)
        var m = try plain("main.dat", in: folder)
        for offset in [0x1000, 0x600000, 0x990000] {
            m.replaceSubrange(offset..<(offset + 24), with: town)
            m.replaceSubrange((offset + 28)..<(offset + 52), with: player)
        }
        // Identical display names with different IDs must not be renamed.
        m.replaceSubrange(0x1100..<0x1118, with: try identity(id: 0xAAAAAAAA, name: "Marina"))
        m.replaceSubrange(0x1120..<0x1138, with: try identity(id: 0xBBBBBBBB, name: "Palm Bay"))
        m.replaceSubrange(0x1140..<0x1154, with: try SettingsLayout.nameBytes("Marina"))
        m.put16(2213, at: SettingsLayout.nativeFruit); m.put16(2286, at: SettingsLayout.sisterFruit)
        m[SettingsLayout.fruitFlags] = 1
        try writePair("main.dat", plain: m, regions: SaveLayout.mainRegions)
        var other = p
        other.replaceSubrange((SettingsLayout.personalID + 0x1C)..<(SettingsLayout.personalID + 0x34), with: try identity(id: 0x11112222, name: "Alex"))
        other.replaceSubrange(0x2000..<0x2018, with: player)
        try writePair("Villager1/personal.dat", plain: other, regions: SaveLayout.personalRegions)
        for (name, size, regions) in ResidentSaveFiles.layouts where name != "personal" {
            var data = Data(repeating: 0, count: size)
            data.replaceSubrange(0x200..<0x218, with: town)
            data.replaceSubrange(0x240..<0x258, with: player)
            data[0x300] = 0xAC
            try writePair("Villager0/\(name).dat", plain: data, regions: regions)
        }
        try Data("opaque metadata".utf8).write(to: folder.appendingPathComponent("landname.dat"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testLiteralNHSEOffsetsAndLoadedSettings() throws {
        XCTAssertEqual(SettingsLayout.personalID, 0xC248)
        XCTAssertEqual(SettingsLayout.birthday, 0x1352C)
        XCTAssertEqual(SettingsLayout.profileBirthday, 0x36598)
        XCTAssertEqual(SettingsLayout.hemisphere, 0x1E3714)
        XCTAssertEqual(SettingsLayout.airportColor, 0x575DC0)
        XCTAssertEqual(SettingsLayout.nativeFruit, 0x495170)
        XCTAssertEqual(SettingsLayout.fruitFlags, 0x22EDF6)
        let session = try SaveSession(folder: folder)
        XCTAssertEqual(session.initial.playerSettings.name, "Marina")
        XCTAssertEqual(session.initial.islandSettings.name, "Palm Bay")
        XCTAssertEqual(session.initial.playerSettings.birthDay, 15)
        let destination = root.appendingPathComponent("Noop")
        try session.export(session.initial, to: destination)
        XCTAssertEqual(try VerifiedFiles.digests(folder), try VerifiedFiles.digests(destination))
    }
    func testCombinedRenameUpdatesAllIdentityReferencesAndPreservesForeignNames() throws {
        let session = try SaveSession(folder: folder)
        var draft = session.initial
        draft.playerSettings.name = "Álex 🌴"; draft.islandSettings.name = "New Bay"
        let destination = root.appendingPathComponent("Renamed")
        try session.export(draft, to: destination)
        let reopened = try SaveSession(folder: destination)
        XCTAssertEqual(reopened.initial, draft)
        let newTown = try identity(id: islandID, name: "New Bay"), newPlayer = try identity(id: playerID, name: "Álex 🌴")
        XCTAssertEqual(reopened.main.subdata(in: 0x1000..<0x1018), newTown)
        XCTAssertEqual(reopened.main.subdata(in: 0x101C..<0x1034), newPlayer)
        XCTAssertEqual(reopened.main.subdata(in: 0x1100..<0x1154), session.main.subdata(in: 0x1100..<0x1154))
        for (name, _, regions) in ResidentSaveFiles.layouts where name != "personal" {
            let path = "Villager0/\(name).dat", old = try plain("Villager0/\(name).dat", in: folder)
            let updated = try plain(path, in: destination)
            XCTAssertEqual(updated.subdata(in: 0x200..<0x218), newTown)
            XCTAssertEqual(updated.subdata(in: 0x240..<0x258), newPlayer)
            XCTAssertEqual(updated[0x300], 0xAC)
            try SaveLayout.verify(updated, regions: regions, name: name)
            var expected = old
            expected.replaceSubrange(0x200..<0x218, with: newTown); expected.replaceSubrange(0x240..<0x258, with: newPlayer)
            SaveLayout.rehash(&expected, regions: regions)
            XCTAssertEqual(updated, expected, "Unrelated \(name) bytes must stay unchanged")
        }
        let second = try plain("Villager1/personal.dat", in: destination)
        XCTAssertEqual(SettingsLayout.player(from: second).name, "Alex")
        XCTAssertEqual(SettingsLayout.island(from: reopened.main, personal: second).name, "New Bay")
        XCTAssertEqual(second.subdata(in: 0x2000..<0x2018), newPlayer)
        for path in session.originals.keys where path.hasSuffix("Header.dat") { XCTAssertEqual(session.originals[path], reopened.originals[path]) }
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("landname.dat")), Data("opaque metadata".utf8))
        try session.ensureUnchanged()
        if let output = ProcessInfo.processInfo.environment["ACNH_SETTINGS_FIXTURE_OUTPUT"] {
            try FileManager.default.copyItem(at: folder, to: URL(fileURLWithPath: output))
        }
    }
    func testAllSettingsRoundTripAndOnlyExpectedBytesChange() throws {
        let session = try SaveSession(folder: folder)
        var draft = session.initial
        draft.playerSettings.birthMonth = 2; draft.playerSettings.birthDay = 29
        draft.islandSettings.hemisphere = 1; draft.islandSettings.airportColor = 3
        draft.islandSettings.weatherSeed = UInt32.max; draft.islandSettings.tourWeatherSeed = 0x12345678
        draft.islandSettings.tourHemisphere = 1
        draft.islandSettings.nativeFruit = 2287; draft.islandSettings.sisterFruit = 2285
        draft.islandSettings.nativeFlower = 7; draft.islandSettings.sisterFlower = 6
        let output = try session.encoded(draft)
        XCTAssertEqual(Set(output.keys), Set(["main.dat", "Villager0/personal.dat"]))
        let destination = root.appendingPathComponent("Settings")
        try session.export(draft, to: destination)
        let reopened = try SaveSession(folder: destination)
        XCTAssertEqual(reopened.initial, draft)
        var expectedP = session.personal, expectedM = session.main
        expectedP[0x1352C] = 2; expectedP[0x1352D] = 29
        expectedP[0x36598] = 2; expectedP[0x36599] = 29; expectedP.put16(2287, at: 0x3659C)
        expectedM[0x1E3714] = 1; expectedM[0x575DC0] = 3
        expectedM.put32(UInt32.max, at: 0x1E3718)
        expectedM[0x97D470] = 1; expectedM.put32(0x12345678, at: 0x97D474)
        expectedM.put16(2287, at: 0x495170); expectedM.put16(2285, at: 0x495172)
        expectedM[0x495195] = 7; expectedM[0x495194] = 6
        expectedM.replaceSubrange(0x22EDF6..<0x22EDFB, with: Data([0, 0, 0, 0, 1]))
        SaveLayout.rehash(&expectedP, regions: SaveLayout.personalRegions); SaveLayout.rehash(&expectedM, regions: SaveLayout.mainRegions)
        XCTAssertEqual(reopened.personal, expectedP); XCTAssertEqual(reopened.main, expectedM)
        for (path, bytes) in session.originals where path != "main.dat" && path != "Villager0/personal.dat" { XCTAssertEqual(reopened.originals[path], bytes) }
    }
    func testNamesDatesAndSettingsRejectInvalidDraftsBeforeWriting() throws {
        let session = try SaveSession(folder: folder)
        for invalid in ["", "   ", "abcdefghijk", "🌴🌴🌴🌴🌴🌴", "Bad\0Name", "Bad\nName"] {
            var draft = session.initial; draft.playerSettings.name = invalid
            XCTAssertThrowsError(try session.encoded(draft), invalid)
            draft = session.initial; draft.islandSettings.name = invalid
            XCTAssertThrowsError(try session.encoded(draft), invalid)
        }
        XCTAssertEqual(try SettingsLayout.nameBytes("🌴🌴🌴🌴🌴").count, 20)
        for (month, day): (UInt8, UInt8) in [(0, 1), (13, 1), (2, 30), (4, 31), (1, 0), (1, 32)] {
            var draft = session.initial; draft.playerSettings.birthMonth = month; draft.playerSettings.birthDay = day
            XCTAssertThrowsError(try session.encoded(draft))
        }
        var draft = session.initial; draft.islandSettings.hemisphere = 2
        XCTAssertThrowsError(try session.encoded(draft))
        draft = session.initial; draft.islandSettings.airportColor = 4
        XCTAssertThrowsError(try session.encoded(draft))
        draft = session.initial; draft.islandSettings.nativeFruit = 0
        XCTAssertThrowsError(try session.encoded(draft))
        draft = session.initial; draft.islandSettings.sisterFlower = 8
        let destination = root.appendingPathComponent("Invalid")
        XCTAssertThrowsError(try session.export(draft, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        try session.ensureUnchanged()
    }
    func testRenameBackupRestoreAndRollbackIncludeAdditionalFiles() throws {
        let session = try SaveSession(folder: folder), original = try VerifiedFiles.digests(folder)
        var draft = session.initial; draft.playerSettings.name = "New Name"; draft.islandSettings.name = "New Island"
        let backup = try session.save(draft, backupRoot: backups)
        let changed = try SaveSession(folder: folder)
        XCTAssertEqual(changed.initial, draft)
        _ = try changed.restore(backup, backupRoot: backups)
        XCTAssertEqual(try VerifiedFiles.digests(folder), original)
        let fresh = try SaveSession(folder: folder)
        let rollbackBackup = try BackupRecord.create(session: fresh, root: backups)
        var calls = 0
        XCTAssertThrowsError(try fresh.replace(fresh.encoded(draft), backup: rollbackBackup) { data, url in
            calls += 1
            if calls == 4 { throw SaveError("Simulated failure after several resident writes") }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertEqual(try VerifiedFiles.digests(folder), original)
    }
    func testMissingCorruptAndExternallyChangedResidentFilesAreRejected() throws {
        let session = try SaveSession(folder: folder)
        let path = folder.appendingPathComponent("Villager0/postbox.dat")
        var damaged = try Data(contentsOf: path); damaged[0x300] ^= 1
        try damaged.write(to: path)
        XCTAssertThrowsError(try session.ensureUnchanged())
        XCTAssertThrowsError(try SaveSession(folder: folder))
        try session.originals["Villager0/postbox.dat"]!.write(to: path)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Villager0/postboxHeader.dat"))
        XCTAssertThrowsError(try SaveSession(folder: folder))
    }
}
