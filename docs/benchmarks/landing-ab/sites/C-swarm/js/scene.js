// Procedural 3D model of the Tidewell Glide 3, built from primitives with three.js.
// Reacts to pointer (orbit/tilt) and hero scroll progress (spin-up, exploded tanks, lay-flat).
import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;

function stripeTexture() {
  const c = document.createElement("canvas");
  c.width = 256; c.height = 64;
  const g = c.getContext("2d");
  g.fillStyle = "#1fb4dd"; g.fillRect(0, 0, 256, 64);
  for (let i = 0; i < 16; i++) {
    g.fillStyle = i % 2 ? "#63dcfa" : "#0f93bd";
    g.fillRect(i * 16, 0, 8, 64);
  }
  // Fibre noise for a fabric roller feel
  for (let i = 0; i < 1400; i++) {
    g.fillStyle = `rgba(255,255,255,${Math.random() * 0.18})`;
    g.fillRect(Math.random() * 256, Math.random() * 64, 1, 3);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(2, 1);
  return t;
}

function screenTexture() {
  const c = document.createElement("canvas");
  c.width = c.height = 256;
  const g = c.getContext("2d");
  const draw = (pct, mode) => {
    g.fillStyle = "#031320"; g.fillRect(0, 0, 256, 256);
    g.strokeStyle = "#2fc6ec"; g.lineWidth = 14; g.lineCap = "round";
    g.beginPath(); g.arc(128, 128, 96, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * pct); g.stroke();
    g.fillStyle = "#e9f7fc"; g.font = "700 72px sans-serif"; g.textAlign = "center"; g.textBaseline = "middle";
    g.fillText(String(Math.round(pct * 100)), 128, 118);
    g.font = "600 28px sans-serif"; g.fillStyle = "#7ce8ff";
    g.fillText(mode, 128, 172);
  };
  draw(1, "AUTO");
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return { texture: t, draw };
}

function glowTexture() {
  const c = document.createElement("canvas");
  c.width = c.height = 128;
  const g = c.getContext("2d");
  const grad = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  grad.addColorStop(0, "rgba(0,0,0,0.55)");
  grad.addColorStop(1, "rgba(0,0,0,0)");
  g.fillStyle = grad; g.fillRect(0, 0, 128, 128);
  return new THREE.CanvasTexture(c);
}

function dropletSprite() {
  const c = document.createElement("canvas");
  c.width = c.height = 64;
  const g = c.getContext("2d");
  const grad = g.createRadialGradient(28, 26, 2, 32, 32, 30);
  grad.addColorStop(0, "rgba(255,255,255,1)");
  grad.addColorStop(0.35, "rgba(124,232,255,0.9)");
  grad.addColorStop(1, "rgba(47,198,236,0)");
  g.fillStyle = grad; g.beginPath(); g.arc(32, 32, 30, 0, Math.PI * 2); g.fill();
  return new THREE.CanvasTexture(c);
}

export function createScene(canvas, state) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.75));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(renderer), 0.04).texture;
  pmrem.dispose();

  const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 100);
  camera.position.set(0, 1.9, 9);

  // Lights
  scene.add(new THREE.HemisphereLight(0xcff4ff, 0x06223a, 0.6));
  const key = new THREE.DirectionalLight(0xffffff, 1.6);
  key.position.set(3, 5, 4);
  scene.add(key);
  const rim = new THREE.PointLight(0x2fc6ec, 30, 12);
  rim.position.set(-2.5, 2.5, -2);
  scene.add(rim);
  const warm = new THREE.PointLight(0xffb547, 10, 10);
  warm.position.set(2.5, 0.6, 2);
  scene.add(warm);

  // Materials
  const pearl = new THREE.MeshPhysicalMaterial({ color: 0xf2f8fb, roughness: 0.28, metalness: 0.05, clearcoat: 1, clearcoatRoughness: 0.15 });
  const graphite = new THREE.MeshStandardMaterial({ color: 0x0d2233, roughness: 0.35, metalness: 0.7 });
  const accent = new THREE.MeshStandardMaterial({ color: 0x2fc6ec, roughness: 0.3, metalness: 0.2, emissive: 0x0a4f68, emissiveIntensity: 0.4 });
  const glass = new THREE.MeshPhysicalMaterial({ color: 0xcff4ff, roughness: 0.05, metalness: 0, transparent: true, opacity: 0.28, clearcoat: 1, side: THREE.DoubleSide, depthWrite: false });
  const waterClean = new THREE.MeshStandardMaterial({ color: 0x2fc6ec, roughness: 0.1, transparent: true, opacity: 0.8, emissive: 0x0b6f96, emissiveIntensity: 0.35 });
  const waterDirty = new THREE.MeshStandardMaterial({ color: 0x8a7a5a, roughness: 0.3, transparent: true, opacity: 0.75 });
  const led = new THREE.MeshStandardMaterial({ color: 0x2fc6ec, emissive: 0x2fc6ec, emissiveIntensity: 2.2 });
  const rollerTex = stripeTexture();
  const rollerMat = new THREE.MeshStandardMaterial({ map: rollerTex, roughness: 0.85 });

  // ---- Model hierarchy ----
  const root = new THREE.Group();     // positioned in the layout
  const tilt = new THREE.Group();     // pointer tilt + scroll spin
  root.add(tilt);
  scene.add(root);

  // Head (floor unit)
  const head = new THREE.Group();
  tilt.add(head);
  const headBody = new THREE.Mesh(new RoundedBoxGeometry(1.7, 0.3, 0.72, 5, 0.12), pearl);
  headBody.position.set(0, 0.2, -0.05);
  head.add(headBody);
  const visor = new THREE.Mesh(new RoundedBoxGeometry(1.5, 0.12, 0.5, 4, 0.05), graphite);
  visor.position.set(0, 0.36, -0.08);
  head.add(visor);
  const rollerGroup = new THREE.Group();
  rollerGroup.position.set(0, 0.17, 0.33);
  const roller = new THREE.Mesh(new THREE.CylinderGeometry(0.17, 0.17, 1.64, 40, 1), rollerMat);
  roller.rotation.z = Math.PI / 2;
  rollerGroup.add(roller);
  const hood = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 1.68, 32, 1, true, Math.PI * 0.95, Math.PI * 0.9), glass);
  hood.rotation.z = Math.PI / 2;
  rollerGroup.add(hood);
  head.add(rollerGroup);
  // Headlight strip
  const lightStrip = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.025, 0.02), led);
  lightStrip.position.set(0, 0.3, 0.52);
  head.add(lightStrip);

  // Neck joint + upper assembly (pivots for lay-flat)
  const neck = new THREE.Group();
  neck.position.set(0, 0.34, -0.1);
  tilt.add(neck);
  const joint = new THREE.Mesh(new THREE.SphereGeometry(0.17, 32, 16), graphite);
  neck.add(joint);

  const body = new THREE.Group();
  neck.add(body);
  const shell = new THREE.Mesh(new THREE.CapsuleGeometry(0.3, 0.95, 8, 32), pearl);
  shell.position.set(0, 0.85, -0.05);
  body.add(shell);

  // Clean-water tank (back) — separates backwards in exploded view
  const cleanTank = new THREE.Group();
  cleanTank.position.set(0, 0.95, -0.28);
  const cleanShell = new THREE.Mesh(new THREE.CapsuleGeometry(0.2, 0.55, 6, 24), glass);
  const cleanWater = new THREE.Mesh(new THREE.CapsuleGeometry(0.17, 0.4, 6, 24), waterClean);
  cleanWater.position.y = -0.05;
  cleanTank.add(cleanShell, cleanWater);
  body.add(cleanTank);

  // Dirty-water tank (front) — separates forwards
  const dirtyTank = new THREE.Group();
  dirtyTank.position.set(0, 0.62, 0.2);
  const dirtyShell = new THREE.Mesh(new THREE.CylinderGeometry(0.26, 0.24, 0.62, 32), glass);
  const dirtyWater = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.21, 0.22, 32), waterDirty);
  dirtyWater.position.y = -0.18;
  const dirtyCap = new THREE.Mesh(new THREE.CylinderGeometry(0.27, 0.27, 0.06, 32), graphite);
  dirtyCap.position.y = 0.33;
  dirtyTank.add(dirtyShell, dirtyWater, dirtyCap);
  body.add(dirtyTank);

  // LED ring + screen
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.025, 12, 48), led);
  ring.position.set(0, 1.3, 0.265);
  body.add(ring);
  const scr = screenTexture();
  const screen = new THREE.Mesh(new THREE.CircleGeometry(0.17, 40), new THREE.MeshBasicMaterial({ map: scr.texture, toneMapped: false }));
  screen.position.set(0, 1.3, 0.262);
  body.add(screen);

  // Stick + handle
  const stick = new THREE.Mesh(new THREE.CylinderGeometry(0.055, 0.055, 1.35, 20), graphite);
  stick.position.set(0, 2.25, -0.05);
  body.add(stick);
  const collar = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.12, 0.14, 24), accent);
  collar.position.set(0, 1.6, -0.05);
  body.add(collar);
  const handle = new THREE.Mesh(new THREE.TorusGeometry(0.22, 0.05, 16, 40, Math.PI * 1.25), pearl);
  handle.position.set(0, 3.02, -0.05);
  handle.rotation.z = -Math.PI * 0.125;
  body.add(handle);
  const grip = new THREE.Mesh(new THREE.CapsuleGeometry(0.065, 0.3, 6, 16), graphite);
  grip.position.set(0, 3.12, -0.05);
  grip.rotation.z = Math.PI / 2;
  body.add(grip);
  const trigger = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.14, 0.08), accent);
  trigger.position.set(0.12, 2.94, -0.05);
  body.add(trigger);

  // Floor: contact shadow + a wet sheen trail
  const shadow = new THREE.Mesh(new THREE.PlaneGeometry(3.4, 1.8), new THREE.MeshBasicMaterial({ map: glowTexture(), transparent: true, depthWrite: false }));
  shadow.rotation.x = -Math.PI / 2;
  shadow.position.y = 0.002;
  tilt.add(shadow);
  const trailMat = new THREE.MeshBasicMaterial({ color: 0x7ce8ff, transparent: true, opacity: 0.12, depthWrite: false });
  const trail = new THREE.Mesh(new THREE.PlaneGeometry(1.7, 4), trailMat);
  trail.rotation.x = -Math.PI / 2;
  trail.position.set(0, 0.001, -2.1);
  tilt.add(trail);

  // Floating water droplets
  const COUNT = 90;
  const pos = new Float32Array(COUNT * 3);
  const seeds = new Float32Array(COUNT);
  for (let i = 0; i < COUNT; i++) {
    pos[i * 3] = (Math.random() - 0.5) * 5;
    pos[i * 3 + 1] = Math.random() * 3.6;
    pos[i * 3 + 2] = (Math.random() - 0.5) * 3;
    seeds[i] = Math.random() * Math.PI * 2;
  }
  const dropsGeo = new THREE.BufferGeometry();
  dropsGeo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  const drops = new THREE.Points(dropsGeo, new THREE.PointsMaterial({ size: 0.09, map: dropletSprite(), transparent: true, depthWrite: false, opacity: 0.8 }));
  root.add(drops);

  // ---- Layout / resize ----
  let w = 1, h = 1, mobile = false;
  function resize() {
    const r = canvas.getBoundingClientRect();
    w = Math.max(1, r.width); h = Math.max(1, r.height);
    mobile = w < 860;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.fov = mobile ? 40 : 32;
    camera.updateProjectionMatrix();
  }
  resize();
  window.addEventListener("resize", resize);

  // ---- Animation ----
  const clock = new THREE.Clock();
  const cur = { rx: 0, ry: 0, p: 0 };
  const ledColor = new THREE.Color();
  const dirty = new THREE.Color(0xff5f6b);
  const clean = new THREE.Color(0x2fc6ec);
  let lastPct = -1;
  let running = false;
  let raf = 0;

  function frame() {
    raf = requestAnimationFrame(frame);
    const dt = Math.min(clock.getDelta(), 0.05);
    const t = clock.elapsedTime;
    const k = 1 - Math.pow(0.001, dt); // frame-rate independent easing
    cur.rx = lerp(cur.rx, state.pointerY * 0.18, k);
    cur.ry = lerp(cur.ry, state.pointerX * 0.55, k);
    cur.p = lerp(cur.p, state.progress, state.reduced ? 1 : k * 1.4);
    const p = cur.p;

    // Chapter weights: 0 suction, 1 tanks, 2 lay-flat
    const explode = smooth(0.3, 0.45, p) * (1 - smooth(0.6, 0.72, p));
    const flat = smooth(0.68, 0.9, p);
    const idle = state.reduced ? 0 : Math.sin(t * 0.5) * 0.12;

    // Layout: right side on desktop, centered below copy on mobile
    const s = mobile ? 0.62 : 1;
    root.scale.setScalar(s);
    root.position.set(mobile ? flat * 0.8 : lerp(1.55, 1.3, flat), mobile ? lerp(-1.95, -1.6, flat) : -1.55, 0);

    // Front three-quarter → side view (tanks) → full profile (lay-flat)
    const turn = -0.5 + smooth(0, 0.3, p) * 0.4 + smooth(0.3, 0.45, p) * 1.4 + smooth(0.68, 0.9, p) * 0.25;
    tilt.rotation.y = turn + cur.ry + idle;
    tilt.rotation.x = cur.rx + 0.08;

    neck.rotation.x = -flat * 1.35;
    neck.position.z = -0.1 - flat * 0.1;
    cleanTank.position.z = -0.28 - explode * 0.75;
    cleanTank.position.y = 0.95 + explode * 0.15;
    dirtyTank.position.z = 0.2 + explode * 0.8;
    dirtyTank.position.y = 0.62 - explode * 0.05;

    // Roller spins faster in the suction chapter
    const spin = (state.reduced ? 0.4 : 2) + (1 - smooth(0.25, 0.35, p)) * 6;
    rollerTex.offset.x -= dt * spin * 0.3;
    roller.rotation.x += dt * spin;

    // Water sloshes
    const slosh = state.reduced ? 0 : Math.sin(t * 2.2) * 0.08;
    cleanWater.rotation.z = slosh;
    dirtyWater.rotation.z = -slosh;
    dirtyWater.scale.y = 1 + explode * 0.6;

    // LED turns from red (dirty) to blue (clean) as you scroll
    ledColor.copy(dirty).lerp(clean, smooth(0.05, 0.4, p));
    led.color.copy(ledColor); led.emissive.copy(ledColor);
    const pct = Math.round(lerp(100, 72, p) );
    if (pct !== lastPct) { scr.draw(pct / 100, p < 0.33 ? "MAX" : p < 0.66 ? "AUTO" : "ECO"); scr.texture.needsUpdate = true; lastPct = pct; }

    trailMat.opacity = 0.08 + Math.sin(t * 1.5) * 0.03;

    const arr = dropsGeo.attributes.position.array;
    if (!state.reduced) {
      for (let i = 0; i < COUNT; i++) {
        arr[i * 3 + 1] += dt * (0.12 + (seeds[i] % 1) * 0.15);
        arr[i * 3] += Math.sin(t + seeds[i]) * dt * 0.05;
        if (arr[i * 3 + 1] > 3.8) arr[i * 3 + 1] = 0;
      }
      dropsGeo.attributes.position.needsUpdate = true;
    }

    camera.position.x = cur.ry * 0.6;
    camera.position.y = 1.9 + cur.rx * 1.5 - flat * 0.3;
    camera.lookAt(mobile ? 0 : 0.2, mobile ? -0.2 : 0.1, 0);

    renderer.render(scene, camera);
  }

  function start() { if (!running) { running = true; clock.getDelta(); frame(); } }
  function stop() { running = false; cancelAnimationFrame(raf); }

  // Only render when visible
  const io = new IntersectionObserver(([e]) => (e.isIntersecting && !document.hidden ? start() : stop()), { threshold: 0 });
  io.observe(canvas);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stop();
    else if (canvas.getBoundingClientRect().bottom > 0) start();
  });

  renderer.render(scene, camera);
  return { start, stop };
}
