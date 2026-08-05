import CoreGraphics
import Foundation

/// A rounded rectangle parametrised by arc length, starting at top centre and
/// running clockwise. `t` is 0…1 along the perimeter, which is what lets the
/// border burn down at a constant speed no matter which edge it is on.
struct RingPath {
    struct Sample {
        let point: CGPoint
        /// Unit vector pointing the way the burn travels.
        let tangent: CGPoint
        /// Unit vector pointing into the screen, away from the edge.
        var inward: CGPoint { CGPoint(x: tangent.y, y: -tangent.x) }
    }

    private enum Seg {
        case line(from: CGPoint, to: CGPoint)
        /// Angles in radians, always decreasing (clockwise in AppKit's y-up space).
        case arc(center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat)

        var length: CGFloat {
            switch self {
            case .line(let a, let b): return hypot(b.x - a.x, b.y - a.y)
            case .arc(_, let r, let s, let e): return r * abs(e - s)
            }
        }
    }

    private let segs: [Seg]
    private let offsets: [CGFloat]   // cumulative distance at each segment start
    let length: CGFloat

    init(rect: CGRect, radius: CGFloat) {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        let (minX, maxX, minY, maxY) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        let cx = rect.midX
        let q = CGFloat.pi / 2

        var s: [Seg] = []
        s.append(.line(from: CGPoint(x: cx, y: maxY), to: CGPoint(x: maxX - r, y: maxY)))
        if r > 0 { s.append(.arc(center: CGPoint(x: maxX - r, y: maxY - r), radius: r, start: q, end: 0)) }
        s.append(.line(from: CGPoint(x: maxX, y: maxY - r), to: CGPoint(x: maxX, y: minY + r)))
        if r > 0 { s.append(.arc(center: CGPoint(x: maxX - r, y: minY + r), radius: r, start: 0, end: -q)) }
        s.append(.line(from: CGPoint(x: maxX - r, y: minY), to: CGPoint(x: minX + r, y: minY)))
        if r > 0 { s.append(.arc(center: CGPoint(x: minX + r, y: minY + r), radius: r, start: -q, end: -.pi)) }
        s.append(.line(from: CGPoint(x: minX, y: minY + r), to: CGPoint(x: minX, y: maxY - r)))
        if r > 0 { s.append(.arc(center: CGPoint(x: minX + r, y: maxY - r), radius: r, start: .pi, end: q)) }
        s.append(.line(from: CGPoint(x: minX + r, y: maxY), to: CGPoint(x: cx, y: maxY)))

        var offs: [CGFloat] = []
        var total: CGFloat = 0
        for seg in s { offs.append(total); total += seg.length }
        segs = s
        offsets = offs
        length = max(1, total)
    }

    /// Sub-path covering the perimeter range [t0, t1].
    func path(from t0: CGFloat, to t1: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let d0 = clamp01(t0) * length
        let d1 = clamp01(t1) * length
        guard d1 - d0 > 0.01 else { return p }

        var started = false
        for (i, seg) in segs.enumerated() {
            let s = offsets[i], len = seg.length
            guard len > 0, s + len > d0, s < d1 else { continue }
            let u0 = clamp01((d0 - s) / len)
            let u1 = clamp01((d1 - s) / len)
            switch seg {
            case .line(let a, let b):
                if !started { p.move(to: lerp(a, b, u0)); started = true }
                p.addLine(to: lerp(a, b, u1))
            case .arc(let c, let r, let a0, let a1):
                let s0 = a0 + (a1 - a0) * u0
                let s1 = a0 + (a1 - a0) * u1
                if !started { p.move(to: onCircle(c, r, s0)); started = true }
                p.addArc(center: c, radius: r, startAngle: s0, endAngle: s1, clockwise: true)
            }
        }
        return p
    }

    func sample(at t: CGFloat) -> Sample {
        let d = clamp01(t) * length
        var idx = segs.count - 1
        for (i, seg) in segs.enumerated() where d <= offsets[i] + seg.length {
            idx = i
            break
        }
        let seg = segs[idx]
        let len = seg.length
        let u = len > 0 ? clamp01((d - offsets[idx]) / len) : 0
        switch seg {
        case .line(let a, let b):
            let dir = CGPoint(x: b.x - a.x, y: b.y - a.y)
            return Sample(point: lerp(a, b, u), tangent: normalized(dir))
        case .arc(let c, let r, let a0, let a1):
            let a = a0 + (a1 - a0) * u
            return Sample(point: onCircle(c, r, a), tangent: CGPoint(x: sin(a), y: -cos(a)))
        }
    }
}

// MARK: - small math helpers

func clamp01(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

private func onCircle(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) -> CGPoint {
    CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
}

private func normalized(_ v: CGPoint) -> CGPoint {
    let m = hypot(v.x, v.y)
    return m > 0 ? CGPoint(x: v.x / m, y: v.y / m) : CGPoint(x: 1, y: 0)
}
