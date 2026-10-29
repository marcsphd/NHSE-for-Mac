// Native Mac port. GPL-3.0; save-layout metadata credited in THIRD-PARTY-NOTICES.md.
import Foundation
import CryptoKit
import SaveCrypto

public struct SaveError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

extension Data {
    public func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    public func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
    public mutating func put16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }
    public mutating func put32(_ value: UInt32, at offset: Int) {
        put16(UInt16(truncatingIfNeeded: value), at: offset)
        put16(UInt16(truncatingIfNeeded: value >> 16), at: offset + 2)
    }
    public var sha256: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}

public enum SaveCodec {
    public static func crypt(_ data: Data, header: Data) throws -> Data {
        guard header.count == 0x300, !data.isEmpty else { throw SaveError("A save header must be exactly 768 bytes.") }
        var result = data
        let count = result.count
        let ok = header.withUnsafeBytes { h in
            result.withUnsafeMutableBytes { d in
                acnh_crypt(h.bindMemory(to: UInt8.self).baseAddress, header.count, d.bindMemory(to: UInt8.self).baseAddress, count)
            }
        }
        guard ok == 1 else { throw SaveError("Unable to decrypt this save.") }
        return result
    }

    public static func hash(_ data: Data, start: Int, length: Int) -> UInt32 {
        data.withUnsafeBytes { raw in acnh_hash(raw.bindMemory(to: UInt8.self).baseAddress! + start, length) }
    }

    public static func readMoney(_ data: Data, at offset: Int) throws -> UInt32 {
        let encrypted = data.u32(offset)
        let checksum = UInt8(truncatingIfNeeded: encrypted &+ (encrypted >> 8) &+ (encrypted >> 16) &+ (encrypted >> 24) &- 0x2D)
        guard data[offset + 7] == checksum else { throw SaveError("A money field has an invalid checksum. Open a known-good backup.") }
        let shift = Int(data[offset + 6] &+ 3) & 31
        let rotated = (encrypted >> shift) | (encrypted << ((32 - shift) & 31))
        return rotated &+ 0x80E32B11 &- UInt32(data.u16(offset + 4))
    }

    public static func writeMoney(_ value: UInt32, to data: inout Data, at offset: Int) {
        let shift = (Int(data[offset + 6]) + 3) & 31
        let adjusted = value &+ UInt32(data.u16(offset + 4)) &- 0x80E32B11
        let encrypted = (adjusted << shift) | (adjusted >> ((32 - shift) & 31))
        data.put32(encrypted, at: offset)
        data[offset + 7] = UInt8(truncatingIfNeeded: encrypted &+ (encrypted >> 8) &+ (encrypted >> 16) &+ (encrypted >> 24) &- 0x2D)
    }
}

public struct HashRegion: Equatable {
    public let offset: Int
    public let length: Int
    public init(_ offset: Int, _ length: Int) { self.offset = offset; self.length = length }
}

public enum SaveLayout {
    public static let personalSize = 0x74A40
    public static let mainSize = 0x9B0E90
    public static let wallet = 0x37D60, bank = 0x6527C, miles = 0x12718, loan = 0x33CBF0
    public static let pocketBase = 0x37CA8
    public static let extraPocketBase = 0x37BF0
    public static let pocketCount = pocketBase + 20 * 8
    public static let extraPocketCount = extraPocketBase + 20 * 8
    public static func unlockedPocketOffsets(in personal: Data) throws -> [Int] {
        let first = personal.u32(pocketCount), extra = personal.u32(extraPocketCount)
        guard first <= 20, extra <= 20, first + extra > 0 else {
            throw SaveError("The saved pocket capacity is invalid. Each pocket block must have 0–20 unlocked slots, with at least one slot in total.")
        }
        // NHSE's Pocket (slots 1–20) follows Bag (slots 21–40) in memory.
        return (0..<Int(first)).map { pocketBase + $0 * 8 } + (0..<Int(extra)).map { extraPocketBase + $0 * 8 }
    }
    public static let personalRegions = [HashRegion(0x110, 0x37ACC), HashRegion(0x37BE0, 0x3CE5C)]
    public static let mainRegions = [
        HashRegion(0x110, 0x1E339C), HashRegion(0x1E34B0, 0x3D089C),
        HashRegion(0x5B3E60, 0x37ACC), HashRegion(0x5EB930, 0x3CE5C),
        HashRegion(0x6288A0, 0x37ACC), HashRegion(0x660370, 0x3CE5C),
        HashRegion(0x69D2E0, 0x37ACC), HashRegion(0x6D4DB0, 0x3CE5C),
        HashRegion(0x711D20, 0x37ACC), HashRegion(0x7497F0, 0x3CE5C),
        HashRegion(0x786760, 0x37ACC), HashRegion(0x7BE230, 0x3CE5C),
        HashRegion(0x7FB1A0, 0x37ACC), HashRegion(0x832C70, 0x3CE5C),
        HashRegion(0x86FBE0, 0x37ACC), HashRegion(0x8A76B0, 0x3CE5C),
        HashRegion(0x8E4620, 0x37ACC), HashRegion(0x91C0F0, 0x3CE5C), HashRegion(0x958F50, 0x57F3C)
    ]
    public static func version(_ header: Data) throws -> String {
        guard header.count == 0x300, header.u32(0) == 0xA0002, header.u32(4) == 0xA0028,
              header.u16(8) == 2, header.u16(10) == 0, header.u16(12) == 2,
              (31...34).contains(header.u16(14)) else {
            throw SaveError("Unsupported save version. This Mac port supports ACNH 3.0.0–3.0.3 exported saves.")
        }
        return "3.0.\(header.u16(14) - 31)"
    }
    public static func verify(_ data: Data, regions: [HashRegion], name: String) throws {
        for r in regions {
            guard r.offset + 4 + r.length <= data.count,
                  data.u32(r.offset) == SaveCodec.hash(data, start: r.offset + 4, length: r.length) else {
                throw SaveError("\(name) failed its integrity check at \(String(format: "0x%X", r.offset)). Use a fresh export or a known-good backup.")
            }
        }
    }
    public static func rehash(_ data: inout Data, regions: [HashRegion]) {
        for r in regions { data.put32(SaveCodec.hash(data, start: r.offset + 4, length: r.length), at: r.offset) }
    }
}

public struct PocketItem: Equatable, Codable {
    public var raw: Data
    public init(raw: Data) { self.raw = raw }
    public static var empty: PocketItem { PocketItem(raw: Data([0xFE, 0xFF, 0, 0, 0, 0, 0, 0])) }
    public var id: UInt16 { raw.u16(0) }
    public var isEmpty: Bool { id == 0xFFFE }
    public var storedCount: Int { Int(raw.u16(4)) }
    public static func make(id: UInt16, quantity: Int, maxStack: Int) throws -> PocketItem {
        guard id < 0xFFFD, quantity >= 1, quantity <= maxStack, maxStack <= 99 else { throw SaveError("Invalid item or stack quantity.") }
        var raw = Data(repeating: 0, count: 8)
        raw.put16(id, at: 0)
        // Stack counts in ACNH are zero-based; non-stackable items use their default variation.
        raw.put16(UInt16(quantity - 1), at: 4)
        return PocketItem(raw: raw)
    }
}

public struct SaveDraft: Equatable {
    public var economy: [UInt32]
    public var pockets: [PocketItem]
    public var storage: [PocketItem] = []
    public var island = IslandEdits()
    public var playerSettings = PlayerSettings()
    public var islandSettings = IslandSettings()
    public static let limits: [UInt32] = [99_999, 999_999_999, 9_999_999, 9_999_999]
    public static let labels = ["Wallet Bells", "Bank Bells", "Nook Miles", "House loan"]
    public init(economy: [UInt32], pockets: [PocketItem]) { self.economy = economy; self.pockets = pockets }
}

public struct SaveSession {
    public static let paths = ["main.dat", "mainHeader.dat", "Villager0/personal.dat", "Villager0/personalHeader.dat"]
    public let folder: URL
    public let version: String
    public let originals: [String: Data]
    public let personal: Data
    public let main: Data
    public let initial: SaveDraft
    public let pocketOffsets: [Int]
    private let additionalPairs: [String: AdditionalSavePair]

    public init(folder: URL) throws {
        let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".acnh-write-in-progress").path) {
            throw SaveError("An interrupted write was detected. Open the last backup from the Backups screen and export a recovered copy before using this folder.")
        }
        var files: [String: Data] = [:]
        for path in Self.paths {
            let url = folder.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { throw SaveError("Missing \(path). Open the complete exported save folder containing main.dat, mainHeader.dat, and Villager0.") }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= 16_000_000 else { throw SaveError("Invalid save file: \(path).") }
            files[path] = try Data(contentsOf: url)
        }
        let pHeader = files[Self.paths[3]]!, mHeader = files[Self.paths[1]]!
        let version = try SaveLayout.version(pHeader)
        guard try SaveLayout.version(mHeader) == version,
              files[Self.paths[0]]!.count == SaveLayout.mainSize,
              files[Self.paths[2]]!.count == SaveLayout.personalSize else { throw SaveError("The save files have mismatched versions or unexpected sizes.") }
        let personal = try SaveCodec.crypt(files[Self.paths[2]]!, header: pHeader)
        let main = try SaveCodec.crypt(files[Self.paths[0]]!, header: mHeader)
        guard personal.prefix(16) == pHeader.prefix(16), main.prefix(16) == mHeader.prefix(16) else { throw SaveError("Save headers do not match the encrypted data.") }
        try SaveLayout.verify(personal, regions: SaveLayout.personalRegions, name: "personal.dat")
        try SaveLayout.verify(main, regions: SaveLayout.mainRegions, name: "main.dat")
        let economy = try [SaveCodec.readMoney(personal, at: SaveLayout.wallet), SaveCodec.readMoney(personal, at: SaveLayout.bank), SaveCodec.readMoney(personal, at: SaveLayout.miles), SaveCodec.readMoney(main, at: SaveLayout.loan)]
        let pocketOffsets = try SaveLayout.unlockedPocketOffsets(in: personal)
        let pockets = pocketOffsets.map { PocketItem(raw: personal.subdata(in: $0..<($0 + 8))) }
        self.pocketOffsets = pocketOffsets
        self.additionalPairs = try ResidentSaveFiles.read(folder: folder, version: version, originals: &files)
        self.folder = folder; self.version = version; self.originals = files
        self.personal = personal; self.main = main
        var initial = SaveDraft(economy: economy, pockets: pockets)
        initial.playerSettings = SettingsLayout.player(from: personal)
        initial.islandSettings = SettingsLayout.island(from: main, personal: personal)
        initial.storage = try StorageLayout.read(from: personal)
        self.initial = initial
    }

    public func encoded(_ draft: SaveDraft) throws -> [String: Data] {
        guard draft.economy.count == 4, draft.pockets.count == pocketOffsets.count,
              draft.pockets.allSatisfy({ $0.raw.count == 8 }) else { throw SaveError("The edit contains an invalid inventory layout.") }
        var p = personal, m = main
        for i in 0..<4 where draft.economy[i] != initial.economy[i] {
            guard draft.economy[i] <= SaveDraft.limits[i] else { throw SaveError("\(SaveDraft.labels[i]) exceeds the in-game limit.") }
            if i == 3 { SaveCodec.writeMoney(draft.economy[i], to: &m, at: SaveLayout.loan) }
            else { SaveCodec.writeMoney(draft.economy[i], to: &p, at: [SaveLayout.wallet, SaveLayout.bank, SaveLayout.miles][i]) }
        }
        for i in pocketOffsets.indices where draft.pockets[i] != initial.pockets[i] {
            let offset = pocketOffsets[i]
            p.replaceSubrange(offset..<(offset + 8), with: draft.pockets[i].raw)
        }
        try StorageLayout.apply(draft.storage, original: initial.storage, to: &p)
        try draft.island.applying(to: &m)
        try SettingsLayout.applyValues(draft, initial: initial, personal: &p, main: &m)
        let identities = try SettingsLayout.identityChanges(draft, initial: initial, personal: personal)
        SettingsLayout.replacingIdentities(in: &p, changes: identities)
        SettingsLayout.replacingIdentities(in: &m, changes: identities)
        SaveLayout.rehash(&p, regions: SaveLayout.personalRegions)
        SaveLayout.rehash(&m, regions: SaveLayout.mainRegions)
        var output = [Self.paths[0]: try SaveCodec.crypt(m, header: originals[Self.paths[1]]!), Self.paths[2]: try SaveCodec.crypt(p, header: originals[Self.paths[3]]!)]
        if !identities.isEmpty {
            for (path, pair) in additionalPairs {
                var data = pair.plaintext
                SettingsLayout.replacingIdentities(in: &data, changes: identities)
                if data != pair.plaintext {
                    SaveLayout.rehash(&data, regions: pair.regions)
                    output[path] = try SaveCodec.crypt(data, header: originals[pair.headerPath]!)
                }
            }
        }
        return output
    }

    public func ensureUnchanged() throws {
        for path in originals.keys {
            guard try Data(contentsOf: folder.appendingPathComponent(path)) == originals[path] else {
                throw SaveError("The save changed outside this app. Reopen the folder before saving.")
            }
        }
        for slot in 0..<8 {
            for (name, _, _) in ResidentSaveFiles.layouts {
                for suffix in [".dat", "Header.dat"] {
                    let path = "Villager\(slot)/\(name)\(suffix)"
                    guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path) == (originals[path] != nil) else {
                        throw SaveError("The resident save files changed outside this app. Reopen the folder before saving.")
                    }
                }
            }
        }
    }

    public func export(_ draft: SaveDraft, to destination: URL) throws {
        try ensureUnchanged()
        let output = try encoded(draft)
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !destination.path.hasPrefix(folder.path + "/"), destination != folder else { throw SaveError("Choose a new folder outside the original save.") }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw SaveError("The destination already exists. Choose a new folder name.") }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".acnh-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try VerifiedFiles.copy(folder, to: staging)
        for (path, data) in output { try data.write(to: staging.appendingPathComponent(path), options: .atomic) }
        _ = try SaveSession(folder: staging)
        try ensureUnchanged()
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    @discardableResult public func save(_ draft: SaveDraft, backupRoot: URL) throws -> BackupRecord {
        try ensureUnchanged()
        let output = try encoded(draft)
        let backup = try BackupRecord.create(session: self, root: backupRoot)
        try replace(output, backup: backup)
        return backup
    }

    public func restore(_ backup: BackupRecord, backupRoot: URL) throws -> BackupRecord {
        try backup.verify()
        let prior = try SaveSession(folder: backup.saveFolder)
        guard Set(prior.originals.keys) == Set(originals.keys),
              originals.keys.filter({ $0.hasSuffix("Header.dat") }).allSatisfy({ prior.originals[$0] == originals[$0] }),
              backup.sourcePath == folder.path else { throw SaveError("This backup belongs to a different save or uses different encryption headers. Open the backup and export a separate copy.") }
        try ensureUnchanged()
        let recovery = try BackupRecord.create(session: self, root: backupRoot)
        try replace(prior.originals.filter { !$0.key.hasSuffix("Header.dat") }, backup: recovery)
        return recovery
    }

    func replace(_ output: [String: Data], backup: BackupRecord, writer: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        try ensureUnchanged()
        let marker = folder.appendingPathComponent(".acnh-write-in-progress")
        try Data(backup.directory.path.utf8).write(to: marker, options: .atomic)
        do {
            for path in output.keys.sorted() {
                let url = folder.appendingPathComponent(path)
                try writer(output[path]!, url)
                guard try Data(contentsOf: url) == output[path] else { throw SaveError("Write verification failed for \(path).") }
            }
            try FileManager.default.removeItem(at: marker)
        } catch {
            let writeError = error
            do {
                for path in output.keys.sorted() { try writer(originals[path]!, folder.appendingPathComponent(path)) }
                for path in output.keys { guard try Data(contentsOf: folder.appendingPathComponent(path)) == originals[path] else { throw SaveError("Rollback verification failed.") } }
                try FileManager.default.removeItem(at: marker)
            } catch {
                throw SaveError("The write and rollback could not finish. Your verified backup is at \(backup.saveFolder.path). Open it and export a recovered copy.")
            }
            throw writeError
        }
    }
}

public enum VerifiedFiles {
    public static func digests(_ folder: URL) throws -> [String: String] {
        let fm = FileManager.default
        var result: [String: String] = [:], total = 0
        func visit(_ directory: URL, relative: String, depth: Int) throws {
            guard depth <= 32 else { throw SaveError("The save folder contains too many nested folders.") }
            for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                let path = relative.isEmpty ? url.lastPathComponent : relative + "/" + url.lastPathComponent
                guard values.isSymbolicLink != true else { throw SaveError("Save folders containing symbolic links are not supported.") }
                if values.isDirectory == true { try visit(url, relative: path, depth: depth + 1) }
                else if values.isRegularFile == true {
                    total += values.fileSize ?? 0
                    guard total <= 512 * 1024 * 1024, result.count < 10_000 else { throw SaveError("This folder is too large. Select only the exported ACNH save folder.") }
                    result[path] = try Data(contentsOf: url).sha256
                } else { throw SaveError("The save folder contains an unsupported file: \(path).") }
            }
        }
        try visit(folder, relative: "", depth: 0)
        return result
    }
    @discardableResult public static func copy(_ folder: URL, to destination: URL) throws -> [String: String] {
        let before = try digests(folder)
        try FileManager.default.copyItem(at: folder, to: destination)
        let after = try digests(destination)
        guard before == after, try digests(folder) == before else { throw SaveError("The folder changed while copying, or its copy failed verification.") }
        return before
    }
}

public struct BackupRecord: Codable, Identifiable {
    public let id: String
    public let created: Date
    public let sourcePath: String
    public let hashes: [String: String]
    public var directory: URL
    public var saveFolder: URL { directory.appendingPathComponent("Save", isDirectory: true) }
    public static func create(session: SaveSession, root: URL) throws -> BackupRecord {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let hashes = try VerifiedFiles.copy(session.folder, to: directory.appendingPathComponent("Save"))
            try session.ensureUnchanged()
            let record = BackupRecord(id: directory.lastPathComponent, created: Date(), sourcePath: session.folder.path, hashes: hashes, directory: directory)
            try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            return record
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    public func verify() throws {
        guard try VerifiedFiles.digests(saveFolder) == hashes else { throw SaveError("This backup failed verification. It has been changed since it was created.") }
    }
    public static func list(root: URL) -> [BackupRecord] {
        let directories = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return directories.compactMap { directory in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")), var record = try? JSONDecoder().decode(BackupRecord.self, from: data) else { return nil }
            record.directory = directory
            return record
        }.sorted { $0.created > $1.created }
    }
}
