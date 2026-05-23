// Icons.swift — line-icon set mirroring ccgauge-app-design/project/icons.jsx.
//
// All paths are 1.5–1.8px stroke, 16x16 viewBox (re-scaled to whatever
// `size` the caller passes), currentColor (i.e. inherits .foregroundStyle).

import SwiftUI

// MARK: - Gauge (the brand mark / menubar icon)

public struct GaugeIcon: View {
    public var size: CGFloat = 18
    public var stroke: CGFloat = 1.6
    public var foreground: Color = .primary

    public init(size: CGFloat = 18, stroke: CGFloat = 1.6,
                foreground: Color = .primary) {
        self.size = size
        self.stroke = stroke
        self.foreground = foreground
    }

    public var body: some View {
        // ViewBox is 20x20 in the original. Scale paths accordingly.
        Canvas { ctx, _ in
            let s = size / 20.0
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            var arc = Path()
            arc.addArc(center: pt(10, 13.5), radius: 7 * s,
                       startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(arc, with: .color(foreground), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            // Tick marks on each end of the arc
            for (x, y1, y2) in [(3.0, 13.5, 14.5), (17.0, 13.5, 14.5)] {
                var p = Path()
                p.move(to: pt(x, y1))
                p.addLine(to: pt(x, y2))
                ctx.stroke(p, with: .color(foreground), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }

            // Needle: from pivot to upper-right
            var needle = Path()
            needle.move(to: pt(10, 13.5))
            needle.addLine(to: pt(13.5, 7.5))
            ctx.stroke(needle, with: .color(foreground), style: StrokeStyle(lineWidth: stroke, lineCap: .round))

            // Pivot dot
            let dotR = 1.2 * s
            let dot = Path(ellipseIn: CGRect(x: 10 * s - dotR, y: 13.5 * s - dotR,
                                             width: dotR * 2, height: dotR * 2))
            ctx.fill(dot, with: .color(foreground))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - SF Symbols mapped to design-icon needs
//
// SwiftUI ships with hundreds of perfectly-shaped symbols already; building
// each icon as a Canvas would be a lot of pixel-fidgeting for no payoff.
// Where the design's icon matches an SF Symbol closely, we use it.

public struct ExternalIcon: View {
    public var size: CGFloat = 11
    public init(size: CGFloat = 11) { self.size = size }
    public var body: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: size, weight: .semibold))
    }
}

public struct GearIcon: View {
    public var size: CGFloat = 14
    public init(size: CGFloat = 14) { self.size = size }
    public var body: some View {
        Image(systemName: "gearshape")
            .font(.system(size: size, weight: .regular))
    }
}

public struct RefreshIcon: View {
    public var size: CGFloat = 11
    public var spin: Bool = false
    @State private var angle: Double = 0
    public init(size: CGFloat = 11, spin: Bool = false) {
        self.size = size
        self.spin = spin
    }
    public var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: size, weight: .semibold))
            .rotationEffect(.degrees(angle))
            .onAppear {
                if spin {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        angle = 360
                    }
                }
            }
    }
}

public struct AlertIcon: View {
    public var size: CGFloat = 14
    public init(size: CGFloat = 14) { self.size = size }
    public var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: size))
    }
}

public struct InfoIcon: View {
    public var size: CGFloat = 14
    public init(size: CGFloat = 14) { self.size = size }
    public var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: size))
    }
}

public struct ChevronDown: View {
    public var size: CGFloat = 10
    public init(size: CGFloat = 10) { self.size = size }
    public var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: size, weight: .semibold))
    }
}

public struct CloseIcon: View {
    public var size: CGFloat = 11
    public init(size: CGFloat = 11) { self.size = size }
    public var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: size, weight: .semibold))
    }
}

public struct MoneyIcon: View {
    public var size: CGFloat = 12
    public var active: Bool = false
    public init(size: CGFloat = 12, active: Bool = false) {
        self.size = size; self.active = active
    }
    public var body: some View {
        Image(systemName: "dollarsign")
            .font(.system(size: size, weight: active ? .semibold : .regular))
    }
}

public struct HashIcon: View {
    public var size: CGFloat = 12
    public var active: Bool = false
    public init(size: CGFloat = 12, active: Bool = false) {
        self.size = size; self.active = active
    }
    public var body: some View {
        Image(systemName: "number")
            .font(.system(size: size, weight: active ? .semibold : .regular))
    }
}

public struct SearchIcon: View {
    public var size: CGFloat = 11
    public init(size: CGFloat = 11) { self.size = size }
    public var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: size, weight: .regular))
    }
}

public struct ChevronRight: View {
    public var size: CGFloat = 10
    public init(size: CGFloat = 10) { self.size = size }
    public var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: size, weight: .semibold))
    }
}
