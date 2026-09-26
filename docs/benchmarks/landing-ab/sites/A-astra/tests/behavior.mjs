// Dependency-free behavioral checks. These exercise real site scripts against
// a minimal DOM/WebGL boundary; browser layout and GPU compilation are separate.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const root = new URL('../', import.meta.url);
class Element {
  handlers = {}; classes = new Set(); attrs = {}; hidden = false;
  style = { setProperty: (key, value) => { this.style[key] = value; } };
  classList = {
    add: name => this.classes.add(name), remove: name => this.classes.delete(name),
    toggle: (name, enabled) => enabled ? this.classes.add(name) : this.classes.delete(name),
  };
  addEventListener(type, callback) { (this.handlers[type] ??= []).push(callback); }
  fire(type, event = {}) { for (const callback of this.handlers[type] ?? []) callback({ target: this, ...event }); }
  setAttribute(key, value) { this.attrs[key] = value; }
  getBoundingClientRect() { return { width: 600, height: 780, left: 0, top: 0, right: 600, bottom: 780 }; }
  setPointerCapture() {}
  focus() { this.focused = true; }
  closest() { return null; }
}
function environment({ webgl = true, reduced = false } = {}) {
  const elements = new Map();
  const element = selector => {
    if (!elements.has(selector)) elements.set(selector, new Element());
    return elements.get(selector);
  };
  const document = new Element();
  document.body = new Element(); document.documentElement = new Element();
  document.querySelector = element;
  document.querySelectorAll = () => [];
  const window = new Element();
  const media = new Element(); media.matches = reduced;
  const queue = [];
  let buffer; let count = 0; const matrices = [];
  const gl = new Proxy({
    getShaderParameter: () => true, getProgramParameter: () => true,
    createShader: () => ({}), createProgram: () => ({}), createBuffer: () => ({}),
    getAttribLocation: () => 0, getUniformLocation: (_, name) => name,
    bufferData: (_, data) => { buffer = data; },
    uniformMatrix4fv: (_, __, values) => matrices.push(values),
    drawArrays: (_, __, value) => { count = value; },
  }, { get(target, key) { return target[key] ?? (key.toUpperCase() === key ? 1 : () => {}); } });
  element('#product-canvas').getContext = () => webgl ? gl : null;
  const dialog = element('#order-dialog');
  const dismiss = new Element();
  dialog.querySelectorAll = () => [dismiss];
  dialog.showModal = () => { dialog.open = true; };
  dialog.close = () => { dialog.open = false; dialog.fire('close'); };
  const context = vm.createContext({
    document, window, matchMedia: () => media,
    requestAnimationFrame: callback => { queue.push(callback); return queue.length; },
    ResizeObserver: class { constructor(callback) { this.callback = callback; } observe() { this.callback(); } },
    IntersectionObserver: class { observe() {} unobserve() {} },
    devicePixelRatio: 2, scrollY: 0, innerHeight: 900,
    Float32Array, Math, console,
  });
  const flush = () => { let n = 0; while (queue.length && n++ < 200) queue.shift()(); assert(n < 200, 'Render loop must settle'); };
  return { element, document, context, flush, dismiss, media, matrices, get buffer() { return buffer; }, get count() { return count; } };
}
const scene = readFileSync(new URL('scene.js', root), 'utf8');
const env = environment();
vm.runInContext(scene, env.context); env.flush();
assert(env.element('#product-stage').classes.has('scene-ready'));
assert(env.count > 10000, 'Product must have substantive 3D geometry');
assert.equal(env.buffer.length, env.count * 9);
for (let i = 0; i < env.buffer.length; i += 9) {
  const vertex = env.buffer.subarray(i, i + 9);
  assert(vertex.every(Number.isFinite), 'All vertex attributes finite');
  assert(Math.abs(Math.hypot(...vertex.subarray(3, 6)) - 1) < .0001, 'Normals normalized');
  assert(vertex.subarray(6).every(value => value >= 0 && value <= 1), 'Colors in range');
}
assert(env.matrices.every(matrix => matrix.length === 16 && matrix.every(Number.isFinite)));
const first = [...env.matrices.at(-2)];
env.element('#product-canvas').fire('keydown', { key: 'ArrowRight', preventDefault() {} }); env.flush();
assert.notDeepEqual(env.matrices.at(-2), first, 'Keyboard rotates actual model matrix');
const second = [...env.matrices.at(-2)];
env.element('#product-canvas').fire('pointerdown', { button: 0, clientX: 200, pointerId: 1 });
env.element('#product-canvas').fire('pointermove', { clientX: 290, pointerType: 'mouse' });
env.element('#product-canvas').fire('pointerup'); env.flush();
assert.notDeepEqual(env.matrices.at(-2), second, 'Pointer drag rotates actual model matrix');
env.element('#product-canvas').fire('webglcontextlost', { preventDefault() {} });
assert(env.element('#product-canvas').hidden, 'Context loss restores static fallback');
const unsupported = environment({ webgl: false }); vm.runInContext(scene, unsupported.context);
assert(unsupported.element('#product-canvas').hidden);
assert(unsupported.element('#rotate-product').hidden);
const reduced = environment({ reduced: true }); vm.runInContext(scene, reduced.context); reduced.flush();
reduced.element('#rotate-product').fire('click'); reduced.flush();
assert.equal(reduced.matrices.length, 4, 'Reduced-motion button renders one new frame');

const app = readFileSync(new URL('app.js', root), 'utf8');
const ui = environment(); vm.runInContext(app, ui.context);
const slider = ui.element('#clean-slider');
slider.value = '80'; slider.fire('input');
assert.equal(ui.element('#comparison').style['--clean'], '80%');
assert.equal(slider.attrs['aria-valuetext'], '20 percent clean');
ui.element('#buy-button').fire('click');
assert(ui.element('#order-dialog').open);
ui.dismiss.fire('click');
assert.equal(ui.element('#order-dialog').open, false);
assert(ui.element('#buy-button').focused, 'Closing dialog restores trigger focus');
console.log(`PASS: ${env.count.toLocaleString()} valid 3D vertices, finite matrices, keyboard/drag rotation, reduced motion, WebGL fallback, slider semantics, offer dialog and focus restoration`);
