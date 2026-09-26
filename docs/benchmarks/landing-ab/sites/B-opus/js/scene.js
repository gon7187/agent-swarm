/* Lazy bootstrap for the three.js product scene.
   The SVG poster is shown first; three.js is fetched after the page is idle,
   and only if WebGL is available. */
const canvas = document.getElementById('scene');

function hasWebGL() {
  try {
    const c = document.createElement('canvas');
    return !!(window.WebGLRenderingContext && (c.getContext('webgl2') || c.getContext('webgl')));
  } catch {
    return false;
  }
}

function whenIdle() {
  return new Promise((resolve) => {
    const go = () => ('requestIdleCallback' in window ? requestIdleCallback(resolve, { timeout: 1200 }) : setTimeout(resolve, 200));
    if (document.readyState === 'complete') go();
    else addEventListener('load', go, { once: true });
  });
}

if (canvas && hasWebGL()) {
  whenIdle()
    .then(() => import('./product3d.js'))
    .then((m) => m.start(canvas))
    .catch((err) => {
      // Keep the SVG poster if the CDN is unreachable; never break the page.
      console.warn('3D scene unavailable, showing illustration instead.', err);
    });
}
