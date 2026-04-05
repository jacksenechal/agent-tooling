#!/usr/bin/env node

// Exports storage state (cookies + localStorage) from the golden session's
// running Chromium via Playwright's CDP connection.
//
// Usage: node export-storage-state.js [output-path]
//   output-path defaults to /home/pwuser/storage-state.json
//
// Requires the golden session's Chromium to be running with
// --remote-debugging-port=9222.

const { chromium } = require('playwright-core');
const OUTPUT_PATH = process.argv[2] || '/home/pwuser/storage-state.json';
const CDP_ENDPOINT = process.env.CDP_ENDPOINT || 'http://localhost:9222';

async function main() {
  let browser;
  try {
    browser = await chromium.connectOverCDP(CDP_ENDPOINT);
  } catch (e) {
    console.error(`Cannot connect to golden browser at ${CDP_ENDPOINT}.`);
    console.error('Is the golden session running with --remote-debugging-port=9222?');
    console.error(e.message);
    process.exit(1);
  }

  const contexts = browser.contexts();
  if (contexts.length === 0) {
    console.error('No browser contexts found. Open a page in the golden session first.');
    browser.close();
    process.exit(1);
  }

  // Export storage state from the first (default) context
  const state = await contexts[0].storageState({ path: OUTPUT_PATH });
  console.log(`Storage state exported to ${OUTPUT_PATH}`);
  console.log(`  Cookies: ${state.cookies.length}`);
  console.log(`  Origins with localStorage: ${state.origins.length}`);

  // Disconnect (does not close the browser)
  browser.close();
}

main().catch((e) => {
  console.error('Export failed:', e.message);
  process.exit(1);
});
