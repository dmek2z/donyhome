import AppKit

// Build a rounded, edge-to-edge blue tile, keeping the original wordmark.
let source = NSImage(contentsOfFile: CommandLine.arguments[1])!
let output = CommandLine.arguments[2]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 220, yRadius: 220).addClip()
source.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
