import puppeteer from 'puppeteer-core';

const browser = await puppeteer.launch({
  headless: true,
  executablePath: '/root/.cache/ms-playwright/chromium-1194/chrome-linux/chrome',
  args: ['--no-sandbox', '--disable-setuid-sandbox']
});
const page = await browser.newPage();
await page.setViewport({ width: 640, height: 900, deviceScaleFactor: 2 });
await page.goto(`file:///home/user/Agent-monitor-tools/ui-preview.html`);
await new Promise(r => setTimeout(r, 500));
await page.screenshot({ path: '/home/user/Agent-monitor-tools/ui-screenshot.png', fullPage: true });
await browser.close();
console.log('Screenshot saved.');
