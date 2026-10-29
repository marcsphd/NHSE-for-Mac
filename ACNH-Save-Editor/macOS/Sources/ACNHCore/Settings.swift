// NHSE 3.0 layouts and identity propagation; see THIRD-PARTY-NOTICES.md.
import Foundation

public struct PlayerSettings: Equatable {
    public var name = ""
    public var birthMonth: UInt8 = 0
    public var birthDay: UInt8 = 0
    public init() {}
}

public struct IslandSettings: Equatable {
    public var name = ""
    public var hemisphere: UInt8 = 0
    public var airportColor: UInt8 = 0
    public var weatherSeed: UInt32 = 0
    public var tourHemisphere: UInt8 = 0
    public var tourWeatherSeed: UInt32 = 0
    public var nativeFruit: UInt16 = 0
    public var sisterFruit: UInt16 = 0
    public var nativeFlower: UInt8 = 0
    public var sisterFlower: UInt8 = 0
    public init() {}
    public static let fruits: [(id: UInt16, name: String)] = [(2213, "Apple"), (2214, "Orange"), (2285, "Pear"), (2286, "Peach"), (2287, "Cherry")]
    public static let flowers = ["Windflower", "Hyacinth", "Tulip", "Rose", "Cosmos", "Lily", "Mums", "Pansy"]
    public static let hemispheres = ["Northern", "Southern"]
    public static let airportColors = ["Blue", "Yellow", "Orange", "Green"]
}

public enum SettingsLayout {
    public static let personalID = 0x110 + 0xC138
    public static let birthday = 0x110 + 0x1341C
    public static let profileBirthday = 0x110 + 0x13430 + 0x23058
    public static let profileFruit = profileBirthday + 4
    public static let hemisphere = 0x110 + 0x1E35F0 + 0x14
    public static let weatherSeed = hemisphere + 4
    public static let airportColor = 0x110 + 0x575CB0
    public static let tourHemisphere = 0x5B3D50 + 0x3C970C + 0x14
    public static let tourWeatherSeed = tourHemisphere + 4
    public static let nativeFruit = 0x110 + 0x494760 + 0x900
    public static let sisterFruit = nativeFruit + 2
    public static let sisterFlower = 0x110 + 0x494760 + 0x924
    public static let nativeFlower = sisterFlower + 1
    public static let fruitFlags = 0x110 + 0x22EBF0 + 246

    public static func readName(_ data: Data, at offset: Int) -> String {
        let units = (0..<10).map { data.u16(offset + $0 * 2) }.prefix { $0 != 0 }
        return String(decoding: units, as: UTF16.self)
    }
    public static func nameBytes(_ name: String) throws -> Data {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf16.count <= 10,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw SaveError("Names must contain 1–10 UTF-16 units, with no line breaks or control characters. Emoji can use more than one unit.")
        }
        var bytes = Data(repeating: 0, count: 20)
        for (index, unit) in name.utf16.enumerated() { bytes.put16(unit, at: index * 2) }
        return bytes
    }
    public static func player(from personal: Data) -> PlayerSettings {
        var result = PlayerSettings()
        result.name = readName(personal, at: personalID + 0x20)
        result.birthMonth = personal[birthday]; result.birthDay = personal[birthday + 1]
        return result
    }
    public static func island(from main: Data, personal: Data) -> IslandSettings {
        var result = IslandSettings()
        result.name = readName(personal, at: personalID + 4)
        result.hemisphere = main[hemisphere]; result.airportColor = main[airportColor]
        result.weatherSeed = main.u32(weatherSeed)
        result.tourHemisphere = main[tourHemisphere]; result.tourWeatherSeed = main.u32(tourWeatherSeed)
        result.nativeFruit = main.u16(nativeFruit); result.sisterFruit = main.u16(sisterFruit)
        result.nativeFlower = main[nativeFlower]; result.sisterFlower = main[sisterFlower]
        return result
    }
    public static func validate(_ draft: SaveDraft, initial: SaveDraft) throws {
        if draft.playerSettings.name != initial.playerSettings.name { _ = try nameBytes(draft.playerSettings.name) }
        if draft.islandSettings.name != initial.islandSettings.name { _ = try nameBytes(draft.islandSettings.name) }
        let p = draft.playerSettings, old = initial.playerSettings
        if p.birthMonth != old.birthMonth || p.birthDay != old.birthDay {
            let days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            guard (1...12).contains(p.birthMonth), p.birthDay >= 1, Int(p.birthDay) <= days[Int(p.birthMonth) - 1] else {
                throw SaveError("Choose a valid birthday. February 29 is allowed.")
            }
        }
        let s = draft.islandSettings, before = initial.islandSettings
        guard (s.hemisphere == before.hemisphere || s.hemisphere <= 1),
              (s.tourHemisphere == before.tourHemisphere || s.tourHemisphere <= 1),
              (s.airportColor == before.airportColor || s.airportColor <= 3),
              (s.nativeFlower == before.nativeFlower || s.nativeFlower <= 7),
              (s.sisterFlower == before.sisterFlower || s.sisterFlower <= 7),
              (s.nativeFruit == before.nativeFruit || IslandSettings.fruits.contains { $0.id == s.nativeFruit }),
              (s.sisterFruit == before.sisterFruit || IslandSettings.fruits.contains { $0.id == s.sisterFruit }) else {
            throw SaveError("Choose a supported hemisphere, airport color, fruit, and flower.")
        }
    }
    static func applyValues(_ draft: SaveDraft, initial: SaveDraft, personal: inout Data, main: inout Data) throws {
        try validate(draft, initial: initial)
        let p = draft.playerSettings, old = initial.playerSettings
        if p.birthMonth != old.birthMonth || p.birthDay != old.birthDay {
            for offset in [birthday, profileBirthday] { personal[offset] = p.birthMonth; personal[offset + 1] = p.birthDay }
        }
        let s = draft.islandSettings, before = initial.islandSettings
        for (offset, value, original) in [(hemisphere, s.hemisphere, before.hemisphere), (airportColor, s.airportColor, before.airportColor),
            (tourHemisphere, s.tourHemisphere, before.tourHemisphere), (nativeFlower, s.nativeFlower, before.nativeFlower), (sisterFlower, s.sisterFlower, before.sisterFlower)] where value != original { main[offset] = value }
        if s.weatherSeed != before.weatherSeed { main.put32(s.weatherSeed, at: weatherSeed) }
        if s.tourWeatherSeed != before.tourWeatherSeed { main.put32(s.tourWeatherSeed, at: tourWeatherSeed) }
        if s.sisterFruit != before.sisterFruit { main.put16(s.sisterFruit, at: sisterFruit) }
        if s.nativeFruit != before.nativeFruit {
            main.put16(s.nativeFruit, at: nativeFruit)
            personal.put16(s.nativeFruit, at: profileFruit)
            for (index, fruit) in IslandSettings.fruits.enumerated() { main[fruitFlags + index] = fruit.id == s.nativeFruit ? 1 : 0 }
        }
    }
    // Match NHSE's full 24-byte ID + name identity, not arbitrary occurrences of a name.
    static func identityChanges(_ draft: SaveDraft, initial: SaveDraft, personal: Data) throws -> [(Data, Data)] {
        var changes: [(Data, Data)] = []
        for (offset, name, original) in [(personalID + 0x1C, draft.playerSettings.name, initial.playerSettings.name),
                                        (personalID, draft.islandSettings.name, initial.islandSettings.name)] where name != original {
            let old = personal.subdata(in: offset..<(offset + 24))
            guard old.u32(0) != 0 else { throw SaveError("This save has no valid identity for the requested rename.") }
            var new = old; new.replaceSubrange(4..<24, with: try nameBytes(name))
            changes.append((old, new))
        }
        return changes
    }
    static func replacingIdentities(in data: inout Data, changes: [(Data, Data)]) {
        for (old, new) in changes {
            var start = 0
            while start <= data.count - old.count, let range = data.range(of: old, in: start..<data.count) {
                data.replaceSubrange(range, with: new)
                start = range.upperBound
            }
        }
    }
}

struct AdditionalSavePair {
    let headerPath: String
    let plaintext: Data
    let regions: [HashRegion]
}

enum ResidentSaveFiles {
    static let layouts: [(String, Int, [HashRegion])] = [
        ("personal", SaveLayout.personalSize, SaveLayout.personalRegions),
        ("postbox", 0x47430, [HashRegion(0x100, 0x4732C)]),
        ("photo_studio_island", 0x2F650, [HashRegion(0x100, 0x2F54C)]),
        ("profile", 0x69560, [HashRegion(0x100, 0x6945C)]),
        ("wherearen", 0xB8A4E0, [HashRegion(0x100, 0xB8A3DC)])
    ]
    static func read(folder: URL, version: String, originals: inout [String: Data]) throws -> [String: AdditionalSavePair] {
        let fm = FileManager.default
        var pairs: [String: AdditionalSavePair] = [:]
        for slot in 0..<8 {
            let directory = folder.appendingPathComponent("Villager\(slot)")
            guard fm.fileExists(atPath: directory.path) else { continue }
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw SaveError("Invalid resident folder: Villager\(slot).") }
            for (name, size, regions) in layouts {
                let path = "Villager\(slot)/\(name).dat", headerPath = "Villager\(slot)/\(name)Header.dat"
                let exists = fm.fileExists(atPath: folder.appendingPathComponent(path).path)
                let headerExists = fm.fileExists(atPath: folder.appendingPathComponent(headerPath).path)
                guard exists || headerExists else { continue }
                guard exists && headerExists else { throw SaveError("Missing data or encryption header for \(path). Keep the complete save folder together.") }
                if path == SaveSession.paths[2] { continue }
                for (file, expectedSize) in [(path, size), (headerPath, 0x300)] {
                    let url = folder.appendingPathComponent(file)
                    let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == expectedSize else { throw SaveError("Invalid size or file type: \(file).") }
                    originals[file] = try Data(contentsOf: url)
                }
                let header = originals[headerPath]!
                guard try SaveLayout.version(header) == version else { throw SaveError("Mismatched save revision: \(path).") }
                let plain = try SaveCodec.crypt(originals[path]!, header: header)
                guard plain.prefix(16) == header.prefix(16) else { throw SaveError("Save header does not match \(path).") }
                try SaveLayout.verify(plain, regions: regions, name: path)
                pairs[path] = AdditionalSavePair(headerPath: headerPath, plaintext: plain, regions: regions)
            }
        }
        return pairs
    }
}
