import SwiftUI
import ACNHCore

struct InventorySelectionHint: View {
    let selection: InventorySelection
    var paged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Click a slot to select it. Shift-click selects a range; ⌘-click adds or removes individual slots.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("\(selection.indices.count) selected\(paged ? " · Selection stays on this page" : "")")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }
}
