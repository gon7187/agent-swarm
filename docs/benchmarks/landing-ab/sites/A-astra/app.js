(() => {
  'use strict';
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const reveals = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window && !reducedMotion.matches) {
    document.body.classList.add('motion-ready');
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    }, { threshold: 0.08 });
    reveals.forEach(element => observer.observe(element));
    reducedMotion.addEventListener('change', event => {
      if (event.matches) document.body.classList.remove('motion-ready');
    });
  }

  const slider = document.querySelector('#clean-slider');
  slider.addEventListener('input', () => {
    document.querySelector('#comparison').style.setProperty('--clean', `${slider.value}%`);
    slider.setAttribute('aria-valuetext', `${100 - Number(slider.value)} percent clean`);
  });
  slider.setAttribute('aria-valuetext', '52 percent clean');

  const dialog = document.querySelector('#order-dialog');
  const purchaseButton = document.querySelector('#buy-button');
  purchaseButton.addEventListener('click', () => dialog.showModal());
  dialog.querySelectorAll('.dialog-close, .dialog-dismiss').forEach(button => {
    button.addEventListener('click', () => dialog.close());
  });
  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });
  dialog.addEventListener('close', () => purchaseButton.focus({ preventScroll: true }));

  // A small squeegee follows the pointer; native cursors stay on the 3D and range controls.
  const cursor = document.querySelector('#clean-cursor');
  const finePointer = matchMedia('(hover: hover) and (pointer: fine)');
  let frame = 0;
  let x = 0;
  let y = 0;
  const cursorEnabled = () => finePointer.matches && !reducedMotion.matches;
  document.addEventListener('pointermove', event => {
    if (!cursorEnabled() || event.pointerType === 'touch') return;
    x = event.clientX; y = event.clientY;
    if (event.target.closest('canvas, input, dialog')) {
      cursor.style.opacity = '0';
      document.body.classList.remove('cursor-on');
      return;
    }
    document.body.classList.add('cursor-on');
    cursor.style.opacity = '1';
    cursor.classList.toggle('active', Boolean(event.target.closest('a, button, summary')));
    if (!frame) frame = requestAnimationFrame(() => {
      cursor.style.transform = `translate(${x - 12}px,${y - 12}px)`;
      frame = 0;
    });
  }, { passive: true });
  const hideCursor = () => { cursor.style.opacity = '0'; document.body.classList.remove('cursor-on'); };
  document.documentElement.addEventListener('pointerleave', hideCursor);
  window.addEventListener('blur', hideCursor);
  document.addEventListener('keydown', event => { if (event.key === 'Tab') hideCursor(); });
  reducedMotion.addEventListener('change', hideCursor);
  finePointer.addEventListener('change', hideCursor);
})();
