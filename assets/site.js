// Progressive enhancement: both language pages and setup copy work without JS.
document.querySelectorAll('[data-tabs]').forEach(group => {
  const tabs = [...group.querySelectorAll('[role="tab"]')];
  const activate = tab => {
    tabs.forEach(item => {
      const selected = item === tab;
      item.setAttribute('aria-selected', String(selected));
      item.tabIndex = selected ? 0 : -1;
      document.getElementById(item.getAttribute('aria-controls')).hidden = !selected;
    });
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => activate(tab));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next !== undefined) {
        event.preventDefault(); activate(tabs[next]); tabs[next].focus();
      }
    });
  });
});
document.querySelectorAll('[data-copy]').forEach(button => {
  button.addEventListener('click', async () => {
    const code = document.getElementById(button.dataset.copy);
    const feedback = document.getElementById('copy-feedback');
    try {
      await navigator.clipboard.writeText(code.textContent.trim());
      feedback.textContent = button.dataset.success;
    } catch {
      const selection = window.getSelection();
      const range = document.createRange(); range.selectNodeContents(code);
      selection.removeAllRanges(); selection.addRange(range);
      feedback.textContent = button.dataset.fallback;
    }
  });
});

// Always leave the durable latest-Release link usable if the API is unavailable.
(async () => {
  const links = [...document.querySelectorAll('[data-latest-release]')];
  if (!links.length) return;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  try {
    const response = await fetch('https://api.github.com/repos/guoquan/mountfs/releases/latest', {
      signal: controller.signal, headers: { Accept: 'application/vnd.github+json' }
    });
    if (!response.ok) return;
    const release = await response.json();
    if (release.draft || release.prerelease || typeof release.tag_name !== 'string' ||
        !/^v\d+\.\d+\.\d+-build\.\d+$/.test(release.tag_name) ||
        !Array.isArray(release.assets) || !release.assets.some(asset =>
          typeof asset.name === 'string' && /^mouNTFS-[\d.]+-dev-(arm64|x86_64)\.zip$/.test(asset.name))) return;
    const destination = 'https://github.com/guoquan/mountfs/releases/tag/' + encodeURIComponent(release.tag_name);
    links.forEach(link => { link.href = destination; });
    const prefix = document.documentElement.lang === 'zh-CN' ? '最新开发构建：' : 'Latest development build: ';
    document.querySelectorAll('[data-release-info]').forEach(item => {
      item.textContent = prefix + release.tag_name;
    });
  } catch { /* Network errors and rate limits keep the static latest link. */ }
  finally { clearTimeout(timeout); }
})();
