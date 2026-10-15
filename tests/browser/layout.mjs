import assert from "node:assert/strict";
import { createReadStream, existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const site = join(root, "_build/browser-site");
const evidence = JSON.parse(readFileSync(join(root, "examples/layout_playground/evidence.json"), "utf8"));
const output = (name) => join(root, `_build/browser-layout-${name}`);
for (const page of ["index.html", "proof.html", "layout.html"]) assert.ok(existsSync(join(site, page)));
const server = createServer((request, response) => {
  let path;
  try { path = decodeURIComponent(new URL(request.url, "http://localhost").pathname); }
  catch { response.writeHead(400).end(); return; }
  // Serve below the real Pages prefix so root-absolute asset regressions fail.
  if (!path.startsWith("/gpui.mbt/")) { response.writeHead(404).end(); return; }
  const file = normalize(join(site, path.slice("/gpui.mbt/".length) || "index.html"));
  if (!file.startsWith(`${site}/`) || !existsSync(file) || !statSync(file).isFile()) { response.writeHead(404).end(); return; }
  response.writeHead(200, { "content-type": { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json" }[extname(file)] || "application/octet-stream" });
  createReadStream(file).pipe(response);
});

const passed = [];
const errors = [];
let browser;
let page;
let stage = "production server";
const bounds = () => page.locator("#live-canvas").getAttribute("data-bounds").then(JSON.parse);
async function settled(status) {
  await page.waitForFunction((value) => document.querySelector("#comparison")?.dataset.status === value, status);
  assert.equal(await page.locator("#diagnostic").isVisible(), false);
}
async function select(index) {
  await page.locator("#preset").selectOption(String(index));
  await settled("match");
}
async function edit(label, value) {
  const control = page.getByRole("spinbutton", { name: label, exact: true });
  const { field, child } = await control.evaluate((input) => ({ ...input.dataset }));
  await control.fill(String(value));
  await control.press("Tab");
  await page.waitForFunction(({ field, child, expected }) => {
    const config = JSON.parse(document.querySelector("#live-canvas").dataset.config);
    return (config.children[Number(child)][field] ?? null) === expected;
  }, { field, child, expected: value === "" ? null : Number(value) });
  await settled("unmeasured");
}
function closeEnough(actual, expected) {
  for (let i = 0; i < expected.length; i += 1) {
    for (let j = 0; j < 4; j += 1) assert.ok(Math.abs(actual[i][j] - expected[i][j]) <= evidence.tolerance);
  }
}

try {
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  browser = await chromium.launch({ headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH } : {}) });
  page = await browser.newPage({ viewport: { width: 1440, height: 1050 } });
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("response", (response) => { if (response.status() >= 400) errors.push(`${response.status()} ${response.url()}`); });
  const url = `http://127.0.0.1:${server.address().port}/gpui.mbt/`;
  stage = "all measured cases through real browser controls";
  await page.goto(`${url}layout.html`);
  for (let i = 0; i < evidence.cases.length; i += 1) {
    await select(i);
    closeEnough(await bounds(), evidence.cases[i].upstream);
    assert.equal(await page.locator("#delta").textContent(), "0 pt");
  }
  passed.push("29 measured browser cases / exact coordinate tables");

  stage = "live grow shrink gap min max and reset";
  await select(0);
  await edit("Child A max", "");
  closeEnough(await bounds(), [[0,0,100,20],[0,0,50,10],[50,0,50,10]]);
  await edit("Child A grow", 3);
  closeEnough(await bounds(), [[0,0,100,20],[0,0,65,10],[65,0,35,10]]);
  const saved = await page.locator("#upstream-canvas").getAttribute("data-bounds");
  assert.equal(saved, JSON.stringify(evidence.cases[0].upstream));
  assert.equal(await page.locator("#delta").textContent(), "—");
  await page.getByRole("spinbutton", { name: "Child A max", exact: true }).fill("30");
  await page.getByRole("spinbutton", { name: "Child A grow", exact: true }).fill("1");
  await settled("match");
  await page.locator("#reset").click(); await settled("match");
  assert.equal(await page.locator("#reset").evaluate((button) => button === document.activeElement), true);
  assert.equal(await page.getByRole("spinbutton", { name: "Child A min", exact: true }).inputValue(), "0");
  await page.getByRole("slider", { name: "Container gap", exact: true }).focus();
  await page.keyboard.press("ArrowRight"); await settled("unmeasured");
  assert.equal((await bounds())[2][0], 31);
  await page.locator("#reset").click(); await settled("match");
  await page.getByRole("slider", { name: "Container main-axis size", exact: true }).focus();
  await page.keyboard.press("ArrowRight"); await settled("unmeasured");
  assert.equal((await bounds())[0][2], 101);
  await page.getByRole("button", { name: "Minimum shrink", exact: true }).click(); await settled("match");
  await edit("Child A shrink", 0);
  assert.equal((await bounds())[1][2], 40);
  await edit("Child A min", 35);
  await page.locator("#reset").click(); await settled("match");
  await edit("Child A min", 35);
  assert.equal((await bounds())[1][2], 35);
  await page.getByRole("button", { name: "Overflow", exact: true }).click(); await settled("match");
  assert.equal(await page.locator("#overflow").textContent(), "Overflow remains");
  passed.push("grow/shrink/gap/extent/min/max edits, overflow and reset");

  stage = "atomic invalid edits and keyboard select";
  await select(0);
  const initial = await bounds();
  await page.getByRole("spinbutton", { name: "Child A min", exact: true }).fill("31");
  assert.equal(await page.getByRole("spinbutton", { name: "Child A min", exact: true }).getAttribute("aria-invalid"), "true");
  assert.deepEqual(await bounds(), initial);
  assert.match(await page.locator("#input-message").textContent(), /not applied/);
  await page.locator("#reset").click(); await settled("match");
  await page.locator('[data-field="direction"]').focus();
  await page.keyboard.press("ArrowDown"); await settled("unmeasured");
  assert.equal((await bounds())[0][3], 100);
  await page.locator('[data-field="justify"]').selectOption("2");
  await select(3);
  await page.locator('[data-field="justify"]').selectOption("2");
  await settled("unmeasured");
  assert.equal((await bounds())[1][0], 30);
  passed.push("invalid min/max preserves valid state; keyboard direction and justify");

  stage = "canvas pixels and responsive layouts";
  await select(0);
  assert.ok(await page.locator("#live-canvas").evaluate((canvas) => {
    const data = canvas.getContext("2d").getImageData(0,0,canvas.width,canvas.height).data;
    let a = 0; let b = 0;
    for (let i = 0; i < data.length; i += 4) {
      if (data[i] === 107 && data[i+1] === 135 && data[i+2] === 81) a += 1;
      if (data[i] === 203 && data[i+1] === 148 && data[i+2] === 101) b += 1;
    }
    return a > 100 && b > 100;
  }));
  await page.screenshot({ path: output("desktop.png"), fullPage: true });
  for (const width of [1024, 768, 720, 390, 320]) {
    await page.setViewportSize({ width, height: 900 });
    await page.waitForFunction(() => {
      const c = document.querySelector("#live-canvas");
      return Math.abs(c.width - Math.round(c.getBoundingClientRect().width * devicePixelRatio)) <= 1;
    });
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `no page overflow at ${width}`);
    assert.ok((await page.locator("#live-canvas").boundingBox()).width > 200);
  }
  await page.screenshot({ path: output("mobile.png"), fullPage: true });
  const mobile = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const touch = await mobile.newPage();
  await touch.goto(`${url}layout.html`);
  await touch.getByRole("button", { name: "Minimum shrink", exact: true }).tap();
  await touch.waitForFunction(() => document.querySelector("#size-b").textContent === "10 pt");
  await touch.close(); await mobile.close();
  passed.push("painted canvas; 320–1440px layouts; touch and DPR 2");

  stage = "retained demo navigation under Pages base";
  await page.getByRole("link", { name: "Weekboard", exact: true }).click();
  await page.waitForFunction(() => window.__gpuiBoardStatus?.()?.active);
  await page.getByRole("link", { name: "Layout Playground ↗", exact: true }).click(); await settled("match");
  await page.getByRole("link", { name: "Interaction Lab", exact: true }).click();
  await page.waitForFunction(() => document.querySelector("#frame-state")?.textContent === "RUNNING");
  await page.getByRole("link", { name: "Layout Playground ↗", exact: true }).click(); await settled("match");
  assert.deepEqual(errors, []);
  passed.push("Weekboard and Interaction Lab remain reachable; Pages prefix assets");
  writeFileSync(output("status.json"), JSON.stringify({ status: "passed", passed, errors }, null, 2));
  console.log(`PASS: ${passed.join("; ")}`);
} catch (error) {
  if (page) await page.screenshot({ path: output("failure.png"), fullPage: true }).catch(() => {});
  writeFileSync(output("status.json"), JSON.stringify({ status: "failed", stage, passed, errors, error: error.stack }, null, 2));
  throw error;
} finally {
  await browser?.close();
  await new Promise((done) => server.close(done));
}
