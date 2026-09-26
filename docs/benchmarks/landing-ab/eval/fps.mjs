import { createRequire } from 'module';
const require = createRequire(process.env.PW_DIR || import.meta.url);
const { chromium } = require('playwright');
const b = await chromium.launch({ headless: false, executablePath: process.env.CH, args: ['--ignore-gpu-blocklist', '--window-size=1440,900'] });
for (const s of ['A-astra', 'B-opus', 'C-swarm']) {
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  await p.goto(`http://127.0.0.1:8801/${s}/`, { waitUntil: 'load' }); await p.waitForTimeout(2500);
  const r = await p.evaluate(async () => {
    const gl = document.createElement('canvas').getContext('webgl'); const d = gl.getExtension('WEBGL_debug_renderer_info'); const rend = d ? gl.getParameter(d.UNMASKED_RENDERER_WEBGL) : '?';
    const H = document.documentElement.scrollHeight; const ft = []; let last = performance.now(), run = true;
    const loop = t => { ft.push(t - last); last = t; if (run) requestAnimationFrame(loop); }; requestAnimationFrame(loop);
    for (let i = 0; i < 200; i++) { window.scrollTo(0, H * i / 200); await new Promise(r => setTimeout(r, 20)); }
    for (let i = 0; i < 60; i++) { document.dispatchEvent(new PointerEvent('pointermove', { clientX: 400 + i * 10, clientY: 400, bubbles: true })); window.dispatchEvent(new MouseEvent('mousemove', { clientX: 400 + i * 10, clientY: 400 })); await new Promise(r => setTimeout(r, 16)); }
    run = false; ft.shift(); ft.sort((a, b) => a - b);
    const avg = ft.reduce((a, b) => a + b, 0) / ft.length;
    return { rend, fps: Math.round(1000 / avg), p95ms: Math.round(ft[Math.floor(ft.length * .95)]), jank50: ft.filter(x => x > 50).length, frames: ft.length };
  });
  console.log(s, JSON.stringify(r)); await p.close();
}
await b.close();
