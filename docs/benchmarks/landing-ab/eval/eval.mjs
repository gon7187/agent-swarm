import { createRequire } from 'module';
const require = createRequire(process.env.PW_DIR || import.meta.url);
const { chromium } = require('playwright');
const OUT = process.env.OUT || new URL('../screenshots', import.meta.url).pathname; // PNG output
const sites = ['A-astra', 'B-opus', 'C-swarm'];
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const res = {};
for (const s of sites) {
  const r = res[s] = { errors: [], failed: [], bytes: 0, reqs: 0 };
  // desktop
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const p = await ctx.newPage();
  p.on('console', m => m.type() === 'error' && r.errors.push(m.text().slice(0, 200)));
  p.on('pageerror', e => r.errors.push('PAGEERR ' + e.message.slice(0, 200)));
  p.on('requestfailed', q => r.failed.push(q.url().slice(0, 120) + ' ' + q.failure()?.errorText));
  p.on('response', async q => { r.reqs++; try { const b = await q.body(); r.bytes += b.length; } catch {} });
  const t0 = Date.now();
  await p.goto(`http://127.0.0.1:8801/${s}/`, { waitUntil: 'load' });
  r.loadMs = Date.now() - t0;
  await p.waitForTimeout(2500);
  r.perf = await p.evaluate(() => { const n = performance.getEntriesByType('navigation')[0]; return { dcl: Math.round(n.domContentLoadedEventEnd), load: Math.round(n.loadEventEnd) }; });
  r.canvas = await p.evaluate(() => [...document.querySelectorAll('canvas')].map(c => { let gl = null; try { gl = c.getContext('webgl2') || c.getContext('webgl'); } catch {} return `${c.width}x${c.height} gl=${!!gl}`; }));
  r.bodyCursor = await p.evaluate(() => getComputedStyle(document.body).cursor + '/' + getComputedStyle(document.documentElement).cursor);
  await p.screenshot({ path: `${OUT}/${s}-d-hero.png` });
  await p.mouse.move(700, 450); await p.mouse.move(760, 480, { steps: 10 }); await p.waitForTimeout(300);
  await p.screenshot({ path: `${OUT}/${s}-d-cursor.png`, clip: { x: 600, y: 350, width: 300, height: 250 } });
  // fps during scroll
  const H = await p.evaluate(() => document.documentElement.scrollHeight);
  r.scrollHeight = H;
  r.fpsScroll = await p.evaluate(async (H) => { let f = 0, run = true; const loop = () => { f++; if (run) requestAnimationFrame(loop); }; requestAnimationFrame(loop); const t = performance.now(); const steps = 120; for (let i = 0; i < steps; i++) { window.scrollTo(0, (H * i) / steps); await new Promise(r => setTimeout(r, 25)); } run = false; return Math.round(f / ((performance.now() - t) / 1000)); }, H);
  r.longTasks = await p.evaluate(() => new Promise(res => { let n = 0, tot = 0; const o = new PerformanceObserver(l => l.getEntries().forEach(e => { n++; tot += e.duration; })); o.observe({ type: 'longtask' }); setTimeout(() => { o.disconnect(); res({ n, totMs: Math.round(tot) }); }, 3000); window.scrollTo(0, 0); }));
  // screenshots at scroll positions
  for (const [i, fr] of [0.12, 0.3, 0.5, 0.75].entries()) { await p.evaluate(y => window.scrollTo(0, y), H * fr); await p.waitForTimeout(900); await p.screenshot({ path: `${OUT}/${s}-d-s${i}.png` }); }
  await p.evaluate(() => window.scrollTo(0, 0)); await p.waitForTimeout(500);
  await p.screenshot({ path: `${OUT}/${s}-d-full.png`, fullPage: true });
  r.overflow1440 = await p.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  r.a11y = await p.evaluate(() => ({ imgsNoAlt: [...document.images].filter(i => !i.hasAttribute('alt')).length, h1: document.querySelectorAll('h1').length, main: !!document.querySelector('main'), lang: document.documentElement.lang, buttonsNoName: [...document.querySelectorAll('button,a')].filter(b => !(b.innerText.trim() || b.getAttribute('aria-label') || b.title)).length }));
  await ctx.close();
  // mobile + tablet overflow
  for (const [w, h, tag] of [[375, 812, 'm'], [768, 1024, 't']]) {
    const c = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: w < 500, isMobile: w < 500 });
    const q = await c.newPage(); q.on('pageerror', e => r.errors.push(`PAGEERR@${w} ` + e.message.slice(0, 150)));
    await q.goto(`http://127.0.0.1:8801/${s}/`, { waitUntil: 'load' }); await q.waitForTimeout(2000);
    r['overflow' + w] = await q.evaluate(() => { const H = document.documentElement.scrollHeight; let m = 0; for (let y = 0; y < H; y += 400) { window.scrollTo(0, y); m = Math.max(m, document.documentElement.scrollWidth - innerWidth); } window.scrollTo(0, 0); return m; });
    await q.waitForTimeout(500);
    if (tag === 'm') { await q.screenshot({ path: `${OUT}/${s}-m-hero.png` }); await q.screenshot({ path: `${OUT}/${s}-m-full.png`, fullPage: true }); }
    await c.close();
  }
  // reduced motion
  const rc = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion: 'reduce' });
  const rp = await rc.newPage(); await rp.goto(`http://127.0.0.1:8801/${s}/`, { waitUntil: 'load' }); await rp.waitForTimeout(1500);
  r.reducedAnimsRunning = await rp.evaluate(() => document.getAnimations().filter(a => a.playState === 'running').length);
  await rc.close();
  console.log(s, JSON.stringify(r));
}
await browser.close();
