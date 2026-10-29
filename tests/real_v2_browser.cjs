// Real bundled UI sign-in smoke; uses the image's globally installed Playwright.
const { chromium, expect } = require('/usr/local/lib/node_modules/@playwright/test')
const base = process.argv[2]
// Hard deadline also bounds launch/close and assertions, not just locator waits.
const deadline = setTimeout(() => {
  console.error('Browser acceptance exceeded 120-second overall deadline')
  process.exit(1)
}, 120000)

async function main() {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] })
  try {
    const page = await browser.newPage()
    page.setDefaultTimeout(15000)
    page.setDefaultNavigationTimeout(30000)
    await page.goto(base)
    await page.getByRole('button', { name: 'Use password', exact: true }).click()
    await page.locator('input[name="server"]').fill(base)
    await page.locator('input[name="password"]').fill('ci-secret')
    await page.getByRole('button', { name: 'Connect', exact: true }).click()
    await expect(page.locator('[data-action="home-add-project"]')).toBeVisible({ timeout: 30000 })
    await expect(page.locator('input[name="password"]')).toHaveCount(0, { timeout: 30000 })
    // The app must retain a working connection after a full reload, not merely
    // hide the sign-in form on submit. No provider credentials/model calls needed.
    await page.reload()
    await expect(page.locator('[data-action="home-add-project"]')).toBeVisible({ timeout: 30000 })
    await expect(page.getByRole('button', { name: 'Use password', exact: true })).toHaveCount(0)
    await expect(page.locator('body')).not.toBeEmpty()
    console.log('PASS: real OpenCode 2.x browser password connection and reload')
  } finally {
    await browser.close()
  }
}
main().catch(error => { console.error(error); process.exitCode = 1 }).finally(() => clearTimeout(deadline))
