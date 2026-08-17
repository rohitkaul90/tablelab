/* TableLab marketing site — theme toggle (vanilla JS, no dependencies).
   The per-page inline FOUC snippet has already stamped data-theme on <html>
   before the stylesheet loaded; this script wires the header toggle button,
   persists the choice, keeps meta[name=theme-color] in sync, and dispatches a
   'themechange' CustomEvent that canvas-based pages (the calculators) listen
   for to repaint with the new palette. */
(function () {
  var THEME_COLORS = { dark: '#111811', light: '#F6F8F4' };

  function currentTheme() {
    return document.documentElement.getAttribute('data-theme') === 'light'
      ? 'light'
      : 'dark';
  }

  function syncMetaThemeColor(theme) {
    var meta = document.querySelector('meta[name="theme-color"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.setAttribute('name', 'theme-color');
      document.head.appendChild(meta);
    }
    meta.setAttribute('content', THEME_COLORS[theme]);
  }

  function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    syncMetaThemeColor(theme);
    try {
      localStorage.setItem('theme', theme);
    } catch (e) {
      /* private mode / storage disabled — the toggle still works per page */
    }
    window.dispatchEvent(
      new CustomEvent('themechange', { detail: { theme: theme } })
    );
  }

  // The FOUC snippet may have resolved a theme that disagrees with the page's
  // static meta theme-color — sync it (no persist, no event: nothing changed).
  syncMetaThemeColor(currentTheme());

  // Event delegation so one listener covers the header button on every page.
  document.addEventListener('click', function (e) {
    var btn = e.target && e.target.closest ? e.target.closest('.theme-toggle') : null;
    if (!btn) return;
    applyTheme(currentTheme() === 'light' ? 'dark' : 'light');
  });

  // Mobile nav (☰): the header's <details class="nav-menu"> panel is filled
  // from the page's own inline .site-nav links (hidden by CSS under 560px), so
  // each page's menu mirrors its own nav with one identical markup snippet.
  var menu = document.querySelector('details.nav-menu');
  if (menu) {
    var panel = menu.querySelector('nav');
    // Walk the plain .link anchors AND the Tools dropdown together, so the ☰
    // panel mirrors the desktop nav in the same order (querySelectorAll returns
    // document order). The dropdown itself is display:none under 560px, so its
    // calculator links have to be flattened in here or they'd be unreachable.
    document.querySelectorAll('.site-nav > a.link, .site-nav > .nav-dropdown').forEach(function (el) {
      if (el.classList.contains('nav-dropdown')) {
        el.querySelectorAll('nav a').forEach(function (a) {
          panel.appendChild(a.cloneNode(true));
        });
        return;
      }
      var copy = el.cloneNode(true);
      copy.classList.remove('link'); // the .link class is display:none on mobile
      panel.appendChild(copy);
    });
    // Close after picking a link (matters for same-page anchors) and on any
    // tap/click outside the open panel.
    document.addEventListener('click', function (e) {
      if (!menu.hasAttribute('open')) return;
      var t = e.target;
      var inside = t && t.closest ? t.closest('details.nav-menu') : null;
      if (!inside || (t.closest && t.closest('.nav-menu nav a'))) {
        menu.removeAttribute('open');
      }
    });
  }

  // Tools dropdown: <details> handles open/close and keyboard on its own; this
  // just adds the two behaviours it doesn't give you — closing when you click
  // away or pick a link, and closing on Escape (returning focus to the summary).
  var dropdown = document.querySelector('details.nav-dropdown');
  if (dropdown) {
    document.addEventListener('click', function (e) {
      if (!dropdown.hasAttribute('open')) return;
      var t = e.target;
      var inside = t && t.closest ? t.closest('details.nav-dropdown') : null;
      if (!inside || (t.closest && t.closest('.nav-dropdown nav a'))) {
        dropdown.removeAttribute('open');
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape' || !dropdown.hasAttribute('open')) return;
      dropdown.removeAttribute('open');
      var summary = dropdown.querySelector('summary');
      if (summary) summary.focus();
    });
  }

  // ── Cookie consent ─────────────────────────────────────────────────────────
  // Each page's inline GA4 snippet defaults Consent Mode to DENIED and restores a
  // stored 'granted' before gtag('config') runs. This asks the question once,
  // records the answer in localStorage (not a cookie — storing the consent choice
  // itself is exempt), and updates Consent Mode live so the current page starts
  // being measured immediately rather than only from the next navigation.
  var CONSENT_KEY = 'tl-consent';

  function readConsent() {
    try { return localStorage.getItem(CONSENT_KEY); } catch (e) { return null; }
  }

  function setConsent(value) {
    try { localStorage.setItem(CONSENT_KEY, value); } catch (e) { /* private mode */ }
    if (typeof window.gtag === 'function') {
      window.gtag('consent', 'update', {
        analytics_storage: value === 'granted' ? 'granted' : 'denied'
      });
    }
  }

  function showConsentBar() {
    if (document.querySelector('.consent-bar')) return;
    var bar = document.createElement('div');
    bar.className = 'consent-bar';
    bar.setAttribute('role', 'dialog');
    bar.setAttribute('aria-label', 'Cookie choices');
    bar.innerHTML =
      '<p>We use Google Analytics to count visits and see which link brought you here. ' +
      'Accepting sets one cookie. Decline and nothing is stored. ' +
      '<a href="/privacy">Privacy policy</a></p>' +
      '<div class="consent-actions">' +
        '<button type="button" data-consent="denied">Decline</button>' +
        '<button type="button" data-consent="granted">Accept</button>' +
      '</div>';
    bar.addEventListener('click', function (e) {
      var btn = e.target && e.target.closest ? e.target.closest('button[data-consent]') : null;
      if (!btn) return;
      setConsent(btn.getAttribute('data-consent'));
      bar.remove();
    });
    document.body.appendChild(bar);
  }

  if (!readConsent()) showConsentBar();

  // ── Conversion clicks ──────────────────────────────────────────────────────
  // Two clicks count as converting on the marketing site: heading to the Play
  // Store, and opening the web app. Enhanced Measurement would catch the Play
  // Store one on its own (it is outbound), but the "Open the App" link is
  // SAME-DOMAIN and the app root is deliberately untagged — so without this the
  // more important of the two conversions is completely invisible. Tracking both
  // explicitly also keeps them comparable and independent of whatever Enhanced
  // Measurement happens to be set to.
  //
  // If consent was declined these fire as unreported cookieless pings, which is
  // the intended behaviour — declined visitors are not measured.
  document.addEventListener('click', function (e) {
    if (typeof window.gtag !== 'function') return;
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;

    var href = a.getAttribute('href') || '';
    var name = null;
    if (href.indexOf('play.google.com') !== -1) {
      name = 'play_store_click';
    } else if (href === '/' || /^https?:\/\/(www\.)?tablelab\.app\/(\?|$)/.test(href)) {
      name = 'open_app_click';
    }
    if (!name) return;

    // gtag uses sendBeacon where available, so the hit survives the navigation.
    window.gtag('event', name, {
      link_url: href,
      source_page: location.pathname
    });
  });

  // Let the choice be revisited. Injected rather than hand-added to every page's
  // duplicated footer, so there is one copy to maintain.
  var footerLinks = document.querySelector('footer a[href="/terms"]');
  if (footerLinks && footerLinks.parentNode) {
    var sep = document.createTextNode(' · ');
    var link = document.createElement('a');
    link.href = '#';
    link.textContent = 'Cookie choices';
    link.addEventListener('click', function (e) {
      e.preventDefault();
      showConsentBar();
    });
    footerLinks.parentNode.insertBefore(sep, footerLinks.nextSibling);
    footerLinks.parentNode.insertBefore(link, sep.nextSibling);
  }
})();
