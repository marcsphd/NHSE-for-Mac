import XCTest
import CryptoKit
@testable import ACNHCore

final class ExampleSaveTests: XCTestCase {
    private var example: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/ACNHMac/ExampleSave")
    }
    func testContributedIslandIsCompleteAndMatchesItsManifest() throws {
        struct Manifest: Decodable { let island: String; let version: String; let sha256: [String: String] }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: example.appendingPathComponent("manifest.json")))
        let folder = example.appendingPathComponent("Save")
        for (path, expected) in manifest.sha256 {
            let data = try Data(contentsOf: folder.appendingPathComponent(path))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, expected, path)
        }
        let loaded = try SaveSession(folder: folder)
        XCTAssertEqual(loaded.version, manifest.version)
        XCTAssertEqual(loaded.initial.islandSettings.name, manifest.island)
        XCTAssertFalse(loaded.initial.pockets.isEmpty)
        XCTAssertFalse(loaded.initial.storage.isEmpty)
        let world = IslandSnapshot(main: loaded.main)
        XCTAssertTrue((0..<IslandLayout.buildingCount).contains { world.building($0).kind != 0 })
        XCTAssertTrue((0..<IslandLayout.fieldCount).contains { !world.fieldItem($0).isEmpty })
        XCTAssertTrue((0..<112*96).contains { world.terrain($0).isWater })
        XCTAssertTrue((0..<112*96).contains { !world.terrain($0).isWater })
        let encoded = try loaded.encoded(loaded.initial)
        XCTAssertFalse(encoded.isEmpty)
        for (path, data) in encoded { XCTAssertEqual(data, loaded.originals[path], path) }
        try loaded.ensureUnchanged()
    }
}
