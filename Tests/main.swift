import Foundation
import CoreGraphics

// A plain executable rather than XCTest: the app is built with swiftc, and the
// two things worth pinning down — duration parsing and the ring's arc length —
// are pure Foundation and CoreGraphics.

var failures = 0
var checks = 0

func check(_ ok: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !ok {
        failures += 1
        let extra = detail()
        print("  ✗ \(what)\(extra.isEmpty ? "" : " — \(extra)")")
    }
}

func equal(_ a: Double?, _ b: Double?, _ what: String, tolerance: Double = 0.0001) {
    switch (a, b) {
    case let (x?, y?): check(abs(x - y) <= tolerance, what, "\(x) ≠ \(y)")
    case (nil, nil):   check(true, what)
    default:           check(false, what, "\(String(describing: a)) ≠ \(String(describing: b))")
    }
}

// MARK: - Duration.parse

print("Duration.parse")
equal(Duration.parse("25"), 25 * 60, "bare number is minutes")
equal(Duration.parse("45m"), 45 * 60, "minutes")
equal(Duration.parse("2h"), 2 * 3600, "hours")
equal(Duration.parse("90s"), 90, "seconds")
equal(Duration.parse("1h30"), 5400, "trailing number after hours is minutes")
equal(Duration.parse("2m30"), 150, "trailing number after minutes is seconds")
equal(Duration.parse("1h30m"), 5400, "explicit units")
equal(Duration.parse("25:00"), 1500, "mm:ss")
equal(Duration.parse("1:05:30"), 3930, "h:mm:ss")
equal(Duration.parse(" 25 m "), 1500, "spaces ignored")
equal(Duration.parse("25M"), 1500, "case ignored")
equal(Duration.parse("0.5h"), 1800, "fractions")
equal(Duration.parse(""), nil, "empty is nil")
equal(Duration.parse("soon"), nil, "words are nil")
equal(Duration.parse("0"), nil, "zero is nil")
equal(Duration.parse("25x"), nil, "unknown unit is nil")
equal(Duration.parse("1:2:3:4"), nil, "too many colon parts is nil")

// MARK: - Format

print("Format")
check(Format.clock(59) == "0:59", "clock under a minute", Format.clock(59))
check(Format.clock(1500) == "25:00", "clock minutes", Format.clock(1500))
check(Format.clock(3930) == "1:05:30", "clock hours", Format.clock(3930))
check(Format.clock(0.2) == "0:01", "clock rounds up a part second", Format.clock(0.2))
check(Format.human(1500) == "25 min", "human minutes", Format.human(1500))
check(Format.human(3600) == "1h", "human whole hour", Format.human(3600))
check(Format.human(5400) == "1h 30m", "human hour and minutes", Format.human(5400))

// MARK: - RingPath

print("RingPath")
let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
let square = RingPath(rect: rect, topRadius: 0, bottomRadius: 0)
equal(Double(square.length), 1400, "square perimeter", tolerance: 0.5)

let rounded = RingPath(rect: rect, topRadius: 50, bottomRadius: 50)
// Four quarter-circles replace four corners: 2πr instead of 8r.
equal(Double(rounded.length), 1400 - 8 * 50 + 2 * .pi * 50, "rounded perimeter", tolerance: 0.5)

// A MacBook screen: rounded along the top, square along the bottom.
let mac = RingPath(rect: rect, topRadius: 50, bottomRadius: 0)
equal(Double(mac.length), 1400 - 4 * 50 + .pi * 50, "top-only rounded perimeter", tolerance: 0.5)
check(mac.sample(at: 0.5).point.y == rect.minY, "bottom edge still reaches the corner",
      "\(mac.sample(at: 0.5).point)")

let start = square.sample(at: 0)
equal(Double(start.point.x), 200, "starts at top centre (x)")
equal(Double(start.point.y), 300, "starts at top centre (y)")
check(start.tangent.x > 0.99, "starts running clockwise", "\(start.tangent)")
check(square.sample(at: 1).point.x == start.point.x, "ends where it started")

// Inward points into the screen, away from the edge it is on.
check(square.sample(at: 0).inward.y < -0.99, "top edge points down")
check(square.sample(at: 0.25).inward.x < -0.99, "right edge points left")

// Arc length parametrisation: equal steps in t cover equal distance. Measured
// along one straight edge, because a step that straddles a corner is measured
// here as a chord and is legitimately shorter than the arc it spans.
func stepRange(from a: CGFloat, to b: CGFloat, steps: Int) -> (min: Double, max: Double) {
    var previous = square.sample(at: a).point
    var lo = Double.greatestFiniteMagnitude
    var hi = 0.0
    for i in 1...steps {
        let p = square.sample(at: a + (b - a) * CGFloat(i) / CGFloat(steps)).point
        let d = Double(hypot(p.x - previous.x, p.y - previous.y))
        lo = min(lo, d)
        hi = max(hi, d)
        previous = p
    }
    return (lo, hi)
}

let alongTop = stepRange(from: 0.01, to: 0.13, steps: 60)      // inside the top edge
check(alongTop.max - alongTop.min < 0.001, "constant speed along an edge",
      "\(alongTop.min)…\(alongTop.max)")
equal(alongTop.max, Double(square.length) * 0.12 / 60, "step matches arc length", tolerance: 0.001)

// Around the whole ring, no step may exceed the arc length it covers.
let wholeRing = stepRange(from: 0, to: 1, steps: 200)
check(wholeRing.max <= Double(square.length) / 200 + 0.001, "no step overshoots its arc",
      "\(wholeRing.max)")

// Sub-paths stay inside the rectangle they were built from.
let sub = square.path(from: 0.3, to: 0.6)
check(!sub.isEmpty, "sub-path is drawable")
check(rect.insetBy(dx: -1, dy: -1).contains(sub.boundingBox), "sub-path stays on the ring")
check(square.path(from: 0.5, to: 0.5).isEmpty, "empty range draws nothing")
check(square.path(from: 0.9, to: 0.1).isEmpty, "reversed range draws nothing")

// MARK: -

print(failures == 0
      ? "\n✓ \(checks) checks passed"
      : "\n✗ \(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)
