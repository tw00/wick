import AppKit
import QuartzCore

struct RingState {
    var consumed: CGFloat
    var phase: TimerEngine.Phase
    /// Total length of the timer — the minute ticks need to know how many.
    var duration: TimeInterval = 25 * 60
}

/// Draws the burning border. One of these per screen, inside a click-through
/// overlay window.
///
/// Two things shape the drawing. First, the overlay is transparent and sits over
/// whatever you happen to be looking at, so nothing can rely on the backdrop:
/// every lit line gets a thin dark keyline under it so it reads on a white
/// document and a dark editor alike, and glows stay tight and saturated instead
/// of wide and faint (a wide faint glow is a brown smudge on white).
/// Second, it samples the timer every frame rather than being pushed to, and
/// marks only the region that actually changed as dirty — a 25 minute timer
/// shouldn't cost a full-screen repaint sixty times a second.
final class BorderView: NSView {
    var stateProvider: (() -> RingState)?
    /// Shrinks the line to suit a small sample view; 1 for a real screen.
    var previewScale: CGFloat = 1
    /// Corner radius for the screen this view covers, in points.
    /// Corner radii of the screen this border is on, in points.
    var corners: Screens.Corners = .square

    private var link: CADisplayLink?
    private var clock: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var drawnConsumed: CGFloat = 0
    private var sparks: [Spark] = []
    private var emitAccumulator: CGFloat = 0
    private var needsFullRedraw = true
    private var lastPhase: TimerEngine.Phase = .idle
    private var lastUrgencyStep = -1
    private var lastFullRedraw: CFTimeInterval = 0
    private var lastTick = -1

    /// The style to draw. Reduce Motion is a request to stop things moving in
    /// the corner of someone's eye, which is exactly what most of these do, so
    /// it falls back to the still one.
    private static var effectiveStyle: RingStyle {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .plain : Prefs.shared.style
    }

    /// How often a style that animates its whole ring should repaint, if it does.
    private static func wholeRingInterval(_ style: RingStyle) -> CFTimeInterval? {
        switch style {
        case .tide:   return 1.0 / 20
        case .aurora: return 1.0 / 15
        case .level:  return 1.0 / 24
        default:      return nil
        }
    }

    private struct Spark {
        var pos: CGPoint
        var prev: CGPoint
        var vel: CGPoint
        var age: CGFloat
        var life: CGFloat
        var size: CGFloat
        var warmth: CGFloat   // 0 = deep orange, 1 = white hot
    }

    // MARK: - Palette

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(colorSpace: sRGB, components: [r, g, b, a])!
    }
    private static func clear(_ base: CGColor) -> CGColor {
        let k = base.components ?? [0, 0, 0, 1]
        return c(k[0], k[1], k[2], 0)
    }

    /// Under every lit line: reads as a shadow on light backgrounds, disappears
    /// on dark ones, and stops the border looking like a floating pastel stripe.
    private static let keyline   = c(0, 0, 0, 0.30)
    /// Mid grey, so the unrun part of the ring is visible either way.
    private static let track     = c(0.5, 0.5, 0.5, 0.22)
    private static let scorch    = c(0.10, 0.09, 0.08, 0.30)

    private static let grey      = c(0.58, 0.58, 0.60, 1)
    private static let blue      = c(0.28, 0.55, 1.00, 1)
    private static let blueLight = c(0.72, 0.86, 1.00, 1)
    /// Pale twisted hemp, like a real bomb fuse: cream cord, warm shadow in the
    /// twist, straw-coloured highlight on the ridges.
    private static let cord      = c(0.90, 0.84, 0.73, 1)
    private static let cordShade = c(0.53, 0.44, 0.33, 1)
    private static let cordLight = c(1.00, 0.98, 0.92, 1)
    private static let ember     = c(1.00, 0.42, 0.06, 1)
    private static let emberHot  = c(1.00, 0.80, 0.36, 1)
    private static let sparkGold = c(1.00, 0.88, 0.55, 1)
    private static let slate     = c(0.44, 0.50, 0.58, 1)
    private static let slateLight = c(0.88, 0.93, 1.00, 1)
    private static let liquid    = c(0.24, 0.62, 0.86, 1)
    private static let snakeSkin = c(0.36, 0.74, 0.38, 1)
    private static let apple     = c(0.87, 0.19, 0.19, 1)
    private static let leaf      = c(0.42, 0.72, 0.33, 1)
    private static let white     = c(1, 1, 1, 1)
    private static let amber     = c(1.00, 0.62, 0.12, 1)
    private static let alarm     = c(1.00, 0.26, 0.22, 1)

    // MARK: - Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? stopLink() : startLink()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateAll()
    }

    private func startLink() {
        guard link == nil else { return }
        let l = displayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        lastTimestamp = 0
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    /// Force a clean repaint — style, thickness or screen changed.
    func invalidateAll() {
        needsFullRedraw = true
        sparks.removeAll()
        needsDisplay = true
    }

    // MARK: - Frame step

    @objc private func step(_ sender: CADisplayLink) {
        let now = sender.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(0.1, now - lastTimestamp)
        lastTimestamp = now

        guard let state = stateProvider?() else { return }
        let animating = state.phase == .running || state.phase == .finished
        if animating { clock += dt }

        if state.phase != lastPhase {
            lastPhase = state.phase
            needsFullRedraw = true
        }
        // The burn can also run backwards — a timer being extended, or the
        // looping preview — and then the old head has to be cleaned up.
        if state.consumed < drawnConsumed - 0.0001 { needsFullRedraw = true }
        let step = urgencyStep(state.consumed)
        if step != lastUrgencyStep { lastUrgencyStep = step; needsFullRedraw = true }

        let style = Self.effectiveStyle
        let w = lineWidth
        let ring = currentRing()

        if style == .fuse && state.phase == .running {
            emitSparks(dt: dt, ring: ring, at: state.consumed, width: w)
        }
        advanceSparks(dt: dt, burning: style == .fuse && state.phase == .running)

        if needsFullRedraw { needsDisplay = true; drawnConsumed = state.consumed; return }
        guard animating else { return }

        if state.phase == .finished { needsDisplay = true; return }   // whole ring breathes

        // Styles whose whole ring moves can't use a dirty region, so they
        // repaint entirely — at a lower rate, since none of them are fast.
        if let interval = Self.wholeRingInterval(style) {
            guard clock - lastFullRedraw >= interval else { return }
            lastFullRedraw = clock
            drawnConsumed = state.consumed
            needsDisplay = true
            return
        }
        // A minute tick going out changes a spot far from the head.
        if style == .ticks {
            let tick = tickIndex(state)
            if tick != lastTick { lastTick = tick; needsDisplay = true; drawnConsumed = state.consumed; return }
        }

        // A still ring only redraws when the head has actually moved a pixel;
        // the ones with a live head redraw every frame.
        let advanced = (state.consumed - drawnConsumed) * ring.length
        if (style == .plain || style == .fade || style == .ticks) && advanced < 0.6 { return }

        let pad = headRadius(style, w) + 4
        // Where the drawing actually changes differs by style: Split has two
        // heads travelling in opposite directions, Snake trails a wriggle ahead
        // of itself, Fade dissolves over a long stretch.
        var dirty: NSRect
        switch style {
        case .split:
            dirty = box(ring, from: drawnConsumed / 2 - 0.03, to: state.consumed / 2 + 0.02, pad: pad)
                .union(box(ring, from: 1 - state.consumed / 2 - 0.02,
                           to: 1 - drawnConsumed / 2 + 0.03, pad: pad))
        case .snake:
            // The wriggling neck trails the head, and apples pop just behind it.
            dirty = box(ring, from: drawnConsumed - 0.075, to: state.consumed + 0.02, pad: pad)
        case .fade:
            dirty = box(ring, from: drawnConsumed - 0.03, to: state.consumed + 0.12, pad: pad)
        default:
            dirty = box(ring, from: drawnConsumed - 0.06, to: state.consumed + 0.02, pad: pad)
        }
        for s in sparks {
            let r = s.size * 3 + 2
            dirty = dirty.union(NSRect(x: min(s.pos.x, s.prev.x) - r, y: min(s.pos.y, s.prev.y) - r,
                                       width: abs(s.pos.x - s.prev.x) + r * 2,
                                       height: abs(s.pos.y - s.prev.y) + r * 2))
        }
        drawnConsumed = state.consumed
        if !dirty.isNull { setNeedsDisplay(dirty.insetBy(dx: -2, dy: -2)) }
    }

    // MARK: - Sparks

    private func emitSparks(dt: CGFloat, ring: RingPath, at t: CGFloat, width w: CGFloat) {
        emitAccumulator += dt * 26
        let n = Int(emitAccumulator)
        guard n > 0 else { return }
        emitAccumulator -= CGFloat(n)

        let s = ring.sample(at: t)
        for _ in 0..<n {
            let back = CGFloat.random(in: -0.15...0.75)      // mostly trailing the head
            let speed = CGFloat.random(in: 10...46) * max(0.7, w / 6)
            let dir = CGPoint(x: s.inward.x - s.tangent.x * back + CGFloat.random(in: -0.2...0.2),
                              y: s.inward.y - s.tangent.y * back + CGFloat.random(in: -0.2...0.2))
            let m = max(0.001, hypot(dir.x, dir.y))
            sparks.append(Spark(pos: s.point, prev: s.point,
                                vel: CGPoint(x: dir.x / m * speed, y: dir.y / m * speed),
                                age: 0, life: CGFloat.random(in: 0.25...0.7),
                                size: CGFloat.random(in: 0.45...1.15) * max(0.7, w / 6),
                                warmth: CGFloat.random(in: 0...1)))
        }
        if sparks.count > 200 { sparks.removeFirst(sparks.count - 200) }
    }

    private func advanceSparks(dt: CGFloat, burning: Bool) {
        guard !sparks.isEmpty else { return }
        for i in sparks.indices {
            sparks[i].prev = sparks[i].pos
            sparks[i].vel.y -= 46 * dt                    // gravity
            sparks[i].vel.x *= (1 - 2.2 * dt)             // drag
            sparks[i].vel.y *= (1 - 2.2 * dt)
            sparks[i].pos.x += sparks[i].vel.x * dt
            sparks[i].pos.y += sparks[i].vel.y * dt
            sparks[i].age += dt
        }
        sparks.removeAll { $0.age >= $0.life }
        if !burning { sparks.removeAll() }
    }

    // MARK: - Geometry

    /// A hairline is allowed to be genuinely thin — half a point still lands on
    /// a whole pixel on a Retina display. The settings sample keeps a 1 pt floor,
    /// or the thinnest weights would preview as nothing at all.
    private var lineWidth: CGFloat {
        let floor: CGFloat = previewScale < 1 ? 1 : 0.5
        return max(floor, CGFloat(Prefs.shared.thickness) * previewScale)
    }

    private func currentRing() -> RingPath {
        let t = lineWidth
        // The ring is stroked down the middle of the line, so its centreline
        // radius is the screen's radius less half the line width.
        let top = max(0, CGFloat(corners.top) * previewScale - t / 2)
        let bottom = max(0, CGFloat(corners.bottom) * previewScale - t / 2)
        return RingPath(rect: bounds.insetBy(dx: t / 2, dy: t / 2),
                        topRadius: top, bottomRadius: bottom)
    }

    private func headRadius(_ style: RingStyle, _ w: CGFloat) -> CGFloat {
        switch style {
        case .plain, .fade, .ticks: return w
        case .pulse, .split:        return w * 3.2
        case .snake:                return w * 4.0
        case .fuse:                 return w * 8.0   // covers the sparkler rays
        case .tide, .level, .aurora: return w        // these repaint whole-ring
        }
    }

    private func box(_ ring: RingPath, from t0: CGFloat, to t1: CGFloat, pad: CGFloat) -> NSRect {
        let a = clamp01(t0), b = clamp01(t1)
        guard b >= a else { return .null }
        let steps = max(2, min(28, Int((b - a) * 60) + 2))
        var r = NSRect.null
        for i in 0...steps {
            let p = ring.sample(at: a + (b - a) * CGFloat(i) / CGFloat(steps)).point
            r = r.union(NSRect(x: p.x - pad, y: p.y - pad, width: pad * 2, height: pad * 2))
        }
        return r
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // A layer-backed transparent view keeps whatever was painted last time,
        // so the repaint region has to be wiped or the ring smears a trail
        // behind the head.
        ctx.clear(dirtyRect)

        guard let state = stateProvider?(), state.phase != .idle else { return }
        needsFullRedraw = false

        let w = lineWidth
        let ring = currentRing()
        let p = state.consumed

        if state.phase == .paused { ctx.setAlpha(0.5) }

        switch state.phase {
        case .finished:
            drawFinished(ctx, ring, w)
        default:
            switch Self.effectiveStyle {
            case .plain:  drawPlain(ctx, ring, w, p)
            case .fade:   drawFade(ctx, ring, w, p)
            case .pulse:  drawPulse(ctx, ring, w, p)
            case .split:  drawSplit(ctx, ring, w, p)
            case .ticks:  drawTicks(ctx, ring, w, state)
            case .tide:   drawTide(ctx, ring, w, p)
            case .level:  drawLevel(ctx, ring, w, p)
            case .fuse:   drawFuse(ctx, ring, w, p, clip: dirtyRect)
            case .snake:  drawSnake(ctx, ring, w, p)
            case .aurora: drawAurora(ctx, ring, w, p)
            }
        }
    }

    /// The quiet one: a grey line that shortens. No head, no motion.
    private func drawPlain(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ p: CGFloat) {
        stroke(ctx, ring.path(from: 0, to: 1), Self.track, w * 0.5, cap: .butt)
        lit(ctx, ring.path(from: p, to: 1), urgency(Self.grey, p), w)
    }

    /// Blue line with a breathing head. Nothing travels but the head itself.
    private func drawPulse(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ p: CGFloat) {
        let tint = urgency(Self.blue, p)
        stroke(ctx, ring.path(from: 0, to: 1), Self.track, w * 0.4, cap: .butt)
        lit(ctx, ring.path(from: p, to: 1), tint, w)

        // Afterglow fading out over the stretch the head just left.
        gradientRun(ctx, ring, from: max(0, p - 0.035), to: p, width: w) { u in
            Self.mix(tint, Self.blueLight, Double(u), alpha: 0.5 * Double(u) * Double(u))
        }
        let head = ring.sample(at: p).point
        let breathe = 1 + 0.14 * sin(CGFloat(clock) * 2.6)
        halo(ctx, at: head, radius: w * 2.6 * breathe, inner: Self.blueLight, outer: tint,
             innerAlpha: 0.75, midAlpha: 0.30)
        dot(ctx, at: head, radius: w * 0.5 * breathe, color: Self.white)
    }

    /// Plain, but the leading edge dissolves instead of ending in a cap.
    private func drawFade(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ p: CGFloat) {
        let tint = urgency(Self.grey, p)
        let soft = min(0.10, (1 - p) * 0.5)
        stroke(ctx, ring.path(from: 0, to: 1), Self.track, w * 0.45, cap: .butt)
        lit(ctx, ring.path(from: p + soft, to: 1), tint, w)
        // The dissolving stretch gets no keyline — a keyline would outline the
        // very edge the fade is meant to hide.
        gradientRun(ctx, ring, from: p, to: p + soft, width: w) { u in
            Self.fade(tint, Double(u))
        }
    }

    /// Burns both ways from the top and meets at the bottom. Symmetric, so the
    /// amount left reads as a shape rather than a length.
    private func drawSplit(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ p: CGFloat) {
        let tint = urgency(Self.grey, p)
        let half = p / 2
        stroke(ctx, ring.path(from: 0, to: 1), Self.track, w * 0.45, cap: .butt)
        lit(ctx, ring.path(from: half, to: 1 - half), tint, w)
        for head in [ring.sample(at: half).point, ring.sample(at: 1 - half).point] {
            halo(ctx, at: head, radius: w * 1.9, inner: Self.white, outer: tint,
                 innerAlpha: 0.5, midAlpha: 0.2)
            dot(ctx, at: head, radius: w * 0.34, color: Self.fade(Self.white, 0.9))
        }
    }

    /// One tick per minute. The current minute dims away, then its tick goes out
    /// and the next one starts — so you can count what's left without a clock.
    private func drawTicks(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ state: RingState) {
        let count = tickCount(state)
        let tint = urgency(Self.grey, state.consumed)
        let slot = 1 / CGFloat(count)
        let gap = min(slot * 0.34, (w * 3) / ring.length)
        let elapsed = state.consumed * CGFloat(count)
        let current = Int(elapsed)

        for i in 0..<count {
            let a = CGFloat(i) * slot + gap / 2
            let b = CGFloat(i + 1) * slot - gap / 2
            let path = ring.path(from: a, to: b)
            if i < current {
                stroke(ctx, path, Self.track, w * 0.45, cap: .butt)
            } else if i == current {
                // Dim through the minute you're in.
                let left = 1 - (elapsed - CGFloat(current))
                stroke(ctx, path, Self.keyline, w + min(1.5, w * 0.4))
                stroke(ctx, path, Self.fade(tint, Double(0.2 + 0.8 * left)), w)
            } else {
                lit(ctx, path, tint, w)
            }
        }
    }

    private func tickCount(_ state: RingState) -> Int {
        max(4, min(120, Int((state.duration / 60).rounded())))
    }

    private func tickIndex(_ state: RingState) -> Int {
        Int(state.consumed * CGFloat(tickCount(state)))
    }

    /// A slow bright wave running along what's left. Brightness varies, not
    /// alpha — translucent segments would band where they overlap.
    private func drawTide(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ p: CGFloat) {
        stroke(ctx, ring.path(from: 0, to: 1), Self.track, w * 0.45, cap: .butt)
        let base = urgency(Self.slate, p)
        let chunks = 48
        let span = (1 - p) / CGFloat(chunks)
        guard span > 0 else { return }
        lit(ctx, ring.path(from: p, to: 1), base, w)
        for i in 0..<chunks {
            let a = p + span * CGFloat(i)
            let u = CGFloat(i) / CGFloat(chunks)
            let wave = sin(u * 4 * .pi - CGFloat(clock) * 0.9)
            let crest = max(0, wave)
            guard crest > 0.02 else { continue }
            stroke(ctx, ring.path(from: a, to: min(1, a + span * 1.6)),
                   Self.mix(base, Self.slateLight, Double(crest), alpha: 1), w)
        }
    }

    /// Drains like liquid: the ring below the surface is full, above it empty,
    /// and the surface sloshes a little. Clipping does the corners for free.
    private func drawLevel(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ p: CGFloat) {
        let tint = urgency(Self.liquid, p)
        let full = ring.path(from: 0, to: 1)
        stroke(ctx, full, Self.track, w * 0.45, cap: .butt)

        let slosh = sin(CGFloat(clock) * 1.7) * max(1, w * 0.35)
        let level = bounds.height * (1 - p) + slosh
        guard level > 0 else { return }

        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: bounds.width, height: level))
        lit(ctx, full, tint, w)
        ctx.restoreGState()

        // A bright meniscus where the liquid meets the empty ring.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: max(0, level - w * 1.2), width: bounds.width, height: w * 1.2))
        stroke(ctx, full, Self.fade(Self.white, 0.55), w)
        ctx.restoreGState()
    }

    /// Snake, played properly: the body trails behind the head and grows as the
    /// timer runs, apples wait ahead on the track, and the screen is full when
    /// your time is up.
    private func drawSnake(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ p: CGFloat) {
        stroke(ctx, ring.path(from: 0, to: 1), Self.track, w * 0.4, cap: .butt)

        // Apples still on the track. The one just swallowed pops.
        for i in 1...8 {
            let t = CGFloat(i) / 8
            let point = ring.sample(at: t).point
            if p >= t {
                guard p - t < 0.012 else { continue }
                let u = (p - t) / 0.012
                dot(ctx, at: point, radius: w * (0.8 + 2.4 * u),
                    color: Self.fade(Self.apple, Double(1 - u)))
                continue
            }
            dot(ctx, at: point, radius: w * 0.62, color: Self.apple)
            dot(ctx, at: CGPoint(x: point.x, y: point.y + w * 0.5), radius: w * 0.2, color: Self.leaf)
        }

        // Body behind the head: straight for most of it, wriggling near the neck.
        // It starts out short and wraps back past the top, like the three
        // segments you begin the game with.
        let minBody: CGFloat = 0.025
        let tail = p - max(minBody, p)
        let wiggle = min(0.045, max(minBody, p))
        if tail < 0 { lit(ctx, ring.path(from: 1 + tail, to: 1), Self.snakeSkin, w) }
        let straightFrom = max(0, tail)
        let straightTo = max(straightFrom, p - wiggle)
        if straightTo > straightFrom {
            lit(ctx, ring.path(from: straightFrom, to: straightTo), Self.snakeSkin, w)
        }
        let neck = max(0, p - wiggle)
        if p > neck {
            let body = wavyPath(ring, from: neck, to: p, samples: 40,
                                amplitude: { u in w * 0.5 * u },
                                waves: 1.8, phase: CGFloat(clock) * 4.5)
            stroke(ctx, body, Self.keyline, w + min(1.5, w * 0.4))
            stroke(ctx, body, Self.snakeSkin, w)
        }

        // Head, looking the way it's going.
        let s = ring.sample(at: p)
        let head = CGPoint(x: s.point.x + s.inward.x * w * 0.25, y: s.point.y + s.inward.y * w * 0.25)
        dot(ctx, at: head, radius: w * 0.85, color: Self.snakeSkin)
        for side in [CGFloat(1), -1] {
            let eye = CGPoint(x: head.x + s.tangent.x * w * 0.3 + s.inward.x * side * w * 0.35,
                              y: head.y + s.tangent.y * w * 0.3 + s.inward.y * side * w * 0.35)
            dot(ctx, at: eye, radius: w * 0.22, color: Self.white)
            dot(ctx, at: eye, radius: w * 0.11, color: Self.c(0, 0, 0, 1))
        }
        // Tongue, flicked now and then.
        if sin(CGFloat(clock) * 2.2) > 0.85 {
            let tip = CGPoint(x: head.x + s.tangent.x * w * 1.7, y: head.y + s.tangent.y * w * 1.7)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: head.x + s.tangent.x * w * 0.8, y: head.y + s.tangent.y * w * 0.8))
            path.addLine(to: tip)
            stroke(ctx, path, Self.apple, max(0.7, w * 0.14))
        }
    }

    /// Drifting colour that loses its saturation as the timer runs down: full
    /// aurora at the start, plain grey by the end.
    private func drawAurora(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ p: CGFloat) {
        stroke(ctx, ring.path(from: 0, to: 1), Self.track, w * 0.45, cap: .butt)
        let saturation = 0.62 * Double(1 - p) + 0.04
        let chunks = 64
        let span = (1 - p) / CGFloat(chunks)
        guard span > 0 else { return }
        stroke(ctx, ring.path(from: p, to: 1), Self.keyline, w + min(1.5, w * 0.4))
        for i in 0..<chunks {
            let a = p + span * CGFloat(i)
            let u = CGFloat(i) / CGFloat(chunks)
            let hue = Double((u * 0.55 + CGFloat(clock) * 0.03).truncatingRemainder(dividingBy: 1)
                             * 0.55 + 0.42)   // teal → blue → violet
            let colour = NSColor(hue: CGFloat(hue.truncatingRemainder(dividingBy: 1)),
                                 saturation: CGFloat(saturation),
                                 brightness: 0.92, alpha: 1).cgColor
            stroke(ctx, ring.path(from: a, to: min(1, a + span * 1.7)), colour, w)
        }
    }

    /// A path that waves in and out along the ring — the snake's wriggle.
    private func wavyPath(_ ring: RingPath, from t0: CGFloat, to t1: CGFloat, samples: Int,
                          amplitude: (CGFloat) -> CGFloat, waves: CGFloat, phase: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0...samples {
            let u = CGFloat(i) / CGFloat(samples)
            let s = ring.sample(at: t0 + (t1 - t0) * u)
            let off = amplitude(u) * sin(u * waves * 2 * .pi - phase)
            let pt = CGPoint(x: s.point.x + s.inward.x * off, y: s.point.y + s.inward.y * off)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        return path
    }

    /// The last stretch warms to amber, then red. It's the only thing about the
    /// quiet styles that changes on its own — and the one worth noticing.
    private func urgency(_ base: CGColor, _ p: CGFloat) -> CGColor {
        let left = 1 - p
        if left > 0.15 { return base }
        if left > 0.05 { return Self.mix(base, Self.amber, Double((0.15 - left) / 0.10), alpha: 1) }
        return Self.mix(Self.amber, Self.alarm, Double((0.05 - left) / 0.05), alpha: 1)
    }

    /// Quantised urgency step, so the whole ring is repainted when the tint moves
    /// rather than leaving a two-tone ring behind.
    private func urgencyStep(_ p: CGFloat) -> Int {
        let left = 1 - p
        guard left <= 0.15 else { return -1 }
        return Int(left * 200)
    }

    /// A cord that burns: scorched track behind, twisted hemp ahead, and a
    /// sparkler head throwing rays and grit.
    private func drawFuse(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat, _ p: CGFloat,
                          clip: NSRect) {
        // Scorch mark left behind — a hairline, not a black band.
        stroke(ctx, ring.path(from: 0, to: p), Self.scorch, w * 0.34, cap: .butt)

        // The cord: pale hemp, with diagonal ridges for the twist.
        lit(ctx, ring.path(from: p, to: 1), Self.cord, w)
        twist(ctx, ring, from: p, to: 1, width: w, clip: clip)

        // Embers cooling in the short stretch that just burned.
        gradientRun(ctx, ring, from: max(0, p - 0.014), to: p, width: w * 0.8) { u in
            let t = Double(u) * Double(u)
            return Self.mix(Self.ember, Self.emberHot, t, alpha: 0.85 * t)
        }
        // The bit about to catch.
        gradientRun(ctx, ring, from: p, to: min(1, p + 0.006), width: w) { u in
            Self.mix(Self.emberHot, Self.cord, Double(u), alpha: 1 - Double(u) * 0.5)
        }

        let flicker = 1 + 0.09 * sin(CGFloat(clock) * 15.7) + 0.06 * sin(CGFloat(clock) * 26.1)
        let head = ring.sample(at: p).point
        halo(ctx, at: head, radius: w * 2.6 * flicker, inner: Self.emberHot, outer: Self.ember,
             innerAlpha: 0.85, midAlpha: 0.30)
        starburst(ctx, at: head, width: w)
        dot(ctx, at: head, radius: w * 0.5 * flicker, color: Self.white)
        drawSparks(ctx)
    }

    /// Diagonal ridges across the cord: what makes it read as twisted rope
    /// rather than a stripe. Ridges outside the repaint region are skipped, so
    /// this stays cheap even on a 5K perimeter.
    private func twist(_ ctx: CGContext, _ ring: RingPath, from t0: CGFloat, to t1: CGFloat,
                       width w: CGFloat, clip: NSRect) {
        let spacing = w * 1.25
        guard (t1 - t0) * ring.length > spacing else { return }
        // Ridges are pinned to fixed positions on the ring, never to the head —
        // otherwise the whole rope appears to crawl forward as it burns.
        let first = Int((t0 * ring.length / spacing).rounded(.up))
        let last = Int(t1 * ring.length / spacing)
        guard last >= first else { return }
        let lean: CGFloat = 0.55          // radians the ridge leans off perpendicular
        let pad = w * 1.5
        let region = clip.insetBy(dx: -pad, dy: -pad)

        for i in first...last {
            let t = (CGFloat(i) * spacing) / ring.length
            guard t <= t1 else { break }
            let s = ring.sample(at: t)
            guard region.contains(s.point) else { continue }
            // Ridge direction: the inward normal, leaned over towards the run.
            let dx = s.inward.x * cos(lean) + s.tangent.x * sin(lean)
            let dy = s.inward.y * cos(lean) + s.tangent.y * sin(lean)
            let h = w * 0.62
            let a = CGPoint(x: s.point.x - dx * h, y: s.point.y - dy * h)
            let b = CGPoint(x: s.point.x + dx * h, y: s.point.y + dy * h)
            let line = CGMutablePath()
            line.move(to: a)
            line.addLine(to: b)
            let shade = i % 2 == 0 ? Self.fade(Self.cordShade, 0.5) : Self.fade(Self.cordLight, 0.5)
            stroke(ctx, line, shade, w * 0.34, cap: .butt)
        }
    }

    /// Sparkler rays. Each ray has its own length wobble so the head glitters
    /// instead of spinning.
    private func starburst(_ ctx: CGContext, at p: CGPoint, width w: CGFloat) {
        let rays = 22
        for i in 0..<rays {
            let seed = Self.hash(i)
            let angle = CGFloat(i) / CGFloat(rays) * 2 * .pi + seed * 0.5
            let wobble = sin(CGFloat(clock) * (7 + seed * 9) + seed * 6.28)
            let len = w * (1.2 + 1.9 * (0.55 + 0.45 * wobble)) * (0.6 + 0.7 * seed)
            guard len > w * 0.6 else { continue }
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            let line = CGMutablePath()
            line.move(to: CGPoint(x: p.x + dir.x * w * 0.35, y: p.y + dir.y * w * 0.35))
            line.addLine(to: CGPoint(x: p.x + dir.x * len, y: p.y + dir.y * len))
            let alpha = 0.30 + 0.45 * Double(0.5 + 0.5 * wobble)
            stroke(ctx, line, Self.fade(Self.sparkGold, alpha), max(0.6, w * 0.14))
            if seed > 0.72 {   // a few brighter needles reaching further
                let tip = CGPoint(x: p.x + dir.x * len * 1.35, y: p.y + dir.y * len * 1.35)
                let l2 = CGMutablePath()
                l2.move(to: CGPoint(x: p.x + dir.x * len * 0.6, y: p.y + dir.y * len * 0.6))
                l2.addLine(to: tip)
                stroke(ctx, l2, Self.fade(Self.white, alpha * 0.5), max(0.5, w * 0.09))
            }
        }
    }

    /// Deterministic 0…1 per index — stable ray identities, no per-frame noise.
    private static func hash(_ i: Int) -> CGFloat {
        let v = sin(CGFloat(i) * 12.9898) * 43758.5453
        return v - v.rounded(.down)
    }

    /// Time's up: the whole ring breathes red until dismissed.
    private func drawFinished(_ ctx: CGContext, _ ring: RingPath, _ w: CGFloat) {
        let pulse = 0.4 + 0.6 * pow(abs(sin(CGFloat(clock) * 1.9)), 1.6)
        let path = ring.path(from: 0, to: 1)
        stroke(ctx, path, Self.keyline, w + 1.5)
        stroke(ctx, path, Self.fade(Self.alarm, Double(pulse)), w)
        stroke(ctx, path, Self.fade(Self.white, Double(pulse) * 0.35), w * 0.3, cap: .butt)
    }

    private func drawSparks(_ ctx: CGContext) {
        guard !sparks.isEmpty else { return }
        for s in sparks {
            let life = 1 - s.age / s.life
            let a = Double(life * life)
            let color = Self.mix(Self.ember, Self.emberHot, Double(s.warmth), alpha: a)
            let r = s.size * (0.35 + 0.65 * life)
            dot(ctx, at: s.pos, radius: r * 2.1, color: Self.fade(color, a * 0.22))
            dot(ctx, at: s.pos, radius: r, color: color)
        }
    }

    // MARK: - Drawing primitives

    /// A lit line: dark keyline first so it holds an edge on any background. The
    /// keyline stays proportional, so a 3px hairline doesn't turn into a shadow
    /// with a thread of colour in it.
    private func lit(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, _ width: CGFloat) {
        stroke(ctx, path, Self.keyline, width + min(1.5, width * 0.4))
        stroke(ctx, path, color, width)
    }

    private func stroke(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, _ width: CGFloat,
                        cap: CGLineCap = .round) {
        guard !path.isEmpty, width > 0 else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(cap)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Paints a short run of the ring with a colour that varies along it — `u` is
    /// 0 at the start of the run, 1 at the end.
    ///
    /// Done by clipping to the stroked path and filling a gradient through it.
    /// Chaining translucent sub-strokes instead looks banded: wherever two
    /// segments overlap the alpha doubles, which shows up as a checkerboard.
    private func gradientRun(_ ctx: CGContext, _ ring: RingPath, from t0: CGFloat, to t1: CGFloat,
                             width: CGFloat, color: (CGFloat) -> CGColor) {
        guard t1 > t0, width > 0 else { return }
        let path = ring.path(from: t0, to: t1)
        guard !path.isEmpty else { return }

        let a = ring.sample(at: t0).point
        let b = ring.sample(at: t1).point
        // A run short enough to matter lies along one edge, so a straight
        // gradient tracks it; if it turned a corner and came back on itself,
        // fall back to a flat mid colour.
        guard hypot(b.x - a.x, b.y - a.y) > 1 else {
            stroke(ctx, path, color(0.5), width, cap: .butt)
            return
        }
        let steps = 8
        let colors = (0..<steps).map { color(CGFloat($0) / CGFloat(steps - 1)) }
        let locations = (0..<steps).map { CGFloat($0) / CGFloat(steps - 1) }
        guard let g = CGGradient(colorsSpace: Self.sRGB, colors: colors as CFArray,
                                 locations: locations) else { return }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.setLineCap(.butt)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(g, start: a, end: b,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// Tight two-stop glow around the head. Kept small on purpose: a wide, faint
    /// halo turns into a smudge over a white window.
    private func halo(_ ctx: CGContext, at p: CGPoint, radius: CGFloat,
                      inner: CGColor, outer: CGColor, innerAlpha: Double, midAlpha: Double) {
        let stops: [(CGColor, CGFloat)] = [
            (Self.fade(inner, innerAlpha), 0),
            (Self.fade(outer, midAlpha), 0.4),
            (Self.clear(outer), 1),
        ]
        guard radius > 0,
              let g = CGGradient(colorsSpace: Self.sRGB, colors: stops.map { $0.0 } as CFArray,
                                 locations: stops.map { $0.1 })
        else { return }
        ctx.saveGState()
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius,
                               options: [])
        ctx.restoreGState()
    }

    private func dot(_ ctx: CGContext, at p: CGPoint, radius: CGFloat, color: CGColor) {
        guard radius > 0 else { return }
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        ctx.restoreGState()
    }

    private static func fade(_ color: CGColor, _ alpha: Double) -> CGColor {
        let k = color.components ?? [0, 0, 0, 1]
        return c(k[0], k[1], k[2], max(0, min(1, alpha)))
    }

    private static func mix(_ a: CGColor, _ b: CGColor, _ t: Double, alpha: Double) -> CGColor {
        let ka = a.components ?? [0, 0, 0, 1]
        let kb = b.components ?? [0, 0, 0, 1]
        let m = max(0, min(1, t))
        return c(ka[0] + (kb[0] - ka[0]) * m,
                 ka[1] + (kb[1] - ka[1]) * m,
                 ka[2] + (kb[2] - ka[2]) * m,
                 max(0, min(1, alpha)))
    }
}
