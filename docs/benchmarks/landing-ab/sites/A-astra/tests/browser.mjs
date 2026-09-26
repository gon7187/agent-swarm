// Run with Node 22+ and Chromium. No packages, build, or web server required.
// CHROME=/path/to/chrome node tests/browser.mjs
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const profile = mkdtempSync(fileURLToPath(new URL('./.browser-', import.meta.url)));
const browser = spawn(process.env.CHROME || 'chromium', [
  '--headless', '--no-sandbox', '--disable-dev-shm-usage', '--no-first-run',
  '--no-default-browser-check', '--disable-background-networking',
  '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
  '--remote-debugging-pipe', `--user-data-dir=${profile}`,
], { stdio: ['ignore', 'ignore', 'pipe', 'pipe', 'pipe'] });
let sequence = 0, pendingData = '', browserLog = '', exited = false;
const pending = new Map(), errors = [];
browser.stderr.on('data', chunk => { browserLog += chunk.toString(); });
function failPending(error) { exited = true; for (const p of pending.values()) { clearTimeout(p.timer); p.reject(error); } pending.clear(); }
browser.on('error', failPending);
for (const stream of browser.stdio.filter(Boolean)) stream.on('error', error => failPending(new Error(`${error.message}. ${browserLog.slice(-1500)}`)));
browser.on('exit', code => failPending(new Error(`Chromium exited (${code}): ${browserLog.slice(-1500)}`)));
browser.stdio[4].on('data', chunk => {
  pendingData += chunk.toString();
  let end;
  while ((end = pendingData.indexOf('\0')) !== -1) {
    const message = JSON.parse(pendingData.slice(0, end)); pendingData = pendingData.slice(end + 1);
    if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails.text);
    if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') errors.push(message.params.entry.text);
    if (message.method === 'Runtime.consoleAPICalled' && message.params.type === 'error') errors.push('console.error');
    const request = pending.get(message.id);
    if (request) {
      clearTimeout(request.timer); pending.delete(message.id);
      if (message.error) request.reject(new Error(JSON.stringify(message.error))); else request.resolve(message.result);
    }
  }
});
function call(method, params = {}, sessionId) {
  return new Promise((resolve, reject) => {
    if (exited) { reject(new Error(`Browser unavailable: ${browserLog.slice(-1500)}`)); return; }
    const id = ++sequence;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 15000);
    pending.set(id, { resolve, reject, timer });
    browser.stdio[3].write(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }) + '\0');
  });
}
try {
  const { targetId } = await call('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await call('Target.attachToTarget', { targetId, flatten: true });
  const cdp = (method, params) => call(method, params, sessionId);
  await cdp('Runtime.enable'); await cdp('Log.enable'); await cdp('Page.enable');
  const evaluate = async expression => {
    const result = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    assert(!result.exceptionDetails, JSON.stringify(result.exceptionDetails));
    return result.result.value;
  };
  for (const width of [375, 768, 1440, 1920]) {
    await cdp('Emulation.setDeviceMetricsOverride', { width, height: 1000, deviceScaleFactor: 1, mobile: false });
    await cdp('Page.navigate', { url: process.env.TEST_URL || new URL('../index.html', import.meta.url).href });
    await evaluate(`new Promise(resolve => { const check = () => document.readyState === 'complete' && document.querySelector('#product-stage')?.classList.contains('scene-ready') ? resolve(true) : setTimeout(check, 30); check(); })`);
    assert(await evaluate('document.documentElement.scrollWidth <= innerWidth'), `Horizontal overflow at ${width}px`);
    assert(await evaluate("[...document.images].every(image => image.loading === 'lazy' || (image.complete && image.naturalWidth > 0))"), 'Image failed');
    assert(await evaluate("document.querySelector('#product-canvas').width > 0"));
    assert(await evaluate("!!document.querySelector('#product-canvas').getContext('webgl')"));
    assert(await evaluate("document.querySelector('#product-canvas').getContext('webgl').getError() === 0"));
    console.log(`PASS: ${width}px — no overflow, first-paint images loaded, live WebGL without GPU errors`);
  }
  await evaluate("document.querySelector('#buy-button').click()");
  assert(await evaluate("document.querySelector('#order-dialog').open"));
  await cdp('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
  await cdp('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
  assert(await evaluate("!document.querySelector('#order-dialog').open"));
  await evaluate("document.querySelector('summary').click()");
  assert(await evaluate("document.querySelector('details').open"));
  await evaluate("const slider = document.querySelector('#clean-slider'); slider.value = 80; slider.dispatchEvent(new Event('input')); ");
  assert.equal(await evaluate("document.querySelector('#clean-slider').getAttribute('aria-valuetext')"), '20 percent clean');
  await cdp('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
  assert.equal(await evaluate("getComputedStyle(document.documentElement).scrollBehavior"), 'auto');
  assert.deepEqual(errors, [], 'No browser console errors');
  console.log('PASS: offer dialog, Escape dismissal, FAQ, slider, reduced-motion CSS, no browser errors');
} catch (error) {
  console.error(error.message); process.exitCode = 1;
} finally {
  browser.kill();
  await new Promise(resolve => exited ? resolve() : browser.once('exit', resolve));
  rmSync(profile, { recursive: true, force: true });
}
