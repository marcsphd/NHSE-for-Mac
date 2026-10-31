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

    @MainActor
    func testPointerHitTestingDoesNotDependOnSwiftUIContentShapes() {
        let scroll = makeScroll()
        let host = MapView.MapDocumentView(rootView: EmptyView())
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
        scroll.documentView = host
        for scale in [1.0, 1.375, 2, 3.7, 5] {
            scroll.zoom(to: scale)
            for point in [NSPoint(x: 1, y: 1), NSPoint(x: 360, y: 320), NSPoint(x: 719, y: 639)] {
                let hit = host.hitTest(host.convert(point, to: host.superview))
                XCTAssertTrue(hit === host, "Missing pointer target at \(point), zoom \(scale)")
            }
            XCTAssertNil(host.hitTest(host.convert(NSPoint(x: -1, y: 100), to: host.superview)))
        }
    }

    @MainActor
    func testPointerCoordinatesUseNativeMagnificationAndPanning() {
        let scroll = makeScroll()
        let host = MapView.MapDocumentView(rootView: EmptyView())
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
        scroll.documentView = host
        for scale in [1.0, 1.375, 2, 3.7, 5] {
            scroll.zoom(to: scale)
            let center = mapCenter(scroll)
            // This is a screen-space offset, independent of document resolution.
            let windowPoint = scroll.convert(NSPoint(x: scroll.bounds.midX + 90,
                                                     y: scroll.bounds.midY + (scroll.isFlipped ? 60 : -60)), to: nil)
            let selected = host.mapPoint(fromWindow: windowPoint)
            XCTAssertEqual(selected.x, center.x + 90 / scale, accuracy: 0.0001)
            let topDownCenterY = host.isFlipped ? center.y : host.bounds.height - center.y
            XCTAssertEqual(selected.y, topDownCenterY + 60 / scale, accuracy: 0.0001)
            if scale > 2 {
                var bounds = scroll.contentView.bounds
                bounds.origin.x += 20
                bounds.origin.y += 30
                scroll.contentView.scroll(to: bounds.origin)
            }
        }
    }

    @MainActor
    func testMouseDownDragAndUpDeliverOneStrokeInLogicalCoordinates() throws {
        let scroll = makeScroll()
        let host = MapView.MapDocumentView(rootView: EmptyView())
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
        scroll.documentView = host
        scroll.zoom(to: 3.7)
        var actions = [String]()
        var points = [NSPoint]()
        host.onPointerBegan = { actions.append("begin") }
        host.onPointer = { actions.append("point"); points.append($0) }
        host.onPointerEnded = { actions.append("end") }
        let expected = [NSPoint(x: 300, y: 200), NSPoint(x: 315, y: 220)]
        for (type, point) in [(NSEvent.EventType.leftMouseDown, expected[0]), (.leftMouseDragged, expected[1]), (.leftMouseUp, expected[1])] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: host.convert(point, to: nil),
                                                       modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                       context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: host.mouseDown(with: event)
            case .leftMouseDragged: host.mouseDragged(with: event)
            default: host.mouseUp(with: event)
            }
        }
        XCTAssertEqual(actions, ["begin", "point", "point", "end"])
        XCTAssertEqual(points.count, 2)
        for (point, wanted) in zip(points, expected) {
            XCTAssertEqual(point.x, wanted.x, accuracy: 0.0001)
            XCTAssertEqual(point.y, host.isFlipped ? wanted.y : host.bounds.height - wanted.y, accuracy: 0.0001)
        }
    }

}
