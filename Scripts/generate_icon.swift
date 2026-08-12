#!/usr/bin/env swift
// Erzeugt die PNG-Dateien für ein .iconset (Eingabe für `iconutil -c icns`).
// Aufruf: swift Scripts/generate_icon.swift <ausgabeverzeichnis>.iconset

import AppKit

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift generate_icon.swift <output-iconset-dir>")
    exit(1)
}
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.set()
        let imageRect = NSRect(origin: .zero, size: size)
        imageRect.fill()
        self.draw(in: imageRect, from: .zero, operation: .destinationIn, fraction: 1.0)
        image.unlockFocus()
        return image
    }
}

func drawIcon(size: Int) -> NSImage {
    let canvas = CGFloat(size)
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()

    let rect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let cornerRadius = canvas * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.30, alpha: 1.0),
        NSColor(calibratedRed: 0.03, green: 0.52, blue: 0.55, alpha: 1.0)
    ])
    gradient?.draw(in: path, angle: -60)
    NSGraphicsContext.restoreGraphicsState()

    let symbolConfig = NSImage.SymbolConfiguration(pointSize: canvas * 0.52, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {
        let tinted = symbol.tinted(with: .white)
        let symSize = tinted.size
        let origin = CGPoint(x: (canvas - symSize.width) / 2, y: (canvas - symSize.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

for entry in sizes {
    let img = drawIcon(size: entry.size)
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let path = outDir + "/\(entry.name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
