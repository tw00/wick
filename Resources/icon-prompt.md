# Icon prompt

The current `AppIcon.icns` is a placeholder generated with ImageMagick. Paste the
prompt below into ChatGPT (image generation), then drop the result in as
`Resources/icon_1024.png` and run:

```bash
./Resources/make-icon.sh
```

---

Design a macOS app icon for **Wick**, a minimal menu-bar timer. The app draws a
thin glowing line around the outer edge of the screen that burns away as your
time runs out — like a fuse tracing the border of a display.

**Concept:** a single continuous line tracing the inside of a rounded square,
most of the way around, with a small bright ember at its leading tip. The gap in
the line is the time already spent. Read it as a screen edge burning down, not as
a clock face — no hands, no numbers, no dial ticks, no hourglass.

**Style:** modern macOS Big Sur / Sonoma icon language. A rounded-square
(squircle) tile with a soft matte gradient background in near-black charcoal
(#1B1B1E → #2A2A2E), gentle top-down lighting, and a very subtle inner edge
highlight. Everything sits inside the tile with comfortable padding — the burning
line should be inset from the tile edge, not touching it.

**The line:** warm amber to orange (#FFB74A → #FF7A18), evenly weighted, with a
crisp bright white-hot point at the tip and a tight, restrained glow around it —
a small controlled bloom, not a big soft haze. A faint darker scorch trail may
fade out behind the tip. Corners of the line should be smoothly rounded, matching
the tile's curvature.

**Mood:** calm, precise, engineered. Closer to a well-made instrument than to a
cartoon bomb or a birthday candle.

**Avoid:** text or letters, drop shadows outside the tile, skeuomorphic rope or
wax textures, sparks scattered across the tile, clock or stopwatch imagery,
gradients that muddy into brown, busy detail that disappears at 32×32.

**Output:** 1024×1024 PNG, square, front-facing, centred, flat presentation (no
perspective, no mockup, no device frame, no background scene beyond the tile
itself).
