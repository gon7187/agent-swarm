/* Ondine Glide S1 — UI interactions (no dependencies) */
(() => {
  'use strict';

  const doc = document.documentElement;
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const finePointer = matchMedia('(hover: hover) and (pointer: fine)');
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

  requestAnimationFrame(() => requestAnimationFrame(() => doc.classList.add('is-loaded')));

  /* ---------- scroll reveals (staggered per parent) ---------- */
  const reveals = $$('.reveal');
  if ('IntersectionObserver' in window && !reduceMotion.matches) {
    const groups = new Map();
    reveals.forEach((el) => {
      const p = el.parentElement;
      const i = groups.get(p) || 0;
      groups.set(p, i + 1);
      el.style.setProperty('--d', `${Math.min(i, 6) * 0.08}s`);
    });
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add('is-in'));
  }

  /* ---------- count-up numbers ---------- */
  const fmt = new Intl.NumberFormat('en-US');
  const counters = $$('[data-count]');
  const runCounter = (el) => {
    const end = +el.dataset.count;
    if (reduceMotion.matches || end === 0) { el.textContent = fmt.format(end); return; }
    const dur = 1600;
    const t0 = performance.now();
    const tick = (t) => {
      const k = clamp((t - t0) / dur);
      const eased = 1 - Math.pow(1 - k, 4);
      el.textContent = fmt.format(Math.round(end * eased));
      if (k < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };
  if ('IntersectionObserver' in window) {
    const cio = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { runCounter(e.target); cio.unobserve(e.target); } });
    }, { threshold: 0.6 });
    counters.forEach((c) => cio.observe(c));
    const rating = $('.rating');
    if (rating) {
      const rio = new IntersectionObserver(([e]) => { if (e.isIntersecting) { rating.classList.add('is-in'); rio.disconnect(); } }, { threshold: 0.4 });
      rio.observe(rating);
    }
  }

  /* ---------- scroll-linked UI (nav, buy bar, anatomy steps, how-it-works) ---------- */
  const nav = $('[data-nav]');
  const buybar = $('[data-buybar]');
  const anatomy = $('#anatomy');
  const anatomySteps = $$('.anatomy__step');
  const pricing = $('#pricing');
  const finalCta = $('#buy');
  const how = $('#how');
  const howSteps = $$('.how__step');
  const flow = $('.flow');
  const flowClean = $('.flow__path--clean');
  const flowDirty = $('.flow__path--dirty');
  const tankClean = $('.tank-clean');
  const tankDirty = $('.tank-dirty');
  const spokes = $('.roller-spokes');
  [flowClean, flowDirty].forEach((p) => p && p.setAttribute('pathLength', '1'));

  let lastY = scrollY;
  let ticking = false;
  let curStep = -1;
  let curHow = -1;

  const onScroll = () => {
    ticking = false;
    const y = scrollY;
    const vh = innerHeight;

    nav.classList.toggle('is-scrolled', y > 20);
    nav.classList.toggle('is-hidden', y > lastY && y > vh * 0.9 && !nav.contains(document.activeElement));
    lastY = y;

    // Buy bar: after the hero, hidden while pricing / final CTA are in view
    const pr = pricing.getBoundingClientRect();
    const fr = finalCta.getBoundingClientRect();
    const overOffer = (pr.top < vh && pr.bottom > 0) || fr.top < vh;
    buybar.classList.toggle('is-shown', y > vh * 0.8 && !overOffer);

    // Anatomy: which part is highlighted
    const ar = anatomy.getBoundingClientRect();
    const ap = clamp(-ar.top / (ar.height - vh));
    const step = Math.min(anatomySteps.length - 1, Math.floor(ap * anatomySteps.length * 0.999));
    if (step !== curStep) {
      curStep = step;
      anatomySteps.forEach((s, i) => s.classList.toggle('is-active', i === step));
    }

    // How it works: water flow along the paths
    const hr = how.getBoundingClientRect();
    const hp = clamp((vh * 0.6 - hr.top) / (hr.height - vh * 0.4));
    const fillClean = clamp(hp / 0.4);
    const fillDirty = clamp((hp - 0.3) / 0.35);
    flowClean.style.strokeDashoffset = String(1 - fillClean);
    flowDirty.style.strokeDashoffset = String(1 - fillDirty);
    tankClean.setAttribute('height', String(lerp(90, 40, clamp(hp / 0.7))));
    tankClean.setAttribute('y', String(lerp(96, 146, clamp(hp / 0.7))));
    const dirtyH = lerp(0, 70, fillDirty);
    tankDirty.setAttribute('height', String(dirtyH));
    tankDirty.setAttribute('y', String(336 - dirtyH));
    spokes.style.transform = `rotate(${hp * 1080}deg)`;
    flow.classList.toggle('is-heat', hp > 0.72);

    let active = 0;
    howSteps.forEach((s, i) => {
      const r = s.getBoundingClientRect();
      if (r.top < vh * 0.62) active = i;
    });
    if (active !== curHow) {
      curHow = active;
      howSteps.forEach((s, i) => s.classList.toggle('is-active', i === active));
    }
  };
  const requestScroll = () => { if (!ticking) { ticking = true; requestAnimationFrame(onScroll); } };
  addEventListener('scroll', requestScroll, { passive: true });
  addEventListener('resize', requestScroll);
  onScroll();

  /* ---------- magnetic buttons + card spotlight/tilt (fine pointers only) ---------- */
  if (finePointer.matches) {
    $$('[data-magnetic]').forEach((btn) => {
      btn.addEventListener('pointermove', (e) => {
        const r = btn.getBoundingClientRect();
        const dx = e.clientX - (r.left + r.width / 2);
        const dy = e.clientY - (r.top + r.height / 2);
        btn.style.setProperty('--rx', `${((e.clientX - r.left) / r.width) * 100}%`);
        btn.style.setProperty('--ry', `${((e.clientY - r.top) / r.height) * 100}%`);
        if (!reduceMotion.matches) {
          btn.style.setProperty('--bx', `${dx * 0.22}px`);
          btn.style.setProperty('--by', `${dy * 0.3}px`);
        }
      });
      btn.addEventListener('pointerleave', () => {
        btn.style.setProperty('--bx', '0px');
        btn.style.setProperty('--by', '0px');
      });
    });

    $$('[data-tilt]').forEach((card) => {
      card.addEventListener('pointermove', (e) => {
        const r = card.getBoundingClientRect();
        const px = (e.clientX - r.left) / r.width;
        const py = (e.clientY - r.top) / r.height;
        card.style.setProperty('--mx', `${px * 100}%`);
        card.style.setProperty('--my', `${py * 100}%`);
        if (!reduceMotion.matches) {
          card.style.transform = `perspective(900px) rotateX(${(0.5 - py) * 5}deg) rotateY(${(px - 0.5) * 6}deg)`;
        }
      });
      card.addEventListener('pointerleave', () => { card.style.transform = ''; });
    });
  }

  /* ---------- demo "buy" buttons ---------- */
  const toast = $('.toast');
  let toastTimer;
  const showToast = (msg) => {
    toast.textContent = msg;
    toast.classList.add('is-shown');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('is-shown'), 3200);
  };
  $$('[data-buy]').forEach((b) => b.addEventListener('click', (e) => {
    e.preventDefault();
    showToast(`✓ ${b.dataset.buy} ($${b.dataset.price}) added to cart — this is a demo checkout.`);
  }));

  /* ---------- FAQ: keep one open at a time ---------- */
  const faqs = $$('.faq__list details');
  faqs.forEach((d) => d.addEventListener('toggle', () => {
    if (d.open) faqs.forEach((o) => { if (o !== d) o.open = false; });
  }));

  /* ---------- Wipe-the-floor demo ---------- */
  const wipeWrap = $('.wipe__canvas-wrap');
  if (wipeWrap) initWipe(wipeWrap);

  function initWipe(wrap) {
    const canvas = $('.wipe__canvas', wrap);
    const ctx = canvas.getContext('2d');
    const pctEl = $('.wipe__pct', wrap);
    const floor = document.createElement('canvas');
    const dirt = document.createElement('canvas');
    const wet = document.createElement('canvas');
    let W = 0, H = 0, dpr = 1, initialDirt = 1, done = false, raf = 0, last = null, dirty = true, wetAlpha = 0;

    const reset = document.createElement('button');
    reset.type = 'button';
    reset.className = 'btn btn--ghost btn--sm wipe__reset';
    reset.textContent = 'Make a mess again';
    Object.assign(reset.style, { position: 'absolute', right: '16px', top: '12px', display: 'none', background: 'rgba(6,17,28,.8)' });
    wrap.appendChild(reset);
    reset.addEventListener('click', () => { build(); reset.style.display = 'none'; });

    // deterministic PRNG so the mess looks designed, not noisy
    let seed = 7;
    const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);

    function drawFloor(c, w, h) {
      const g = c.getContext('2d');
      const plankH = h / 6;
      for (let row = 0; row < 7; row++) {
        let x = -((row * 137) % 220);
        while (x < w) {
          const pw = 220 + ((row * 53 + x) % 140);
          const tone = 30 + ((row * 17 + Math.abs(x)) % 12);
          const grad = g.createLinearGradient(0, row * plankH, 0, (row + 1) * plankH);
          grad.addColorStop(0, `hsl(${tone} 45% 70%)`);
          grad.addColorStop(1, `hsl(${tone} 40% 62%)`);
          g.fillStyle = grad;
          g.fillRect(x, row * plankH, pw, plankH);
          g.strokeStyle = 'rgba(70,45,20,.18)';
          g.lineWidth = 1;
          for (let k = 0; k < 6; k++) {
            g.beginPath();
            const yy = row * plankH + (k + 0.5) * (plankH / 6);
            g.moveTo(x, yy);
            g.bezierCurveTo(x + pw * 0.3, yy + 3, x + pw * 0.6, yy - 3, x + pw, yy);
            g.stroke();
          }
          g.fillStyle = 'rgba(60,35,15,.45)';
          g.fillRect(x, row * plankH, 2, plankH);
          x += pw;
        }
        g.fillStyle = 'rgba(60,35,15,.4)';
        g.fillRect(0, row * plankH - 1, w, 2);
      }
      // glossy "just cleaned" highlight
      const shine = g.createLinearGradient(0, 0, w, h);
      shine.addColorStop(0, 'rgba(255,255,255,0)');
      shine.addColorStop(0.45, 'rgba(255,255,255,.28)');
      shine.addColorStop(0.55, 'rgba(255,255,255,0)');
      g.fillStyle = shine;
      g.fillRect(0, 0, w, h);
    }

    function drawDirt(c, w, h) {
      const g = c.getContext('2d');
      seed = 7;
      // dull film everywhere
      g.fillStyle = 'rgba(120, 100, 70, .55)';
      g.fillRect(0, 0, w, h);
      // dust speckle
      for (let i = 0; i < 900; i++) {
        g.fillStyle = `rgba(${60 + rnd() * 40},${45 + rnd() * 30},${25 + rnd() * 20},${0.2 + rnd() * 0.4})`;
        g.fillRect(rnd() * w, rnd() * h, 1 + rnd() * 2.5, 1 + rnd() * 2.5);
      }
      // coffee spills
      const spill = (x, y, r) => {
        const rg = g.createRadialGradient(x, y, r * 0.1, x, y, r);
        rg.addColorStop(0, 'rgba(90,50,20,.75)');
        rg.addColorStop(0.8, 'rgba(80,45,15,.6)');
        rg.addColorStop(1, 'rgba(60,30,10,0)');
        g.fillStyle = rg;
        g.beginPath();
        for (let a = 0; a <= Math.PI * 2 + 0.01; a += 0.3) {
          const rr = r * (0.8 + rnd() * 0.3);
          g.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr * 0.8);
        }
        g.fill();
        g.strokeStyle = 'rgba(70,35,10,.6)';
        g.lineWidth = 2;
        g.beginPath();
        g.ellipse(x + r * 0.9, y - r * 0.4, r * 0.35, r * 0.3, 0, 0, Math.PI * 2);
        g.stroke();
      };
      spill(w * 0.24, h * 0.32, w * 0.11);
      spill(w * 0.72, h * 0.7, w * 0.08);
      // paw prints
      const paw = (x, y, s, rot) => {
        g.save();
        g.translate(x, y);
        g.rotate(rot);
        g.fillStyle = 'rgba(70,50,30,.7)';
        g.beginPath(); g.ellipse(0, 0, s, s * 0.8, 0, 0, Math.PI * 2); g.fill();
        [[-1.1, -1.2], [-0.4, -1.7], [0.4, -1.7], [1.1, -1.2]].forEach(([dx, dy]) => {
          g.beginPath(); g.ellipse(dx * s, dy * s, s * 0.32, s * 0.4, 0, 0, Math.PI * 2); g.fill();
        });
        g.restore();
      };
      for (let i = 0; i < 7; i++) {
        paw(w * (0.4 + i * 0.085), h * (0.18 + (i % 2) * 0.1 + i * 0.07), w * 0.018, 1.9 + (rnd() - 0.5) * 0.3);
      }
      // crumbs
      for (let i = 0; i < 70; i++) {
        g.fillStyle = `rgba(${170 + rnd() * 40},${120 + rnd() * 40},${60 + rnd() * 30},.95)`;
        const x = w * (0.1 + rnd() * 0.35), y = h * (0.62 + rnd() * 0.3);
        g.beginPath(); g.arc(x, y, 1.5 + rnd() * 3, 0, Math.PI * 2); g.fill();
      }
      // muddy streak
      g.strokeStyle = 'rgba(80,60,35,.5)';
      g.lineCap = 'round';
      g.lineWidth = w * 0.03;
      g.beginPath();
      g.moveTo(w * 0.55, h * 0.45);
      g.bezierCurveTo(w * 0.65, h * 0.4, w * 0.8, h * 0.5, w * 0.92, h * 0.38);
      g.stroke();
    }

    // coverage is sampled on a tiny copy so it stays cheap while scrubbing
    const probe = document.createElement('canvas');
    probe.width = 96; probe.height = 72;
    const pctx = probe.getContext('2d', { willReadFrequently: true });
    function measure() {
      pctx.clearRect(0, 0, probe.width, probe.height);
      pctx.drawImage(dirt, 0, 0, probe.width, probe.height);
      const data = pctx.getImageData(0, 0, probe.width, probe.height).data;
      let sum = 0;
      for (let i = 3; i < data.length; i += 4) sum += data[i];
      return sum;
    }

    function build() {
      const r = wrap.getBoundingClientRect();
      dpr = Math.min(devicePixelRatio || 1, 2);
      W = Math.round(r.width); H = Math.round(r.height);
      canvas.width = W * dpr; canvas.height = H * dpr;
      [floor, dirt, wet].forEach((c) => { c.width = W * dpr; c.height = H * dpr; c.getContext('2d').setTransform(dpr, 0, 0, dpr, 0, 0); });
      drawFloor(floor, W, H);
      drawDirt(dirt, W, H);
      initialDirt = measure() || 1;
      done = false;
      pctEl.textContent = '0%';
      wrap.classList.remove('is-touched');
      dirty = true;
      loop();
    }

    function render() {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(floor, 0, 0);
      ctx.drawImage(dirt, 0, 0);
      if (wetAlpha > 0.01) {
        ctx.globalAlpha = wetAlpha;
        ctx.drawImage(wet, 0, 0);
        ctx.globalAlpha = 1;
      }
    }

    function loop() {
      cancelAnimationFrame(raf);
      const step = () => {
        if (wetAlpha > 0.01) { wetAlpha *= 0.96; dirty = true; }
        if (dirty) { render(); dirty = false; }
        if (wetAlpha > 0.01) raf = requestAnimationFrame(step);
      };
      raf = requestAnimationFrame(step);
    }

    let measureTimer = 0;
    function scrub(x, y) {
      const w = Math.max(46, W * 0.16);
      const d = dirt.getContext('2d');
      const wg = wet.getContext('2d');
      const from = last || { x, y };
      d.save();
      d.globalCompositeOperation = 'destination-out';
      d.lineCap = 'round';
      d.lineJoin = 'round';
      d.lineWidth = w;
      d.strokeStyle = 'rgba(0,0,0,1)';
      d.beginPath(); d.moveTo(from.x, from.y); d.lineTo(x, y); d.stroke();
      d.restore();
      // fading wet sheen along the stroke
      wg.clearRect(0, 0, W, H);
      wg.lineCap = 'round';
      wg.lineWidth = w * 0.9;
      wg.strokeStyle = 'rgba(190, 250, 255, .35)';
      wg.beginPath(); wg.moveTo(from.x, from.y); wg.lineTo(x, y); wg.stroke();
      wetAlpha = 1;
      last = { x, y };
      dirty = true;
      loop();
      if (!measureTimer) {
        measureTimer = setTimeout(() => {
          measureTimer = 0;
          const pct = Math.round((1 - measure() / initialDirt) * 100);
          if (pct >= 90 && !done) {
            done = true;
            d.clearRect(0, 0, W, H);
            dirty = true; loop();
            pctEl.textContent = '100%';
            reset.style.display = '';
          } else if (!done) {
            pctEl.textContent = `${clamp(pct, 0, 100)}%`;
          }
        }, 120);
      }
    }

    const pos = (e) => {
      const r = canvas.getBoundingClientRect();
      return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    let down = false;
    canvas.addEventListener('pointerdown', (e) => { down = true; last = null; wrap.classList.add('is-touched'); const p = pos(e); scrub(p.x, p.y); });
    canvas.addEventListener('pointermove', (e) => {
      // mouse users can "hover-clean" too — it feels like steering the head
      if (down || e.pointerType === 'mouse') {
        wrap.classList.add('is-touched');
        const p = pos(e);
        scrub(p.x, p.y);
      }
    });
    const up = () => { down = false; last = null; };
    canvas.addEventListener('pointerup', up);
    canvas.addEventListener('pointercancel', up);
    canvas.addEventListener('pointerleave', up);

    let lastW = 0;
    const ro = new ResizeObserver(() => {
      const w = Math.round(wrap.getBoundingClientRect().width);
      if (Math.abs(w - lastW) > 2) { lastW = w; build(); }
    });
    ro.observe(wrap);
  }

  /* ---------- Custom cursor: a water droplet that stretches, drips and ripples ---------- */
  const cursorEl = $('.cursor');
  if (cursorEl && finePointer.matches) initCursor(cursorEl);
  finePointer.addEventListener?.('change', (e) => { if (!e.matches) doc.classList.remove('has-cursor'); });

  function initCursor(root) {
    const drop = $('.cursor__drop', root);
    const ring = $('.cursor__ring', root);
    const label = $('.cursor__label', root);
    const trail = $('.cursor__trail', root);
    const tctx = trail.getContext('2d');
    let mx = -100, my = -100, x = -100, y = -100, rx = -100, ry = -100, px = -100, py = -100;
    let angle = 0, stretch = 1, active = false, raf = 0, idleFrames = 0;
    const particles = [];
    const ripples = [];

    const sizeTrail = () => { trail.width = innerWidth; trail.height = innerHeight; };
    sizeTrail();
    addEventListener('resize', sizeTrail);

    const wake = () => { idleFrames = 0; if (!raf) raf = requestAnimationFrame(frame); };

    addEventListener('pointermove', (e) => {
      if (e.pointerType !== 'mouse') return;
      if (!active) {
        active = true;
        doc.classList.add('has-cursor');
        x = rx = px = mx = e.clientX; y = ry = py = my = e.clientY;
      }
      mx = e.clientX; my = e.clientY;
      root.classList.remove('is-hidden');
      wake();
    }, { passive: true });
    document.addEventListener('pointerleave', () => root.classList.add('is-hidden'));
    addEventListener('blur', () => root.classList.add('is-hidden'));

    addEventListener('pointerdown', (e) => {
      if (e.pointerType !== 'mouse') return;
      ripples.push({ x: e.clientX, y: e.clientY, r: 4, a: 1 });
      if (!reduceMotion.matches) {
        for (let i = 0; i < 10; i++) {
          const a = Math.random() * Math.PI * 2, s = 1.5 + Math.random() * 3;
          particles.push({ x: e.clientX, y: e.clientY, vx: Math.cos(a) * s, vy: Math.sin(a) * s - 2, r: 1.5 + Math.random() * 2.5, life: 1 });
        }
      }
      drop.animate?.([{ scale: '1' }, { scale: '.7' }, { scale: '1' }], { duration: 300, easing: 'ease-out' });
      wake();
    });

    // hover states
    const interactive = 'a, button, summary, [role="button"], [data-cursor], input, select, textarea, label';
    document.addEventListener('pointerover', (e) => {
      const t = e.target.closest?.(interactive);
      root.classList.toggle('is-hover', !!t);
      root.classList.toggle('is-wipe', !!t && t.matches('.wipe__canvas-wrap'));
      if (t) {
        label.textContent = t.dataset.cursor || (t.matches('summary') ? (t.parentElement.open ? 'Close' : 'Open') : t.matches('a[href^="#"]') ? 'Go' : 'Tap');
      }
    });
    document.addEventListener('click', (e) => {
      const s = e.target.closest?.('summary');
      if (s) setTimeout(() => { label.textContent = s.parentElement.open ? 'Close' : 'Open'; }, 0);
    });

    function frame() {
      raf = 0;
      const rm = reduceMotion.matches;
      x = lerp(x, mx, rm ? 1 : 0.4); y = lerp(y, my, rm ? 1 : 0.4);
      const follow = rm ? 1 : root.classList.contains('is-wipe') ? 0.5 : 0.18;
      rx = lerp(rx, mx, follow); ry = lerp(ry, my, follow);
      const vx = x - px, vy = y - py;
      px = x; py = y;
      const speed = Math.hypot(vx, vy);

      // orient the droplet so its tail trails the motion, stretch with speed
      const target = speed > 1.2 ? Math.atan2(-vx, vy) : 0;
      let diff = target - angle;
      diff = Math.atan2(Math.sin(diff), Math.cos(diff));
      angle += diff * (speed > 1.2 ? 0.25 : 0.08);
      stretch = lerp(stretch, 1 + Math.min(speed / 30, 0.6), 0.25);
      const squash = 1 / Math.sqrt(stretch);
      drop.style.transform = `translate3d(${x}px, ${y}px, 0) rotate(${rm ? 0 : angle}rad) scale(${rm ? 1 : squash}, ${rm ? 1 : stretch})`;
      ring.style.transform = `translate3d(${rx}px, ${ry}px, 0)`;

      // drip trail
      if (!rm && speed > 6 && particles.length < 120 && !root.classList.contains('is-hover')) {
        particles.push({ x: x - vx * 0.5, y: y - vy * 0.5, vx: -vx * 0.05 + (Math.random() - 0.5), vy: -vy * 0.05, r: 1 + Math.random() * 2.2, life: 1 });
      }

      tctx.clearRect(0, 0, trail.width, trail.height);
      for (let i = particles.length - 1; i >= 0; i--) {
        const p = particles[i];
        p.vy += 0.12; p.x += p.vx; p.y += p.vy; p.life -= 0.025;
        if (p.life <= 0) { particles.splice(i, 1); continue; }
        tctx.beginPath();
        tctx.fillStyle = `rgba(140, 245, 235, ${p.life * 0.8})`;
        tctx.ellipse(p.x, p.y, p.r, p.r * (1 + Math.min(Math.abs(p.vy) * 0.12, 0.8)), 0, 0, Math.PI * 2);
        tctx.fill();
      }
      for (let i = ripples.length - 1; i >= 0; i--) {
        const r = ripples[i];
        r.r += rm ? 6 : 2.2; r.a -= rm ? 0.1 : 0.025;
        if (r.a <= 0) { ripples.splice(i, 1); continue; }
        tctx.lineWidth = 2;
        for (let k = 0; k < 3; k++) {
          const rr = r.r - k * 10;
          if (rr <= 0) continue;
          tctx.strokeStyle = `rgba(94, 240, 224, ${r.a * (1 - k * 0.3)})`;
          tctx.beginPath();
          tctx.ellipse(r.x, r.y, rr, rr * 0.45, 0, 0, Math.PI * 2);
          tctx.stroke();
        }
      }

      const settled = speed < 0.05 && Math.abs(rx - mx) < 0.3 && Math.abs(ry - my) < 0.3 && !particles.length && !ripples.length && Math.abs(stretch - 1) < 0.01;
      idleFrames = settled ? idleFrames + 1 : 0;
      if (idleFrames < 10) raf = requestAnimationFrame(frame);
    }
  }
})();
