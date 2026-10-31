import AppKit
import SwiftUI
import ACNHCore

/// Original generated fan artwork, separate from NHSE/Nintendo inventory assets.
@MainActor final class BuildingIconStore {
    static let shared = BuildingIconStore()
    private var images: [String: NSImage] = [:]
    static func resource(for kind: UInt16) -> String? {
        let name: String
        switch kind {
        case 1...8: name = "player-house"
        case 9...18: name = "villager-house"
        case 19: name = "nooks-cranny"
        case 20: name = "resident-services"
        case 21: name = "museum"
        case 22: name = "airport"
        case 23: name = "resident-tent"
        case 24: name = "able-sisters"
        case 25: name = "campsite"
        case 26: name = "bridge"
        case 27: name = "incline"
        case 28: name = "redd-trawler"
        case 29: name = "studio"
        case 42: name = "hotel"
        default: return nil
        }
        return "building-icon-" + name
    }
    func image(for kind: UInt16) -> NSImage? {
        guard let name = Self.resource(for: kind) else { return nil }
        if let cached = images[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        images[name] = image
        return image
    }
}

struct BuildingIcon: View {
    let kind: UInt16
    var size: CGFloat = 64
    var body: some View {
        Group {
            if let image = BuildingIconStore.shared.image(for: kind) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "building.2.fill").resizable().scaledToFit().foregroundStyle(Color.island)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
