// UI behaviour: reveals, counters, hero scroll chapters, custom cursor, micro-interactions.
// The three.js scene is loaded lazily so the page stays usable if WebGL or the CDN is unavailable.
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));

const root = document.documentElement;
root.classList.remove("no-js");
const reducedMQ = matchMedia("(prefers-reduced-motion: reduce)");
const finePointer = matchMedia("(hover: hover) and (pointer: fine)");

// Shared state consumed by the 3D scene
const state = { progress: 0, pointerX: 0, pointerY: 0, reduced: reducedMQ.matches };
reducedMQ.addEventListener?.("change", (e) => (state.reduced = e.matches));

/* ---------- Scroll-driven reveals ---------- */
const revealIO = new IntersectionObserver(
  (entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add("is-in");
      $$(".count", e.target).forEach(countUp);
      revealIO.unobserve(e.target);
    }
  },
  { rootMargin: "0px 0px -10% 0px", threshold: 0.12 }
);
$$(".reveal").forEach((el) => revealIO.observe(el));

function countUp(el) {
  if (el.dataset.done) return;
  el.dataset.done = "1";
  const to = +el.dataset.to;
  const fmt = (n) => Math.round(n).toLocaleString("en-US");
  if (state.reduced || to === 0) { el.textContent = fmt(to); return; }
  const dur = 1400;
  const t0 = performance.now();
  const tick = (now) => {
    const t = clamp((now - t0) / dur);
    el.textContent = fmt(to * (1 - Math.pow(1 - t, 4)));
    if (t < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

/* ---------- Nav, hero progress, chapters, buy bar ---------- */
const nav = $(".nav");
const hero = $(".hero");
const heroCopy = $(".hero__copy");
const stage = $("#stage");
const chapters = $$(".chapter");
const buybar = $(".buybar");
const pricing = $("#pricing");
let lastY = scrollY;
let ticking = false;

function onScroll() {
  ticking = false;
  const y = scrollY;
  nav.classList.toggle("is-scrolled", y > 40);
  nav.classList.toggle("is-hidden", y > lastY && y > 600 && y - lastY > 4);
  if (y < lastY - 4 || y < 600) nav.classList.remove("is-hidden");
  lastY = y;

  const r = hero.getBoundingClientRect();
  const span = r.height - innerHeight;
  const p = clamp(-r.top / span);
  state.progress = p;
  const copyOpacity = 1 - clamp((p - 0.04) / 0.1);
  heroCopy.style.opacity = String(copyOpacity);
  // On narrow screens the product sits behind the copy: keep it dim until the copy fades
  stage.style.opacity = innerWidth < 860 ? String(0.3 + 0.7 * (1 - copyOpacity)) : "";
  heroCopy.style.visibility = p > 0.15 ? "hidden" : "visible";
  const idx = p < 0.16 ? -1 : p < 0.45 ? 0 : p < 0.72 ? 1 : 2;
  chapters.forEach((c, i) => c.classList.toggle("is-active", i === idx));

  const pr = pricing.getBoundingClientRect();
  const inPricing = pr.top < innerHeight && pr.bottom > 0;
  buybar.classList.toggle("is-visible", r.bottom < innerHeight * 0.5 && !inPricing);
}
addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(onScroll); } }, { passive: true });
addEventListener("resize", onScroll);
onScroll();

/* ---------- 3D scene (lazy) ---------- */
const canvas = $("#scene");
function webglOK() {
  try {
    const c = document.createElement("canvas");
    return !!(window.WebGLRenderingContext && (c.getContext("webgl2") || c.getContext("webgl")));
  } catch { return false; }
}
if (canvas && webglOK()) {
  import("./scene.js")
    .then(({ createScene }) => {
      createScene(canvas, state);
      root.classList.add("is-3d");
    })
    .catch((err) => console.warn("3D scene unavailable, showing illustration instead.", err));
}

addEventListener("pointermove", (e) => {
  state.pointerX = (e.clientX / innerWidth) * 2 - 1;
  state.pointerY = (e.clientY / innerHeight) * 2 - 1;
}, { passive: true });

/* ---------- Before / after slider ---------- */
const ba = $("#ba");
if (ba) {
  const range = $(".ba__range", ba);
  const set = (v) => ba.style.setProperty("--pos", `${v}%`);
  range.addEventListener("input", () => set(range.value));
  // Gentle auto-hint the first time it scrolls into view
  if (!state.reduced) {
    const io = new IntersectionObserver(([e]) => {
      if (!e.isIntersecting) return;
      io.disconnect();
      const t0 = performance.now();
      const anim = (now) => {
        if (range.dataset.touched) return;
        const t = clamp((now - t0) / 1600);
        const v = 50 + Math.sin(t * Math.PI * 2) * 22 * (1 - t);
        range.value = String(v); set(v);
        if (t < 1) requestAnimationFrame(anim);
      };
      requestAnimationFrame(anim);
    }, { threshold: 0.6 });
    io.observe(ba);
    range.addEventListener("pointerdown", () => (range.dataset.touched = "1"));
    range.addEventListener("keydown", () => (range.dataset.touched = "1"));
  }
}

/* ---------- Micro-interactions ---------- */
if (finePointer.matches && !state.reduced) {
  // Magnetic buttons
  $$(".magnetic").forEach((b) => {
    b.addEventListener("pointermove", (e) => {
      const r = b.getBoundingClientRect();
      b.style.setProperty("--bx", `${(e.clientX - r.left - r.width / 2) * 0.25}px`);
      b.style.setProperty("--by", `${(e.clientY - r.top - r.height / 2) * 0.35}px`);
    });
    b.addEventListener("pointerleave", () => { b.style.setProperty("--bx", "0px"); b.style.setProperty("--by", "0px"); });
  });
  // Tilt cards with a light spot following the pointer
  $$(".tilt").forEach((c) => {
    c.addEventListener("pointermove", (e) => {
      const r = c.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width;
      const y = (e.clientY - r.top) / r.height;
      c.style.setProperty("--ry", `${(x - 0.5) * 8}deg`);
      c.style.setProperty("--rx", `${(0.5 - y) * 8}deg`);
      c.style.setProperty("--mx", `${x * 100}%`);
      c.style.setProperty("--my", `${y * 100}%`);
    });
    c.addEventListener("pointerleave", () => { c.style.setProperty("--rx", "0deg"); c.style.setProperty("--ry", "0deg"); });
  });
}

// Water-ripple on button press
document.addEventListener("pointerdown", (e) => {
  const b = e.target.closest?.(".btn");
  if (!b || state.reduced) return;
  const r = b.getBoundingClientRect();
  const d = Math.max(r.width, r.height) * 2.2;
  const s = document.createElement("span");
  s.className = "ripple";
  s.style.cssText = `width:${d}px;height:${d}px;left:${e.clientX - r.left - d / 2}px;top:${e.clientY - r.top - d / 2}px`;
  b.appendChild(s);
  s.addEventListener("animationend", () => s.remove());
});

/* ---------- Toast, cart, countdown, signup ---------- */
const toast = $("#toast");
let toastTimer;
function showToast(msg) {
  toast.textContent = msg;
  toast.classList.add("is-on");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove("is-on"), 2800);
}
$$(".add-to-cart").forEach((b) =>
  b.addEventListener("click", (e) => {
    e.preventDefault();
    showToast(`✓ ${b.dataset.plan} added to cart — $${b.dataset.price}. Free 2-day shipping.`);
    b.textContent = "Added ✓";
    setTimeout(() => (b.textContent = "Add to cart"), 2200);
  })
);

const cd = $("#countdown");
const deadline = (() => {
  const d = Date.now() + (2 * 24 + 7) * 3600e3 + 23 * 60e3;
  try {
    const saved = +sessionStorage.getItem("tw-deadline");
    if (saved > Date.now()) return saved;
    sessionStorage.setItem("tw-deadline", String(d));
  } catch { /* storage unavailable (privacy mode) */ }
  return d;
})();
function tickCountdown() {
  const s = Math.max(0, Math.floor((deadline - Date.now()) / 1000));
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  const pad = (n) => String(n).padStart(2, "0");
  cd.textContent = `${d}d ${pad(h)}h ${pad(m)}m ${pad(sec)}s`;
}
tickCountdown();
setInterval(tickCountdown, 1000);

const form = $("#signup");
const msg = $("#signup-msg");
form.addEventListener("submit", (e) => {
  e.preventDefault();
  const email = form.email.value.trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    msg.textContent = "Please enter a valid email address.";
    form.email.focus();
    return;
  }
  msg.textContent = "You're in! Your $30 code is on its way — check your inbox.";
  form.reset();
});

/* ---------- Final CTA ripple canvas (runs only when visible) ---------- */
(() => {
  const c = $("#ripples");
  if (!c) return;
  const g = c.getContext("2d");
  const rings = [];
  let w = 0, h = 0, raf = 0, on = false, last = 0;
  const dpr = Math.min(devicePixelRatio, 1.5);
  const size = () => { w = c.clientWidth; h = c.clientHeight; c.width = w * dpr; c.height = h * dpr; g.setTransform(dpr, 0, 0, dpr, 0, 0); };
  const add = (x, y) => rings.push({ x, y, r: 0, a: 0.6 });
  const loop = (now) => {
    raf = requestAnimationFrame(loop);
    if (now - last > 900) { add(Math.random() * w, Math.random() * h); last = now; }
    g.clearRect(0, 0, w, h);
    for (let i = rings.length - 1; i >= 0; i--) {
      const r = rings[i];
      r.r += 1.2; r.a *= 0.985;
      if (r.a < 0.02) { rings.splice(i, 1); continue; }
      for (let k = 0; k < 3; k++) {
        g.beginPath();
        g.strokeStyle = `rgba(124,232,255,${r.a * (1 - k * 0.3)})`;
        g.lineWidth = 1.5;
        g.ellipse(r.x, r.y, r.r + k * 14, (r.r + k * 14) * 0.45, 0, 0, Math.PI * 2);
        g.stroke();
      }
    }
  };
  size();
  addEventListener("resize", size);
  if (state.reduced) return;
  c.parentElement.parentElement.addEventListener("pointermove", (e) => {
    if (Math.random() < 0.12) { const r = c.getBoundingClientRect(); add(e.clientX - r.left, e.clientY - r.top); }
  });
  new IntersectionObserver(([e]) => {
    if (e.isIntersecting && !on) { on = true; raf = requestAnimationFrame(loop); }
    else if (!e.isIntersecting && on) { on = false; cancelAnimationFrame(raf); }
  }).observe(c);
})();

/* ---------- Custom cursor: a water droplet that leaves a drying wet trail
   and becomes a spinning roller over anything clickable ---------- */
(() => {
  if (!finePointer.matches) return;
  const cur = $(".cursor");
  const drop = $(".cursor__drop");
  const dropSvg = $("svg", drop);
  const roller = $(".cursor__roller");
  const label = $(".cursor__label");
  const trail = $(".cursor__trail");
  const g = trail.getContext("2d");
  root.classList.add("has-cursor");

  const dpr = Math.min(devicePixelRatio, 2);
  const size = () => { trail.width = innerWidth * dpr; trail.height = innerHeight * dpr; g.setTransform(dpr, 0, 0, dpr, 0, 0); };
  size();
  addEventListener("resize", size);

  let x = innerWidth / 2, y = innerHeight / 2; // pointer
  let dx = x, dy = y, vx = 0, vy = 0;        // droplet (spring)
  let rx = x, ry = y;                         // roller (lerp)
  let hover = false, visible = false;
  const blobs = [];
  const splashes = [];
  let raf = 0, idleFrames = 0;

  const wake = () => { idleFrames = 0; if (!raf) raf = requestAnimationFrame(loop); };

  addEventListener("pointermove", (e) => {
    if (e.pointerType !== "mouse" && e.pointerType !== "pen") return;
    x = e.clientX; y = e.clientY;
    if (!visible) { visible = true; dx = rx = x; dy = ry = y; cur.classList.remove("is-hidden"); }
    const t = e.target.closest?.("a, button, summary, .ba__range, label, [data-cursor]");
    const isText = !!e.target.closest?.("input[type=email]");
    cur.classList.toggle("is-text", isText);
    if (!!t !== hover) { hover = !!t; cur.classList.toggle("is-hover", hover); }
    if (t) {
      label.textContent = t.dataset.cursor ||
        (t.classList.contains("ba__range") ? "Drag" :
          t.matches("summary") ? "Open" :
            t.matches(".add-to-cart, [href='#pricing']") ? "Buy" : "Clean");
    }
    if (!state.reduced && Math.hypot(x - dx, y - dy) > 2) {
      blobs.push({ x, y, r: 3 + Math.random() * 5, a: 0.5 });
      if (blobs.length > 120) blobs.shift();
    }
    wake();
  }, { passive: true });

  document.addEventListener("mouseout", (e) => { if (!e.relatedTarget) { visible = false; cur.classList.add("is-hidden"); } });
  addEventListener("blur", () => { visible = false; cur.classList.add("is-hidden"); });
  addEventListener("pointerdown", (e) => {
    if (e.pointerType !== "mouse") return;
    cur.classList.add("is-down");
    if (!state.reduced) for (let i = 0; i < 3; i++) splashes.push({ x: e.clientX, y: e.clientY, r: 4 + i * 6, a: 0.8 - i * 0.2 });
    wake();
  });
  addEventListener("pointerup", () => cur.classList.remove("is-down"));

  function loop() {
    // Spring for the droplet gives a liquid, slightly wobbly lag
    const k = state.reduced ? 1 : 0.28, damp = 0.62;
    vx = (vx + (x - dx) * k) * damp;
    vy = (vy + (y - dy) * k) * damp;
    dx += vx; dy += vy;
    if (state.reduced) { dx = x; dy = y; vx = vy = 0; }
    rx += (x - rx) * 0.22; ry += (y - ry) * 0.22;

    const speed = Math.min(Math.hypot(vx, vy), 40);
    const ang = -30 + clamp(vx / 30, -1, 1) * 25;
    const stretch = 1 + speed / 70;
    // Tip of the droplet (top-centre of the SVG) is the hotspot
    drop.style.transform = `translate(${dx - 14}px, ${dy}px)`;
    if (!hover && !cur.classList.contains("is-down") && !cur.classList.contains("is-text")) {
      dropSvg.style.transform = `rotate(${ang}deg) scale(${1 / Math.sqrt(stretch)}, ${stretch})`;
    } else {
      dropSvg.style.transform = "";
    }
    roller.style.transform = `translate(${rx}px, ${ry}px) scale(${hover ? 1 : 0.4})`;

    // Wet trail that "dries" out
    g.clearRect(0, 0, innerWidth, innerHeight);
    for (let i = blobs.length - 1; i >= 0; i--) {
      const b = blobs[i];
      b.a *= 0.93; b.r *= 0.985;
      if (b.a < 0.02) { blobs.splice(i, 1); continue; }
      g.beginPath();
      g.fillStyle = `rgba(47,198,236,${b.a * 0.55})`;
      g.arc(b.x, b.y, b.r, 0, Math.PI * 2);
      g.fill();
      g.beginPath();
      g.fillStyle = `rgba(255,255,255,${b.a * 0.7})`;
      g.arc(b.x - b.r * 0.35, b.y - b.r * 0.35, b.r * 0.25, 0, Math.PI * 2);
      g.fill();
    }
    for (let i = splashes.length - 1; i >= 0; i--) {
      const s = splashes[i];
      s.r += 2.2; s.a *= 0.9;
      if (s.a < 0.03) { splashes.splice(i, 1); continue; }
      g.beginPath();
      g.strokeStyle = `rgba(47,198,236,${s.a})`;
      g.lineWidth = 2;
      g.ellipse(s.x, s.y, s.r, s.r * 0.6, 0, 0, Math.PI * 2);
      g.stroke();
    }

    const settled = Math.abs(x - dx) < 0.1 && Math.abs(y - dy) < 0.1 && Math.abs(x - rx) < 0.1 && !blobs.length && !splashes.length;
    if (settled && ++idleFrames > 10) { raf = 0; return; }
    raf = requestAnimationFrame(loop);
  }
  cur.classList.add("is-hidden");
})();
