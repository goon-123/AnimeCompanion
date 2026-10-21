// Real browser interactions with the generated offline report. No source sites.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.MANGA_MATRIX_PLAYWRIGHT || '../Tools/MangaAudit/node_modules/playwright');

(async () => {
  const file = path.resolve(process.argv[2] || 'build/manga-audit/compatibility.html');
  const output = path.resolve(process.argv[3] || 'build/manga-matrix-browser');
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1040 }, acceptDownloads: true });
    const errors = [], network = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (/^https?:/.test(request.url())) network.push(request.url()); });
    await page.route(/^https?:/, route => route.abort());
    await page.goto(pathToFileURL(file).href);
    const data = await page.locator('#matrix-data').evaluate(el => JSON.parse(el.textContent));
    assert(data.rows.length > 0, 'The report needs audited rows');
    for (const status of ['verified', 'partial', 'unsupported', 'unverified']) {
      await page.selectOption('#status', status);
      const expected = data.rows.filter(row => row.status === status).length;
      assert.equal(await page.locator('#rows tr').count(), Math.min(expected, 80));
      assert.equal(await page.locator('#empty').isVisible(), expected === 0);
    }
    await page.click('#clear');
    const tested = data.rows.find(row => row.status === 'verified') || data.rows[0];
    await page.fill('#search', tested.package);
    const matching = data.rows.filter(row => row.package.includes(tested.package));
    assert.equal(await page.locator('#rows tr').count(), Math.min(matching.length, 80));
    await page.locator('.evidence-button').first().click();
    assert(await page.locator('#detail').isVisible());
    assert((await page.locator('#detail-body').innerText()).includes('SHA-256'));
    await page.click('#close');
    const downloadPromise = page.waitForEvent('download');
    await page.click('#download');
    const download = await downloadPromise;
    const csv = await fs.readFile(await download.path(), 'utf8');
    assert(csv.includes('"SHA-256"'));
    assert(csv.includes(tested.sha256));
    await page.click('#clear');
    const language = data.rows.find(row => row.language)?.language;
    if (language) {
      await page.selectOption('#language', language);
      assert.equal(await page.locator('#rows tr').count(), Math.min(80, data.rows.filter(row => row.language === language).length));
    }
    await page.click('#clear');
    if (data.rows.length > 80) {
      const first = await page.locator('#rows tr').first().innerText();
      await page.click('#next');
      assert.notEqual(await page.locator('#rows tr').first().innerText(), first);
      await page.click('#previous');
      assert.equal(await page.locator('#rows tr').first().innerText(), first);
    }
    await page.click('[data-view="dependencies"]');
    assert(await page.locator('#dependencies-view').isVisible());
    assert.equal(await page.locator('#dependencies tr').count(), data.dependencySummary.length);
    await page.click('[data-view="backlog"]');
    if (data.observedGaps.length) {
      await page.locator('.api-button').first().click();
      assert(await page.locator('#sources-view').isVisible());
      assert.equal(await page.inputValue('#search'), data.observedGaps[0].api);
      assert(await page.locator('#rows tr').count() > 0);
    }
    await page.click('[data-view="sources"]');
    await page.click('#clear');
    await page.selectOption('#status', 'verified');
    await page.screenshot({ path: path.join(output, 'desktop.png') });
    await page.setViewportSize({ width: 393, height: 852 });
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await page.screenshot({ path: path.join(output, 'phone.png') });
    assert.deepEqual(errors, [], 'The matrix must have no browser JavaScript errors');
    assert.deepEqual(network, [], 'The offline matrix must make no website requests');
    console.log(JSON.stringify({ rows: data.rows.length, statuses: data.sourceStatuses, checks: 'filters, identities, evidence dialog, CSV, pagination, backlog, phone layout, offline transport' }));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
