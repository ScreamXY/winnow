// Winnow stories strip. The app loads Instagram's home page in a second, small web view and injects
// this script. It finds the stories tray, pins it to the top and hides everything else, so the
// strip shows only the tray. The For You posts on that page are never shown and their videos are
// paused and muted. Tapping a story is handled by the app, which opens it in the main web view.
//
// The tray has no stable name, so it is found by its parts: story links (/stories/…), elements whose
// label mentions a story, or round avatar canvases, in one row near the top of the page.
(() => {
  'use strict';

  if (window.__winnowStrip) {
    return;
  }
  if (!/(^|\.)instagram\.com$/.test(location.hostname)) {
    return;
  }

  const post = (message) => {
    try {
      window.webkit.messageHandlers.winnowStrip.postMessage(message);
    } catch (_) {
      // Not inside the app.
    }
  };

  const CSS = `
    html.winnow-strip, html.winnow-strip body { overflow: hidden !important; }
    html.winnow-strip body * { visibility: hidden !important; }
    html.winnow-strip [data-winnow-tray], html.winnow-strip [data-winnow-tray] * { visibility: visible !important; }
    html.winnow-strip [data-winnow-tray] {
      position: fixed !important; top: 0 !important; left: 0 !important; right: 0 !important;
      width: 100vw !important; max-width: none !important; margin: 0 !important;
      box-sizing: border-box !important; bottom: auto !important;
      height: var(--winnow-tray-height, auto) !important;
      z-index: 2147483647 !important; background: var(--winnow-strip-bg, transparent) !important;
    }`;

  const ensureStyle = () => {
    if (document.getElementById('winnow-strip-style')) return;
    const style = document.createElement('style');
    style.id = 'winnow-strip-style';
    style.textContent = CSS;
    (document.head || document.documentElement).appendChild(style);
  };

  const STORY_LABEL = /\bstor(y|ys|ies|ia|ie)\b/i;
  const MAX_TOP = 400;
  const MAX_TRAY_HEIGHT = 220;

  const isNearTop = (el) => {
    const r = el.getBoundingClientRect();
    return r.width > 16 && r.height > 16 && r.top >= 0 && r.top < MAX_TOP;
  };

  const storyItems = () => {
    const items = new Set();
    document.querySelectorAll('a[href^="/stories/"]').forEach((el) => items.add(el));
    document.querySelectorAll('[aria-label]').forEach((el) => {
      if (STORY_LABEL.test(el.getAttribute('aria-label') || '')) items.add(el);
    });
    let found = [...items].filter(isNearTop);
    if (found.length < 2) {
      // Avatar rings are drawn on small, square canvases.
      found = [...document.querySelectorAll('canvas')].filter((el) => {
        const r = el.getBoundingClientRect();
        return isNearTop(el) && r.width < 120 && Math.abs(r.width - r.height) < 4;
      });
    }
    return found;
  };

  const commonAncestor = (a, b) => {
    const seen = new Set();
    for (let n = a; n; n = n.parentElement) seen.add(n);
    for (let n = b; n; n = n.parentElement) if (seen.has(n)) return n;
    return null;
  };

  const findTray = () => {
    const items = storyItems();
    if (items.length < 2) return null;
    const rowTop = items[0].getBoundingClientRect().top;
    const row = items.filter((el) => Math.abs(el.getBoundingClientRect().top - rowTop) < 12);
    if (row.length < 2) return null;
    let tray = commonAncestor(row[0], row[row.length - 1]);
    // Grow to the box that scrolls the row sideways, or else to the full-width row, but never into
    // a tall block. A row wider than the screen sits inside such a box: pinning the row itself
    // would take it out of the box, and it could no longer scroll.
    for (let n = tray; n && n !== document.body && n.tagName !== 'MAIN'; n = n.parentElement) {
      const r = n.getBoundingClientRect();
      if (r.height > MAX_TRAY_HEIGHT) break;
      tray = n;
      if (/auto|scroll/.test(getComputedStyle(n).overflowX)) break;
      if (Math.abs(r.width - window.innerWidth) <= 2) break;
    }
    return tray && tray !== document.body ? tray : null;
  };

  let tray = null;
  let reported = -1;

  const update = () => {
    ensureStyle();
    if (!tray || !tray.isConnected) {
      if (tray) tray.removeAttribute('data-winnow-tray');
      tray = findTray();
      if (!tray) {
        document.documentElement.classList.remove('winnow-strip');
        if (reported !== 0) {
          reported = 0;
          post({ type: 'tray', found: false, height: 0 });
        }
        return;
      }
      // Keep the height the tray has in the page. Pinned, a height given in % (iPad layout) would
      // grow to the whole strip, and "auto" would collapse the row inside.
      const pageHeight = Math.round(tray.getBoundingClientRect().height);
      document.documentElement.style.setProperty('--winnow-tray-height', pageHeight + 'px');
      tray.setAttribute('data-winnow-tray', '');
      const background = getComputedStyle(document.body).backgroundColor;
      document.documentElement.style.setProperty('--winnow-strip-bg', background);
      document.documentElement.classList.add('winnow-strip');
    }
    const height = Math.round(tray.getBoundingClientRect().height);
    if (height !== reported) {
      reported = height;
      post({ type: 'tray', found: height > 0, height });
    }
  };

  // Videos of the hidden posts must never play or make sound.
  const silence = () => {
    document.querySelectorAll('video').forEach((video) => {
      video.muted = true;
      if (!video.paused) video.pause();
    });
  };

  let timer = null;
  const schedule = () => {
    if (timer !== null) return;
    timer = setTimeout(() => {
      timer = null;
      update();
      silence();
    }, 200);
  };

  const describe = () => ({
    found: !!tray,
    height: reported,
    items: storyItems().length,
    path: location.pathname,
  });

  window.__winnowStrip = { update, describe, version: 1 };

  const start = () => {
    update();
    new MutationObserver(schedule).observe(document.documentElement, {
      childList: true,
      subtree: true,
    });
    setInterval(silence, 1000);
  };

  if (document.documentElement) {
    start();
  } else {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  }
})();
