/* FLOE's product is built from real, lit 3D geometry. Native WebGL keeps the
   complete experience local and removes a network dependency from the hero. */
(() => {
  'use strict';
  const canvas = document.querySelector('#product-canvas');
  const stage = document.querySelector('#product-stage');
  const hint = document.querySelector('#scene-hint');
  const rotateButton = document.querySelector('#rotate-product');
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const fallback = () => {
    stage.classList.remove('scene-ready');
    canvas.hidden = true;
    rotateButton.hidden = true;
  };
  let gl;
  try { gl = canvas.getContext('webgl', { alpha: true, antialias: true, powerPreference: 'low-power' }); }
  catch { fallback(); return; }
  if (!gl) { fallback(); return; }

  const vertexSource = `
    attribute vec3 aPosition;
    attribute vec3 aNormal;
    attribute vec3 aColor;
    uniform mat4 uModel;
    uniform mat4 uProjection;
    varying vec3 vNormal;
    varying vec3 vColor;
    varying vec3 vPosition;
    void main() {
      vec4 world = uModel * vec4(aPosition, 1.0);
      vPosition = world.xyz;
      vNormal = mat3(uModel) * aNormal;
      vColor = aColor;
      gl_Position = uProjection * vec4(world.xyz + vec3(0.0, 0.0, -9.4), 1.0);
    }`;
  const fragmentSource = `
    precision mediump float;
    varying vec3 vNormal;
    varying vec3 vColor;
    varying vec3 vPosition;
    void main() {
      vec3 normal = normalize(vNormal);
      vec3 key = normalize(vec3(-3.0, 6.0, 5.0));
      vec3 fill = normalize(vec3(4.0, 1.0, 2.0));
      vec3 eye = normalize(vec3(0.0, 0.0, 9.4) - vPosition);
      float diffuse = max(dot(normal, key), 0.0);
      float side = max(dot(normal, fill), 0.0);
      float specular = pow(max(dot(normal, normalize(key + eye)), 0.0), 55.0);
      float rim = pow(1.0 - max(dot(normal, eye), 0.0), 3.0);
      vec3 color = vColor * (0.46 + diffuse * 0.47 + side * 0.15);
      color += vec3(0.96, 1.0, 0.89) * specular * 0.28 + rim * 0.025;
      gl_FragColor = vec4(color, 1.0);
    }`;
  function shader(type, source) {
    const result = gl.createShader(type);
    gl.shaderSource(result, source); gl.compileShader(result);
    if (!gl.getShaderParameter(result, gl.COMPILE_STATUS)) throw new Error('Shader compilation unavailable');
    return result;
  }
  let program;
  try {
    program = gl.createProgram();
    gl.attachShader(program, shader(gl.VERTEX_SHADER, vertexSource));
    gl.attachShader(program, shader(gl.FRAGMENT_SHADER, fragmentSource));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error('WebGL linking unavailable');
    gl.useProgram(program);
  } catch { fallback(); return; }

  const vertices = [];
  const color = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255);
  const shell = color('#edf0e6');
  const edge = color('#c4ceba');
  const graphite = color('#303b32');
  const tank = color('#62725c');
  const metal = color('#b9c7ad');
  const lime = color('#cbe684');
  const rubber = color('#263028');
  function vertex(position, normal, tint) { vertices.push(...position, ...normal, ...tint); }
  function tri(a, b, c, tint) { for (const v of [a, b, c]) vertex(v.p, v.n, tint); }
  function normalize(v) { const length = Math.hypot(...v) || 1; return v.map(n => n / length); }

  // A rounded cuboid uses six subdivided faces projected onto a bevel radius.
  function box(center, dimensions, radius, tint) {
    const half = dimensions.map(n => n / 2);
    const inner = half.map(n => Math.max(0, n - radius));
    const steps = 10;
    for (let axis = 0; axis < 3; axis++) for (const sign of [-1, 1]) {
      const u = (axis + 1) % 3, v = (axis + 2) % 3;
      const point = (a, b) => {
        const p = [0, 0, 0];
        p[axis] = half[axis] * sign;
        p[u] = (a / steps * 2 - 1) * half[u];
        p[v] = (b / steps * 2 - 1) * half[v];
        const nearest = p.map((n, i) => Math.max(-inner[i], Math.min(inner[i], n)));
        const n = normalize(p.map((value, i) => value - nearest[i]));
        return { p: nearest.map((value, i) => value + n[i] * radius + center[i]), n };
      };
      for (let a = 0; a < steps; a++) for (let b = 0; b < steps; b++) {
        const p = [point(a, b), point(a + 1, b), point(a + 1, b + 1), point(a, b + 1)];
        tri(p[0], p[1], p[2], tint); tri(p[0], p[2], p[3], tint);
      }
    }
  }
  function cylinder(center, radius, length, tint, axis = 1, segments = 40) {
    const u = (axis + 1) % 3, v = (axis + 2) % 3;
    const point = (angle, side, cap = false) => {
      const p = [...center], n = [0, 0, 0];
      p[axis] += side * length / 2;
      p[u] += Math.cos(angle) * radius; p[v] += Math.sin(angle) * radius;
      if (cap) n[axis] = side; else { n[u] = Math.cos(angle); n[v] = Math.sin(angle); }
      return { p, n };
    };
    for (let i = 0; i < segments; i++) {
      const a = i / segments * Math.PI * 2, b = (i + 1) / segments * Math.PI * 2;
      tri(point(a, -1), point(b, -1), point(b, 1), tint);
      tri(point(a, -1), point(b, 1), point(a, 1), tint);
      for (const side of [-1, 1]) {
        const p = [...center], n = [0, 0, 0]; p[axis] += side * length / 2; n[axis] = side;
        tri({ p, n }, point(a, side, true), point(b, side, true), tint);
      }
    }
  }
  function ring(center, radius, thickness, tint) {
    const segments = 56, cross = 8;
    const point = (a, b) => {
      const n = [Math.cos(a) * Math.cos(b), Math.sin(a) * Math.cos(b), Math.sin(b)];
      return { p: [center[0] + (radius + thickness * Math.cos(b)) * Math.cos(a), center[1] + (radius + thickness * Math.cos(b)) * Math.sin(a), center[2] + thickness * Math.sin(b)], n };
    };
    for (let i = 0; i < segments; i++) for (let j = 0; j < cross; j++) {
      const a = i * 2 * Math.PI / segments, b = (i + 1) * 2 * Math.PI / segments;
      const c = j * 2 * Math.PI / cross, d = (j + 1) * 2 * Math.PI / cross;
      tri(point(a, c), point(b, c), point(b, d), tint); tri(point(a, c), point(b, d), point(a, d), tint);
    }
  }
  // Roller head, edge bumpers, and tread: these remain dimensional as it rotates.
  box([0, .19, .13], [1.58, .29, .91], .11, rubber);
  box([0, .33, .09], [1.63, .31, .95], .13, shell);
  box([0, .31, .53], [1.42, .22, .13], .045, graphite);
  cylinder([0, .285, .585], .092, 1.28, lime, 0, 48);
  for (let i = 0; i < 33; i++) cylinder([-.62 + i * .039, .285, .585], .094, .008, color('#a6bd77'), 0, 16);
  box([0, .16, .62], [1.45, .045, .085], .017, edge);
  for (const x of [-.71, .71]) cylinder([x, .195, -.17], .16, .13, rubber, 0);
  box([0, .5, -.15], [.36, .37, .39], .11, graphite);
  cylinder([0, .48, -.14], .16, .44, metal, 0);
  // Spine, back clean-water reservoir, front dirty-water reservoir.
  box([0, 1.47, -.15], [.43, 1.91, .46], .19, graphite);
  box([0, 1.77, -.2], [.53, 1.46, .48], .18, edge);
  box([0, 1.86, -.3], [.43, 1.13, .28], .12, shell);
  box([0, 1.45, .08], [.71, 1.67, .58], .24, shell);
  box([0, 1.34, .29], [.58, 1.17, .31], .18, tank);
  box([-.208, 1.38, .433], [.025, .79, .025], .009, color('#99aa8c'));
  box([0, .88, .383], [.34, .055, .14], .02, graphite);
  box([0, 1.86, .351], [.48, .045, .125], .018, edge);
  box([0, 1.73, -.415], [.2, .05, .06], .017, graphite);
  // Circular power display with a lit battery glyph.
  cylinder([0, 2.04, .325], .176, .034, rubber, 2, 56);
  ring([0, 2.04, .348], .137, .009, lime);
  box([0, 2.04, .35], [.11, .061, .016], .007, lime);
  box([.06, 2.04, .352], [.013, .03, .016], .004, lime);
  // Metal wand and a softly rounded, open loop grip.
  cylinder([0, 3.21, -.14], .077, 2.04, metal);
  cylinder([0, 2.44, -.14], .098, .12, graphite);
  box([0, 4.3, -.14], [.18, .5, .19], .075, graphite);
  box([.02, 4.86, -.14], [.21, .69, .23], .10, graphite);
  box([.24, 5.16, -.14], [.57, .22, .23], .105, graphite);
  box([.46, 4.86, -.14], [.18, .69, .23], .085, graphite);
  box([.25, 4.53, -.14], [.53, .20, .23], .09, graphite);
  box([.02, 4.59, -.004], [.085, .17, .035], .032, lime);
  box([.13, 5.229, -.025], [.27, .018, .014], .006, color('#7e8c73'));
  // Discrete product badge, integrated into the front shell.
  box([0, 2.29, .158], [.22, .024, .023], .008, color('#738567'));
  box([0, 2.255, .184], [.12, .015, .019], .005, color('#9bac8e'));

  const data = new Float32Array(vertices);
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer); gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
  for (const [name, offset] of [['aPosition', 0], ['aNormal', 12], ['aColor', 24]]) {
    const attribute = gl.getAttribLocation(program, name);
    gl.enableVertexAttribArray(attribute); gl.vertexAttribPointer(attribute, 3, gl.FLOAT, false, 36, offset);
  }
  const modelLocation = gl.getUniformLocation(program, 'uModel');
  const projectionLocation = gl.getUniformLocation(program, 'uProjection');
  gl.enable(gl.DEPTH_TEST); gl.clearColor(0, 0, 0, 0);

  const identity = () => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  function multiply(a, b) {
    const out = new Array(16).fill(0);
    for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) for (let k = 0; k < 4; k++) out[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
    return out;
  }
  function rotation(axis, angle) {
    const m = identity(), c = Math.cos(angle), s = Math.sin(angle);
    if (axis === 0) { m[5] = c; m[6] = s; m[9] = -s; m[10] = c; }
    if (axis === 1) { m[0] = c; m[2] = -s; m[8] = s; m[10] = c; }
    if (axis === 2) { m[0] = c; m[1] = s; m[4] = -s; m[5] = c; }
    return m;
  }
  let targetRotation = -.37, currentRotation = -.37, pointerTilt = 0;
  let targetTilt = 0, scrollTilt = 0, visible = true, raf = 0, lost = false;
  function draw() {
    raf = 0;
    if (!visible || lost || document.hidden) return;
    currentRotation += (targetRotation - currentRotation) * .12;
    pointerTilt += (targetTilt - pointerTilt) * .12;
    const move = identity(); move[13] = -2.69;
    const model = multiply(rotation(2, -.20 + pointerTilt), multiply(rotation(0, .1 + scrollTilt), multiply(rotation(1, currentRotation), move)));
    const aspect = canvas.width / canvas.height;
    const f = 1 / Math.tan(35 * Math.PI / 360), near = .1, far = 50;
    const projection = [f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) / (near - far), -1, 0, 0, 2 * far * near / (near - far), 0];
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.uniformMatrix4fv(modelLocation, false, model); gl.uniformMatrix4fv(projectionLocation, false, projection);
    gl.drawArrays(gl.TRIANGLES, 0, data.length / 9);
    if (Math.abs(targetRotation - currentRotation) > .001 || Math.abs(targetTilt - pointerTilt) > .001) schedule();
  }
  function schedule() { if (!raf && visible && !lost) raf = requestAnimationFrame(draw); }
  function resize() {
    const bounds = canvas.getBoundingClientRect();
    const ratio = Math.min(devicePixelRatio || 1, 1.75);
    canvas.width = Math.max(1, Math.round(bounds.width * ratio)); canvas.height = Math.max(1, Math.round(bounds.height * ratio));
    schedule();
  }
  new ResizeObserver(resize).observe(canvas);
  new IntersectionObserver(entries => { visible = entries[0].isIntersecting; if (visible) schedule(); }, { rootMargin: '80px' }).observe(stage);
  let dragging = false, startX = 0, startRotation = 0;
  canvas.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    dragging = true; startX = event.clientX; startRotation = targetRotation;
    canvas.setPointerCapture(event.pointerId);
  });
  canvas.addEventListener('pointermove', event => {
    if (dragging) {
      targetRotation = startRotation + (event.clientX - startX) * .009;
      hint.textContent = 'Looking good from every angle';
    } else if (!reducedMotion.matches && event.pointerType !== 'touch') {
      const rect = canvas.getBoundingClientRect();
      targetTilt = ((event.clientX - rect.left) / rect.width - .5) * .09;
    }
    if (reducedMotion.matches) currentRotation = targetRotation;
    schedule();
  });
  const endDrag = () => { dragging = false; };
  canvas.addEventListener('pointerup', endDrag); canvas.addEventListener('pointercancel', endDrag); canvas.addEventListener('lostpointercapture', endDrag);
  canvas.addEventListener('pointerleave', () => { targetTilt = 0; schedule(); });
  function rotate(amount) { targetRotation += amount; if (reducedMotion.matches) currentRotation = targetRotation; schedule(); }
  canvas.addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') { event.preventDefault(); rotate(event.key === 'ArrowLeft' ? -.3 : .3); }
    if (event.key === 'Home') { event.preventDefault(); targetRotation = -.37; if (reducedMotion.matches) currentRotation = targetRotation; schedule(); }
  });
  rotateButton.addEventListener('click', () => { rotate(Math.PI / 2); hint.textContent = 'Click to see another side'; });
  window.addEventListener('scroll', () => { if (reducedMotion.matches || !visible) return; scrollTilt = Math.min(scrollY / innerHeight, 1) * .09; schedule(); }, { passive: true });
  document.addEventListener('visibilitychange', () => { if (!document.hidden) schedule(); });
  reducedMotion.addEventListener('change', () => { targetTilt = 0; scrollTilt = 0; currentRotation = targetRotation; schedule(); });
  canvas.addEventListener('webglcontextlost', event => { event.preventDefault(); lost = true; fallback(); });
  stage.classList.add('scene-ready');
  resize();
})();
