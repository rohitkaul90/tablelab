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
})();
