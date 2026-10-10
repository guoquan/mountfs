#!/usr/bin/env python3
"""Render the two dependency-free GitHub Pages editions from aligned copy."""
from html import escape
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parents[1]
REPO = 'https://github.com/guoquan/mountfs'
# Production links are durable. Set CONTENT_REF explicitly for a staging render.
REF = os.environ.get('CONTENT_REF', 'main')
COPY = {
 'en': {
  'file': 'index.html', 'other': 'zh-CN.html', 'switch': '简体中文', 'otherlang': 'zh-CN',
  'title': 'mouNTFS — Write to NTFS. On your Mac.',
  'description': 'A free, open-source Mac menu bar app for external NTFS drives. Keep NTFS, enable writing and continue in Finder. Requires macFUSE and ntfs-3g.',
  'skip': 'Skip to content', 'nav': ['The app', 'Get started', 'Our story'],
  'eyebrow': 'Free & open source · For macOS', 'headline': ['Write to NTFS.', 'On your Mac.'],
  'hero': 'No reformatting. Enable writing from the menu bar, then copy files in Finder.',
  'cta': 'Get the development app', 'source': 'View source',
  'fine': 'macOS 13+ · Requires macFUSE, ntfs-3g and system permissions. Development builds are ad-hoc signed and not notarized.',
  'heroalt': 'Actual mouNTFS menu with a sample drive marked writable',
  'caption': 'Actual app UI · Sample drive data · UI currently in English',
  'benefits': [('Keep NTFS', 'Use the drive you already have.'), ('Continue in Finder', 'Copy and edit files after enabling writing.'), ('Free & open source', 'MIT licensed. No app license activation.')],
  'workflowtitle': 'Your drive. Your usual workflow.',
  'workflowintro': 'After driver setup, everyday use starts in the menu bar.',
  'steps': [('Connect your drive', 'Open mouNTFS and select the external NTFS partition you want to use.'), ('Enable writing', 'Choose Enable Write Access, complete macOS authorization and wait for mounting to finish.'), ('Continue in Finder', 'Copy and edit files. Close files before using Safely Eject when you are finished.')],
  'showtitle': 'A small app, right where you need it.',
  'showintro': 'See your drives, enable writing and open Finder from the menu bar. Progress stays visible while the app works; reports are there when you need them.',
  'tablabel': 'Example app states', 'tabs': ['Read-only', 'Writable', 'In progress'],
  'alts': ['Actual menu with a read-only sample NTFS drive', 'Actual menu with a writable sample NTFS drive', 'Actual menu during a sample mounting operation'],
  'sample': 'Sample interface states; no disk was mounted to create these captures.',
  'nojs': 'The writable example is shown below. Enable JavaScript to switch between all three examples.',
  'installtitle': 'A little setup. Then back to your files.',
  'installintro': 'Start with the drivers, then add the app. These steps are required before you can enable writing.',
  'driverlabel': '01 · Drivers & permissions', 'drivertitle': 'Prepare your Mac',
  'driverintro': 'With Homebrew installed, run these two commands:',
  'copy': 'Copy commands', 'copied': 'Commands copied.', 'fallback': 'Commands selected. Press ⌘C or Ctrl+C to copy.',
  'driverafter': 'Follow the macFUSE setup guide for approval and restart requirements. The default kernel backend may require a startup security change on Apple Silicon.',
  'driverlink': 'macFUSE setup guide ↗',
  'downloadlabel': '02 · Development download', 'downloadtitle': 'Add mouNTFS to Applications',
  'downloadintro': 'Builds are currently distributed through GitHub Actions, rather than as a notarized public release.',
  'downloadsteps': ['Open Checks and choose a successful run for the native-app development branch.', 'Sign in to GitHub and download the development-app artifact. Extract the outer ZIP and the versioned archive inside it.', 'Quit the old app if updating, then place mouNTFS.app in Applications. Open it and connect your drive.'],
  'downloadcta': 'Browse app builds ↗', 'guidelink': 'Full installation guide ↗',
  'permissionnote': 'Device access denied? Check Full Disk Access for the actual ntfs-3g executable. Administrator authorization is a separate permission. The usage guide covers both.',
  'faqtitle': 'Before you plug in.', 'faqintro': 'A few things worth knowing before your first write.',
  'questions': [
   ('Will it format my drive?', 'No. mouNTFS enables writing to an existing external NTFS partition. It does not format drives. A damaged or hibernated volume may need attention in Windows before writing can be enabled.'),
   ('Does it enable writing automatically?', 'No. Connecting a drive updates the list; you choose when to enable writing. macOS may request administrator authorization during an operation. The app does not save your password.'),
   ('Can I use any Mac or NTFS drive?', 'The app requires macOS 13+ and compatible drivers. Ordinary mounting has limited user-reported success on Apple Silicon; broader hardware and driver combinations still need testing. Only external NTFS partitions are mount targets.'),
   ('What if it does not work?', 'Open Diagnostics for the operation log and read-only disk scan. Check the usage guide for driver compatibility, permissions and busy drives. Do not format a drive just because an operation failed.')],
  'faqguide': 'Usage & troubleshooting ↗',
  'storylabel': 'Human–AI collaboration', 'storytitle': 'Built with AI.<br>Shaped by humans.',
  'story': 'An experiment in making a useful little tool together. AI writes the code; humans lead the design, review, testing and direction. From a shell script to a native Mac app, the project keeps growing with real-world feedback.',
  'contribute': 'Help shape the next step ↗', 'sponsor': 'Support the project ↗',
  'footer': 'Free & open source · MIT License', 'issues': 'Report an issue', 'docs': 'Documentation', 'roadmap': 'Roadmap',
 },
 'zh-CN': {
  'file': 'zh-CN.html', 'other': 'index.html', 'switch': 'English', 'otherlang': 'en',
  'title': 'mouNTFS — Mac，也能写入 NTFS。',
  'description': '免费开源的 Mac NTFS 菜单栏工具。保留磁盘格式，启用写入，继续在 Finder 中使用。需安装 macFUSE 与 ntfs-3g。',
  'skip': '跳到正文', 'nav': ['看看应用', '开始使用', '项目故事'],
  'eyebrow': '免费开源 · 为 macOS 而做', 'headline': ['Mac，也能', '写入 NTFS。'],
  'hero': '无需格式化。从菜单栏启用写入，继续在 Finder 中拷贝文件。',
  'cta': '获取开发版应用', 'source': '查看源代码',
  'fine': 'macOS 13+ · 需安装 macFUSE、ntfs-3g 并完成系统授权。开发构建使用 ad-hoc 签名，尚未公证。',
  'heroalt': 'mouNTFS 实际菜单界面，示例磁盘显示可写状态',
  'caption': '实际应用界面 · 示例磁盘数据 · 当前界面为英文',
  'benefits': [('保留 NTFS 格式', '继续使用你已有的磁盘。'), ('继续在 Finder 中使用', '启用写入后，拷贝和编辑文件。'), ('免费开源', 'MIT 许可，无需激活应用许可证。')],
  'workflowtitle': '你的磁盘，熟悉的使用方式。',
  'workflowintro': '完成驱动配置后，日常使用从菜单栏开始。',
  'steps': [('连接磁盘', '打开 mouNTFS，从菜单中选择要使用的外置 NTFS 分区。'), ('启用写入', '点击 Enable Write Access，完成 macOS 授权，等待挂载完成。'), ('继续在 Finder 中使用', '拷贝和编辑文件。用完关闭占用磁盘的文件，再点 Safely Eject 安全弹出。')],
  'showtitle': '一个小应用，就在菜单栏。',
  'showintro': '查看磁盘，启用写入，打开 Finder。操作时显示进度，需要排查时再查看报告，不用一直盯着终端。',
  'tablabel': '应用界面示例状态', 'tabs': ['只读', '可写', '进行中'],
  'alts': ['实际菜单界面，显示只读示例 NTFS 磁盘', '实际菜单界面，显示可写示例 NTFS 磁盘', '实际菜单界面，显示挂载操作进行中的示例状态'],
  'sample': '界面状态为示例；生成截图时未执行磁盘挂载。',
  'nojs': '下方显示可写示例。启用 JavaScript 后可切换三个界面示例。',
  'installtitle': '先做好配置，再回到你的文件。',
  'installintro': '先安装驱动，再放入应用。完成这些步骤后，才能启用写入。',
  'driverlabel': '01 · 驱动与权限', 'drivertitle': '准备好你的 Mac',
  'driverintro': '安装 Homebrew 后，执行这两条命令：',
  'copy': '复制命令', 'copied': '命令已复制。', 'fallback': '命令已选中，请按 ⌘C 或 Ctrl+C 复制。',
  'driverafter': '按 macFUSE 安装指南完成批准和重启。默认内核后端在 Apple Silicon 上可能需要调整启动安全策略。',
  'driverlink': 'macFUSE 安装指南 ↗',
  'downloadlabel': '02 · 下载开发构建', 'downloadtitle': '将 mouNTFS 放入 Applications',
  'downloadintro': '目前通过 GitHub Actions 提供开发构建，尚未作为已公证的正式版本发布。',
  'downloadsteps': ['打开 Checks，选择原生应用开发分支中成功的构建。', '登录 GitHub，下载 development-app artifact。解压外层 ZIP，再解压内部带版本号的下载包。', '更新时先退出旧应用，再将 mouNTFS.app 放入 Applications。打开应用，连接磁盘。'],
  'downloadcta': '查看应用构建 ↗', 'guidelink': '完整安装说明 ↗',
  'permissionnote': '设备访问被拒绝？核对实际 ntfs-3g 可执行文件的完全磁盘权限。管理员授权是另一项权限，使用说明中有对应处理步骤。',
  'faqtitle': '插盘之前，先了解这些。', 'faqintro': '首次启用写入前，你可能关心的几个问题。',
  'questions': [
   ('会格式化我的磁盘吗？', '不会。mouNTFS 为已有外置 NTFS 分区启用写入，不格式化磁盘。损坏或处于休眠状态的卷，可能需要先在 Windows 中处理，才能启用写入。'),
   ('插盘后会自动启用写入吗？', '不会。插盘只更新列表，由你决定何时启用写入。操作时 macOS 可能要求管理员授权，应用不保存密码。'),
   ('所有 Mac 和 NTFS 磁盘都能用吗？', '应用需要 macOS 13 或以上及兼容驱动。普通挂载已有有限的 Apple Silicon 使用反馈，更多硬件和驱动组合仍需验证；目前只处理外置 NTFS 分区。'),
   ('遇到问题怎么办？', '在 Diagnostics 中查看操作日志和只读磁盘扫描。使用说明涵盖驱动兼容、权限及磁盘忙碌等情况。不要因为操作失败就格式化磁盘。')],
  'faqguide': '使用与故障处理 ↗',
  'storylabel': '人机协同开发', 'storytitle': '与 AI 一起开发，<br>由人类把握方向。',
  'story': '这是一场把小工具做得更好用的人机协同实验。AI 写代码，人类负责设计、审查、测试与方向。从 Shell 脚本到原生 Mac 应用，项目在真实使用反馈中继续成长。',
  'contribute': '一起完善下一步 ↗', 'sponsor': '支持这个项目 ↗',
  'footer': '免费开源 · MIT 许可', 'issues': '反馈问题', 'docs': '使用说明', 'roadmap': '后续计划',
 },
}

def render(lang, c):
    e = escape
    zh = lang == 'zh-CN'
    guide = f'{REPO}/blob/{REF}/docs/USAGE.{"zh-CN" if zh else "en"}.md'
    source = f'{REPO}/tree/{REF}'
    builds = f'{REPO}/actions/workflows/checks.yml?query=branch%3A{REF.replace("/", "%2F")}'
    canonical = 'https://mountfs.sh/' + (c['file'] if zh else '')
    icons = ['<path d="M5 5h14v14H5zM8 15h.01M8 9h8"/>', '<path d="M4 7h6l2 2h8v11H4zM4 7V4h6l2 3"/>', '<path d="m8 7-5 5 5 5m8-10 5 5-5 5m-3-13-2 16"/>']
    benefits = ''.join(f'<div class="benefit"><span class="symbol" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">{symbol}</svg></span><div><strong>{e(title)}</strong><p>{e(body)}</p></div></div>' for symbol, (title, body) in zip(icons, c['benefits']))
    workflow_heading = e(c['workflowtitle']).replace('，', '，<br class="mobile-break">', 1) if zh else e(c['workflowtitle'])
    install_heading = e(c['installtitle']).replace('，', '，<br class="mobile-break">', 1) if zh else e(c['installtitle'])
    steps = ''.join(f'<article class="step"><div class="number">0{i}</div><h3>{e(title)}</h3><p>{e(body)}</p></article>' for i, (title, body) in enumerate(c['steps'], 1))
    tabs = ''.join(f'<button class="tab" role="tab" id="tab-{i}" aria-controls="panel-{i}" aria-selected="{str(i == 1).lower()}" tabindex="{0 if i == 1 else -1}">{e(title)}</button>' for i, title in enumerate(c['tabs']))
    panels = ''.join(f'<div id="panel-{i}" role="tabpanel" aria-labelledby="tab-{i}" tabindex="0" {"hidden" if i != 1 else ""}><img src="assets/menu-{state}.png" alt="{e(c["alts"][i])}" width="356" height="351" loading="lazy"></div>' for i, state in enumerate(['readonly', 'writable', 'progress']))
    downloadsteps = ''.join(f'<li>{e(s)}</li>' for s in c['downloadsteps'])
    questions = ''.join(f'<details><summary>{e(q)}</summary><p>{e(a)}</p></details>' for q, a in c['questions'])
    return f'''<!doctype html>
<html lang="{lang}">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{e(c['title'])}</title><meta name="description" content="{e(c['description'])}">
  <meta name="theme-color" content="#fcfcff"><link rel="canonical" href="{canonical}">
  <link rel="alternate" hreflang="en" href="https://mountfs.sh/">
  <link rel="alternate" hreflang="zh-CN" href="https://mountfs.sh/zh-CN.html">
  <link rel="alternate" hreflang="x-default" href="https://mountfs.sh/">
  <meta property="og:type" content="website"><meta property="og:url" content="{canonical}">
  <meta property="og:title" content="{e(c['title'])}"><meta property="og:description" content="{e(c['description'])}">
  <meta property="og:locale" content="{'zh_CN' if zh else 'en_US'}">
  <meta property="og:image" content="https://mountfs.sh/assets/share.{lang}.png">
  <meta property="og:image:alt" content="{e(c['title'])}"><meta property="og:image:width" content="1254"><meta property="og:image:height" content="1254">
  <meta name="twitter:card" content="summary_large_image"><meta name="twitter:site" content="@guoquan">
  <meta name="twitter:image" content="https://mountfs.sh/assets/share.{lang}.png">
  <link rel="icon" type="image/svg+xml" href="assets/icon.svg">
  <link rel="stylesheet" href="assets/site.css"><script src="assets/site.js" defer></script>
</head>
<body class="{'zh' if zh else 'en'}">
<a class="skip" href="#main">{e(c['skip'])}</a>
<header class="header"><nav class="wrap nav" aria-label="{'主导航' if zh else 'Main navigation'}">
  <a href="{c['file']}" class="wordmark" aria-label="mouNTFS"><span class="mount">mouNT</span><span class="fs">FS</span></a>
  <div class="nav-links"><a class="desktop" href="#app">{e(c['nav'][0])}</a><a href="#get-started">{e(c['nav'][1])}</a><a class="desktop" href="#story">{e(c['nav'][2])}</a><a class="language" href="{c['other']}" lang="{c['otherlang']}" hreflang="{c['otherlang']}">{c['switch']}</a></div>
</nav></header>
<main id="main">
<section class="hero"><div class="wrap"><div class="hero-grid">
  <div class="hero-text">
    <h1>{e(c['headline'][0])}<span>{e(c['headline'][1])}</span></h1><p class="hero-copy">{e(c['hero'])}</p>
    <div class="actions"><a class="button primary" href="#get-started">{e(c['cta'])}<span aria-hidden="true">↓</span></a><a class="button" href="{source}">{e(c['source'])}<span aria-hidden="true">↗</span></a></div>
    <p class="fine">{e(c['fine'])}</p><p class="hero-signoff">{e(c['eyebrow'])}</p>
  </div>
  <figure class="hero-art"><img class="app-image" src="assets/menu-writable.png" alt="{e(c['heroalt'])}" width="356" height="351" fetchpriority="high"><figcaption>{e(c['caption'])}</figcaption></figure>
</div><div class="benefits">{benefits}</div></div></section>
<section id="app" class="section wrap"><div class="section-head"><h2>{workflow_heading}</h2><p>{e(c['workflowintro'])}</p></div>
  <div class="steps">{steps}</div>
  <div class="showcase"><div><h3>{e(c['showtitle'])}</h3><p>{e(c['showintro'])}</p>
    <div class="tabs" role="tablist" aria-label="{e(c['tablabel'])}" data-tabs>{tabs}</div>
    <noscript><p class="no-js">{e(c['nojs'])}</p></noscript>
  </div><figure class="preview">{panels}<figcaption>{e(c['sample'])}</figcaption></figure></div>
</section>
<section id="get-started" class="section wrap"><div class="section-head"><h2>{install_heading}</h2><p>{e(c['installintro'])}</p></div>
  <div class="install-grid">
    <article class="install-card"><span class="label">{e(c['driverlabel'])}</span><h3>{e(c['drivertitle'])}</h3><p>{e(c['driverintro'])}</p>
      <div class="command"><button class="copy" data-copy="driver-commands" data-success="{e(c['copied'])}" data-fallback="{e(c['fallback'])}">{e(c['copy'])}</button><pre><code id="driver-commands">brew install --cask macfuse
brew install gromgit/fuse/ntfs-3g-mac</code></pre></div><p id="copy-feedback" class="copy-feedback" role="status" aria-live="polite"></p>
      <p>{e(c['driverafter'])}</p><div class="actions"><a class="text-link" href="https://github.com/macfuse/macfuse/wiki/Getting-Started">{e(c['driverlink'])}</a></div>
    </article>
    <article class="install-card"><span class="label">{e(c['downloadlabel'])}</span><h3>{e(c['downloadtitle'])}</h3><p>{e(c['downloadintro'])}</p><ol>{downloadsteps}</ol>
      <div class="actions"><a class="button primary" href="{builds}">{e(c['downloadcta'])}</a><a class="text-link" href="{guide}">{e(c['guidelink'])}</a></div>
    </article>
  </div><p class="notice">{e(c['permissionnote'])}</p>
</section>
<section class="section wrap faq"><div class="section-head"><h2>{e(c['faqtitle'])}</h2><p>{e(c['faqintro'])}</p><div class="actions"><a class="text-link" href="{guide}">{e(c['faqguide'])}</a></div></div><div>{questions}</div></section>
<div class="wrap"><section class="story" id="story"><div><h2>{c['storytitle']}</h2><p class="story-label">{e(c['storylabel'])}</p></div><div><p>{e(c['story'])}</p><div class="actions"><a class="text-link" href="{REPO}/blob/{REF}/CONTRIBUTING.md">{e(c['contribute'])}</a><a class="text-link" href="https://github.com/sponsors/guoquan">{e(c['sponsor'])}</a></div></div></section></div>
</main>
<footer class="footer"><div class="wrap footer-row"><div>{e(c['footer'])}<br>© 2024–2026 <a href="https://guoquan.net">{'郭泉' if zh else 'Quan Guo'}</a></div><div class="footer-links"><a href="{REPO}">GitHub</a><a href="{guide}">{e(c['docs'])}</a><a href="{REPO}/issues">{e(c['issues'])}</a><a href="{REPO}/blob/{REF}/ROADMAP.md">{e(c['roadmap'])}</a></div></div></footer>
</body></html>
'''

if __name__ == '__main__':
    assert COPY['en'].keys() == COPY['zh-CN'].keys(), 'Language keys must match'
    for lang, copy in COPY.items():
        (ROOT / copy['file']).write_text(render(lang, copy), encoding='utf-8')
    print(f'Rendered both language pages; content links use {REF}.')
