#!/usr/bin/swift
import AppKit
import Foundation

// MARK: - Pixel grid (12 × 18) — matches PixelMascot.swift
// 0=transparent  1=glacier  2=cyan  3=dark  4=white  5=coral  6=gold
let grid: [[Int]] = [
    [0,0,0,0,6,0,0,0,0,0,0,0],
    [0,0,0,0,3,0,0,0,0,0,0,0],
    [0,0,1,1,1,1,1,0,0,0,0,0],
    [0,1,1,1,1,1,1,1,0,0,0,0],
    [1,1,1,1,1,1,1,1,1,0,0,0],
    [1,1,3,3,1,1,3,3,1,0,0,0],
    [1,1,3,4,1,1,3,4,1,0,0,0],
    [1,1,1,1,5,5,1,1,1,0,0,0],
    [1,1,1,1,1,1,1,1,1,0,0,0],
    [0,1,1,1,1,1,1,1,0,0,0,0],
    [0,0,1,1,1,1,1,0,0,0,0,0],
    [0,2,0,2,0,2,0,2,0,2,0,0],
    [2,2,2,0,2,2,2,0,2,2,0,0],
    [2,2,2,2,2,2,2,2,2,2,2,0],
    [2,2,2,0,2,2,2,0,2,2,0,0],
    [0,2,0,2,0,2,0,2,0,2,0,0],
    [0,0,3,0,0,0,0,3,0,0,0,0],
    [0,0,3,3,0,0,3,3,0,0,0,0],
]

let cols = grid[0].count  // 12
let rows = grid.count     // 18

// MARK: - NSColor palette
func nsColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}
let palette: [Int: NSColor] = [
    1: nsColor(0.227, 0.659, 0.788),
    2: nsColor(0.133, 0.827, 0.933),
    3: nsColor(0.090, 0.133, 0.196),
    4: .white,
    5: nsColor(1.0,   0.42,  0.42 ),
    6: nsColor(1.0,   0.843, 0.0  ),
]

// MARK: - Render
func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // Dark navy background with rounded corners
    let bg = NSColor(srgbRed: 0.059, green: 0.090, blue: 0.141, alpha: 1)
    bg.setFill()
    let radius = s * 0.22
    NSBezierPath(roundedRect: NSRect(x:0,y:0,width:s,height:s),
                 xRadius: radius, yRadius: radius).fill()

    // Subtle radial glow in center
    let glow = NSGradient(colors: [
        NSColor(srgbRed: 0.133, green: 0.827, blue: 0.933, alpha: 0.08),
        NSColor.clear,
    ])
    glow?.draw(in: NSRect(x:0,y:0,width:s,height:s), relativeCenterPosition: NSPoint(x:0.35,y:0.55))

    // Scale pixel size so sprite fits with ~12% padding on each side
    let padFactor: CGFloat = 0.76
    let px = floor(min(s * padFactor / CGFloat(cols), s * padFactor / CGFloat(rows)))
    let spriteW = CGFloat(cols) * px
    let spriteH = CGFloat(rows) * px
    let originX = (s - spriteW) / 2
    let originY = (s - spriteH) / 2

    for (r, rowData) in grid.enumerated() {
        for (c, idx) in rowData.enumerated() {
            guard idx != 0, let color = palette[idx] else { continue }
            color.setFill()
            // NSImage coords: Y=0 at bottom, so flip row
            let x = originX + CGFloat(c) * px
            let y = originY + CGFloat(rows - 1 - r) * px
            NSBezierPath(rect: NSRect(x:x, y:y, width:px, height:px)).fill()
        }
    }

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("ERROR: could not encode \(path)")
        return
    }
    let url = URL(fileURLWithPath: path)
    do {
        try png.write(to: url)
        print("✓ \(path)")
    } catch {
        print("ERROR writing \(path): \(error)")
    }
}

// MARK: - Generate all sizes
let script = URL(fileURLWithPath: #file)
let root   = script.deletingLastPathComponent().deletingLastPathComponent()
let iconDir = root
    .appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
    .path

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16",   16),
    ("icon_32x32",   32),
    ("icon_64x64",   64),
    ("icon_128x128", 128),
    ("icon_256x256", 256),
    ("icon_512x512", 512),
    ("icon_1024x1024", 1024),
]

for s in sizes {
    let img = renderIcon(size: s.px)
    savePNG(img, to: "\(iconDir)/\(s.name).png")
}
print("All icons written to \(iconDir)")
