// Console screenshots for a live drill, taken on the GitHub runner with headless Chromium.
//
// Usage (repo root, inside the drill job, after apply):
//   node live/console-shots.mjs <stack> <outputs.json> <out_dir>
// Needs: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN (the drill role's OIDC session),
//        ACCOUNT_ID (to redact), AWS_REGION. Reads live/screenshots.yml.
//
// How it signs in: the role's temporary credentials go to AWS's federation endpoint, which returns a
// one-time sign-in token; Chromium opens the console with it. Credentials and the sign-in URL never leave
// this process and are never logged. The session can only do what the drill role can do.
//
// Redaction, before every capture: every occurrence of the account ID in the page (text, input values,
// titles) becomes <ACCOUNT_ID>, and the console header (user, account, region menu) is masked. The page is
// then searched again and the capture is refused if the account ID is still visible.
//
// Output: <out_dir>/<name>.png at 2x device pixels (3200 x 2000 for the 1600 x 1000 viewport), lossless.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { chromium } from "playwright";

const [stack, outputsPath, outDir] = process.argv.slice(2);
if (!stack || !outputsPath || !outDir) {
  console.error("usage: node live/console-shots.mjs <stack> <outputs.json> <out_dir>");
  process.exit(2);
}
const { AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, ACCOUNT_ID } = process.env;
const region = process.env.AWS_REGION ?? "us-east-1";
if (!AWS_ACCESS_KEY_ID || !AWS_SECRET_ACCESS_KEY || !AWS_SESSION_TOKEN || !/^\d{12}$/.test(ACCOUNT_ID ?? "")) {
  console.error("console-shots: missing role credentials or ACCOUNT_ID");
  process.exit(2);
}

// live/screenshots.yml -> JSON with yq (preinstalled on GitHub's Ubuntu images).
const all = JSON.parse(execFileSync("yq", ["-o=json", "live/screenshots.yml"], { encoding: "utf8" }));
const entries = all[stack] ?? [];
if (!entries.length) {
  console.log(`console-shots: no screenshots listed for ${stack}`);
  process.exit(0);
}

// {region} and {<output>} from `terraform output -json` (string outputs only).
const outputs = JSON.parse(readFileSync(outputsPath, "utf8"));
const fill = (url) =>
  url.replace(/\{([a-z0-9_]+)\}/g, (m, key) => {
    if (key === "region") return region;
    const v = outputs[key]?.value;
    if (typeof v !== "string") throw new Error(`screenshots.yml uses {${key}}, which is not a string output of ${stack}`);
    return encodeURIComponent(v);
  });

async function signinUrl(destination) {
  const session = JSON.stringify({ sessionId: AWS_ACCESS_KEY_ID, sessionKey: AWS_SECRET_ACCESS_KEY, sessionToken: AWS_SESSION_TOKEN });
  const tokenRes = await fetch("https://signin.aws.amazon.com/federation", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ Action: "getSigninToken", Session: session }),
  });
  if (!tokenRes.ok) throw new Error(`federation getSigninToken answered HTTP ${tokenRes.status}`);
  const { SigninToken } = await tokenRes.json();
  const q = new URLSearchParams({
    Action: "login",
    Issuer: "https://github.com/rodrigopimenta10/aws-platform-terraform",
    Destination: destination,
    SigninToken,
  });
  return `https://signin.aws.amazon.com/federation?${q}`;
}

// Replace the account ID everywhere in the page; return how many visible occurrences remain.
async function redact(page) {
  return page.evaluate((id) => {
    const dashed = `${id.slice(0, 4)}-${id.slice(4, 8)}-${id.slice(8)}`;
    const swap = (s) => s.split(id).join("<ACCOUNT_ID>").split(dashed).join("<ACCOUNT_ID>");
    const roots = [document];
    for (const el of document.querySelectorAll("*")) if (el.shadowRoot) roots.push(el.shadowRoot);
    for (const root of roots) {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        if (n.nodeValue.includes(id) || n.nodeValue.includes(dashed)) n.nodeValue = swap(n.nodeValue);
      }
      for (const el of root.querySelectorAll("input, textarea")) if (el.value.includes(id)) el.value = swap(el.value);
      for (const el of root.querySelectorAll("[title], [aria-label]")) {
        for (const a of ["title", "aria-label"]) {
          const v = el.getAttribute(a);
          if (v && (v.includes(id) || v.includes(dashed))) el.setAttribute(a, swap(v));
        }
      }
    }
    const text = document.body.innerText;
    return (text.split(id).length - 1) + (text.split(dashed).length - 1);
  }, ACCOUNT_ID);
}

const HEADER = [
  "#awsc-navigation-container",
  "header#awsc-nav-header",
  "[data-testid='awsc-nav-header']",
  "#awsc-top-level-nav",
  "[data-testid='awsc-nav-account-menu-button']",
];

async function steps(page, entry) {
  for (const step of entry.steps ?? []) {
    if (step.tab) await page.getByRole("tab", { name: step.tab, exact: false }).first().click();
    if (step.search) {
      const box = page.getByRole("searchbox").or(page.getByPlaceholder(/find|search|filter/i)).first();
      await box.fill(step.search);
      await box.press("Enter");
    }
    if (step.click) await page.getByText(step.click, { exact: false }).first().click();
    if (step.wait_for) await page.getByText(step.wait_for, { exact: false }).first().waitFor({ timeout: 30_000 });
    await page.waitForTimeout(1500);
  }
}

async function dismissPopups(page) {
  for (const name of ["Dismiss", "Close", "Got it", "Not now", "Accept all"]) {
    const b = page.getByRole("button", { name, exact: true });
    if (await b.count()) await b.first().click({ timeout: 2000 }).catch(() => {});
  }
}

mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1600, height: 1000 },
  deviceScaleFactor: 2,
  locale: "en-US",
  timezoneId: "UTC",
  colorScheme: "light",
});
const page = await context.newPage();
const results = [];
let failed = 0;
try {
  await page.goto(await signinUrl(fill(entries[0].url)), { waitUntil: "domcontentloaded", timeout: 90_000 });
  for (const entry of entries) {
    const file = join(outDir, `${entry.name}.png`);
    try {
      await page.goto(fill(entry.url), { waitUntil: "domcontentloaded", timeout: 60_000 });
      await page.waitForLoadState("networkidle", { timeout: 30_000 }).catch(() => {});
      await page.waitForTimeout(3000); // console tables fill in after the network settles
      await dismissPopups(page);
      await steps(page, entry);
      const left = await redact(page);
      if (left > 0) throw new Error(`account ID still visible ${left} time(s) after redaction`);
      const mask = HEADER.map((s) => page.locator(s));
      await page.screenshot({ path: file, type: "png", mask, maskColor: "#000000", animations: "disabled" });
      results.push({ name: entry.name, file: `${entry.name}.png`, proves: entry.proves, ok: true });
      console.log(`console-shots: ${entry.name} ok`);
    } catch (e) {
      failed += 1;
      results.push({ name: entry.name, proves: entry.proves, ok: false, error: String(e.message ?? e).slice(0, 300) });
      console.log(`console-shots: ${entry.name} FAILED: ${String(e.message ?? e).slice(0, 300)}`);
    }
  }
} finally {
  await browser.close();
}
writeFileSync(join(outDir, "screenshots.json"), JSON.stringify(results, null, 2));
console.log(`console-shots: ${results.length - failed}/${results.length} captured`);
// Screenshots are evidence, not a gate: a missing one never blocks the destroy that follows.
process.exit(0);
