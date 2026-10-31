import AppKit
import SwiftUI
import XCTest
@testable import ACNHMac

final class MapZoomScrollViewTests: XCTestCase {
    private typealias MapView = MapZoomScrollView<EmptyView>

    @MainActor
    private func makeScroll() -> MapView.MapScrollView {
        let scroll = MapView.MapScrollView(frame: NSRect(x: 0, y: 0, width: 1100, height: 660))
        scroll.contentView = MapView.CenteredClipView()
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.allowsMagnification = false
        scroll.minMagnification = 1
        scroll.maxMagnification = 5
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 640))
        scroll.tile()
        scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(scroll.contentView.bounds).origin)
        return scroll
    }

    @MainActor
    private func mapCenter(_ scroll: NSScrollView) -> NSPoint {
        scroll.documentView!.convert(NSPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY), from: scroll.contentView)
    }

    @MainActor
    func testSmallDocumentIsCentered() {
        let scroll = makeScroll()
        XCTAssertEqual(mapCenter(scroll).x, 360, accuracy: 0.0001)
        XCTAssertEqual(mapCenter(scroll).y, 320, accuracy: 0.0001)
        XCTAssertLessThan(scroll.contentView.bounds.origin.x, 0)
        XCTAssertLessThan(scroll.contentView.bounds.origin.y, 0)
    }

    @MainActor
    func testRepeatedFractionalZoomReversalsKeepTheCenter() {
        let scroll = makeScroll()
        // Cross both points where the map becomes larger than the viewport.
        let scales = stride(from: 1.0, through: 5.0, by: 0.03125).map { $0 }
        for scale in scales + scales.reversed() + [1.375, 1.362, 1.389, 2.731, 2.709, 5, 1] {
            scroll.zoom(to: scale)
            XCTAssertEqual(scroll.magnification, scale, accuracy: 0.000001)
            XCTAssertEqual(mapCenter(scroll).x, 360, accuracy: 0.0001)
            XCTAssertEqual(mapCenter(scroll).y, 320, accuracy: 0.0001)
            XCTAssertEqual(scroll.documentView!.frame.size, NSSize(width: 720, height: 640))
        }
    }

    @MainActor
    func testPannedCenterAndScaleLimits() {
        let scroll = makeScroll()
        scroll.zoom(to: 2)
        scroll.contentView.scroll(to: NSPoint(x: 150, y: 180))
        let center = mapCenter(scroll)
        for scale in [2.1, 2.093, 3.7, 5.0, 2.0] {
            scroll.zoom(to: scale)
            XCTAssertEqual(mapCenter(scroll).x, center.x, accuracy: 0.0001)
            XCTAssertEqual(mapCenter(scroll).y, center.y, accuracy: 0.0001)
        }
        scroll.zoom(to: 10)
        XCTAssertEqual(scroll.magnification, 5)
        scroll.zoom(to: 0.5)
        XCTAssertEqual(scroll.magnification, 1)
    }
}
