// Renders demo.html frame by frame and encodes a GIF (for the README) and an MP4
// for each cut:
//   cmddock-demo.*       basic flow, a command without variables (top of the README)
//   cmddock-variables.*  the {{variables}} form (Variables section)
//
//   npm i --no-save puppeteer-core   (uses your installed Google Chrome)
//   node docs/demo/render.mjs [basic|variables]   (both by default)
//
// Needs ffmpeg and gifski (brew install ffmpeg gifski).
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = dirname(fileURLToPath(import.meta.url));
const FPS = 30;
const chrome = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' });
const CUTS = { basic: 'cmddock-demo', variables: 'cmddock-variables' };
const wanted = process.argv[2] ? [process.argv[2]] : Object.keys(CUTS);

const browser = await puppeteer.launch({ executablePath: chrome, headless: true });
for (const variant of wanted) {
  const name = CUTS[variant];
  if (!name) throw new Error(`unknown cut: ${variant}`);
  const frames = mkdtempSync(join(tmpdir(), 'cmddock-frames-'));
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 720, deviceScaleFactor: 1 });
  await page.goto(pathToFileURL(join(here, 'demo.html')).href + `?capture&v=${variant}`);
  const duration = await page.evaluate(() => window.DURATION);
  const total = Math.round(duration * FPS);
  for (let i = 0; i < total; i++) {
    await page.evaluate(t => window.render(t), i / FPS);
    await page.screenshot({ path: join(frames, `f${String(i).padStart(4, '0')}.png`) });
    if (i % 60 === 0) process.stdout.write(`${name}: frame ${i}/${total}\n`);
  }

  run('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS), '-i', join(frames, 'f%04d.png'),
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-movflags', '+faststart',
    join(here, `${name}.mp4`)]);
  // GIF: half the frame rate and 960px wide keeps it small enough for a README.
  const gifFrames = [];
  for (let i = 0; i < total; i += 2) gifFrames.push(join(frames, `f${String(i).padStart(4, '0')}.png`));
  run('gifski', ['--quiet', '--fps', String(FPS / 2), '--width', '960', '--quality', '85',
    '-o', join(here, `${name}.gif`), ...gifFrames]);
  rmSync(frames, { recursive: true, force: true });
}
await browser.close();
console.log('done → docs/demo/cmddock-{demo,variables}.{gif,mp4}');
