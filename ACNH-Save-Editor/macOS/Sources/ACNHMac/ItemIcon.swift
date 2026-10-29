import AppKit
import SwiftUI

/// NHSE's bundled inventory icons, resolved by item ID rather than display name.
@MainActor private final class ItemIconStore {
    static let shared = ItemIconStore()
    private let names: [String: String]
    private let images = NSCache<NSString, NSImage>()

    private init() {
        let data = Bundle.module.url(forResource: "item-icons", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        names = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        images.countLimit = 192
        images.totalCostLimit = 8 * 1024 * 1024
    }

    func image(for id: UInt16) -> NSImage? {
        let name = names[String(id)] ?? "item-icon-leaf"
        if let cached = images.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: name as NSString, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
}

struct ItemIcon: View {
    let id: UInt16
    var size: CGFloat = 32

    var body: some View {
        Group {
            if id == 0xFFFE {
                Image(systemName: "plus").font(.system(size: size * 0.55)).foregroundStyle(Color.secondary.opacity(0.35))
            } else if let image = ItemIconStore.shared.image(for: id) {
                Image(nsImage: image).resizable().renderingMode(.original).interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "leaf.fill").resizable().scaledToFit().padding(size * 0.18).foregroundStyle(Color.island)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
