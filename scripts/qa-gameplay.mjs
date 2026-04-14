import fs from 'fs/promises';
import path from 'path';
import { chromium } from 'playwright';

const QA_URL = process.env.QA_URL || 'http://127.0.0.1:3333/';
const QA_DURATION_MS = Number(process.env.QA_DURATION_MS || 30000);
const QA_STEPS = Number(process.env.QA_STEPS || 40);
const REPORT_DIR = path.resolve(process.cwd(), 'build', 'qa');
const SCREENSHOT_PATH = path.join(REPORT_DIR, 'last-run.png');
const REPORT_PATH = path.join(REPORT_DIR, 'bug-report.md');
const JSON_REPORT_PATH = path.join(REPORT_DIR, 'bug-report.json');

const defects = [];
const logs = [];
const SEVERITY_DEFINITIONS = {
  p0: 'Critical: player cannot start, control, or continue gameplay.',
  p1: 'High: core gameplay is heavily degraded but not fully blocked.',
  p2: 'Medium: noticeable quality issue while gameplay remains possible.',
  p3: 'Low: cosmetic or minor polish issue.',
};
const QA_COVERAGE = [
  'Boot and render: page loads and gameplay canvas is visible.',
  'Gameplay input loop: repeated click and keyboard interactions respond.',
  'Runtime stability: uncaught errors and console errors are tracked.',
  'Front UI continuity: run should not freeze or terminate unexpectedly.',
];
const metrics = {
  startedAt: new Date().toISOString(),
  url: QA_URL,
  durationMs: QA_DURATION_MS,
  stepsRequested: QA_STEPS,
  stepsExecuted: 0,
  uncaughtPageErrors: 0,
  consoleErrors: 0,
  blackFrameSamples: 0,
  frozenFrameStreak: 0,
};

let maxFrozenFrameStreak = 0;

function addDefect(severity, title, details) {
  defects.push({
    severity,
    title,
    details,
    timestamp: new Date().toISOString(),
  });
}

function addLog(message) {
  logs.push({
    timestamp: new Date().toISOString(),
    message,
  });
}

function summarizeDefects() {
  if (defects.length === 0) {
    return 'No P0/P1 defects detected by automated gameplay simulation.';
  }
  return defects
    .map((d, idx) => `${idx + 1}. [${d.severity}] ${d.title} - ${d.details}`)
    .join('\n');
}

async function writeReport() {
  await fs.mkdir(REPORT_DIR, { recursive: true });
  const markdown = `# Gameplay QA Bug Report

## Run Metadata
- URL: ${metrics.url}
- Started at: ${metrics.startedAt}
- Duration target (ms): ${metrics.durationMs}
- Steps requested: ${metrics.stepsRequested}
- Steps executed: ${metrics.stepsExecuted}
- Uncaught page errors: ${metrics.uncaughtPageErrors}
- Console errors: ${metrics.consoleErrors}
- Screenshot: \`${SCREENSHOT_PATH}\`

## Severity Model
- P0 (critical): ${SEVERITY_DEFINITIONS.p0}
- P1 (high): ${SEVERITY_DEFINITIONS.p1}
- P2 (medium): ${SEVERITY_DEFINITIONS.p2}
- P3 (low): ${SEVERITY_DEFINITIONS.p3}

## QA Coverage In This Run
${QA_COVERAGE.map((item) => `- ${item}`).join('\n')}

## Findings
${summarizeDefects()}

## Event Log
${logs.length === 0 ? '- No notable events captured.' : logs.map((l) => `- ${l.timestamp}: ${l.message}`).join('\n')}

## Suggested Next Action
- If findings include high severity issues, prioritize reproduction from this run and fix gameplay-blocking defects first.
`;

  const reportPayload = {
    metrics,
    defects,
    logs,
    severityModel: SEVERITY_DEFINITIONS,
    coverage: QA_COVERAGE,
    screenshotPath: SCREENSHOT_PATH,
  };

  await fs.writeFile(REPORT_PATH, markdown, 'utf8');
  await fs.writeFile(JSON_REPORT_PATH, JSON.stringify(reportPayload, null, 2), 'utf8');
}

async function run() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
  });
  const page = await context.newPage();

  page.on('pageerror', (error) => {
    metrics.uncaughtPageErrors += 1;
    addDefect('p0', 'Uncaught page exception', error.message);
  });

  page.on('console', (message) => {
    if (message.type() === 'error') {
      metrics.consoleErrors += 1;
      addLog(`Console error: ${message.text()}`);
    }
  });

  try {
    addLog(`Navigating to ${QA_URL}`);
    await page.goto(QA_URL, { waitUntil: 'networkidle', timeout: 45000 });
    await page.waitForTimeout(2000);

    const startTime = Date.now();
    const keyPool = ['Space', 'ArrowUp', 'ArrowLeft', 'ArrowRight'];
    let previousFrameSignature = null;

    for (let i = 0; i < QA_STEPS; i += 1) {
      if (Date.now() - startTime > QA_DURATION_MS) {
        addLog('Simulation stopped at duration limit.');
        break;
      }

      const x = 100 + Math.floor(Math.random() * 1000);
      const y = 120 + Math.floor(Math.random() * 520);
      const key = keyPool[Math.floor(Math.random() * keyPool.length)];

      await page.mouse.move(x, y);
      await page.mouse.click(x, y, { delay: 30 });
      await page.keyboard.press(key);
      await page.waitForTimeout(350);

      const frameProbe = await page.evaluate(() => {
        const canvas = document.querySelector('canvas');
        if (!canvas) {
          return { ok: false, reason: 'no-canvas' };
        }
        const ctx = canvas.getContext('2d', { willReadFrequently: true });
        if (!ctx) {
          return { ok: false, reason: 'no-context' };
        }
        const w = canvas.width;
        const h = canvas.height;
        if (w < 4 || h < 4) {
          return { ok: false, reason: 'canvas-too-small' };
        }
        const sampleW = Math.min(160, w);
        const sampleH = Math.min(90, h);
        const image = ctx.getImageData(0, 0, sampleW, sampleH).data;
        let luminanceSum = 0;
        let signature = 0;
        let pixelCount = 0;
        for (let p = 0; p < image.length; p += 16) {
          const r = image[p];
          const g = image[p + 1];
          const b = image[p + 2];
          luminanceSum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
          signature = (signature + r * 3 + g * 5 + b * 7 + pixelCount) % 1000000007;
          pixelCount += 1;
        }
        return {
          ok: true,
          avgLuminance: pixelCount === 0 ? 0 : luminanceSum / pixelCount,
          signature,
        };
      });

      if (frameProbe.ok) {
        if (frameProbe.avgLuminance < 7) {
          metrics.blackFrameSamples += 1;
        }
        if (previousFrameSignature !== null && previousFrameSignature === frameProbe.signature) {
          metrics.frozenFrameStreak += 1;
          maxFrozenFrameStreak = Math.max(maxFrozenFrameStreak, metrics.frozenFrameStreak);
        } else {
          metrics.frozenFrameStreak = 0;
        }
        previousFrameSignature = frameProbe.signature;
      }

      metrics.stepsExecuted += 1;
    }

    const hasCanvas = await page.locator('canvas').count();
    if (hasCanvas === 0) {
      addDefect(
        'p0',
        'Gameplay canvas not rendered',
        'No canvas element was detected after loading the page.'
      );
    } else {
      addLog(`Canvas count detected: ${hasCanvas}`);
    }

    if (metrics.uncaughtPageErrors > 0) {
      addDefect(
        'p0',
        'Runtime exceptions observed',
        `Detected ${metrics.uncaughtPageErrors} uncaught browser exceptions during simulation.`
      );
    }

    if (metrics.consoleErrors > 0) {
      addDefect(
        'p2',
        'Console errors observed',
        `Detected ${metrics.consoleErrors} console error messages during simulation.`
      );
    }

    if (metrics.blackFrameSamples >= Math.max(5, Math.floor(metrics.stepsExecuted * 0.5))) {
      addDefect(
        'p0',
        'Mostly black gameplay frames detected',
        `Detected ${metrics.blackFrameSamples} very-dark frame samples during active simulation.`
      );
    }

    if (maxFrozenFrameStreak >= 8) {
      addDefect(
        'p0',
        'Possible frozen gameplay loop',
        `Frame signature stayed unchanged for ${maxFrozenFrameStreak} consecutive probes.`
      );
    }

    await fs.mkdir(REPORT_DIR, { recursive: true });
    await page.screenshot({ path: SCREENSHOT_PATH, fullPage: true });
    addLog('Captured screenshot for visual debugging.');
  } catch (error) {
    addDefect('p0', 'QA runner execution failure', error.message);
  } finally {
    await writeReport();
    await context.close();
    await browser.close();
  }

  if (defects.length > 0) {
    console.log(`QA completed with ${defects.length} finding(s).`);
  } else {
    console.log('QA completed with no findings.');
  }
  console.log(`Markdown report: ${REPORT_PATH}`);
  console.log(`JSON report: ${JSON_REPORT_PATH}`);
}

run().catch(async (error) => {
  addDefect('p0', 'Unhandled QA runner crash', error.message);
  await writeReport();
  console.error(error);
  process.exit(1);
});
