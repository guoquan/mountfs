import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const url = process.env.SITE_URL || 'http://127.0.0.1:8080';
const output = process.env.QA_OUTPUT || 'qa-output';
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CHROME_PATH || undefined, headless: true, args: ['--no-sandbox'] });
const report = [];
try {
  for (const [language, file, copyLabel] of [['en', 'index.html', 'Copy commands'], ['zh-CN', 'zh-CN.html', '复制命令']]) {
    for (const width of [320, 390, 768, 1440]) {
      const context = await browser.newContext({ viewport: { width, height: 1000 }, permissions: ['clipboard-read', 'clipboard-write'] });
      const page = await context.newPage();
      const errors = []; const failures = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('response', response => { if (response.status() >= 400 && response.url().startsWith(url)) failures.push(response.url()); });
      await page.goto(`${url}/${file}`, { waitUntil: 'networkidle' });
      await page.evaluate(() => document.fonts.ready);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
      assert.equal(overflow, false, `${language} at ${width}px has horizontal overflow`);
      const images = await page.locator('img').evaluateAll(images => images.every(image => image.complete && image.naturalWidth > 0));
      // Hidden lazy-loaded previews are checked after selecting their tab below.
      const hero = page.locator('.app-image');
      assert.equal(await hero.evaluate(image => image.complete && image.naturalWidth > 0), true);
      for (const index of [0, 2, 1]) {
        await page.locator(`#tab-${index}`).click();
        await page.locator(`#panel-${index} img`).waitFor({ state: 'visible' });
        await page.waitForFunction(i => {
          const img = document.querySelector(`#panel-${i} img`); return img.complete && img.naturalWidth > 0;
        }, index);
        assert.equal(await page.locator('[role="tabpanel"]:visible').count(), 1);
        assert.equal(await page.locator(`#tab-${index}`).getAttribute('aria-selected'), 'true');
      }
      await page.locator('#tab-1').focus(); await page.keyboard.press('ArrowRight');
      assert.equal(await page.locator('#tab-2').getAttribute('aria-selected'), 'true');
      await page.keyboard.press('Home');
      assert.equal(await page.locator('#tab-0').getAttribute('aria-selected'), 'true');
      await page.locator('#tab-1').click();
      await page.getByRole('button', { name: copyLabel, exact: true }).click();
      assert.equal(await page.evaluate(() => navigator.clipboard.readText()), 'brew install --cask macfuse\nbrew install gromgit/fuse/ntfs-3g-mac');
      const question = page.locator('summary').first(); await question.click();
      assert.equal(await page.locator('details').first().getAttribute('open'), '');
      await question.click();
      await page.locator('.language').click();
      assert.equal(await page.locator('html').getAttribute('lang'), language === 'en' ? 'zh-CN' : 'en');
      await page.goto(`${url}/${file}`, { waitUntil: 'networkidle' });
      await page.screenshot({ path: `${output}/${language}-${width}.png`, fullPage: true });
      if (width === 1440) await page.screenshot({ path: `${output}/${language}-hero.png` });
      assert.deepEqual(errors, []); assert.deepEqual(failures, []);
      report.push({ language, width, layout: 'no horizontal overflow', tabs: 'click and keyboard passed', copy: 'passed', faq: 'passed', languageSwitch: 'passed', errors, failures, allImagesInitiallyLoaded: images });
      await context.close();
    }
    const context = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
    const page = await context.newPage(); await page.goto(`${url}/${file}`);
    assert.equal(await page.locator('h1').isVisible(), true);
    assert.equal(await page.locator('#panel-1').isVisible(), true);
    assert.equal(await page.locator('.no-js').isVisible(), true);
    assert.equal(await page.locator('.language').isVisible(), true);
    await context.close();
  }
  await writeFile(`${output}/report.json`, JSON.stringify(report, null, 2));
  console.log('Both languages passed at 320, 390, 768 and 1440px; tabs, keyboard, copy, FAQ, language switching and no-JS content verified.');
} finally { await browser.close(); }
