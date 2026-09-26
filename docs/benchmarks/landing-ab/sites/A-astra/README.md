# FLOE One

A self-contained English product landing page for a fictional cordless wet-and-dry floor washer. Cold white, soft graphite, and lime; large typography, dimensional product imagery, and approachable everyday-life copy.

## Run

From the repository root:

```sh
python3 -m http.server 8000
```

Open `http://localhost:8000`. No build, packages, remote fonts, or network assets. Opening `index.html` directly also works.

## Experience

- Native WebGL product scene with locally generated rounded geometry, lighting, pointer parallax, drag rotation, scroll response, arrow-key rotation, and a rotate button. No 3D library download.
- Local SVG product and interior illustrations; SVG product fallback when WebGL is unavailable.
- Keyboard-operable before/after slider, scroll reveals, hover transitions, and a small squeegee cursor for fine pointers. Reduced-motion preferences turn off decorative movement and smooth scrolling.
- Benefits, technical details, comparison table, fictional reviews, $349 offer, 60-day trial, warranty, and native FAQ accordions.
- Accessible native offer dialog with Escape dismissal and return focus. This is explicitly a concept preview, not a real checkout. No personal or payment data collected.

## Checks

```sh
node --check app.js
node --check scene.js
node tests/check.mjs
node tests/behavior.mjs
node tests/browser.mjs
```

The first four checks pass. Behavioral checks validate all 102,672 mesh vertices, normal vectors, transform matrices, pointer/keyboard rotation, reduced-motion rendering, WebGL fallback, comparison semantics, and dialog/focus behavior.

`tests/browser.mjs` is a dependency-free Chromium/CDP smoke test for widths 375, 768, 1440, and 1920, overflow, live WebGL, loaded first-paint imagery, console errors, dialog, FAQ, comparison, and reduced-motion CSS. Set `CHROME` if the executable is not `chromium`; optionally set `TEST_URL` to a running HTTP server.

**Environment limitation:** browser verification could not run in the authoring sandbox. Chromium fails with `setsockopt: Operation not permitted`, and Python's HTTP server is blocked from opening sockets. These are not passing browser checks. Re-run the browser check in an environment permitting Chromium before release. Actual GPU shader compilation, rendered responsive layout, and real-device performance remain unverified here.

## Production boundaries

All brand details, specs, prices, reviews, and guarantees are fictional as requested. They are disclosed as illustrative in the footer and offer dialog. Connect an actual store and replace these claims with verified product information before accepting orders. WebGL context loss falls back to the local illustration; reload to restore the 3D scene.
