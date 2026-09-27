I read the brief, all four round-2 answers, and the full source of every branch head. Branch heads match the manifest and no worktree is dirty. My sandbox denied Chromium, node, and http.server, so this verdict rests on code inspection, not on a live render. That limitation applies equally to all four entries, since none of them rendered in a browser either.

## Verdict

**Recommended: a2 (Tidewell Glide 3).** It satisfies every hard requirement in the brief and exceeds the others by a clear margin on the four dimensions the brief stresses most: 3D, cursor, imagery, and selling.

**Ranking:** a2 > a1 > a4 ≈ a3.

## Per-branch assessment

**a2 (swarm/swarm/a2, e4d6a8d)**
- 3D is the most ambitious: three.js with RoomEnvironment lighting, rounded-box body, procedural roller and screen textures, and scroll-driven chapters that spin the roller, explode the tanks, lay the body flat, and shift the LED from red to blue. Pointer tilts it. Renders only while visible, lazy-imported after a WebGL check, with an SVG fallback.
- Cursor is genuinely unusual and on-theme: spring-lagged droplet that stretches with velocity, a wet trail that "dries," a splash on click, and a spinning roller ring with context labels over interactive elements. Off unless hover plus fine pointer.
- Richest imagery: SVG before/after floors, animated dock illustration, animated step art, bento visualizations, all local.
- Strongest selling: three bundles, guarantees, countdown, email capture, press strip, six reviews, four-way comparison, mobile buy bar.
- Committed properly and the answer contains the required summary.
- **Defect found:** the hero chapter cards have no `bottom` value, so they hang downward from the anchor line at the bottom of the sticky hero. On mobile and short laptop viewports the last line of each card is clipped by the hero's overflow. One-line CSS fix.

**a1 (swarm/swarm/a1, 774819d)**
- Solid, complete, well-structured, with careful reduced-motion handling and contrast fixes. Committed with a good summary.
- 3D is simpler (primitives, auto-spin, drag, scroll rotation) and renders every frame even offscreen. Cursor is a droplet plus ring, which is only modestly beyond "a dot." Imagery is thin: icons, a rain canvas, and the 3D scene.
- **Defect found:** the fixed header is transparent at the top and its brand, nav links, and menu toggle are navy on the navy hero. The header is effectively unreadable until the user scrolls past 12px. This hits the first viewport on every device.

**a4 (swarm/swarm/a4, 452f815)**
- Dependency-free native WebGL with a detailed mesh, specular shading, and a good SVG fallback. Very light page weight. Has a real self-check script.
- 3D reacts only to pointer hover position and two buttons; no drag, no scroll. Animations are limited to reveals and hover. Cursor is a small mop icon.
- **Defect found:** body has no horizontal overflow clip and the hero stage does not clip its decorative orbit ring, so at viewport widths of roughly 701 to 750px the 405px ring extends past the viewport and causes horizontal scroll.
- Did not commit; the orchestrator auto-committed. Answer is in Russian but covers the required summary points.

**a3 (swarm/swarm/a3, 4d39f4d)**
- Meets every hard requirement: native WebGL with pointer, drag, keyboard, and scroll pitch; CSS-drawn scenes; before/after slider; comparison; reviews; offer; FAQ.
- Thinnest on animation (reveals and hover only) and on selling depth (no steps, no specs, the primary CTA is a mailto link).
- Did not commit; the orchestrator auto-committed. The answer omits the required section list and limitations summary.

## Unresolved

- No entry has been rendered in a browser. 3D framing, frame rate, absence of console errors, and 375–1920px layout remain unverified for all four.
- a2's chapter clipping and a1's invisible header are inferred from CSS, not observed. Both are cheap fixes but should be confirmed with a render before shipping.
- a2 depends on jsdelivr and Google Fonts at runtime; a1 depends on jsdelivr. a3 depends on Google Fonts. a4 has no external dependencies.

WINNER: swarm/swarm/a2
