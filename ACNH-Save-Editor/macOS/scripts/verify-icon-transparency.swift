import AppKit
import Foundation

// Read-only regression check for the icon PNG and the representations decoded from ICNS.
guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift verify-icon-transparency.swift icon.png [representation.png ...]\n", stderr)
    exit(1)
}
var failed = false
for path in CommandLine.arguments.dropFirst() {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let bitmap = NSBitmapImageRep(data: data) else { throw NSError(domain: "Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot decode image"]) }
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
        let clearCorners = corners.allSatisfy { bitmap.colorAt(x: $0.0, y: $0.1)!.alphaComponent < 0.01 }
        let opaqueCenter = bitmap.colorAt(x: width / 2, y: height / 2)!.alphaComponent > 0.99
        guard bitmap.hasAlpha, clearCorners, opaqueCenter else {
            fputs("FAIL: \(path) must have transparent exterior corners and an opaque center.\n", stderr)
            failed = true
            continue
        }
        print("PASS: \(URL(fileURLWithPath: path).lastPathComponent), \(width)×\(height), transparent corners")
    } catch {
        fputs("FAIL: \(path): \(error.localizedDescription)\n", stderr)
        failed = true
    }
}
exit(failed ? 1 : 0)
