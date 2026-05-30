#!/usr/bin/env swift

// generate-app-icon.swift — produce a 1024×1024 PNG of the ccgauge-bar
// app icon: an Apple-grid squircle (824 body inside the 1024 canvas, NOT
// full-bleed) + indigo gradient + the SAME gauge glyph the app draws
// in-app (GaugeIcon). Invoked from `make icon`.
//
// Two things this version gets right that the old CoreGraphics one didn't:
//
//   1. Size. macOS lays every icon out on a grid where the rounded body
//      is 824×824 inside a 1024 canvas (~100px transparent margin per
//      side, where the drop shadow lives). The old generator painted the
//      squircle full-bleed (0,0,1024,1024), so on the Launchpad / Dock
//      grid it rendered noticeably LARGER than every neighbour. We now
//      inset to the 824 body.
//
//   2. Glyph orientation. The old generator re-coded the gauge with
//      CGContext.addArc under a y-flip (scaleBy y:-1), which inverted the
//      dial — it domed DOWN like a smile instead of up like a speedometer.
//      That's the exact Y-axis confusion that once garbled the menubar
//      glyph. We now draw the glyph through a SwiftUI `Canvas` with the
//      identical coordinate semantics to GaugeIcon.swift, so the app icon
//      and the in-app / menubar mark are guaranteed to be the same shape.
//
// Usage:
//   swift Tools/generate-app-icon.swift <output.png>

import SwiftUI
import AppKit

let canvas: CGFloat = 1024
// Apple macOS icon grid: rounded body is 824×824 centred in the 1024
// canvas. The ~100px margin per side is intentional — it's where the
// shadow sits and it's what makes our icon the same visual size as the
// neighbours instead of overflowing the cell.
let bodySize: CGFloat = 824

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: generate-app-icon.swift <output.png>\n".utf8))
    exit(2)
}
let outPath = CommandLine.arguments[1]

// MARK: - Gauge glyph
//
// Faithful copy of the in-app `GaugeIcon` Canvas (Sources/.../UI/Icons.swift).
// Kept in the same SwiftUI coordinate space as the original so the dial
// domes UP and the needle points up-right — copying the drawing rather
// than re-deriving it under a CGContext flip is what prevents the icon
// from drifting out of sync with the app's own mark.
struct GaugeGlyph: View {
    var size: CGFloat
    var stroke: CGFloat
    var foreground: Color

    var body: some View {
        Canvas { ctx, _ in
            let s = size / 20.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Dial: upper-half arc, centre (10, 13.5), radius 7.
            var arc = Path()
            arc.addArc(center: pt(10, 13.5), radius: 7 * s,
                       startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(arc, with: .color(foreground),
                       style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            // Tick marks hanging off each end of the dial.
            for (x, y1, y2) in [(3.0, 13.5, 14.5), (17.0, 13.5, 14.5)] {
                var p = Path()
                p.move(to: pt(x, y1))
                p.addLine(to: pt(x, y2))
                ctx.stroke(p, with: .color(foreground),
                           style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }

            // Needle: pivot → upper-right.
            var needle = Path()
            needle.move(to: pt(10, 13.5))
            needle.addLine(to: pt(13.5, 7.5))
            ctx.stroke(needle, with: .color(foreground),
                       style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            // Pivot dot.
            let dotR = 1.2 * s
            let dot = Path(ellipseIn: CGRect(x: 10 * s - dotR, y: 13.5 * s - dotR,
                                             width: dotR * 2, height: dotR * 2))
            ctx.fill(dot, with: .color(foreground))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Icon composition

struct AppIconArt: View {
    // Indigo gradient — matches Theme.indigo (#818CF8) → indigoStrong (#A5B4FC).
    private let gradTop = Color(.sRGB, red: 0x81 / 255, green: 0x8C / 255, blue: 0xF8 / 255)
    private let gradBottom = Color(.sRGB, red: 0xA5 / 255, green: 0xB4 / 255, blue: 0xFC / 255)
    private var corner: CGFloat { bodySize * 0.2237 }   // Apple squircle approximation
    private var glyphSize: CGFloat { bodySize * 0.66 }

    var body: some View {
        ZStack {
            Color.clear   // transparent 1024 canvas → grid margin

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [gradTop, gradBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                // Soft top light so the tile has a hint of dimension.
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.22), .white.opacity(0)],
                                             center: UnitPoint(x: 0.5, y: 0.16),
                                             startRadius: 0, endRadius: bodySize * 0.62))
                )
                .frame(width: bodySize, height: bodySize)
                .shadow(color: .black.opacity(0.18), radius: canvas * 0.013, y: canvas * 0.011)

            GaugeGlyph(size: glyphSize, stroke: glyphSize * 0.10, foreground: .white)
                .offset(y: -bodySize * 0.015)   // optical-centre the dial
        }
        .frame(width: canvas, height: canvas)
    }
}

// MARK: - Render → PNG
//
// SwiftUI's ImageRenderer renders the view at its point size × scale; the
// view is 1024pt and scale = 1, so we get a 1024×1024px buffer. cgImage
// (rather than nsImage) sidesteps the NSImage-reports-points size quirk.
//
// ImageRenderer is @MainActor. A `swift` shebang script's top-level code
// is nonisolated but DOES run on the main thread at startup, so
// MainActor.assumeIsolated lets us reach the renderer without an async
// hop (and without standing up an NSApplication run loop).

struct RenderedIcon { let data: Data; let width: Int; let height: Int }

func renderIcon() -> RenderedIcon? {
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: AppIconArt())
        renderer.scale = 1
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return RenderedIcon(data: png, width: cg.width, height: cg.height)
    }
}

guard let icon = renderIcon() else {
    FileHandle.standardError.write(Data("ImageRenderer failed to produce a PNG\n".utf8))
    exit(1)
}

do {
    try icon.data.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath) (\(icon.width)x\(icon.height))")
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
    exit(1)
}
