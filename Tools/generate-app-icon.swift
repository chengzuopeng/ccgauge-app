#!/usr/bin/env swift

// generate-app-icon.swift — produce a 1024×1024 PNG of the ccgauge-bar
// app icon (squircle + indigo gradient + white gauge glyph), mirroring
// the in-app `BrandMark` view. Invoked from `make icon`.
//
// Usage:
//   swift Tools/generate-app-icon.swift <output-png-path>
//
// Standalone — no SwiftUI / no app dependency.

import AppKit
import CoreGraphics
import Foundation

let canvas: CGFloat = 1024
let cornerRadius: CGFloat = canvas * 0.2237  // Apple squircle approximation

guard CommandLine.arguments.count >= 2 else {
    print("usage: generate-app-icon.swift <output.png>")
    exit(2)
}
let outPath = CommandLine.arguments[1]

guard let ctx = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("CGContext init failed")
    exit(1)
}

// MARK: - Background squircle

let bgRect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
let bgPath = CGPath(roundedRect: bgRect,
                    cornerWidth: cornerRadius,
                    cornerHeight: cornerRadius,
                    transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// Linear gradient: indigo (#818CF8) top-left → indigoStrong (#A5B4FC) bottom-right.
// Matches Theme.indigo / Theme.indigoStrong dark palette.
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let colors = [
    CGColor(colorSpace: space, components: [0x81 / 255.0, 0x8C / 255.0, 0xF8 / 255.0, 1])!,
    CGColor(colorSpace: space, components: [0xA5 / 255.0, 0xB4 / 255.0, 0xFC / 255.0, 1])!
]
let gradient = CGGradient(colorsSpace: space,
                          colors: colors as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: canvas),
                       end: CGPoint(x: canvas, y: 0),
                       options: [])

// Subtle radial highlight near the top — gives the icon a hint of light.
let highlightColors = [
    CGColor(colorSpace: space, components: [1, 1, 1, 0.20])!,
    CGColor(colorSpace: space, components: [1, 1, 1, 0])!
]
let highlight = CGGradient(colorsSpace: space,
                           colors: highlightColors as CFArray,
                           locations: [0, 1])!
ctx.drawRadialGradient(highlight,
                       startCenter: CGPoint(x: canvas * 0.5, y: canvas * 0.88),
                       startRadius: 0,
                       endCenter: CGPoint(x: canvas * 0.5, y: canvas * 0.88),
                       endRadius: canvas * 0.6,
                       options: [])
ctx.restoreGState()

// MARK: - Gauge glyph

// The glyph lives in a 20×20 design-time viewBox (same as GaugeIcon.swift).
// We render it filling ~62% of the icon canvas, anchored slightly above
// vertical center so the dial reads balanced.
let glyphSize: CGFloat = canvas * 0.62
let glyphScale = glyphSize / 20.0
let glyphX = (canvas - glyphSize) / 2
let glyphY = (canvas - glyphSize) / 2 - canvas * 0.04

ctx.saveGState()
// Move origin to glyph rect, then flip Y so we can use SVG-style top-down
// coords inside (matching the design SVG that GaugeIcon mirrors).
ctx.translateBy(x: glyphX, y: glyphY + glyphSize)
ctx.scaleBy(x: glyphScale, y: -glyphScale)

// White stroke, line width tuned to match the in-app proportions
// (1.8 of 20-unit viewBox = 9% of glyph).
let strokeW: CGFloat = 1.8
ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
ctx.setLineWidth(strokeW)
ctx.setLineCap(.round)

// Upper-half arc: center (10, 13.5), radius 7. clockwise=true in flipped
// coords paints the top half of the circle.
ctx.beginPath()
ctx.addArc(center: CGPoint(x: 10, y: 13.5),
           radius: 7,
           startAngle: .pi,         // left end
           endAngle: 0,             // right end
           clockwise: true)
ctx.strokePath()

// Two short tick marks at each arc endpoint, sticking out downward.
for x in [3.0, 17.0] {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: x, y: 13.5))
    ctx.addLine(to: CGPoint(x: x, y: 14.5))
    ctx.strokePath()
}

// Needle: from pivot (10, 13.5) up-right to (13.5, 7.5).
ctx.beginPath()
ctx.move(to: CGPoint(x: 10, y: 13.5))
ctx.addLine(to: CGPoint(x: 13.5, y: 7.5))
ctx.strokePath()

// Pivot dot.
let dotR: CGFloat = 1.4
ctx.fillEllipse(in: CGRect(x: 10 - dotR,
                           y: 13.5 - dotR,
                           width: dotR * 2,
                           height: dotR * 2))
ctx.restoreGState()

// MARK: - Write PNG

guard let cgImage = ctx.makeImage() else {
    print("makeImage failed")
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    print("PNG encode failed")
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath) (\(canvas)x\(canvas))")
} catch {
    print("write failed: \(error)")
    exit(1)
}
