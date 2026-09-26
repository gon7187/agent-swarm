# Landing page brief

Build a production-quality, **selling** marketing landing page in **English** for a fictional product:
**a handheld wet-and-dry washing vacuum** (cordless, cleans hard floors with water + suction, self-cleaning).
Invent the brand name, product name, specs, price, reviews, FAQ, guarantees.

Hard requirements:
- Static site: entry point `index.html` at the repository root (extra css/js/assets files allowed). Must work when served by `python3 -m http.server`. No build step. Libraries only via CDN (e.g. cdn.jsdelivr.net, unpkg, cdnjs) — three.js, GSAP etc. are allowed.
- Imagery: rich visuals. No AI image generator is available — make pictures yourself (SVG, canvas, CSS, procedural 3D renders) or hotlink free stock photos (e.g. images.unsplash.com). Everything must actually load.
- Real **3D**: at least one interactive 3D scene of the product (WebGL / three.js or equivalent), reacting to scroll and/or pointer.
- Rich animations: scroll-driven reveals, micro-interactions, transitions. Smooth (target 60fps), respect `prefers-reduced-motion`.
- An **unusual custom cursor** that fits the product concept (not just a dot) — disabled gracefully on touch devices.
- It must **sell**: clear value proposition, benefits, social proof, comparison, pricing/offer, FAQ, strong CTAs.
- Responsive (mobile 375px to desktop 1920px), no horizontal scroll, no console errors, accessible basics (contrast, alt text, semantic HTML, keyboard focus).
- Fast: reasonable page weight, lazy-load heavy stuff.

Commit your work with git when done (Claude workers). Finish your answer with a short summary: concept, sections, tech used, known limitations.
