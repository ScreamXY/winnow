// Winnow page script for instagram.com.
//
// The app injects this file at document start, in its own script world, after a line that sets
// `window.__winnowBoot = { config, css }`. Instagram's own scripts cannot see this world, but
// both worlds share the page (DOM), so marks and styles work.
//
// Rules of thumb:
// - Prefer link targets (href) and page structure over class names or visible text.
// - Never remove nodes. Mark them with data-winnow-hidden="<reason>" and let CSS hide them, so
//   Instagram's own code keeps working and a switch in Settings can show them again.
// - Text labels depend on the language. Keep them in the lists below.
(() => {
  'use strict';

  if (window.__winnow) {
    return;
  }
  if (!/(^|\.)instagram\.com$/.test(location.hostname)) {
    return;
  }

  const boot = window.__winnowBoot || {};
  let config = Object.assign(
    {
      forceFollowing: true,
      hideReels: true,
      hideExplore: true,
      hideSuggestions: true,
      hideSponsored: true,
      hideSeen: true,
      flickMode: true,
    },
    boot.config || {},
  );

  // Exact labels, compared after trimming. Add more languages here when needed.
  const SUGGESTED_LABELS = new Set([
    'Suggested for you',
    'Suggested posts',
    'Suggested reels',
    'Vorschläge für dich',
    'Vorgeschlagen für dich',
    'Vorgeschlagene Beiträge',
    'Vorgeschlagene Reels',
    'Empfohlen für dich',
    'Suggestions pour vous',
    'Suggerimenti per te',
  ]);
  const SPONSORED_LABELS = new Set([
    'Sponsored',
    'Gesponsert',
    'Anzeige',
    'Sponsorisé',
    'Sponsorizzato',
    'Publicidad',
    'Patrocinado',
  ]);
  const LANDMARKS = new Set(['HTML', 'BODY', 'MAIN', 'NAV', 'HEADER', 'FOOTER']);
  // A hidden block must stay small. A bigger block would likely hide real content.
  const MAX_BLOCK_TEXT = 1500;

  // Returns false when the app is not there to receive the message.
  const post = (message) => {
    try {
      window.webkit.messageHandlers.winnow.postMessage(message);
      return true;
    } catch (_) {
      // Not running inside the app (for example in a desktop browser while testing).
      return false;
    }
  };

  // Page types. Only some need special rules.
  const routeOf = (path) => {
    if (path === '/') {
      return 'home';
    }
    if (path === '/explore/') {
      return 'explore';
    }
    if (path.startsWith('/explore/')) {
      return 'explore-detail';
    }
    if (path.startsWith('/reels/')) {
      return 'reels';
    }
    if (/^\/([^/]+\/)?reel\//.test(path)) {
      return 'reel';
    }
    if (path.startsWith('/direct/')) {
      return 'direct';
    }
    return 'other';
  };
  const currentRoute = () =>
    routeOf(location.pathname.endsWith('/') ? location.pathname : location.pathname + '/');

  const setFlag = (name, on) => {
    const root = document.documentElement;
    if (!root) {
      return;
    }
    if (on) {
      root.setAttribute(name, '');
    } else {
      root.removeAttribute(name);
    }
  };

  const applyFlags = () => {
    const root = document.documentElement;
    if (!root) {
      return;
    }
    root.setAttribute('data-winnow-route', currentRoute());
    setFlag('data-winnow-hide-reels', config.hideReels);
    setFlag('data-winnow-hide-explore', config.hideExplore);
    setFlag('data-winnow-hide-suggestions', config.hideSuggestions);
    setFlag('data-winnow-hide-sponsored', config.hideSponsored);
    setFlag('data-winnow-hide-seen', config.hideSeen);
    setFlag('data-winnow-force-following', config.forceFollowing);
  };

  const ensureStyle = () => {
    if (!boot.css || document.getElementById('winnow-style')) {
      return;
    }
    const style = document.createElement('style');
    style.id = 'winnow-style';
    style.textContent = boot.css;
    (document.head || document.documentElement).appendChild(style);
  };

  const mark = (element, reason) => {
    if (element && element.getAttribute('data-winnow-hidden') !== reason) {
      element.setAttribute('data-winnow-hidden', reason);
    }
  };

  // A tab bar item is the link plus the wrappers that hold only this link.
  const navItemOf = (link) => {
    let item = link;
    while (
      item.parentElement &&
      !LANDMARKS.has(item.parentElement.tagName) &&
      item.parentElement.children.length === 1
    ) {
      item = item.parentElement;
    }
    return item;
  };

  // The smallest useful block around an element: grow while the parent holds no posts,
  // is not a page landmark, and has little text.
  const blockOf = (element) => {
    let block = element;
    while (block.parentElement) {
      const parent = block.parentElement;
      if (
        LANDMARKS.has(parent.tagName) ||
        parent.getAttribute('role') === 'main' ||
        parent.getAttribute('role') === 'dialog' ||
        parent.querySelector('article') ||
        (parent.textContent || '').length > MAX_BLOCK_TEXT
      ) {
        break;
      }
      block = parent;
    }
    return LANDMARKS.has(block.tagName) ? null : block;
  };

  // The first photo or video of a post: a picture at least half as wide as the post. The author's
  // avatar in the header is much smaller.
  const mediaOf = (article) => {
    const width = article.getBoundingClientRect().width;
    for (const element of article.querySelectorAll('img, video')) {
      if (element.getBoundingClientRect().width >= width / 2) {
        return element;
      }
    }
    return null;
  };

  // The labels "Sponsored" and "Suggested for you" sit in the post header, next to the author. A
  // caption or a comment may hold the same words (a German caption often starts with "Anzeige"), so
  // only the header counts: everything before the first photo or video, or else the <header>
  // element. Returns null while neither is found (for example before the media is laid out).
  const headerTexts = (article) => {
    const media = mediaOf(article);
    const root = media ? article : article.querySelector('header');
    if (!root) {
      return null;
    }
    const texts = [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (media && !(media.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_PRECEDING)) {
        break;
      }
      const text = node.nodeValue.trim();
      if (text.length > 0 && text.length < 40) {
        texts.push(text);
      }
    }
    return texts;
  };

  const textSeen = new WeakMap();

  // Posts the person scrolled past in the home feed. They are hidden from the next page load on, so
  // the feed starts with new posts and goes on where the person stopped. Posts seen since this load
  // stay, so scrolling back up still works. Only post codes and a day number are kept, in the page's
  // own storage on the device.
  const SEEN_KEY = 'winnow.seenPosts';
  const SEEN_DAYS = 30;
  const SEEN_MAX = 3000;
  const POST_LINK = /^\/(?:[^/]+\/)?(?:p|reel)\/([A-Za-z0-9_-]+)\/?/;
  const today = () => Math.floor(Date.now() / 86400000);
  // Read once per page load. Entries older than SEEN_DAYS are dropped here, so they never count.
  const readSeen = () => {
    try {
      const value = JSON.parse(localStorage.getItem(SEEN_KEY) || '{}');
      if (!value || typeof value !== 'object' || Array.isArray(value)) {
        return {};
      }
      const oldest = today() - SEEN_DAYS;
      return Object.fromEntries(
        Object.entries(value).filter(([, day]) => typeof day === 'number' && day >= oldest),
      );
    } catch (_) {
      return {};
    }
  };
  const seenPosts = readSeen();
  const seenBefore = new Set(Object.keys(seenPosts));
  const saveSeen = () => {
    const entries = Object.entries(seenPosts);
    if (entries.length > SEEN_MAX) {
      // Keep the newest; forget the rest.
      entries
        .sort((a, b) => b[1] - a[1])
        .slice(SEEN_MAX)
        .forEach(([code]) => delete seenPosts[code]);
    }
    try {
      localStorage.setItem(SEEN_KEY, JSON.stringify(seenPosts));
    } catch (_) {
      // Storage is full or blocked. The feed still works; seen posts stay visible.
    }
  };

  // The post's own address, from its link to the post (the one around the time, if there is one).
  // A post element keeps its address, so it is looked up once.
  const postCodes = new WeakMap();
  const postCode = (article) => {
    if (postCodes.has(article)) {
      return postCodes.get(article);
    }
    const time = article.querySelector('a[href] time');
    const links = [
      time && time.closest('a[href]'),
      ...article.querySelectorAll('a[href*="/p/"], a[href*="/reel/"]'),
    ];
    for (const link of links) {
      const match = link && POST_LINK.exec(link.getAttribute('href') || '');
      if (match) {
        postCodes.set(article, match[1]);
        return match[1];
      }
    }
    return null;
  };

  const scan = () => {
    ensureStyle();
    applyFlags();

    document
      .querySelectorAll('a[href="/reels/"]')
      .forEach((link) => mark(navItemOf(link), 'reels'));

    // "Suggested for you" accounts always link to the full suggestions list.
    document.querySelectorAll('a[href^="/explore/people/"]').forEach((link) => {
      const block = blockOf(link);
      if (block) {
        mark(block, 'suggestion');
      }
    });

    // Posts seen before this page load.
    let hidSeen = false;
    if (config.hideSeen && seenBefore.size > 0 && currentRoute() === 'home') {
      topLevelArticles().forEach((article) => {
        if (article.hasAttribute('data-winnow-hidden')) {
          return;
        }
        const code = postCode(article);
        if (code && seenBefore.has(code)) {
          mark(article, 'seen');
          hidSeen = true;
        }
      });
    }

    // Posts: check each post again only when its text changed. Only the post header counts.
    document.querySelectorAll('article').forEach((article) => {
      if (article.getAttribute('data-winnow-hidden') === 'seen') {
        return;
      }
      const length = (article.textContent || '').length;
      if (textSeen.get(article) === length) {
        return;
      }
      const texts = headerTexts(article);
      if (!texts) {
        return;
      }
      textSeen.set(article, length);
      if (texts.some((text) => SUGGESTED_LABELS.has(text))) {
        mark(article, 'suggestion');
      } else if (texts.some((text) => SPONSORED_LABELS.has(text))) {
        mark(article, 'sponsored');
      }
    });

    // Suggestion headings outside posts, for example in the activity list.
    // Not in messages: a chat message may contain the same words.
    const headings =
      currentRoute() === 'direct'
        ? []
        : document.querySelectorAll('h2, h3, h4, span, div[role="heading"]');
    headings.forEach((heading) => {
      if (heading.children.length > 0 || heading.closest('article, [data-winnow-hidden]')) {
        return;
      }
      if (!SUGGESTED_LABELS.has((heading.textContent || '').trim())) {
        return;
      }
      const block = blockOf(heading);
      if (block) {
        mark(block, 'suggestion');
      }
    });

    // Stop sound from the reels feed while the app leaves it.
    if (config.hideReels && currentRoute() === 'reels') {
      document.querySelectorAll('video').forEach((video) => video.pause());
    }

    // The title of the Following feed is a link back to the "For you" feed, with a back arrow (in the
    // top bar on a phone, above the posts on an iPad). Winnow never shows that feed: a tap on the
    // title scrolls to the top (see the click handler), so the arrow is hidden.
    const backArrows =
      currentRoute() === 'home' ? document.querySelectorAll('a[href="/?variant=home"] svg') : [];
    backArrows.forEach((svg) => {
      const wrapper = svg.parentElement;
      const onlyChild = wrapper && wrapper.children.length === 1 && !wrapper.matches('a');
      mark(onlyChild ? wrapper : svg, 'back');
    });

    markFeed();

    if (hidSeen) {
      // Instagram loads more posts when the end of the list comes near; hidden posts brought it nearer.
      window.dispatchEvent(new Event('scroll'));
    }
  };

  const topLevelArticles = () =>
    [...document.querySelectorAll('article')].filter(
      (article) => !(article.parentElement && article.parentElement.closest('article')),
    );

  // The app shows the stories tray in a room above the feed. The room is a margin on the list that
  // holds the posts, not on the first post: Instagram keeps only a few posts in the page and
  // removes the ones far above the screen, so the first post in the page is often not the first
  // post of the feed.
  const feedList = () => {
    if (currentRoute() !== 'home') {
      return null;
    }
    const articles = topLevelArticles();
    if (articles.length === 0) {
      return null;
    }
    let list = articles[0].parentElement;
    const last = articles[articles.length - 1];
    while (list && !list.contains(last)) {
      list = list.parentElement;
    }
    return list && list !== document.body && list !== document.documentElement ? list : null;
  };

  // A dialog (a menu or a sheet) covers the page. The stories tray is a native view above the page,
  // so the app hides it while a dialog is open.
  const isDialogOpen = () =>
    [...document.querySelectorAll('[role="dialog"], [aria-modal="true"], dialog[open]')].some(
      (element) => {
        const rect = element.getBoundingClientRect();
        return (
          rect.width > 0 && rect.height > 0 && getComputedStyle(element).visibility !== 'hidden'
        );
      },
    );
  let dialogWasOpen = false;
  // Where the room for the tray was last reported. Content above the feed can change size (for
  // example when the back arrow is hidden), and then the app must place the tray again.
  let lastRoomTop = null;

  const roomOf = (list) => {
    if (!list) {
      return null;
    }
    const rect = list.getBoundingClientRect();
    const space = parseFloat(getComputedStyle(list).marginTop) || 0;
    return { top: rect.top + window.scrollY - space, left: rect.left, width: rect.width };
  };

  const markFeed = () => {
    const list = feedList();
    let changed = false;
    const dialogOpen = isDialogOpen();
    if (dialogOpen !== dialogWasOpen) {
      dialogWasOpen = dialogOpen;
      changed = true;
    }
    document.querySelectorAll('[data-winnow-feed]').forEach((element) => {
      if (element !== list) {
        element.removeAttribute('data-winnow-feed');
        changed = true;
      }
    });
    if (list && !list.hasAttribute('data-winnow-feed')) {
      list.setAttribute('data-winnow-feed', '');
      changed = true;
    }
    const room = roomOf(list);
    const roomTop = room ? Math.round(room.top) : null;
    if (roomTop !== lastRoomTop) {
      lastRoomTop = roomTop;
      changed = true;
    }
    if (changed) {
      post({ type: 'layoutChanged' });
    }
  };

  let scanTimer = null;
  const scheduleScan = () => {
    if (scanTimer !== null) {
      return;
    }
    scanTimer = setTimeout(() => {
      scanTimer = null;
      scan();
    }, 100);
  };

  // The Home tab and the logo link to "/" (the "For you" feed). Open the Following feed instead.
  window.addEventListener(
    'click',
    (event) => {
      if (!config.forceFollowing || event.defaultPrevented) {
        return;
      }
      const link = event.target instanceof Element ? event.target.closest('a[href]') : null;
      if (!link) {
        return;
      }
      const url = new URL(link.getAttribute('href'), location.href);
      const variant = url.searchParams.get('variant');
      if (url.origin !== location.origin || url.pathname !== '/') {
        return;
      }
      if (variant === 'following' || variant === 'favorites') {
        return;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      if (location.pathname === '/') {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      } else if (!post({ type: 'home' })) {
        // The app goes back to the feed in the history, so the feed keeps its place. A new load
        // starts at the top; it is only the fallback outside the app.
        location.assign('/?variant=following');
      }
    },
    true,
  );

  // Fixed bars cover the top and bottom of the page. Find their height at the screen edges.
  const fixedAncestor = (element) => {
    for (let node = element; node && node !== document.body; node = node.parentElement) {
      const position = getComputedStyle(node).position;
      if (position === 'fixed' || position === 'sticky') {
        return node;
      }
    }
    return null;
  };
  const topInset = () => {
    const top = fixedAncestor(document.elementFromPoint(Math.round(window.innerWidth / 2), 1));
    return top ? Math.max(0, top.getBoundingClientRect().bottom) : 0;
  };
  const chromeInsets = () => {
    const x = Math.round(window.innerWidth / 2);
    const bottom = fixedAncestor(document.elementFromPoint(x, window.innerHeight - 2));
    return {
      top: topInset(),
      bottom: bottom ? Math.max(0, window.innerHeight - bottom.getBoundingClientRect().top) : 0,
    };
  };

  // A post counts as seen once its end went above the top bar. Checked at most once a second while
  // the page scrolls; each post is recorded once per page load.
  const recorded = new WeakSet();
  const recordSeen = () => {
    if (!config.hideSeen || currentRoute() !== 'home') {
      return;
    }
    const top = topInset();
    let changed = false;
    topLevelArticles().forEach((article) => {
      if (recorded.has(article) || article.hasAttribute('data-winnow-hidden')) {
        return;
      }
      const rect = article.getBoundingClientRect();
      if (rect.height <= 40 || rect.bottom > top + 4) {
        return;
      }
      const code = postCode(article);
      if (code) {
        recorded.add(article);
        seenPosts[code] = today();
        changed = true;
      }
    });
    if (changed) {
      saveSeen();
    }
  };
  let seenTimer = null;
  window.addEventListener(
    'scroll',
    (event) => {
      if (!event.isTrusted || seenTimer !== null) {
        return;
      }
      seenTimer = setTimeout(() => {
        seenTimer = null;
        recordSeen();
      }, 1000);
    },
    { passive: true },
  );

  // Post positions for flick mode. The app asks for this when a drag starts.
  const layout = () => {
    const route = currentRoute();
    const posts = [];
    if (route === 'home') {
      topLevelArticles().forEach((article) => {
        const rect = article.getBoundingClientRect();
        if (rect.height > 40) {
          posts.push({ top: rect.top + window.scrollY, height: rect.height });
        }
      });
    }
    const insets = chromeInsets();
    const stories = route === 'home' ? roomOf(document.querySelector('[data-winnow-feed]')) : null;
    return JSON.stringify({
      route,
      posts,
      topInset: insets.top,
      bottomInset: insets.bottom,
      stories,
      dialogOpen: isDialogOpen(),
    });
  };

  // Makes room for the stories tray above the feed. Returns the new layout.
  const setStoriesSpace = (height) => {
    const pixels = Math.max(0, Math.round(Number(height) || 0));
    document.documentElement.style.setProperty('--winnow-stories-space', pixels + 'px');
    setFlag('data-winnow-stories', pixels > 0);
    markFeed();
    return layout();
  };

  const configure = (next) => {
    config = Object.assign(config, next || {});
    scan();
  };

  window.__winnow = { configure, layout, scan, setStoriesSpace, version: 1 };

  const start = () => {
    scan();
    new MutationObserver(scheduleScan).observe(document.documentElement, {
      childList: true,
      subtree: true,
    });
    window.addEventListener('popstate', scheduleScan);
    post({ type: 'ready', route: currentRoute() });
  };

  if (document.documentElement) {
    start();
  } else {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  }
})();
