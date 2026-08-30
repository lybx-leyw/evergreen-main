/* T6 审查脚本 — 6 图双主题 / console / 动图 / reduced-motion 程序化验证 */
"use strict";
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const EDGE = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe";
const BASE = "file:///D:/evg-workplace/docs/architecture";
const FILES = [
  "data-hub.html",
  "agent-architecture.html",
  "flywheel.html",
  "workshops.html",
  "agent-workflow.html",
  "three-view.html"
];
const SHOT_DIR = path.join(__dirname, "review");
fs.mkdirSync(SHOT_DIR, { recursive: true });

function summarizeErrors(errs) {
  return errs.length ? errs.slice(0, 8) : [];
}

(async () => {
  const browser = await chromium.launch({ executablePath: EDGE, headless: true });
  const out = [];

  for (const f of FILES) {
    const entry = { file: f, themes: {}, functional: {}, reducedMotion: {} };

    for (const theme of ["light", "dark"]) {
      const page = await browser.newPage({ viewport: { width: 1440, height: 1400 } });
      const consoleErrors = [];
      const pageErrors = [];
      page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });
      page.on("pageerror", (e) => pageErrors.push(String(e)));
      const url = `${BASE}/${f}?theme=${theme}`;
      try {
        await page.goto(url, { waitUntil: "load", timeout: 30000 });
      } catch (e) { consoleErrors.push("goto:" + e.message); }
      await page.waitForTimeout(1400);

      const info = await page.evaluate(() => {
        const r = {};
        r.dataTheme = document.documentElement.getAttribute("data-theme");
        const label = document.querySelector("[data-evg-theme-label]");
        r.label = label ? label.textContent : null;
        r.bodyBg = getComputedStyle(document.body).backgroundColor;
        r.brandingImgs = Array.from(document.images)
          .filter((i) => (i.getAttribute("src") || "").includes("_shared/branding"));
        r.brandingBroken = r.brandingImgs.filter((i) => !(i.complete && i.naturalWidth > 0))
          .map((i) => i.getAttribute("src"));
        r.toggleBtn = !!document.querySelector("[data-evg-theme-toggle]");
        r.reducedMotionNow = matchMedia("(prefers-reduced-motion: reduce)").matches;
        return r;
      });

      // 切换按钮实测（light 页点击 → 应变 dark + 标签「墨」）
      let toggle = null;
      if (theme === "light") {
        try {
          await page.click("[data-evg-theme-toggle]");
          await page.waitForTimeout(350);
          toggle = await page.evaluate(() => ({
            dataTheme: document.documentElement.getAttribute("data-theme"),
            label: (document.querySelector("[data-evg-theme-label]") || {}).textContent
          }));
        } catch (e) { toggle = "click-error:" + e.message; }
      }

      const shot = path.join(SHOT_DIR, `${f.replace(".html", "")}-${theme}.png`);
      await page.screenshot({ path: shot, fullPage: true });

      entry.themes[theme] = {
        consoleErrors: summarizeErrors(consoleErrors),
        pageErrors: summarizeErrors(pageErrors),
        dataTheme: info.dataTheme,
        label: info.label,
        bodyBg: info.bodyBg,
        brandingCount: info.brandingImgs.length,
        brandingBroken: info.brandingBroken,
        toggleBtn: info.toggleBtn,
        toggle: toggle
      };
      await page.close();
    }

    /* ── 功能/动图检查（light 常规页） ── */
    const page = await browser.newPage({ viewport: { width: 1440, height: 1400 } });
    const errs2 = [];
    page.on("pageerror", (e) => errs2.push(String(e)));
    await page.goto(`${BASE}/${f}?theme=light`, { waitUntil: "load", timeout: 30000 });
    await page.waitForTimeout(1200);

    if (f === "data-hub.html") {
      const phase0 = await page.textContent("#dhPhase");
      await page.waitForTimeout(3600);
      const phase1 = await page.textContent("#dhPhase");
      await page.waitForTimeout(3000);
      const phase2 = await page.textContent("#dhPhase");
      entry.functional = {
        phaseProgression: [phase0, phase1, phase2],
        phasesAdvance: !(phase0 === phase1 && phase1 === phase2),
        flowLines: await page.locator(".dh-flow").count(),
        chips: await page.locator(".dh-chip").count(),
        rungs: await page.locator(".dh-rung").count(),
        pipeSteps: await page.locator(".dh-step").count(),
        pageErrors: summarizeErrors(errs2)
      };
    } else if (f === "agent-architecture.html") {
      const mindPaths = await page.locator("#mindLines path").count();
      await page.click(".mind-branch[data-branch=skill] .mind-branch__head");
      await page.waitForTimeout(500);
      const skillCardHidden = await page.evaluate(() => {
        const c = document.querySelector('.detail-card[data-detail="skill"]');
        return c ? c.hidden : "missing";
      });
      const flowLines = await page.locator("#mindLines path.mind-line--flow").count();
      const hash = await page.evaluate(() => location.hash);
      const loopPhases = await page.locator("#loopSvg .phase").count();
      entry.functional = {
        mindPaths,
        skillCardHiddenAfterClick: skillCardHidden,
        flowLinesActive: flowLines,
        hashAfterClick: hash,
        loopPhases,
        pageErrors: summarizeErrors(errs2)
      };
    } else if (f === "flywheel.html") {
      const spokes = await page.locator("#fw-spokes line").count();
      const gaps = await page.locator("#fw-gaps path").count();
      const stations = await page.locator(".fw-station").count();
      const active0 = await page.evaluate(() => document.querySelector(".fw-station.fw-active") ? [...document.querySelectorAll(".fw-station")].indexOf(document.querySelector(".fw-station.fw-active")) : -1);
      await page.waitForTimeout(2600);
      const active1 = await page.evaluate(() => document.querySelector(".fw-station.fw-active") ? [...document.querySelectorAll(".fw-station")].indexOf(document.querySelector(".fw-station.fw-active")) : -1);
      entry.functional = {
        spokes, gaps, stations,
        activeRotation: [active0, active1],
        rotates: active0 !== active1,
        pageErrors: summarizeErrors(errs2)
      };
    } else if (f === "workshops.html") {
      entry.functional = {
        lanes: await page.locator(".evg-lane").count(),
        streams: await page.locator(".ws-stream svg").count(),
        bubbles: await page.locator(".ws-bubble").count(),
        packages: await page.locator(".ws-pkg").count(),
        loaders: await page.locator(".ws-loaders .evg-code").count(),
        flowEdges: await page.locator(".ws-stream .evg-edge--flow").count(),
        pageErrors: summarizeErrors(errs2)
      };
    } else if (f === "agent-workflow.html") {
      const t0 = await page.evaluate(() => {
        const el = document.querySelector(".chip-move");
        return el ? getComputedStyle(el).transform : "missing";
      });
      await page.waitForTimeout(1200);
      const t1 = await page.evaluate(() => {
        const el = document.querySelector(".chip-move");
        return el ? getComputedStyle(el).transform : "missing";
      });
      entry.functional = {
        chipMoveTransform0: t0,
        chipMoveTransform1: t1,
        beltMoves: t0 !== t1,
        badges: await page.locator(".badge-circle").count(),
        ownerNodes: await page.locator("g.evg-node").count(),
        flowSlowEdges: await page.locator(".evg-edge--flow-slow").count(),
        pageErrors: summarizeErrors(errs2)
      };
    } else if (f === "three-view.html") {
      entry.functional = {
        animateMotion: await page.locator("animateMotion").count(),
        routeDots: await page.locator(".route-dot").count(),
        refluxDots: await page.locator(".reflux-dot").count(),
        flowSlowEdges: await page.locator(".evg-edge--flow-slow").count(),
        resChips: await page.locator(".res-chip-rect").count(),
        pageErrors: summarizeErrors(errs2)
      };
    }

    /* ── reduced-motion 降级页 ── */
    const rp = await browser.newPage({ viewport: { width: 1440, height: 1400 } });
    await rp.emulateMedia({ reducedMotion: "reduce" });
    const rerrs = [];
    rp.on("pageerror", (e) => rerrs.push(String(e)));
    await rp.goto(`${BASE}/${f}?theme=light`, { waitUntil: "load", timeout: 30000 });
    await rp.waitForTimeout(1000);
    const rm = await rp.evaluate(() => {
      const sel = [".evg-edge--flow", ".evg-reel--auto", ".evg-float", ".chip-move", ".evg-pulse", ".evg-dot--accent.evg-pulse"].find((s) => document.querySelector(s));
      const el = document.querySelector(sel || ".evg-edge--flow");
      return {
        checked: sel,
        animationName: el ? getComputedStyle(el).animationName : null,
        animationDuration: el ? getComputedStyle(el).animationDuration : null,
        stillAnimated: el ? getComputedStyle(el).animationName !== "none" : null
      };
    });
    entry.reducedMotion = { reduced: rm, pageErrors: summarizeErrors(rerrs) };
    await rp.close();
    await page.close();
    out.push(entry);
  }

  await browser.close();
  console.log(JSON.stringify(out, null, 2));
})().catch((e) => { console.error("FATAL", e); process.exit(1); });
