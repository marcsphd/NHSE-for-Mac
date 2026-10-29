import Foundation
import SwiftUI
import ACNHCore

struct TerrainChoice: Codable, Identifiable {
    let id: UInt16
    let name: String
    let road: Bool
}
struct VillagerChoice: Codable, Identifiable {
    let id: String
    let name: String
    let species: UInt8, variant: UInt8, personality: UInt8
    let phrase: String
    var identity: Int { Int(species) * 256 + Int(variant) }
}
struct IslandMetadata: Codable {
    let terrain: [TerrainChoice]
    let villagers: [VillagerChoice]
    static let shared: IslandMetadata = {
        let url = Bundle.module.url(forResource: "island-metadata", withExtension: "json")!
        return try! JSONDecoder().decode(IslandMetadata.self, from: Data(contentsOf: url))
    }()
    func villager(_ record: VillagerEdit) -> VillagerChoice? { villagers.first { $0.identity == record.identity } }
    func name(_ record: VillagerEdit) -> String { record.isEmpty ? "Empty slot" : villager(record)?.name ?? "Unknown resident" }
    func modelName(_ id: UInt16) -> String { terrain.first { $0.id == id }?.name ?? "Unknown \(id)" }
}

struct VillagerPortrait: View {
    let record: VillagerEdit
    let size: CGFloat
    var body: some View {
        Group {
            if let choice = IslandMetadata.shared.villager(record), let url = Bundle.module.url(forResource: "villager-" + choice.id, withExtension: "png"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else { Image(systemName: record.isEmpty ? "person.crop.circle.badge.plus" : "pawprint.fill").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(Color.island.opacity(0.5)) }
        }.frame(width: size, height: size)
    }
}
