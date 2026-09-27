/* Procedural 3D model of the Ondine Glide S1, built from primitives (no model files).
   Reacts to pointer (tilt + drag-to-spin) and scroll (hero → exploded "anatomy" view). */
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };

function canvasTexture(w, h, draw) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}

export function start(canvas) {
  const stage = canvas.closest('.stage');
  const sticky = canvas.parentElement;
  const wrap = document.querySelector('.stage-wrap');
  const hero = document.querySelector('.hero');
  const anatomy = document.getElementById('anatomy');
  const markersEl = stage.querySelector('.stage__markers');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');

  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setClearColor(0x000000, 0);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  pmrem.dispose();

  const camera = new THREE.PerspectiveCamera(30, 1, 0.1, 100);
  camera.position.set(0, 0.7, 12);
  camera.lookAt(0, 0, 0);

  const key = new THREE.DirectionalLight(0xfff1e0, 2.2);
  key.position.set(4, 6, 5);
  scene.add(key);
  const rim = new THREE.PointLight(0x5ef0e0, 30, 14);
  rim.position.set(-3.5, 2.5, -3);
  scene.add(rim);
  scene.add(new THREE.HemisphereLight(0xbfefff, 0x0a1a28, 0.6));

  /* ---------- materials ---------- */
  const M = {
    graphite: new THREE.MeshPhysicalMaterial({ color: 0x1d3040, metalness: 0.35, roughness: 0.36, clearcoat: 0.7, clearcoatRoughness: 0.2 }),
    shell: new THREE.MeshPhysicalMaterial({ color: 0xeef4f5, roughness: 0.26, clearcoat: 1, clearcoatRoughness: 0.08 }),
    glass: new THREE.MeshPhysicalMaterial({ color: 0xd8fffb, roughness: 0.04, metalness: 0, transparent: true, opacity: 0.2, clearcoat: 1, side: THREE.DoubleSide, depthWrite: false }),
    clean: new THREE.MeshPhysicalMaterial({ color: 0x3fdcd2, emissive: 0x0b6a66, emissiveIntensity: 0.7, roughness: 0.08, transparent: true, opacity: 0.85, clearcoat: 1 }),
    dirty: new THREE.MeshPhysicalMaterial({ color: 0x6d563f, roughness: 0.3, transparent: true, opacity: 0.9 }),
    accent: new THREE.MeshStandardMaterial({ color: 0x5ef0e0, emissive: 0x5ef0e0, emissiveIntensity: 1.8 }),
    rubber: new THREE.MeshStandardMaterial({ color: 0x0c151c, roughness: 0.85 }),
    chrome: new THREE.MeshStandardMaterial({ color: 0xc9dde2, metalness: 1, roughness: 0.16 }),
    ring: new THREE.MeshStandardMaterial({ color: 0x5ef0e0, emissive: 0x5ef0e0, emissiveIntensity: 2.2 }),
  };

  const rollerTex = canvasTexture(512, 128, (g, w, h) => {
    g.fillStyle = '#e3eef0'; g.fillRect(0, 0, w, h);
    for (let i = 0; i < 260; i++) {
      const x = Math.random() * w * 1.4 - w * 0.2;
      g.strokeStyle = i % 5 === 0 ? 'rgba(46,190,196,.55)' : `rgba(120,150,160,${0.12 + Math.random() * 0.25})`;
      g.lineWidth = 1 + Math.random() * 3;
      g.beginPath(); g.moveTo(x, 0); g.lineTo(x - w * 0.25, h); g.stroke();
    }
  });
  rollerTex.wrapS = rollerTex.wrapT = THREE.RepeatWrapping;
  const rollerMat = new THREE.MeshStandardMaterial({ map: rollerTex, roughness: 0.95 });

  const displayCanvas = document.createElement('canvas');
  displayCanvas.width = displayCanvas.height = 256;
  const displayTex = new THREE.CanvasTexture(displayCanvas);
  displayTex.colorSpace = THREE.SRGBColorSpace;
  let lastDisplay = '';
  const drawDisplay = (pct, color) => {
    const key = `${pct}|${color}`;
    if (key === lastDisplay) return;
    lastDisplay = key;
    const g = displayCanvas.getContext('2d');
    g.fillStyle = '#050c12'; g.fillRect(0, 0, 256, 256);
    g.strokeStyle = color; g.lineWidth = 10; g.lineCap = 'round';
    g.beginPath(); g.arc(128, 128, 104, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (pct / 100)); g.stroke();
    g.fillStyle = '#eafffd'; g.font = '800 64px Manrope, Arial, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText(`${pct}%`, 128, 122);
    g.fillStyle = color; g.font = '700 22px Manrope, Arial, sans-serif';
    g.fillText('AUTO', 128, 176);
    displayTex.needsUpdate = true;
  };
  drawDisplay(87, '#5ef0e0');
  document.fonts?.ready.then(() => { lastDisplay = ''; });

  const shadowTex = canvasTexture(256, 256, (g) => {
    const r = g.createRadialGradient(128, 128, 0, 128, 128, 128);
    r.addColorStop(0, 'rgba(0,0,0,.6)'); r.addColorStop(0.5, 'rgba(0,0,0,.25)'); r.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = r; g.fillRect(0, 0, 256, 256);
  });

  /* ---------- model ---------- */
  const root = new THREE.Group();   // placed on screen (layout)
  const spin = new THREE.Group();   // rotation from scroll/pointer
  const unit = new THREE.Group();   // the vacuum, origin on the floor
  unit.position.y = -2.35;
  root.add(spin); spin.add(unit); scene.add(root);

  const parts = [];
  const addPart = (step, explode, anchor) => {
    const g = new THREE.Group();
    unit.add(g);
    parts.push({ g, step, explode: new THREE.Vector3(...explode), anchor: anchor ? new THREE.Vector3(...anchor) : null });
    return g;
  };
  const mesh = (geo, mat, parent, pos = [0, 0, 0], rot = [0, 0, 0]) => {
    const m = new THREE.Mesh(geo, mat);
    m.position.set(...pos); m.rotation.set(...rot);
    parent.add(m);
    return m;
  };
  const cyl = (rt, rb, h, seg = 48, open = false, ts = 0, tl = Math.PI * 2) => new THREE.CylinderGeometry(rt, rb, h, seg, 1, open, ts, tl);

  // floor shadow
  const shadow = mesh(new THREE.PlaneGeometry(5, 3.2), new THREE.MeshBasicMaterial({ map: shadowTex, transparent: true, depthWrite: false }), unit, [0, 0.002, 0], [-Math.PI / 2, 0, 0]);
  shadow.renderOrder = -1;

  // head (chassis)
  const head = addPart(-1, [0, -0.35, 0]);
  mesh(new RoundedBoxGeometry(2.5, 0.42, 1.05, 5, 0.18), M.graphite, head, [0, 0.27, -0.05]);
  mesh(new RoundedBoxGeometry(2.3, 0.06, 0.78, 2, 0.03), M.shell, head, [0, 0.49, -0.12]);
  mesh(new THREE.BoxGeometry(2.2, 0.035, 0.04), M.accent, head, [0, 0.43, 0.47]);
  [-1.07, 1.07].forEach((x) => mesh(cyl(0.13, 0.13, 0.12, 24), M.rubber, head, [x, 0.13, -0.42], [0, 0, Math.PI / 2]));
  mesh(new THREE.SphereGeometry(0.23, 32, 16), M.shell, head, [0, 0.56, -0.2]);

  // roller (step 0)
  const roller = addPart(0, [0, -0.1, 1.15], [0.95, 0.3, 0.62]);
  const rollerSpin = new THREE.Group();
  rollerSpin.position.set(0, 0.25, 0.5);
  roller.add(rollerSpin);
  mesh(cyl(0.24, 0.24, 2.34, 48), rollerMat, rollerSpin, [0, 0, 0], [0, 0, Math.PI / 2]);
  [-1.2, 1.2].forEach((x) => mesh(cyl(0.255, 0.255, 0.06, 32), M.graphite, roller, [x, 0.25, 0.5], [0, 0, Math.PI / 2]));
  const cover = mesh(cyl(0.3, 0.3, 2.3, 40, true, 0, Math.PI), M.glass, roller, [0, 0.25, 0.5], [0, 0, Math.PI / 2]);
  cover.renderOrder = 2;

  // spine / motor
  const spine = addPart(-1, [0, 0, 0]);
  mesh(cyl(0.36, 0.41, 0.55), M.graphite, spine, [0, 0.93, -0.2]);
  mesh(new THREE.TorusGeometry(0.385, 0.014, 8, 64), M.accent, spine, [0, 0.78, -0.2], [Math.PI / 2, 0, 0]);
  mesh(cyl(0.38, 0.38, 0.14), M.shell, spine, [0, 1.99, -0.2]);
  mesh(cyl(0.065, 0.065, 2.05), M.chrome, spine, [0, 2.1, -0.6]);

  // dirty tank (step 2)
  const dirtyTank = addPart(2, [1.3, -0.05, 0.35], [0.34, 1.45, 0.1]);
  const dg = mesh(cyl(0.34, 0.34, 0.76), M.glass, dirtyTank, [0, 1.56, -0.2]); dg.renderOrder = 2;
  mesh(cyl(0.355, 0.355, 0.07), M.graphite, dirtyTank, [0, 1.2, -0.2]);
  const dirtyWater = mesh(cyl(0.31, 0.31, 0.3, 40), M.dirty, dirtyTank, [0, 1.38, -0.2]); dirtyWater.renderOrder = 1;
  mesh(cyl(0.085, 0.085, 0.62, 24), M.chrome, dirtyTank, [0, 1.6, -0.2]);

  // clean tank (step 1)
  const cleanTank = addPart(1, [-1.3, 0.1, 0.35], [-0.34, 2.45, 0.1]);
  const cg = mesh(cyl(0.34, 0.34, 0.9), M.glass, cleanTank, [0, 2.51, -0.2]); cg.renderOrder = 2;
  const cleanWater = mesh(cyl(0.31, 0.31, 0.62, 40), M.clean, cleanTank, [0, 2.38, -0.2]); cleanWater.renderOrder = 1;
  const bubbleCount = 26;
  const bubbles = new THREE.InstancedMesh(new THREE.SphereGeometry(0.022, 8, 6), new THREE.MeshBasicMaterial({ color: 0xeafffd, transparent: true, opacity: 0.8 }), bubbleCount);
  bubbles.renderOrder = 1;
  cleanTank.add(bubbles);
  const bubbleData = Array.from({ length: bubbleCount }, () => ({ a: Math.random() * Math.PI * 2, r: Math.random() * 0.25, y: Math.random(), s: 0.15 + Math.random() * 0.25 }));

  // DirtSense display (step 3)
  const display = addPart(3, [0, 0.5, 0.75], [0, 3.13, 0.05]);
  mesh(cyl(0.37, 0.37, 0.16), M.graphite, display, [0, 3.04, -0.2]);
  mesh(new THREE.TorusGeometry(0.305, 0.022, 12, 64), M.ring, display, [0, 3.12, -0.2], [Math.PI / 2, 0, 0]);
  mesh(new THREE.CircleGeometry(0.27, 48), new THREE.MeshBasicMaterial({ map: displayTex, toneMapped: false }), display, [0, 3.123, -0.2], [-Math.PI / 2, 0, 0]);

  // handle + battery (step 4)
  const handle = addPart(4, [0, 0.95, -0.15], [0, 3.55, 0.08]);
  mesh(cyl(0.085, 0.085, 1.35, 24), M.shell, handle, [0, 3.78, -0.2]);
  mesh(new RoundedBoxGeometry(0.34, 0.66, 0.28, 4, 0.1), M.graphite, handle, [0, 3.55, -0.2]);
  for (let i = 0; i < 4; i++) mesh(new THREE.BoxGeometry(0.16, 0.028, 0.012), M.accent, handle, [0, 3.38 + i * 0.07, -0.055]);
  const grip = new THREE.Group();
  grip.position.set(0, 4.45, -0.2); grip.rotation.x = -0.22;
  handle.add(grip);
  mesh(cyl(0.11, 0.1, 0.62, 24), M.rubber, grip, [0, 0.2, 0]);
  mesh(new THREE.SphereGeometry(0.115, 24, 12), M.shell, grip, [0, 0.52, 0]);
  mesh(new THREE.TorusGeometry(0.115, 0.018, 8, 40), M.accent, grip, [0, -0.1, 0], [Math.PI / 2, 0, 0]);
  mesh(new RoundedBoxGeometry(0.07, 0.14, 0.06, 2, 0.02), M.accent, grip, [0, 0.22, 0.1]);

  // floating water droplets around the product
  const dropCount = 18;
  const dropMat = new THREE.MeshPhysicalMaterial({ color: 0xbffcf6, roughness: 0, metalness: 0, transparent: true, opacity: 0.55, clearcoat: 1, emissive: 0x0b4a4a, emissiveIntensity: 0.4 });
  const drops = new THREE.InstancedMesh(new THREE.SphereGeometry(1, 20, 14), dropMat, dropCount);
  root.add(drops);
  const dropData = Array.from({ length: dropCount }, (_, i) => ({
    a: (i / dropCount) * Math.PI * 2 + Math.random() * 0.3,
    r: 2 + Math.random() * 1.3,
    y: -2 + Math.random() * 4.2,
    s: 0.04 + Math.random() * 0.07,
    sp: 0.05 + Math.random() * 0.1,
    ph: Math.random() * 6.28,
  }));

  /* ---------- markers (HTML overlay projected from 3D anchors) ---------- */
  const markers = parts.filter((p) => p.anchor).map((p) => {
    const el = document.createElement('span');
    el.className = 'marker';
    markersEl.appendChild(el);
    return { el, part: p };
  });

  /* ---------- layout & input ---------- */
  let W = 1, H = 1, mobile = false, halfH = 1, halfW = 1;
  const resize = () => {
    W = sticky.clientWidth; H = sticky.clientHeight;
    mobile = W < 861;
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, mobile ? 1.5 : 1.75));
    renderer.setSize(W, H, false);
    camera.aspect = W / H;
    camera.updateProjectionMatrix();
    halfH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * camera.position.z;
    halfW = halfH * camera.aspect;
  };
  resize();
  new ResizeObserver(resize).observe(sticky);

  const pointer = { x: 0, y: 0, tx: 0, ty: 0 };
  let dragging = false, dragX = 0, spinOffset = 0, spinVel = 0;
  addEventListener('pointermove', (e) => {
    pointer.tx = (e.clientX / innerWidth) * 2 - 1;
    pointer.ty = (e.clientY / innerHeight) * 2 - 1;
    if (dragging) {
      const dx = e.clientX - dragX;
      dragX = e.clientX;
      spinVel = dx * 0.006;
      spinOffset += spinVel;
    }
  }, { passive: true });
  wrap.addEventListener('pointerdown', (e) => {
    if (e.pointerType !== 'mouse' || e.button !== 0) return;
    if (e.target.closest('a, button, summary, .hero__copy, .anatomy__panel')) return;
    dragging = true; dragX = e.clientX; spinVel = 0;
    e.preventDefault();
  });
  addEventListener('pointerup', () => { dragging = false; });

  let visible = true;
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; if (visible) kick(); }).observe(wrap);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) kick(); });

  // rotation that presents each part to the camera during the anatomy scroll
  const stepPose = [
    { y: -0.35, x: 0.18 }, // roller
    { y: 0.75, x: 0.08 },  // clean tank (−x side)
    { y: -0.75, x: 0.08 }, // dirty tank (+x side)
    { y: 0.1, x: 0.42 },   // display on top
    { y: 0.35, x: 0.1 },   // handle / battery
  ];

  const tmp = new THREE.Vector3();
  const clock = new THREE.Clock();
  let raf = 0, first = true, t = 0, heroRot = 0;
  const cur = { x: 0, y: 0, s: 1, rx: 0, ry: 0, e: 0 };
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), sc = new THREE.Vector3();
  const ringRed = new THREE.Color(0xff5a5a), ringAqua = new THREE.Color(0x5ef0e0), ringTmp = new THREE.Color();

  function frame() {
    raf = 0;
    if (!visible || document.hidden) return;
    const dt = Math.min(clock.getDelta(), 0.05);
    const rm = reduce.matches;
    if (!rm) t += dt;
    const k = rm || first ? 1 : 1 - Math.pow(0.001, dt); // frame-rate independent smoothing

    // scroll progress
    const vh = innerHeight;
    const heroP = clamp(scrollY / Math.max(1, hero.offsetHeight));
    const ar = anatomy.getBoundingClientRect();
    const ap = clamp(-ar.top / Math.max(1, ar.height - vh));
    const inAnatomy = ar.top < vh * 0.5 && ar.bottom > vh * 0.5;
    const activeStep = Math.min(4, Math.floor(ap * 5 * 0.999));
    const h = smooth(0, 1, heroP);

    // layout targets (screen placement in world units)
    const heroL = mobile ? { x: 0, y: 0.5 * halfH, s: (0.6 * halfH) / 4.9 } : { x: 0.44 * halfW, y: -0.02 * halfH, s: Math.min(1, halfW / 5) };
    const anatL = mobile ? { x: 0, y: 0.3 * halfH, s: Math.min((0.9 * halfH) / 5.6, (1.7 * halfW) / 3.4) } : { x: 0.32 * halfW, y: -0.02 * halfH, s: 0.86 };
    cur.x = lerp(cur.x, lerp(heroL.x, anatL.x, h), k);
    cur.y = lerp(cur.y, lerp(heroL.y, anatL.y, h), k);
    cur.s = lerp(cur.s, lerp(heroL.s, anatL.s, h), k);
    root.position.set(cur.x, cur.y + (rm ? 0 : Math.sin(t * 1.1) * 0.05 * (1 - h)), 0);
    root.scale.setScalar(cur.s);

    // rotation
    pointer.x = lerp(pointer.x, pointer.tx, k * 0.6);
    pointer.y = lerp(pointer.y, pointer.ty, k * 0.6);
    if (!dragging) { spinOffset += spinVel; spinVel *= 0.93; }
    const sf = clamp(ap * 5 - 0.5, 0, 4);
    const i0 = Math.floor(sf), i1 = Math.min(4, i0 + 1), f = smooth(0, 1, sf - i0);
    const poseY = lerp(stepPose[i0].y, stepPose[i1].y, f);
    const poseX = lerp(stepPose[i0].x, stepPose[i1].x, f);
    heroRot = rm ? -0.5 : -0.5 + Math.sin(t * 0.35) * 0.35;
    const ty = lerp(heroRot, poseY, h) + pointer.x * 0.35 + spinOffset;
    const tx = lerp(0.06, poseX, h) + pointer.y * 0.12;
    cur.ry = lerp(cur.ry, ty, k * 0.8);
    cur.rx = lerp(cur.rx, tx, k * 0.8);
    spin.rotation.set(cur.rx, cur.ry, 0);

    // exploded view
    const eTarget = smooth(0.0, 0.07, ap) * (1 - smooth(0.93, 1, ap));
    cur.e = lerp(cur.e, eTarget, k);
    parts.forEach((p) => {
      const boost = inAnatomy && p.step === activeStep ? 1.3 : 1;
      tmp.copy(p.explode).multiplyScalar(cur.e * boost);
      p.g.position.lerp(tmp, k);
    });

    // live details
    rollerSpin.rotation.x -= dt * (rm ? 0 : 6 + cur.e * 6);
    const slosh = (pointer.tx - pointer.x) * 0.6;
    cleanWater.rotation.z = lerp(cleanWater.rotation.z, rm ? 0 : slosh * 0.3, 0.1);
    dirtyWater.rotation.z = cleanWater.rotation.z * 0.8;

    bubbleData.forEach((b, i) => {
      b.y = (b.y + (rm ? 0 : dt) * b.s) % 1;
      tmp.set(Math.cos(b.a + t) * b.r, 2.1 + b.y * 0.56, -0.2 + Math.sin(b.a + t) * b.r);
      m4.makeTranslation(tmp.x, tmp.y, tmp.z);
      bubbles.setMatrixAt(i, m4);
    });
    bubbles.instanceMatrix.needsUpdate = true;

    dropData.forEach((d, i) => {
      const a = d.a + t * d.sp;
      tmp.set(Math.cos(a) * d.r, d.y + Math.sin(t * 0.8 + d.ph) * 0.15, Math.sin(a) * d.r * 0.6 - 0.4);
      const sAlpha = 1 - h * 0.6;
      sc.set(d.s * sAlpha, d.s * 1.25 * sAlpha, d.s * sAlpha);
      m4.compose(tmp, q, sc);
      drops.setMatrixAt(i, m4);
    });
    drops.instanceMatrix.needsUpdate = true;

    // DirtSense ring: red → aqua sweep while its step is active
    const dirtT = inAnatomy && activeStep === 3 ? (Math.sin(t * 1.4) + 1) / 2 : 1;
    ringTmp.copy(ringRed).lerp(ringAqua, dirtT);
    M.ring.color.copy(ringTmp); M.ring.emissive.copy(ringTmp);
    drawDisplay(Math.round(lerp(34, 87, dirtT)), `#${ringTmp.getHexString()}`);

    renderer.render(scene, camera);

    // markers
    markers.forEach(({ el, part }) => {
      const on = inAnatomy && cur.e > 0.6 && part.step === activeStep;
      el.classList.toggle('is-on', on);
      if (on) {
        tmp.copy(part.anchor);
        part.g.localToWorld(tmp);
        tmp.project(camera);
        el.style.transform = `translate(${((tmp.x + 1) / 2) * W}px, ${((1 - tmp.y) / 2) * H}px)`;
      }
    });

    if (first) { first = false; stage.classList.add('is-ready'); }
    kick();
  }
  function kick() { if (!raf) raf = requestAnimationFrame(frame); }
  kick();
}
