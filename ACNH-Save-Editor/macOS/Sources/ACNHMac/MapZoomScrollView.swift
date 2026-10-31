import AppKit
import SwiftUI

/// Keep the document at a stable logical size. AppKit magnifies and positions it
/// in one update, so a pinch never races SwiftUI layout or a delayed scroll fix.
struct MapZoomScrollView<Content: View>: NSViewRepresentable {
    @Binding var scale: Double
    @Binding var isPinching: Bool
    let mapSize: NSSize
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> MapScrollView {
        let scroll = MapScrollView()
        scroll.contentView = CenteredClipView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        // The centered handler below owns magnification, including its limits.
        // Disable AppKit's additional cursor-anchored gestures and elastic zoom.
        scroll.allowsMagnification = false
        scroll.minMagnification = 1
        scroll.maxMagnification = 5
        let host = NSHostingView(rootView: content())
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: mapSize)
        scroll.documentView = host
        return scroll
    }

    func updateNSView(_ scroll: MapScrollView, context: Context) {
        (scroll.documentView as? NSHostingView<Content>)?.rootView = content()
        scroll.scaleChanged = { scale = $0 }
        scroll.pinchChanged = { isPinching = $0 }
        if abs(scroll.magnification - scale) > 0.000001 {
            scroll.zoom(to: scale)
        }
    }

    final class MapScrollView: NSScrollView {
        var scaleChanged: ((Double) -> Void)?
        var pinchChanged: ((Bool) -> Void)?

        func zoom(to scale: Double) {
            let center = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
            setMagnification(min(5, max(1, scale)), centeredAt: center)
        }

        override func endGesture(with event: NSEvent) {
            pinchChanged?(false)
            super.endGesture(with: event)
        }

        override func magnify(with event: NSEvent) {
            let active = !event.phase.contains(.ended) && !event.phase.contains(.cancelled)
            pinchChanged?(active)
            zoom(to: magnification * (1 + event.magnification))
            scaleChanged?(Double(magnification))
        }
    }

    final class CenteredClipView: NSClipView {
        override var isFlipped: Bool { true }

        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var result = super.constrainBoundsRect(proposedBounds)
            guard let documentView else { return result }
            if result.width > documentView.frame.width {
                result.origin.x = (documentView.frame.width - result.width) / 2
            }
            if result.height > documentView.frame.height {
                result.origin.y = (documentView.frame.height - result.height) / 2
            }
            return result
        }
    }
}
