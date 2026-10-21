import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';

const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require('playwright');
} catch (e) {
  playwright = createRequire('/opt/npm-tools/node_modules/')('playwright');
}
const { chromium } = playwright;

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tmpOut = path.join(os.tmpdir(), 'vcs-smoke'); // outside OneDrive
const outDir = path.join(tmpOut, 'out');
fs.mkdirSync(outDir, { recursive: true });

// Pages share one stable origin when served over http (file:// localStorage is flaky across pages in headless Chromium).
// SMOKE_FILE=1 loads from file:// like a downloaded copy.
import http from 'node:http';
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };
let INDEX_URL = 'file://' + path.join(root, 'index.html');
let httpServer = null;
if (!process.env.SMOKE_FILE) {
  httpServer = http.createServer((req, res) => {
    const f = path.join(root, decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html');
    if (!f.startsWith(root) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
    fs.createReadStream(f).pipe(res);
  });
  await new Promise((r) => httpServer.listen(0, '127.0.0.1', r));
  INDEX_URL = 'http://127.0.0.1:' + httpServer.address().port + '/index.html';
}

const failures = [];
function check(name, ok, detail) {
  console.log((ok ? 'PASS ' : 'FAIL ') + name + (detail ? ' - ' + detail : ''));
  if (!ok) failures.push(name + (detail ? ': ' + detail : ''));
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Timing helpers: wait on real state instead of fixed sleeps.
const waitF = (pg, fn, arg, t) => pg.waitForFunction(fn, arg === undefined ? null : arg, { timeout: t || 2000, polling: 30 }).then(() => true, () => false);
const frames = (pg, n) => pg.evaluate((k) => new Promise((res) => { let i = 0; const f = () => (++i >= k ? res() : requestAnimationFrame(f)); requestAnimationFrame(f); }), n || 3);
// Press a key (after a few frames, since the game ignores Esc for ~a frame after transitions) until cond holds; retries up to 3 times.
async function pressUntil(pg, key, fn, arg) {
  for (let i = 0; i < 3; i++) {
    await frames(pg, 4);
    await pg.keyboard.press(key);
    if (await waitF(pg, fn, arg, 900)) return true;
  }
  return false;
}
const IS_PAUSED = () => window.VCS.Game.debugState().state === 'paused' && !document.getElementById('pause').hidden;
// Pause with Esc from the playing state (waits for playing first so a pending resume cannot be re-toggled).
async function escP(pg) {
  await waitF(pg, () => window.VCS.Game.debugState().state === 'playing', null, 3000);
  return pressUntil(pg, 'Escape', IS_PAUSED);
}
// Press a key and return the focused element id once it equals exp (or after the timeout).
async function focusAfter(pg, key, exp) {
  await pg.keyboard.press(key);
  await waitF(pg, (e) => document.activeElement && document.activeElement.id === e, exp, 1000);
  return pg.evaluate(() => document.activeElement && document.activeElement.id);
}

async function launch() {
  try {
    return await chromium.launch({ headless: true });
  } catch (e) {
    console.log('default launch failed, retrying with explicit executable: ' + e.message.split('\n')[0]);
    return await chromium.launch({
      headless: true,
      executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'
    });
  }
}

// Tutorial hints are first-time only (localStorage vcs.seen); suppress them by default so pixel checks stay clean.
const SEEN_ALL = ['tut:ping', 'tut:person', 'tut:vial', 'tut:fear', 'tut:sleep', 'tut:light'];
const opened = [];
// Deterministic Math.random for every page (mulberry32), so wander/idle/break-free rolls cannot flip a check.
const PIN_RANDOM = () => {
  let a = 0x9e3779b9;
  Math.random = function () { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
};
// Close every tracked page except those in keep (a page left open slows every later section: fps drops 60 -> 30-39).
async function closeLeaked(keep) {
  const k = keep || [];
  while (opened.length) {
    const p = opened.pop();
    if (k.indexOf(p) >= 0) continue;
    try { await p.context().close(); } catch (e) { /* already closed */ }
  }
}
// Let the page's localStorage writes reach the browser process before a reload/second tab reads them (Chromium flushes lazily under load).
const settleReload = async (pg) => { await sleep(700); await pg.reload(); };
function secFail(name, e) { check('section completed: ' + name, false, e && e.stack ? e.stack : String(e)); }
// Click "New run" and wait for the run to actually start (no fixed sleep).
async function clickNew(pg) {
  await pg.click('#btn-menu-new', { timeout: 10000 });
  // Either the run starts, or (saved run / other tab) the button turns into the abandon confirm or stays; settle without throwing.
  await waitF(pg, () => window.VCS.Game.debugState().state !== 'title' || /Abandon/.test(document.getElementById('btn-menu-new').textContent), null, 2500);
  await frames(pg, 3);
}
async function newPg(br, opts, tut) {
  const ctx = await br.newContext(opts);
  await ctx.addInitScript(PIN_RANDOM);
  if (!tut) {
    await ctx.addInitScript((ids) => {
      try {
        const v = JSON.parse(localStorage.getItem('vcs.seen') || '[]');
        const l = Array.isArray(v) ? v : [];
        ids.forEach((i) => { if (l.indexOf(i) < 0) l.push(i); });
        localStorage.setItem('vcs.seen', JSON.stringify(l));
      } catch (e) { /* ignore */ }
    }, SEEN_ALL);
  }
  const pgNew = await ctx.newPage();
  opened.push(pgNew);
  return pgNew;
}

// ---------------- --shots mode: deterministic baseline captures, no checks ----------------
if (process.argv.includes('--shots')) {
  const shotsOut = path.join(root, 'tests', 'shots');
  fs.mkdirSync(shotsOut, { recursive: true });
  const br = await launch();
  const names = [];
  const fps = {};
  let code = 0;
  try {
    const url = INDEX_URL + '?seed=7&debug=1';
    // fx (0..2) seeds vcs.settings before the game loads; query adds URL params (e.g. '&map=test').
    const open = async (start, fx, query) => {
      const pg = await newPg(br, { viewport: { width: 1280, height: 720 } });
      if (fx !== undefined) {
        await pg.context().addInitScript((v) => {
          try { localStorage.setItem('vcs.settings', JSON.stringify({ cfgV: 2, effects: v })); } catch (e) { /* ignore */ }
        }, fx);
      }
      pg.on('pageerror', (e) => console.log('pageerror: ' + (e && e.message ? e.message : e)));
      await pg.goto(url + (query || ''));
      await pg.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
      if (start) { await clickNew(pg); await sleep(300); }
      return pg;
    };
    const snap = async (pg, name, pulse) => {
      if (pulse) await pg.evaluate(() => { const G = window.VCS.Game; G.debugPulse(); G.debugAdvance(0.4); });
      await sleep(150);
      await pg.screenshot({ path: path.join(shotsOut, 'base-' + name + '.png') });
      names.push(name);
    };
    const tp = (pg, x, y, a) => pg.evaluate(([X, Y, A]) => window.VCS.Game.debugTeleport(X, Y, A), [x, y, a]);

    // 7 menu (crypt title menu) - fresh page, not started.
    const pm = await open(false);
    await sleep(300);
    await snap(pm, 'menu', false);
    await pm.close();

    const pg = await open(true, 2);
    await snap(pg, 'crypt', true);

    const doors = await pg.evaluate(() => {
      const town = VCS.MapData.maps.town, out = {};
      for (const z of town.zones) {
        if (z.name !== 'tavern' && z.name !== 'church') continue;
        const inZ = (x, y) => x >= z.x0 && x <= z.x1 && y >= z.y0 && y <= z.y1;
        for (let y = z.y0; y <= z.y1; y++) for (let x = z.x0; x <= z.x1; x++) {
          if (town.rows[y][x] !== 'D') continue;
          for (const [dx, dy] of [[0, 1], [0, -1], [1, 0], [-1, 0]]) if (!inZ(x + dx, y + dy) && !out[z.name]) out[z.name] = { x, y, dx, dy };
        }
      }
      return out;
    });
    const pt = (d, k) => ({ x: d.x + 0.5 + d.dx * k, y: d.y + 0.5 + d.dy * k, a: Math.atan2(-d.dy, -d.dx) });
    const town = () => pg.evaluate(() => { window.VCS.Game.debugMap('town', null); window.VCS.Game.debugAdvance(0.1); });
    const at = (p) => tp(pg, p.x, p.y, p.a);

    await town(); await at(pt(doors.tavern, 3));
    await snap(pg, 'street', true);
    await town(); await at(pt(doors.tavern, -3));
    await snap(pg, 'tavern', true);
    await town(); await at(pt(doors.church, -3));
    await snap(pg, 'church', true);

    // FPS: street and tavern, 3 s of real frames, pulse every 0.8 s.
    for (const [label, k, d] of [['street', 3, doors.tavern], ['tavern', -3, doors.tavern]]) {
      await town(); await at(pt(d, k));
      const samples = [];
      const f0 = Date.now();
      let lastPulse = 0;
      while (Date.now() - f0 < 3000) {
        if (Date.now() - lastPulse > 800) { await pg.evaluate(() => window.VCS.Game.debugPulse()); lastPulse = Date.now(); }
        samples.push(await pg.evaluate(() => window.VCS.Game.debugState().fps));
        await sleep(100);
      }
      const sorted = samples.filter((v) => typeof v === 'number' && v > 0).sort((a, b) => a - b);
      fps[label] = sorted.length ? Number(sorted[Math.floor(sorted.length / 2)].toFixed(1)) : 0;
    }

    // 10 shriek, 8 dawn (outdoors, 05:40), 9 weak HUD.
    await town(); await at(pt(doors.tavern, 3));
    await pg.evaluate(() => { const G = window.VCS.Game; G.debugFear(5); G.debugBlood(80); G.debugAdvance(1); G.debugPower('shriek'); G.debugAdvance(0.4); });
    await snap(pg, 'shriek', false);
    await pg.evaluate(() => { const G = window.VCS.Game; G.debugBlood(60); G.debugTime(5, 40); G.debugAdvance(0.2); G.debugPulse(); G.debugAdvance(0.4); });
    await snap(pg, 'dawn', false);
    await pg.evaluate(() => { const G = window.VCS.Game; G.debugTime(20, 30); G.debugBlood(15); G.debugAdvance(0.2); G.debugPulse(); G.debugAdvance(0.4); });
    await snap(pg, 'hud-weak', false);
    await pg.close();


    // Archetype lineup at effects 0, 1 and 2: one villager of each archetype in a row 1.6 cells apart, 2.5 cells ahead of
    // the player and facing them. people[i].mode is set directly (cycling the list below), then one pulse.
    const LINEUP_MODES = ['path', 'sit', 'chat', 'flee', 'cower', 'dazed', 'grapple', 'fed'];
    for (const fx of [0, 1, 2]) {
      const pl = await open(true, fx, '&map=test');
      const lineup = await pl.evaluate((modes) => {
        const G = window.VCS.Game;
        const list = window.VCS.ArchetypeData.list.map((a) => a.id);
        const n = list.length;
        const w = G.debugPeopleState().world;
        const m = window.VCS.MapData.maps.test;
        const at = (x, y, a, i) => {
          const lat = (i - (n - 1) / 2) * 1.6;
          return { x: x + Math.cos(a) * 2.5 - Math.sin(a) * lat, y: y + Math.sin(a) * 2.5 + Math.cos(a) * lat };
        };
        let spot = null;
        for (let y = 1; y < m.rows.length - 1 && !spot; y++) {
          for (let x = 1; x < m.rows[y].length - 1 && !spot; x++) {
            for (const a of [0, Math.PI / 2, Math.PI, -Math.PI / 2]) {
              const px = x + 0.5;
              const py = y + 0.5;
              if (w.blocks(px, py, 0.25)) continue;
              let clear = true;
              for (let i = 0; i < n && clear; i++) { const q = at(px, py, a, i); if (w.blocks(q.x, q.y, 0.25)) clear = false; }
              if (clear) { spot = { x: px, y: py, a: a }; break; }
            }
          }
        }
        if (!spot) return { ok: false, why: 'no open spot on the test map' };
        G.debugTeleport(spot.x, spot.y, spot.a);
        const ids = [];
        for (let i = 0; i < n; i++) {
          const q = at(spot.x, spot.y, spot.a, i);
          const res = G.debugForgeSpawn(list[i], q.x, q.y, spot.a + Math.PI);
          ids.push(res && res.ok ? res.id : null);
        }
        const people = G.debugPeopleState().people;
        ids.forEach((id, i) => { const p = people.find((q) => q.id === id); if (p) p.mode = modes[i % modes.length]; });
        return { ok: true, spawned: ids.filter((v) => v !== null).length, of: n };
      }, LINEUP_MODES);
      console.log('lineup fx' + fx + ': ' + JSON.stringify(lineup));
      await snap(pl, 'lineup-fx' + fx, true);
      await pl.close();
    }

    // 5 feeding (test map has reliable victims), 6 gift panel.
    const pf = await open(true, 2);
    await pf.evaluate(() => {
      const G = window.VCS.Game;
      G.debugMap('test', null);
      G.debugBlood(30);
      G.debugAdvance(5);
      const ppl = G.debugState().people;
      for (const pr of ppl) {
        if (pr.mode !== 'path') continue;
        const x = pr.x - Math.cos(pr.angle) * 1.2, y = pr.y - Math.sin(pr.angle) * 1.2;
        const w = G.debugPeopleState().world;
        if (w.blocks(x, y, 0.25)) continue;
        G.debugTeleport(x, y, Math.atan2(pr.y - y, pr.x - x));
        G.debugAdvance(0.02);
        if (G.debugFeed()) { G.debugAdvance(1.0); return; }
      }
    });
    await snap(pf, 'feeding', false);
    await pf.close();

    const pgi = await open(true);
    await pgi.evaluate(() => { const G = window.VCS.Game; G.debugBlood(100); G.debugOverflow(1000); G.debugAdvance(0.3); });
    await sleep(200);
    await snap(pgi, 'gift', false);
    await pgi.close();

    console.log('BASELINE ' + JSON.stringify({ fps, shots: names }));
  } catch (e) {
    console.log('shots failed: ' + (e && e.stack ? e.stack : e));
    code = 1;
  } finally {
    await br.close();
  }
  process.exit(code);
}

const browser = await launch();
let vis, page, shotsDir, url07, mk07, ds, pg7, bed, fresh, real, p8, shots8;
try {
  try {
  page = await newPg(browser, { viewport: { width: 1000, height: 600 } });
  const consoleErrors = [];
  const csp = [];
  const pageErrors = [];
  page.on('console', (m) => {
    const t = m.text();
    if (t.includes('Content Security Policy')) csp.push(t);
    else if (m.type() === 'error') consoleErrors.push(t);
  });
  page.on('pageerror', (e) => pageErrors.push(String(e && e.message ? e.message : e)));

  await page.goto(INDEX_URL + '?seed=7&debug=1&map=test');
  await page.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state !== 'boot', null, { timeout: 5000 })
    ;
  const s0 = await page.evaluate(() => window.VCS && window.VCS.Game ? window.VCS.Game.debugState() : null);
  check('game booted to title', !!s0 && s0.state === 'title', s0 ? 'state=' + s0.state : 'VCS.Game missing');

  const countLit = () => page.evaluate(() => {
    const c = document.getElementById('view');
    const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let n = 0;
    for (let i = 0; i < d.length; i += 4) {
      if (d[i] > 40 || d[i + 1] > 40 || d[i + 2] > 40) {
        // v0.7: ignore the HUD (vial bottom-left, dial bottom-right) and the centred title card.
        const px = (i >> 2) % c.width;
        const py = Math.floor((i >> 2) / c.width);
        if (py > 280 && (px < 200 || px > 560)) continue;
        if (py > 130 && py < 230 && px > 130 && px < 510) continue;
        n++;
      }
    }
    return n;
  });

  await clickNew(page);
  await sleep(300);
  const darkBefore = await countLit();
  check('dark before any pulse', darkBefore < 50, 'nonblack=' + darkBefore);
  const hasHook = await page.evaluate(() => typeof window.VCS.Game.debugPulse === 'function');
  check('debugPulse exposed with ?debug=1', hasHook);
  const emitted = await page.evaluate(() => window.VCS.Game.debugPulse());
  check('debugPulse emitted', emitted === true);
  await sleep(400);
  const litPulse = await countLit();
  const stPulse = await page.evaluate(() => window.VCS.Game.debugState());
  check('pulse lights pixels', litPulse > 300, 'nonblack=' + litPulse);
  check('pulse lights columns', stPulse.litColumns > 20, 'litColumns=' + stPulse.litColumns);
  await page.screenshot({ path: path.join(outDir, 'smoke-pulse.png') });
  // Game time only advances at <= 0.1 s per frame, so poll rather than assume real time.
  await waitF(page, () => window.VCS.Game.debugState().litColumns === 0, null, 9000);
  const stDark = await page.evaluate(() => window.VCS.Game.debugState());
  check('pulse faded (litColumns 0)', stDark.litColumns === 0, 'litColumns=' + stDark.litColumns);
  await sleep(300);
  const darkAfter = await countLit();
  check('dark after fade', darkAfter < 50, 'nonblack=' + darkAfter);
  await page.screenshot({ path: path.join(outDir, 'smoke-dark.png') });

  // People walk their paths (deterministic simulation via the debug hook).
  const people0 = await page.evaluate(() => window.VCS.Game.debugState().people);
  check('people present', Array.isArray(people0) && people0.length === 3, 'people=' + JSON.stringify(people0));
  await page.evaluate(() => window.VCS.Game.debugAdvance(3));
  const people1 = await page.evaluate(() => window.VCS.Game.debugState().people);
  const maxMove = Math.max(...people0.map((p, i) => Math.hypot(people1[i].x - p.x, people1[i].y - p.y)));
  check('people move over time', maxMove > 0.5, 'maxMove=' + maxMove.toFixed(2));

  // A pulse that reaches a person leaves an echo snapshot; a second pulse adds a trail.
  await page.evaluate(() => window.VCS.Game.debugTeleport(11.5, 2.5, 0));
  await page.evaluate(() => window.VCS.Game.debugPulse());
  await page.evaluate(() => window.VCS.Game.debugAdvance(0.5));
  const stEcho = await page.evaluate(() => window.VCS.Game.debugState());
  check('pulse creates echo snapshot', stEcho.echoes >= 1, 'echoes=' + stEcho.echoes);
  check('echo spawns ripple rings', stEcho.rings >= 1, 'rings=' + stEcho.rings);
  // Second pulse right after cooldown (0.8 s) so the first snapshot (3 s fade) is still alive.
  await page.evaluate(() => window.VCS.Game.debugAdvance(0.4));
  const emitted2 = await page.evaluate(() => window.VCS.Game.debugPulse());
  check('second pulse emitted', emitted2 === true);
  await page.evaluate(() => window.VCS.Game.debugAdvance(0.5));
  const stTrail = await page.evaluate(() => window.VCS.Game.debugState());
  check('second pulse extends the echo trail', stTrail.echoes >= 2, 'echoes=' + stTrail.echoes);
  await page.screenshot({ path: path.join(outDir, 'smoke-people.png') });
  await page.evaluate(() => window.VCS.Game.debugAdvance(4));


  // P4 sound: steps, doors, bounce pulses, people steps.
  await page.evaluate(() => window.VCS.Game.debugTeleport(2.5, 2.5, 0));
  const hasInteract = await page.evaluate(() => typeof window.VCS.Game.debugInteract === 'function');
  check('debugInteract exposed with ?debug=1', hasInteract);
  await page.keyboard.down('KeyW');
  await sleep(1200);
  await page.keyboard.up('KeyW');
  const stSteps = await page.evaluate(() => window.VCS.Game.debugState());
  check('walking creates step pulses', (stSteps.sounds.step || 0) > 0, JSON.stringify(stSteps.sounds));
  check('step pulses come from the floor (z 0)', stSteps.soundZ.step === 0 || !(await page.evaluate(() => typeof window.VCS.Sonar.heightBand === 'function')), JSON.stringify(stSteps.soundZ));
  // Door at column 9 row 3 (cell centre 9.5,3.5): stand left of it facing east.
  await page.evaluate(() => window.VCS.Game.debugTeleport(8.3, 3.5, 0));
  const d0 = await page.evaluate(() => window.VCS.Game.debugState().doorsOpen);
  const r1 = await page.evaluate(() => window.VCS.Game.debugInteract());
  await page.evaluate(() => window.VCS.Game.debugAdvance(0.1));
  const d1 = await page.evaluate(() => window.VCS.Game.debugState());
  check('debugInteract opens a door', r1 === 'door' && d1.doorsOpen === d0 + 1, 'r=' + r1 + ' open ' + d0 + '->' + d1.doorsOpen);
  check('door creates a door pulse', (d1.sounds.door || 0) > 0 || !(await page.evaluate(() => typeof window.VCS.Sonar.emitSound === 'function')), JSON.stringify(d1.sounds));
  await page.evaluate(() => window.VCS.Game.debugInteract());
  const d2 = await page.evaluate(() => window.VCS.Game.debugState().doorsOpen);
  check('debugInteract closes the door again', d2 === d0, 'open=' + d2);
  await page.evaluate(() => window.VCS.Game.debugAdvance(1));
  await page.evaluate(() => window.VCS.Game.debugTeleport(5.5, 8.5, 0));
  await page.evaluate(() => window.VCS.Game.debugPulse());
  await page.evaluate(() => window.VCS.Game.debugAdvance(0.3));
  const stB = await page.evaluate(() => window.VCS.Game.debugState());
  check('ping creates bounce pulses (gen>0)', (stB.sounds.bounce || 0) > 0 || !(await page.evaluate(() => typeof window.VCS.Sonar.emitSound === 'function')), JSON.stringify(stB.sounds));
  // v0.11 echoes: per-hit materials on the ping, mouth beam, voices stay bounded over a ping burst across the town.
  check('v0.11: ping rays carry hit materials', Array.isArray(stB.pingMats) && stB.pingMats.length >= 1, JSON.stringify(stB.pingMats));
  const mats11 = new Set(stB.pingMats);
  let maxVoices = stB.voices || 0;
  for (const [tx, ty, ta] of [[5.5, 8.5, 0], [20.5, 8.5, 1.57], [30.5, 5.5, 3.14], [10.5, 26.5, 0], [44.5, 10.5, 2], [20.5, 20.5, 4.7]]) {
    await page.evaluate(([x, y, a]) => window.VCS.Game.debugTeleport(x, y, a), [tx, ty, ta]);
    for (let k = 0; k < 4; k++) {
      await page.evaluate(() => window.VCS.Game.debugAdvance(0.85));
      await page.evaluate(() => window.VCS.Game.debugPulse());
      const sv = await page.evaluate(() => window.VCS.Game.debugState());
      (sv.pingMats || []).forEach((m) => mats11.add(m));
      maxVoices = Math.max(maxVoices, sv.voices || 0);
    }
  }
  await page.evaluate(() => window.VCS.Game.debugTeleport(5.5, 8.5, 0)); // back where the later checks expect the player
  check('v0.11: more than one wall material reached by pings', mats11.size >= 2, JSON.stringify([...mats11]));
  check('v0.11: voices stay <= 96 over a ping burst', maxVoices <= 96, 'max=' + maxVoices);
  const stV = await page.evaluate(() => window.VCS.Game.debugState());
  check('v0.11: no errors after the ping burst', stV.errors === 0, 'errors=' + stV.errors);
  let personSteps = 0;
  for (let i = 0; i < 5; i++) {
    await page.evaluate(() => window.VCS.Game.debugAdvance(1));
    const st = await page.evaluate(() => window.VCS.Game.debugState());
    personSteps = Math.max(personSteps, st.sounds.personStep || 0);
  }
  check('people step pulses appear over 5 s', personSteps > 0 || !(await page.evaluate(() => typeof window.VCS.People.stepEvents === 'function')), 'max=' + personSteps);

  const before = await page.evaluate(() => window.VCS.Game.debugState());
  await page.keyboard.down('KeyW');
  await sleep(1000);
  await page.keyboard.up('KeyW');
  await page.keyboard.down('KeyD');
  await sleep(500);
  await page.keyboard.up('KeyD');
  await page.keyboard.press('F3');
  await sleep(500);
  const after = await page.evaluate(() => window.VCS.Game.debugState());

  // Pause -> settings -> render scale 0.5 and back -> resume.
  await escP(page);
  const stPaused = await page.evaluate(() => window.VCS.Game.debugState());
  check('Escape pauses', stPaused.state === 'paused', 'state=' + stPaused.state);
  await page.screenshot({ path: path.join(outDir, 'smoke-pause.png') });
  await page.click('#btn-settings', { timeout: 10000 });
  const settingsVisible = await page.evaluate(() => !document.getElementById('settings').hidden);
  check('settings panel opens', settingsVisible);
  await page.screenshot({ path: path.join(outDir, 'smoke-settings.png') });
  await page.selectOption('#set-scale', '0.5');
  await sleep(300);
  await page.selectOption('#set-scale', '1');
  await sleep(300);
  await page.fill('#set-fov', '80');
  await page.check('#set-bob');
  check('Wobbly lines is on by default', await page.evaluate(() => document.getElementById('set-boil').checked && window.VCS.Game.debugState().lineBoil === true));
  await page.uncheck('#set-boil');
  const boilOff = await page.evaluate(() => ({ s: window.VCS.Game.debugState().lineBoil, k: JSON.parse(localStorage.getItem('vcs.settings')).lineBoil }));
  check('Wobbly lines unchecked turns config.lineBoil off', boilOff.s === false && boilOff.k === false, JSON.stringify(boilOff));
  await page.check('#set-boil');
  check('Wobbly lines checked turns config.lineBoil on', await page.evaluate(() => window.VCS.Game.debugState().lineBoil === true));
  const saved = await page.evaluate(() => {
    try { return JSON.parse(localStorage.getItem('vcs.settings')); } catch (e) { return null; }
  });
  check('settings saved', !!saved && saved.renderScale === 1, JSON.stringify(saved));
  await page.evaluate(() => {
    const set = (id, prop, v) => { const el = document.getElementById(id); el[prop] = v; el.dispatchEvent(new Event('change', { bubbles: true })); };
    set('set-keyturn', 'value', '4.6');
    set('set-draglook', 'checked', false);
    set('set-feedtoggle', 'checked', true);
  });
  const saved10 = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('vcs.settings')); } catch (e) { return null; } });
  check('v0.10: key turn / drag look / feed toggle rows save', !!saved10 && saved10.keyTurnSpeed === 4.6 && saved10.dragLook === false && saved10.feedToggle === true, JSON.stringify(saved10));
  await page.evaluate(() => {
    const set = (id, prop, v) => { const el = document.getElementById(id); el[prop] = v; el.dispatchEvent(new Event('change', { bubbles: true })); };
    set('set-keyturn', 'value', '3.2');
    set('set-draglook', 'checked', true);
    set('set-feedtoggle', 'checked', false);
  });
  await page.click('#btn-reset', { timeout: 10000 });
  await page.click('#btn-settings-back', { timeout: 10000 });
  await page.click('#btn-resume', { timeout: 10000 });
  await sleep(300);
  const stResumed = await page.evaluate(() => window.VCS.Game.debugState());
  check('resume after settings', stResumed.state === 'playing', 'state=' + stResumed.state);

  check('state playing or paused', after.state === 'playing' || after.state === 'paused', 'state=' + after.state);
  const moved = Math.hypot(after.player.x - before.player.x, after.player.y - before.player.y);
  check('player moved', moved > 0.1, 'moved=' + moved.toFixed(3));
  check('no ERROR log entries', after.errors === 0, 'errors=' + after.errors);
  check('no page errors', pageErrors.length === 0, pageErrors.join(' | '));
  check('no console errors', consoleErrors.length === 0, consoleErrors.join(' | '));
  check('no CSP violations', csp.length === 0, csp.join(' | '));

  await page.screenshot({ path: path.join(outDir, 'smoke.png') });
  console.log('screenshot: tmp vcs-smoke/out/smoke.png');


  } catch (e) { secFail("boot+pulse+people+sound+settings", e); }
  await closeLeaked([page, pg7, p8]);
  try {
  // ---------------- v0.6 checks ----------------
  shotsDir = path.join(tmpOut, 'shots');
  fs.mkdirSync(shotsDir, { recursive: true });
  const gi = path.join(root, '.gitignore');
  const giTxt = fs.existsSync(gi) ? fs.readFileSync(gi, 'utf8') : '';
  if (!/^\/?shots\/?\s*$/m.test(giTxt)) fs.writeFileSync(gi, giTxt + (giTxt && !giTxt.endsWith('\n') ? '\n' : '') + 'shots/\n');

  const p6 = await newPg(browser, { viewport: { width: 1000, height: 600 } });
  const errs6 = [];
  p6.on('pageerror', (e) => errs6.push(String(e && e.message ? e.message : e)));
  await p6.goto(INDEX_URL + '?seed=7&debug=1');
  await p6.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
  const b0 = await p6.evaluate(() => window.VCS.Game.debugState());
  check('boot without ?map starts on crypt', b0.map === 'crypt' && b0.state === 'title', 'map=' + b0.map + ' state=' + b0.state);
  await clickNew(p6);
  await sleep(300);
  const b1 = await p6.evaluate(() => window.VCS.Game.debugState());
  check('click moves title -> playing', b1.state === 'playing', 'state=' + b1.state);
  check('crypt playerLit === 0', b1.playerLit === 0, 'lit=' + b1.playerLit);

  // REAL walk through the crypt link door.
  const door = await p6.evaluate(() => VCS.MapData.maps.crypt.doors[0]);
  const cx = door.col + 0.5, cy = door.row + 0.5;
  // Stand 2 cells back from the door along its inward side (door is in the south wall -> y smaller).
  const back = { n: [0, -1], s: [0, 1], e: [-1, 0], w: [1, 0] }[door.facing] || [0, -1];
  const sx = cx + back[0] * 2, sy = cy + back[1] * 2;
  const ang = Math.atan2(cy - sy, cx - sx);
  await p6.evaluate(([x, y, a]) => window.VCS.Game.debugTeleport(x, y, a), [sx, sy, ang]);
  let sawTransition = false;
  await p6.keyboard.down('KeyW');
  const t0 = Date.now();
  while (Date.now() - t0 < 6000) {
    const st = await p6.evaluate(() => window.VCS.Game.debugState());
    if (st.state === 'transition' || st.transition) sawTransition = true;
    if (st.map === 'town') break;
    await sleep(30);
  }
  await p6.keyboard.up('KeyW');
  const wk = await p6.evaluate(() => window.VCS.Game.debugState());
  check('real walk crypt -> town', wk.map === 'town', 'map=' + wk.map + ' pos=' + wk.player.x.toFixed(2) + ',' + wk.player.y.toFixed(2));
  check('transition state was observed', sawTransition);
  await p6.waitForFunction(() => window.VCS.Game.debugState().state === 'playing', null, { timeout: 4000 });
  const wk2 = await p6.evaluate(() => window.VCS.Game.debugState());
  check('state returns to playing after walk', wk2.state === 'playing', 'state=' + wk2.state);

  // Walk into the tavern through its door (one continuous town, no transition).
  await p6.evaluate(() => window.VCS.Game.debugMap('town', null));
  const doorInfo = await p6.evaluate(() => {
    const town = VCS.MapData.maps.town;
    const out = {};
    for (const z of town.zones) {
      if (z.name !== 'tavern' && z.name !== 'church') continue;
      const inZ = (x, y) => x >= z.x0 && x <= z.x1 && y >= z.y0 && y <= z.y1;
      for (let y = z.y0; y <= z.y1; y++) for (let x = z.x0; x <= z.x1; x++) {
        if (town.rows[y][x] !== 'D') continue;
        for (const [dx, dy] of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
          if (!inZ(x + dx, y + dy) && !out[z.name]) out[z.name] = { x, y, dx, dy };
        }
      }
    }
    return out;
  });
  check('tavern and church doors found in map data', !!doorInfo.tavern && !!doorInfo.church, JSON.stringify(doorInfo));
  const outsidePt = (d, k) => ({ x: d.x + 0.5 + d.dx * k, y: d.y + 0.5 + d.dy * k, a: Math.atan2(-d.dy, -d.dx) });
  const tp = (pt) => p6.evaluate((q) => window.VCS.Game.debugTeleport(q.x, q.y, q.a), pt);
  await tp(outsidePt(doorInfo.tavern, 2));
  await p6.evaluate(() => window.VCS.Game.debugAdvance(0.1));
  const zOut = await p6.evaluate(() => window.VCS.Game.debugZone());
  check('outside tavern door is not in tavern zone', zOut !== 'tavern', 'zone=' + zOut);
  await p6.keyboard.down('KeyW');
  const tw = Date.now();
  while (Date.now() - tw < 5000) {
    if ((await p6.evaluate(() => window.VCS.Game.debugZone())) === 'tavern') break;
    await sleep(30);
  }
  await p6.keyboard.up('KeyW');
  const inSt = await p6.evaluate(() => ({ z: window.VCS.Game.debugZone(), s: window.VCS.Game.debugState() }));
  check('real walk street -> tavern zone, same map', inSt.z === 'tavern' && inSt.s.map === 'town' && inSt.s.state === 'playing',
    'zone=' + inSt.z + ' map=' + inSt.s.map + ' state=' + inSt.s.state);

  const pulses2 = () => p6.evaluate(() => { const G = window.VCS.Game; G.debugPulse(); G.debugAdvance(0.9); G.debugPulse(); G.debugAdvance(0.5); });
  const shot = async (f) => { await pulses2(); await sleep(150); await p6.screenshot({ path: path.join(shotsDir, 'v06-' + f + '.png') }); };
  for (const old of ['town', 'tavern', 'church']) { try { fs.unlinkSync(path.join(shotsDir, 'v06-' + old + '.png')); } catch (e) { /* none */ } }
  await tp(outsidePt(doorInfo.tavern, 3));
  await shot('street');
  await tp(outsidePt(doorInfo.tavern, -3));
  await shot('tavern-inside');
  await tp(outsidePt(doorInfo.church, -3));
  await shot('church-inside');
  await p6.evaluate(() => window.VCS.Game.debugMap('crypt', null));
  await shot('crypt');
  console.log('screenshots: shots/v06-{street,tavern-inside,church-inside,crypt}.png');
  await p6.evaluate(() => window.VCS.Game.debugMap('town', null));

  // Lit check on town torches.
  await p6.evaluate(() => window.VCS.Game.debugMap('town', null));
  const torch = await p6.evaluate(() => VCS.MapData.maps.town.props.find((q) => q.type === 'torch'));
  const litCell = await p6.evaluate(([c, r]) => {
    const w = window.VCS.Game.debugPeopleState().world;
    let best = null, bl = -1;
    for (let dx = -2; dx <= 2; dx++) for (let dy = -2; dy <= 2; dy++) {
      const x = c + 0.5 + dx, y = r + 0.5 + dy;
      if (w.blocks(x, y, 0.25)) continue;
      const l = w.lightAt(x, y);
      if (l > bl + 1e-9 && Math.hypot(dx, dy) > 0.9) { bl = l; best = [x, y]; }
    }
    return best;
  }, [torch.col, torch.row]);
  await p6.evaluate(([x, y]) => window.VCS.Game.debugTeleport(x, y, 0), litCell);
  await p6.evaluate(() => window.VCS.Game.debugAdvance(0.1));
  const lit = await p6.evaluate(() => window.VCS.Game.debugState().playerLit);
  check('town: player beside torch is lit (> 0.3)', lit > 0.3, 'lit=' + lit + ' torch=' + torch.col + ',' + torch.row);
  await p6.evaluate(() => window.VCS.Game.debugMap('crypt', null));
  await p6.evaluate(() => window.VCS.Game.debugAdvance(0.1));
  check('crypt: playerLit === 0', (await p6.evaluate(() => window.VCS.Game.debugState().playerLit)) === 0);

  // Villager flee.
  await p6.evaluate(() => window.VCS.Game.debugMap('town', null));
  const flee = await p6.evaluate(([tc, tr]) => {
    const G = window.VCS.Game;
    const ppl = G.debugState().people;
    if (!ppl.length) return { none: true };
    const out = { tried: 0, fled: false };
    for (let i = 0; i < ppl.length && !out.fled; i++) {
      G.debugMap('town', null);
      G.debugAdvance(0.5);
      const v = G.debugState().people[i];
      // Stand 2 cells from the villager, facing it, lit by being next to the nearest torch is not possible
      // generally; so instead use the villager's own position: look for any lit spot within view.
      const tx = v.x, ty = v.y;
      for (const dir of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        G.debugTeleport(tx + dir[0] * 2, ty + dir[1] * 2, Math.atan2(-dir[1], -dir[0]));
        G.debugAdvance(0.05);
        const s = G.debugState();
        if (s.playerLit > 0.3) {
          out.tried++;
          G.debugAdvance(2);
          const m = G.debugState().peopleModes;
          if (m.includes('flee')) { out.fled = true; out.modes = m; break; }
        }
      }
    }
    return out;
  }, [torch.col, torch.row]);
  console.log('flee probe: ' + JSON.stringify(flee));
  if (flee.none) check('villager flee (no people in town)', false, 'no people');
  else if (!flee.tried) console.log('WARN villager flee not tested: no lit spot found near any villager (no stable hook to place light)');
  else check('lit player in front of villager makes it flee', flee.fled, JSON.stringify(flee));

  // Villager barks (guarded): standing near the town's villagers for a while makes some of them speak; voices stay bounded, no errors.
  try {
    const bk = await p6.evaluate(() => {
      const G = window.VCS.Game;
      G.debugMap('town', null);
      G.debugAdvance(0.5);
      const out = { barks: 0, maxVoices: 0, secs: 0, people: 0, enabledByDefault: true };
      const n = G.debugState().people.length;
      out.people = n;
      if (!n) return out;
      const w = G.debugPeopleState().world;
      for (let i = 0; i < 90 && out.barks === 0; i++) {
        const v = G.debugState().people[i % n];
        for (const d of [[3, 0], [-3, 0], [0, 3], [0, -3], [2, 2]]) {
          if (w.blocks(v.x + d[0], v.y + d[1], 0.25)) continue;
          G.debugTeleport(v.x + d[0], v.y + d[1], Math.atan2(-d[1], -d[0]));
          break;
        }
        G.debugAdvance(1);
        out.secs++;
        const s = G.debugState();
        out.barks = s.barks;
        out.maxVoices = Math.max(out.maxVoices, s.voices || 0);
      }
      for (let i = 0; i < 20; i++) { G.debugAdvance(1); out.maxVoices = Math.max(out.maxVoices, G.debugState().voices || 0); }
      out.barks = G.debugState().barks;
      out.errors = G.debugState().errors;
      return out;
    });
    console.log('barks probe: ' + JSON.stringify(bk));
    check('barks: villagers bark in town within 90 s', bk.people > 0 && bk.barks > 0, JSON.stringify(bk));
    check('barks: voices <= 96', bk.maxVoices <= 96, 'max=' + bk.maxVoices);
    check('barks: no errors', bk.errors === 0, 'errors=' + bk.errors);
  } catch (e) { secFail('villager barks', e); }

  // FPS on the street and inside the tavern, fully lit.
  for (const [label, k] of [['street', 3], ['tavern', -3]]) {
    await p6.evaluate(() => window.VCS.Game.debugMap('town', null));
    await tp(outsidePt(doorInfo.tavern, k));
    const samples = [];
    const f0 = Date.now();
    let lastPulse = 0;
    while (Date.now() - f0 < 3500) {
      if (Date.now() - lastPulse > 300) { await p6.evaluate(() => window.VCS.Game.debugPulse()); lastPulse = Date.now(); }
      samples.push(await p6.evaluate(() => window.VCS.Game.debugState().fps));
      await sleep(100);
    }
    const sorted = samples.filter((v) => typeof v === 'number' && v > 0).sort((a, b) => a - b);
    const med = sorted.length ? sorted[Math.floor(sorted.length / 2)] : 0;
    console.log('FPS median (' + label + ', lit): ' + med.toFixed(1));
    if (med < 50 && med >= 35) console.log('WARN fps below 50 (' + label + '): ' + med.toFixed(1));
    check(label + ' fps >= 35', med >= 35, 'median=' + med.toFixed(1));
  }

  // B5: street fps at effects 2 with 3 pulses. No saved value means the default, which is 2.
  {
    await p6.evaluate(() => window.VCS.Game.debugMap('town', null));
    await tp(outsidePt(doorInfo.tavern, 3));
    const fxSaved = await p6.evaluate(() => { try { const s = JSON.parse(localStorage.getItem('vcs.settings')); return s && typeof s === 'object' ? s.effects : null; } catch (e) { return null; } });
    const fx2 = fxSaved === null || fxSaved === undefined ? 2 : fxSaved;
    const fpsAt2 = [];
    for (let k = 0; k < 3; k++) {
      await p6.evaluate(() => window.VCS.Game.debugPulse());
      const t1 = Date.now();
      while (Date.now() - t1 < 1000) {
        fpsAt2.push(await p6.evaluate(() => window.VCS.Game.debugState().fps));
        await sleep(100);
      }
    }
    const v2 = fpsAt2.filter((v) => typeof v === 'number' && v > 0).sort((a, b) => a - b);
    const med2 = v2.length ? v2[Math.floor(v2.length / 2)] : 0;
    // C4: no page errors so far and street fps >= 35 at effects 2 (3 pulses).
    check('street at effects 2: no page errors and fps >= 35', fx2 === 2 && errs6.length === 0 && med2 >= 35,
      'effects=' + fx2 + ' median=' + med2.toFixed(1) + ' pageErrors=' + errs6.length);
  }

  // Forced crash shows error screen.
  await p6.evaluate(() => window.VCS.Game.fatal('E_TEST', 'forced crash', null));
  await sleep(200);
  const errVisible = await p6.evaluate(() => { const e = document.getElementById('error'); return !!e && !e.hidden && getComputedStyle(e).display !== 'none'; });
  check('forced crash shows error screen', errVisible && (await p6.evaluate(() => window.VCS.Game.debugState().state)) === 'error');
  check('no page errors (v0.6 page)', errs6.length === 0, errs6.join(' | '));

  // A person's own footstep (no ping) shows feet only: its snapshot band stays low.
  const page3 = await newPg(browser, { viewport: { width: 1000, height: 600 } });
  const errs3 = [];
  page3.on('pageerror', (e) => errs3.push(String(e && e.message ? e.message : e)));
  await page3.goto(INDEX_URL + '?seed=7&debug=1&safe=1&map=test');
  await page3.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
  await clickNew(page3);
  await sleep(300);
  const bandInfo = await page3.evaluate(() => {
    const G = window.VCS.Game;
    G.debugTeleport(2.5, 2.5, 0);
    const seen = [];
    let pinged = 0;
    for (let i = 0; i < 40; i++) {
      G.debugAdvance(0.5);
      for (const e of G.debugEchoes()) {
        const zMax = typeof e.zMax === 'number' ? e.zMax : (e.band && typeof e.band[1] === 'number' ? e.band[1] : null);
        seen.push(zMax);
      }
      pinged += G.debugState().sounds.ping || 0;
      if (seen.length) break;
    }
    return { seen, pinged };
  });
  const bandVals = bandInfo.seen.filter((v) => v !== null);
  check('person step alone leaves a snapshot with a height band', bandVals.length > 0, JSON.stringify(bandInfo));
  check('feet-only snapshot band zMax < 0.8', bandVals.length > 0 && bandVals.every((v) => v < 0.8), JSON.stringify(bandVals));
  check('no page errors (feet page)', errs3.length === 0, errs3.join(' | '));

  // Separate load without ?debug=1: M must not switch to the map.
  const page2 = await newPg(browser, { viewport: { width: 1000, height: 600 } });
  const errs2 = [];
  page2.on('pageerror', (e) => errs2.push(String(e && e.message ? e.message : e)));
  await page2.goto(INDEX_URL);
  await page2.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
  await clickNew(page2);
  await sleep(300);
  await page2.keyboard.press('KeyM');
  await sleep(300);
  const s2 = await page2.evaluate(() => window.VCS.Game.debugState());
  check('M does nothing without ?debug=1', s2.view === 'fp', 'view=' + s2.view);
  check('no debug hook without ?debug=1', await page2.evaluate(() => typeof window.VCS.Game.debugPulse === 'undefined'));
  check('no page errors (no-debug page)', errs2.length === 0, errs2.join(' | '));

  } catch (e) { secFail("v0.6", e); }
  await closeLeaked([page, pg7, p8]);
  try {
  // ---------------- v0.7 checks ----------------
  url07 = INDEX_URL;
  mk07 = async (query) => {
    const pg = await newPg(browser, { viewport: { width: 1000, height: 600 } });
    const errs = [];
    const csps = [];
    pg.on('pageerror', (e) => errs.push(String(e && e.message ? e.message : e)));
    pg.on('console', (m) => {
      const t = m.text();
      if (t.includes('Content Security Policy')) csps.push(t);
      else if (m.type() === 'error') errs.push(t);
    });
    await pg.goto(url07 + query);
    await pg.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
    await clickNew(pg);
    await sleep(250);
    return { pg, errs, csps };
  };
  const G7 = (pg, fn, arg) => pg.evaluate(fn, arg);
  ds = (pg) => pg.evaluate(() => window.VCS.Game.debugState());

  const a7 = await mk07('?seed=7&debug=1');
  pg7 = a7.pg;
  const n0 = await ds(pg7);
  check('v0.7: night starts at 20:00 night 1', !!n0.night && /^20:[0-2]\d$/.test(n0.night.clock) && n0.night.n === 1 && n0.night.status === 'night', JSON.stringify(n0.night));
  check('v0.7: blood starts near 10', n0.night && n0.night.blood > 9 && n0.night.blood <= 10, 'blood=' + (n0.night && n0.night.blood));
  check('v0.7: start card is Night 1', n0.card === 'Night 1', 'card=' + n0.card);
  check('v0.9: snapshot is v4 with night, run and hunger', await pg7.evaluate(() => { const s = window.VCS.Game.getSnapshot(); return s.v === 4 && !!s.run && !!s.run.hunger && Array.isArray(s.run.boons) && !!s.night && s.night.night === 1; }));
  await pg7.evaluate(() => { const G = window.VCS.Game; G.debugAdvance(2.6); G.debugPulse(); G.debugAdvance(0.4); });
  await sleep(150);
  await pg7.screenshot({ path: path.join(shotsDir, 'v07-hud.png') });
  await pg7.evaluate(() => window.VCS.Game.debugAdvance(1));
  check('v0.7: debugBlood(10) makes player weak', (await pg7.evaluate(() => { window.VCS.Game.debugBlood(10); return window.VCS.Game.debugState().night.weak; })) > 0.5);
  check('v0.7: weak player still pings', (await pg7.evaluate(() => { const G = window.VCS.Game; const ok = G.debugPulse(); G.debugAdvance(0.1); return ok && G.debugState().pulses > 0; })) === true);
  await pg7.evaluate(() => { window.VCS.Game.debugBlood(60); window.VCS.Game.debugTime(4, 59); window.VCS.Game.debugAdvance(2); });
  const ch = await ds(pg7);
  check('v0.7: chime at 05:00 shows Dawn card', ch.night.clock >= '05:00' && ch.card === 'Dawn', 'clock=' + ch.night.clock + ' card=' + ch.card);
  await sleep(100);
  await pg7.screenshot({ path: path.join(shotsDir, 'v07-card.png') });
  await pg7.evaluate(() => { window.VCS.Game.debugTime(5, 50); window.VCS.Game.debugAdvance(0.1); });
  await sleep(150);
  await pg7.screenshot({ path: path.join(shotsDir, 'v07-dawn.png') });
  await pg7.evaluate(() => { window.VCS.Game.debugTime(5, 59); window.VCS.Game.debugAdvance(2); });
  const day = await ds(pg7);
  check('v0.7: indoors at dawn the run continues (status day)', day.night.status === 'day' && day.state === 'playing' && day.night.clock === '06:00', JSON.stringify(day.night) + ' ' + day.state);
  await pg7.evaluate(() => window.VCS.Game.debugMap('town', null));
  await pg7.evaluate(() => window.VCS.Game.debugAdvance(0.2));
  const lost1 = await ds(pg7);
  check('v0.7: stepping outdoors by day ends the run', lost1.state === 'runend', 'state=' + lost1.state);
  const re1 = await pg7.evaluate(() => ({ vis: !document.getElementById('runend').hidden, title: document.getElementById('runend-title').textContent, msg: document.getElementById('runend-msg').textContent }));
  check('v0.7: runend panel shows sun message', re1.vis && re1.title === 'The sun found you' && /Nights survived: 0/.test(re1.msg) && /People fed: 0/.test(re1.msg), JSON.stringify(re1));
  await pg7.click('#btn-newrun', { timeout: 10000 });
  await sleep(200);
  const nr = await ds(pg7);
  check('v0.7: New run -> playing, night 1, crypt, 20:00', nr.state === 'playing' && nr.night.n === 1 && nr.map === 'crypt' && nr.night.clock === '20:00' && nr.night.blood > 9, JSON.stringify({ s: nr.state, n: nr.night, m: nr.map }));
  check('v0.7: runend panel hidden after New run', await pg7.evaluate(() => document.getElementById('runend').hidden));
  // Outdoors at 05:59 -> sun at 06:00.
  await pg7.evaluate(() => { const G = window.VCS.Game; G.debugMap('town', null); G.debugTime(5, 59); G.debugAdvance(2); });
  const lost2 = await ds(pg7);
  check('v0.7: outdoors at dawn ends the run', lost2.state === 'runend', 'state=' + lost2.state);
  await pg7.click('#btn-newrun', { timeout: 10000 });
  await sleep(200);

  // Sleep beside the crypt bed.
  bed = await pg7.evaluate(() => { const rows = VCS.MapData.maps.crypt.rows; for (let y = 0; y < rows.length; y++) { const x = rows[y].indexOf('C'); if (x >= 0) return { x, y }; } return null; });
  check('v0.7: crypt bed found in map data', !!bed, JSON.stringify(bed));
  await pg7.evaluate((b) => { const G = window.VCS.Game; G.debugMap('crypt', null); G.debugTeleport(b.x - 0.5, b.y + 0.5, 0); }, bed);
  check('v0.7: debugSleep starts sleeping beside the bed', (await pg7.evaluate(() => window.VCS.Game.debugSleep())) === true);
  check('v0.7: state is sleeping', (await ds(pg7)).state === 'sleeping');
  await pg7.keyboard.press('Escape');
  await sleep(100);
  check('v0.7: Escape ignored while sleeping', (await ds(pg7)).state !== 'paused');
  await pg7.evaluate(() => window.VCS.Game.debugAdvance(2.4));
  const slb = await ds(pg7);
  check('v0.8: after sleep the boon panel is up', slb.state === 'boon' && await pg7.evaluate(() => !document.getElementById('boons').hidden && document.querySelectorAll('#boon-list .card').length === 3), 'state=' + slb.state);
  await pg7.evaluate(() => window.VCS.Game.debugPickBoon(0));
  const sl = await ds(pg7);
  check('v0.7: after sleep+boon: night 2 at 20:00', sl.state === 'playing' && sl.night.n === 2 && sl.night.clock === '20:00' && /^Night 2/.test(sl.card), JSON.stringify({ s: sl.state, n: sl.night, c: sl.card }));
  // Jump to night 5 via snapshot, then sleep -> win.
  const snapOk = await pg7.evaluate((b) => window.VCS.Game.applySnapshot({
    v: 2, map: 'crypt', player: { x: b.x - 0.5, y: b.y + 0.5, angle: 0 }, doors: {}, people: {},
    night: { v: 1, night: 5, min: 545, blood: 60, status: 'night', reason: '', fired: { chime: true, washout: false, dawn: false }, fedCount: 2 }
  }), bed);
  check('v0.7: applySnapshot v2 with night 5', snapOk === true && (await ds(pg7)).night.n === 5);
  check('v0.7: applySnapshot ignores a bad night', await pg7.evaluate(() => { const G = window.VCS.Game; const b = G.getSnapshot(); b.night = { v: 1, night: 99, min: -4 }; const ok = G.applySnapshot(b); return ok && G.debugState().night.n === 5; }));
  await pg7.evaluate((b) => { const G = window.VCS.Game; G.debugTeleport(b.x - 0.5, b.y + 0.5, 0); }, bed);
  check('v0.7: sleep on night 5 starts', (await pg7.evaluate(() => window.VCS.Game.debugSleep())) === true);
  await pg7.evaluate(() => window.VCS.Game.debugAdvance(3));
  const won = await pg7.evaluate(() => ({ s: window.VCS.Game.debugState().state, vis: !document.getElementById('runend').hidden, title: document.getElementById('runend-title').textContent, msg: document.getElementById('runend-msg').textContent }));
  check('v0.7: sleeping on night 5 wins the run', won.s === 'runend' && won.vis && won.title === 'Five nights survived' && /Nights survived: 5/.test(won.msg) && /People fed: 2/.test(won.msg), JSON.stringify(won));
  check('v0.7: no errors (night page)', a7.errs.length === 0, a7.errs.join(' | '));
  check('v0.7: no CSP violations (night page)', a7.csps.length === 0, a7.csps.join(' | '));

  } catch (e) { secFail("v0.7", e); }
  await closeLeaked([page, pg7, p8]);
  try {
  // ---------------- v0.7.2 feeding (hold to drink) ----------------
  const f7 = await mk07('?seed=7&debug=1&map=test');
  let fp = f7.pg;
  const extra = [];
  fresh = async () => { const m = await mk07('?seed=7&debug=1&map=test'); extra.push(m); await m.pg.evaluate(SETUP); return m.pg; };
  // In-page helper: put the player 1.2 cells behind (outside the 1-cell bump distance) (or in front of) a person, aimed at it; returns the id or -1.
  const SETUP = `(function () {
    const G = window.VCS.Game;
    Math.random = function () { return 0.99; }; // victims never tear free mid-test (struggle() break-free roll)
    // Pin every victim's blood pool high so a real-time drink cannot finish between evaluates.
    window.__pin = function () { for (const p of G.debugPeopleState().people) { p.pool = 120; p.left = 120; } };
    window.__place = function (mode, skip) {
      const ppl = G.debugState().people;
      for (const pr of ppl) {
        if (pr.mode !== 'path' || (skip && skip.includes(pr.id))) continue;
        const sgn = mode === 'front' ? 1 : -1;
        const x = pr.x + sgn * Math.cos(pr.angle) * 1.2, y = pr.y + sgn * Math.sin(pr.angle) * 1.2;
        const w = G.debugPeopleState().world;
        if (w.blocks(x, y, 0.25)) continue;
        let clear = true;
        for (let k = 1; k <= 6; k++) { const f = k / 7; if (w.blocks(pr.x + (x - pr.x) * f, pr.y + (y - pr.y) * f, 0.05)) clear = false; }
        if (!clear) continue;
        G.debugTeleport(x, y, Math.atan2(pr.y - y, pr.x - x));
        return pr.id;
      }
      return -1;
    };
  })()`;
  await fp.evaluate(SETUP);
  // 1) Lone dark victim from behind: no gasp, full drain at its pool, fed, nobody screams.
  const drain = await fp.evaluate(() => {
    const G = window.VCS.Game;
    G.debugBlood(10);
    const id = window.__place('behind');
    G.debugAdvance(0.02);
    const id2 = window.__place('behind');
    const b0 = G.debugState().night.blood;
    if (!G.debugFeed()) return { ok: false, id: id2 };
    const pool = G.debugState().drink.pool;
    let steps = 0, scream = 0, flee = 0, maxDrunk = 0;
    while (G.debugState().state === 'feeding' && steps < 900) {
      G.debugAdvance(1 / 60);
      steps++;
      const s = G.debugState();
      if (s.drink) maxDrunk = Math.max(maxDrunk, s.drink.drunk);
      scream += s.sounds.scream || 0;
      if (s.peopleModes.includes('flee')) flee++;
    }
    const s = G.debugState();
    return { ok: true, id: id2, pool, secs: steps / 60, gasp: 0, b0, b1: s.night.blood, state: s.state, fed: s.fed, victim: s.victim, scream, flee, maxDrunk, gaspSeen: 0 };
  });
  const tExp = drain.ok ? (drain.pool / (4.5 * 1.25)) * Math.log(7 / (2.5 + 2.25 / drain.pool)) : 0;
  check('v0.7.2: grab from behind starts a drink', drain.ok, JSON.stringify(drain));
  check('v0.7.2: full drain takes ~7 s at its pool (DRINK_BOOST 1.25)', drain.ok && Math.abs(drain.secs - tExp) < 0.3 && drain.secs > 5 && drain.secs < 14, 'secs=' + (drain.secs && drain.secs.toFixed(2)) + ' expected=' + tExp.toFixed(2) + ' pool=' + (drain.pool && drain.pool.toFixed(1)));
  check('v0.7.2: full drain ends fed (+pool blood, fed count 1)', drain.ok && drain.victim.mode === 'fed' && drain.fed === 1 && drain.state === 'playing' && drain.b1 - drain.b0 > drain.pool - 8, JSON.stringify({ v: drain.victim, f: drain.fed, gain: drain.b1 - drain.b0 }));
  check('v0.7.2: dark drain, no screams, nobody flees', drain.scream === 0 && drain.flee === 0, 'scream=' + drain.scream + ' flee=' + drain.flee);
  // Gasp: front grab emits a gasp pulse; from behind none.
  const gasp = await fp.evaluate(() => {
    const G = window.VCS.Game;
    G.debugBlood(20);
    const sid = (G.debugState().victim || {}).id;
    const idF = window.__place('front', [sid]);
    G.debugAdvance(0.02);
    const idF2 = window.__place('front', [sid]);
    if (!G.debugFeed()) return { ok: false };
    G.debugAdvance(0.03);
    const s = G.debugState();
    const front = s.sounds.gasp || 0;
    G.debugAdvance(0.2);
    const z = G.debugState().soundZ.gasp;
    window.VCS.Game.debugFeedHold(0.05);
    return { ok: true, front, z };
  });
  check('v0.7.2: front grab emits a gasp pulse at head height', gasp.ok && gasp.front >= 1 && Math.abs(gasp.z - 0.8) < 0.01, JSON.stringify(gasp));
  check('v0.7.2: from-behind grab emits no gasp', await fp.evaluate(() => {
    const G = window.VCS.Game;
    G.debugAdvance(8);
    const sid = (G.debugState().victim || {}).id;
    const id = window.__place('behind', [sid]);
    G.debugAdvance(0.02);
    window.__place('behind', [sid]);
    if (!G.debugFeed()) return false;
    G.debugAdvance(0.05);
    const g = G.debugState().sounds.gasp || 0;
    G.debugFeedHold(0.05);
    return g === 0;
  }));
  // 4) Release after 1 s: ~+20 blood, victim dazed, then flees silently after ~3 s; re-feed gets the remainder.
  // Release after an explicit 1 s hold.
  fp = await fresh();
  const hold1 = await fp.evaluate(() => {
    const G = window.VCS.Game;
    G.debugBlood(30);
    let id = -1;
    const all = G.debugState().people.map((p) => p.id);
    for (const c of all) {
      const skip = all.filter((q) => q !== c);
      window.__place('behind', skip);
      G.debugAdvance(0.02);
      if (window.__place('behind', skip) === c && !G.debugState().people.find((p) => p.id === c && p.mode === 'fed')) { id = c; break; }
    }
    if (id < 0) return { ok: false, why: 'place' };
    const b0 = G.debugState().night.blood;
    if (!G.debugFeedHold(2.5)) return { ok: false, why: 'start' };
    const s1 = G.debugState();
    const gain1 = s1.night.blood - b0;
    let scream = 0;
    const modes = [];
    for (let i = 0; i < 20; i++) {
      G.debugAdvance(0.1);
      const s = G.debugState();
      scream += s.sounds.scream || 0;
      modes.push(s.victim.mode);
    }
    const mid = modes[10]; // 1.1 s after release
    for (let i = 0; i < 20; i++) {
      G.debugAdvance(0.1);
      const s = G.debugState();
      scream += s.sounds.scream || 0;
      modes.push(s.victim.mode);
    }
    return { ok: true, id, gain1, victim1: s1.victim, mid, after: modes[modes.length - 1], scream, left1: s1.victim.left, pool: s1.victim.pool, state: s1.state };
  });
  check('v0.7.2: release after 2.5 s gives ~+15..25 blood', hold1.ok && hold1.gain1 > 14 && hold1.gain1 < 25, JSON.stringify(hold1));
  check('v0.7.2: released victim is dazed (keeps its remainder)', hold1.ok && hold1.victim1.mode === 'dazed' && hold1.left1 > 10 && hold1.left1 < hold1.pool - 12 && hold1.state === 'playing', JSON.stringify(hold1.victim1));
  check('v0.7.2: dazed ~1 s later, then flees after ~3 s with no scream', hold1.ok && hold1.mid === 'dazed' && hold1.after === 'flee' && hold1.scream === 0, JSON.stringify({ mid: hold1.mid, after: hold1.after, scream: hold1.scream }));
  fp = await fresh();
  // Cap at 100: release, victim dazed with remainder, not fed.
  const cap = await fp.evaluate(() => {
    const G = window.VCS.Game;
    G.debugBlood(95);
    const all = G.debugState().people.map((p) => p.id);
    const f0 = G.debugState().fed;
    G.debugHungerSet({ giftsTonight: 2 });
    for (const c of all) {
      const skip = all.filter((q) => q !== c);
      window.__place('behind', skip);
      G.debugAdvance(0.02);
      const pr = G.debugState().people.find((p) => p.id === c);
      if (!pr || pr.mode === 'fed' || pr.mode === 'flee' || pr.mode === 'dazed' || pr.mode === 'cower') continue;
      if (window.__place('behind', skip) !== c) continue;
      if (!G.debugFeedHold(6)) continue;
      const s = G.debugState();
      return { ok: true, blood: s.night.blood, mode: s.victim.mode, state: s.state, fed: s.fed - f0, left: s.victim.left };
    }
    return { ok: false };
  });
  check('v0.9: overflow closed (2 gifts taken): blood cap ends the drink at 100, victim dazed, not fed', cap.ok && cap.blood > 99.5 && cap.blood <= 100 && cap.mode === 'dazed' && cap.fed === 0 && cap.state === 'playing' && cap.left > 0.5, JSON.stringify(cap));
  fp = await fresh();
  // v0.9: drinking past full fills the overflow bar; when it is full the drink ends and the gift panel opens.
  const ovr = await fp.evaluate(() => {
    const G = window.VCS.Game;
    G.debugBlood(100);
    G.debugHungerSet({ over: 20 });
    const all = G.debugState().people.map((p) => p.id);
    for (const c of all) {
      const skip = all.filter((q) => q !== c);
      window.__place('behind', skip);
      G.debugAdvance(0.02);
      const pr = G.debugState().people.find((p) => p.id === c);
      if (!pr || pr.mode !== 'path') continue;
      if (window.__place('behind', skip) !== c) continue;
      if (!G.debugFeed()) continue;
      let ovMax = 0;
      for (let i = 0; i < 600 && G.debugState().state === 'feeding'; i++) { G.debugAdvance(1 / 30); ovMax = Math.max(ovMax, G.debugHunger().over); }
      const s = G.debugState();
      return { ok: true, state: s.state, blood: s.night.blood, mode: s.victim.mode, ovMax, fear: G.debugHunger().fear, pend: G.debugPending(), fed: s.fed };
    }
    return { ok: false };
  });
  check('v0.9: drinking past full opens the gift panel (victim released, fear +1)', ovr.ok && ovr.state === 'gift' && ovr.blood > 99.5 && ovr.ovMax >= 35 && ovr.fear >= 1 && ovr.pend && ovr.pend.length === 3 && ovr.fed === 0, JSON.stringify(ovr));
  fp = await fresh();
  // Escape mid-drink: paused, victim dazed.
  const escSetup = await fp.evaluate(() => {
    const G = window.VCS.Game;
    G.debugBlood(10);
    G.debugAdvance(5);
    window.__pin();
    const all = G.debugState().people.map((p) => p.id);
    for (const c of all) {
      const skip = all.filter((q) => q !== c);
      window.__place('behind', skip);
      G.debugAdvance(0.02);
      const pr = G.debugState().people.find((p) => p.id === c);
      if (!pr || pr.mode !== 'path') continue;
      if (window.__place('behind', skip) !== c) continue;
      if (G.debugFeed()) { G.debugAdvance(0.5); return { ok: true, id: c, state: G.debugState().state }; }
    }
    return { ok: false };
  });
  check('v0.7.2: debugFeed starts feeding state', escSetup.ok && escSetup.state === 'feeding', JSON.stringify(escSetup));
  await fp.screenshot({ path: path.join(shotsDir, 'v072-drink.png') });
  const midDrink = await ds(fp);
  check('v0.7.2: debugState reports drink while feeding', !!midDrink.drink && midDrink.drink.drunk > 3 && midDrink.drink.mode === 'grapple', JSON.stringify(midDrink.drink));
  await pressUntil(fp, 'Escape', () => window.VCS.Game.debugState().state === 'paused');
  const esc = await ds(fp);
  check('v0.7.2: Escape mid-drink pauses and leaves the victim dazed', esc.state === 'paused' && esc.drink === null && esc.victim && esc.victim.mode === 'dazed', JSON.stringify({ s: esc.state, d: esc.drink, v: esc.victim }));

  // 2) Torch-lit witnesses (town). A: witness already facing the player. B: facing away, noticed after the first beat.
  const lit7 = await mk07('?seed=7&debug=1');
  const lp = lit7.pg;
  await lp.evaluate(() => { Math.random = function () { return 0.99; }; }); // victim never tears free (struggle() break-free roll) before the witness reacts
  const litTest = async (facing) => lp.evaluate(([facingAway]) => {
    const G = window.VCS.Game;
    G.debugMap('town', null);
    G.debugAdvance(1.3); // arrival grace
    const st = G.debugPeopleState();
    const w = st.world;
    const torch = window.VCS.MapData.maps.town.props.find((q) => q.type === 'torch');
    let P = { x: torch.col + 0.5, y: torch.row + 1.0 };
    let bestL = -1; // the lit core shrank (v0.10.14): stand in the best-lit free cell next to the torch
    for (let dx = -2; dx <= 2; dx++) for (let dy = -2; dy <= 2; dy++) {
      const qx = torch.col + 0.5 + dx, qy = torch.row + 0.5 + dy;
      if (w.blocks(qx, qy, 0.25)) continue;
      const l = w.lightAt(qx, qy);
      if (l > bestL + 1e-9 && Math.hypot(dx, dy) > 0.9) { bestL = l; P = { x: qx, y: qy }; }
    }
    if (st.people.length < 2) return { ok: false, why: 'people' };
    const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    const free = (x, y) => !w.blocks(x, y, 0.25);
    const clear = (ax, ay, bx, by) => { for (let k = 0; k <= 10; k++) if (w.blocks(ax + (bx - ax) * k / 10, ay + (by - ay) * k / 10, 0.05)) return false; return true; };
    for (const d of dirs) {
      const e = d;
      const vx = P.x + d[0] * 1.2, vy = P.y + d[1] * 1.2; // 1.2 cells: outside the lit bump-notice distance
      const wx = P.x + e[0] * 2.6, wy = P.y + e[1] * 2.6;
      if (!free(vx, vy) || !free(wx, wy) || !free(P.x, P.y) || !clear(wx, wy, P.x, P.y)) continue;
      const v = st.people[0], q = st.people[1];
      for (const p of st.people) { p.mode = 'path'; p.state = 'idle'; p.idleLeft = 30; p.x = 2 + p.id * 0.01; p.y = 2; }
      const vang = Math.atan2(d[1], d[0]);
      v.x = vx; v.y = vy; v.angle = vang; v.lookAngle = 0;
      q.x = wx; q.y = wy; q.lookAngle = 0;
      q.angle = facingAway ? Math.atan2(d[1], d[0]) : Math.atan2(-d[1], -d[0]);
      G.debugTeleport(P.x, P.y, vang);
      G.debugAdvance(0.02);
      v.x = vx; v.y = vy; q.x = wx; q.y = wy; q.mode = 'path';
      G.debugBlood(40);
      const b0 = G.debugState().night.blood;
      const lit = G.debugState().playerLit;
      if (!G.debugFeed()) continue;
      let steps = 0;
      while (G.debugState().state === 'feeding' && steps < 900) { G.debugAdvance(1 / 60); steps++; }
      const s = G.debugState();
      return { ok: true, lit, steps, secs: steps / 60, b0, b1: s.night.blood, victim: s.victim, state: s.state, wmode: q.mode };
    }
    return { ok: false, why: 'geometry' };
  }, [facing]);
  const litA = await litTest(false);
  check('v0.7.2: torch-lit witness facing the player interrupts within a few frames', litA.ok && litA.lit > 0.3 && litA.steps <= 6 && litA.victim.mode === 'dazed' && litA.b1 >= litA.b0 - 0.5, JSON.stringify(litA));
  const litB = await litTest(true);
  check('v0.7.2: lit walker facing away: startled by the victim struggle noise as it grows (not a heartbeat; within a few seconds), then sees you, drink ends, blood kept', litB.ok && litB.lit > 0.3 && litB.secs > 0.05 && litB.secs < 8 && litB.victim.mode === 'dazed' && litB.b1 > litB.b0 + 0.3 && litB.wmode === 'flee', JSON.stringify(litB));
  check('v0.7.2: no errors (lit page)', lit7.errs.length === 0, lit7.errs.join(' | '));
  check('v0.7.2: no errors (feed pages)', f7.errs.length === 0 && extra.every((m) => m.errs.length === 0), f7.errs.concat(...extra.map((m) => m.errs)).join(' | '));
  check('v0.7.2: no CSP violations (feed pages)', f7.csps.length === 0 && extra.every((m) => m.csps.length === 0), f7.csps.join(' | '));
  console.log('screenshot: shots/v072-drink.png');

  // REAL-play feed: hold the right mouse button, then let go.
  const r7 = await mk07('?seed=7&debug=1&map=test');
  const rp = r7.pg;
  await rp.evaluate(SETUP);
  real = await rp.evaluate(() => {
    const G = window.VCS.Game;
    G.debugBlood(10);
    window.__pin();
    const all = G.debugState().people.map((p) => p.id);
    for (const c of all) {
      const skip = all.filter((q) => q !== c);
      window.__place('front', skip);
      G.debugAdvance(0.02);
      if (window.__place('front', skip) === c) return { id: c, before: G.debugState().night.blood };
    }
    return null;
  });
  check('v0.7.2: real-feed setup found a person', !!real, JSON.stringify(real));
  const box = await rp.evaluate(() => { const r = document.getElementById('view').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  await rp.mouse.move(box.x, box.y);
  await rp.evaluate((id) => { const G = window.VCS.Game; const all = G.debugState().people.map((p) => p.id); window.__place('front', all.filter((q) => q !== id)); }, real ? real.id : 0);
  await rp.mouse.down({ button: 'right' });
  await waitF(rp, () => { const s = window.VCS.Game.debugState(); return s.state === 'feeding' && s.drink && s.drink.drunk > 5; }, null, 3000);
  const held = await ds(rp);
  check('v0.7.2: holding right click drinks (real mouse)', held.state === 'feeding' && !!held.drink && held.drink.drunk > 1, JSON.stringify({ s: held.state, d: held.drink }));
  await rp.mouse.up({ button: 'right' });
  await waitF(rp, () => window.VCS.Game.debugState().state === 'playing', null, 3000);
  const rs = await ds(rp);
  check('v0.7.2: letting go releases the victim dazed and keeps the blood', rs.state === 'playing' && rs.drink === null && rs.victim && (rs.victim.mode === 'dazed' || rs.victim.mode === 'flee') && rs.night.blood > real.before + 3, JSON.stringify({ s: rs.state, v: rs.victim, b: rs.night.blood, before: real && real.before, ft: await rp.evaluate(() => (JSON.parse(localStorage.getItem('vcs.settings')) || {}).feedToggle) }));
  const noTarget = await rp.evaluate(() => { const G = window.VCS.Game; G.debugTeleport(1.5, 1.5, 0); return G.debugFeed(); });
  check('v0.7: feed with no target returns false', noTarget === false || noTarget === undefined);
  await rp.mouse.down({ button: 'right' });
  await rp.mouse.up({ button: 'right' });
  await frames(rp, 5);
  check('v0.7.2: right click with no target is a harmless miss', (await ds(rp)).state === 'playing');
  // v0.10: feedToggle - two right clicks start then stop a drink.
  await rp.evaluate(() => { const el = document.getElementById('set-feedtoggle'); el.checked = true; el.dispatchEvent(new Event('change', { bubbles: true })); });
  const tg = await rp.evaluate(() => {
    const G = window.VCS.Game;
    G.debugBlood(10);
    window.__pin();
    const all = G.debugState().people.map((p) => p.id);
    for (const c of all) {
      const skip = all.filter((q) => q !== c);
      window.__place('front', skip);
      G.debugAdvance(0.02);
      if (window.__place('front', skip) === c) return { id: c };
    }
    return null;
  });
  check('v0.10: feed-toggle setup found a person', !!tg, JSON.stringify(tg));
  const id0 = tg ? tg.id : 0;
  // Place the person and fire the right click in one page task (so nobody wanders off between the two).
  const rclick = () => rp.evaluate((id) => {
    const G = window.VCS.Game;
    if (id !== null) { const all = G.debugState().people.map((p) => p.id); window.__place('front', all.filter((q) => q !== id)); }
    const cv = document.getElementById('view');
    cv.dispatchEvent(new MouseEvent('mousedown', { button: 2, bubbles: true }));
    window.dispatchEvent(new MouseEvent('mouseup', { button: 2, bubbles: true }));
  }, id0);
  await rclick();
  await waitF(rp, () => { const s = window.VCS.Game.debugState(); return s.state === 'feeding' && s.drink && s.drink.drunk > 1; }, null, 3000);
  const tOn = await ds(rp);
  check('v0.10: feedToggle first right click starts a drink and keeps it after release', tOn.state === 'feeding' && !!tOn.drink && tOn.drink.drunk > 1, JSON.stringify({ s: tOn.state, d: tOn.drink, modes: tOn.peopleModes, c: tOn.card, ft: await rp.evaluate(() => document.getElementById('set-feedtoggle').checked), st: await rp.evaluate(() => JSON.stringify(window.VCS.Game.debugState().player)) }));
  await rp.evaluate(() => {
    const cv = document.getElementById('view');
    cv.dispatchEvent(new MouseEvent('mousedown', { button: 2, bubbles: true }));
    window.dispatchEvent(new MouseEvent('mouseup', { button: 2, bubbles: true }));
  });
  await waitF(rp, () => window.VCS.Game.debugState().state === 'playing', null, 3000);
  const tOff = await ds(rp);
  check('v0.10: feedToggle second right click ends the drink', tOff.state === 'playing' && tOff.drink === null, JSON.stringify({ s: tOff.state, d: tOff.drink }));
  await rp.evaluate(() => { const el = document.getElementById('set-feedtoggle'); el.checked = false; el.dispatchEvent(new Event('change', { bubbles: true })); });
  check('v0.7: no errors (real feed page)', r7.errs.length === 0, r7.errs.join(' | '));
  check('v0.7: no CSP violations (real feed page)', r7.csps.length === 0, r7.csps.join(' | '));
  check('v0.7: debugNight returns a copy', await rp.evaluate(() => { const a = window.VCS.Game.debugNight(); a.night = 77; return window.VCS.Game.debugNight().night === 1; }));
  check('v0.7: no ERROR log entries', (await ds(fp)).errors === 0 && (await ds(pg7)).errors === 0);
  console.log('screenshots: shots/v07-{hud,dawn,card}.png');

  } catch (e) { secFail("v0.7.2 feeding", e); }
  await closeLeaked([page, pg7, p8]);
  try {
  // ---------------- v0.8 runs, saves, menu ----------------
  shots8 = path.join(tmpOut, 'shots8');
  fs.mkdirSync(shots8, { recursive: true });
  p8 = await newPg(browser, { viewport: { width: 1000, height: 600 } });
  const errs8 = [];
  const csp8 = [];
  p8.on('pageerror', (e) => errs8.push(String(e && e.message ? e.message : e)));
  p8.on('console', (m) => {
    const t = m.text();
    if (t.includes('Content Security Policy')) csp8.push(t);
    else if (m.type() === 'error') errs8.push(t);
  });
  const toTitle = async () => {
    await p8.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
  };
  vis = (id) => p8.evaluate((i) => !document.getElementById(i).hidden, id);
  const noticeText = () => p8.evaluate(() => document.getElementById('notice').hidden ? '' : document.getElementById('notice-list').textContent);
  await p8.goto(url07 + '?seed=7&debug=1');
  await toTitle();
  await sleep(700);
  check('v0.8: menu is visible at title', await vis('menu'));
  check('v0.8: Continue disabled with no saved run', await p8.evaluate(() => document.getElementById('btn-continue').disabled));
  const crypt8 = await p8.evaluate(() => { const c = document.getElementById('view'); const x = c.getContext('2d'); const d = x.getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 0; i < d.length; i += 16) if (d[i] + d[i + 1] + d[i + 2] > 60) n++; return n; });
  check('v0.8: crypt menu backdrop drawn on the canvas', crypt8 > 20, 'lit=' + crypt8);
  await p8.screenshot({ path: path.join(shots8, 'menu.png') });
  await clickNew(p8);
  await sleep(250);
  check('v0.8: New run -> playing', (await ds(p8)).state === 'playing');
  check('v0.8: menu hidden while playing', !(await vis('menu')));
  const run0 = await p8.evaluate(() => window.VCS.Game.debugRun());
  check('v0.8: run has a seed and no boons', Number.isInteger(run0.seed) && run0.boons.length === 0 && run0.pendingBoons === null, JSON.stringify(run0));
  check('v0.8: new run saved immediately', await p8.evaluate(() => { const o = JSON.parse(localStorage.getItem('vcs.run')); return !!o && o.kind === 'run' && o.data.v === 4 && o.v === 4; }));
  // Sealed safe spot in town.
  await p8.evaluate(() => window.VCS.Game.debugMap('town', null));
  const sealed = await p8.evaluate(() => (window.VCS.Game.debugRun().closedSafe.town || [])[0] || null);
  check('v0.8: a town safe spot is sealed for this run', !!sealed, JSON.stringify(sealed));
  if (sealed) {
    const sl8 = await p8.evaluate((c) => { const G = window.VCS.Game; G.debugTeleport(c[0] + 0.5, c[1] + 0.5, 0); const r = G.debugSleep(); return { r, s: G.debugState().state, card: G.debugState().card }; }, sealed);
    check('v0.8: sealed safe spot refuses sleep and shows Sealed', sl8.r === false && sl8.s === 'playing' && sl8.card === 'Sealed', JSON.stringify(sl8));
  }
  // Sleep in the crypt -> boon panel -> pick with the keyboard.
  await p8.evaluate((b) => { const G = window.VCS.Game; G.debugMap('crypt', null); G.debugTeleport(b.x - 0.5, b.y + 0.5, 0); }, bed);
  check('v0.8: sleep starts in the crypt', (await p8.evaluate(() => window.VCS.Game.debugSleep())) === true);
  await p8.evaluate(() => window.VCS.Game.debugAdvance(2.4));
  await sleep(300);
  check('v0.8: state is boon after the sleep sequence', (await ds(p8)).state === 'boon');
  check('v0.8: boon panel shows 3 cards with icon canvases', await p8.evaluate(() => document.querySelectorAll('#boon-list .card canvas').length === 3 && !document.getElementById('boons').hidden));
  const iconInk = await p8.evaluate(() => { const c = document.querySelector('#boon-list canvas'); const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i] > 20) n++; return n; });
  check('v0.8: boon icon is drawn', iconInk > 30, 'ink=' + iconInk);
  check('v0.8: pending boons saved with the run', await p8.evaluate(() => { const o = JSON.parse(localStorage.getItem('vcs.run')); return Array.isArray(o.data.run.pendingBoons) && o.data.run.pendingBoons.length === 3; }));
  await p8.screenshot({ path: path.join(shots8, 'boons.png') });
  await p8.keyboard.press('Digit1');
  await sleep(200);
  const n2 = await ds(p8);
  check('v0.8: keyboard 1 picks a boon -> night 2 playing', n2.state === 'playing' && n2.night.n === 2, JSON.stringify({ s: n2.state, n: n2.night }));
  const run1 = await p8.evaluate(() => window.VCS.Game.debugRun());
  check('v0.8: boon recorded, pending cleared', run1.boons.length === 1 && run1.pendingBoons === null && run1.seed === run0.seed, JSON.stringify(run1));
  await p8.evaluate(() => window.VCS.Game.debugSave());
  // Reload: Continue restores the same run.
  await settleReload(p8);
  await toTitle();
  check('v0.8: after reload Continue is enabled', await p8.evaluate(() => !document.getElementById('btn-continue').disabled));
  await p8.click('#btn-continue', { timeout: 10000 });
  await sleep(250);
  const c1 = await ds(p8);
  const run2 = await p8.evaluate(() => window.VCS.Game.debugRun());
  check('v0.8: Continue -> playing on night 2 with the same seed and boon', c1.state === 'playing' && c1.night.n === 2 && run2.seed === run0.seed && run2.boons.length === 1 && run2.boons[0] === run1.boons[0], JSON.stringify({ s: c1.state, n: c1.night, r: run2 }));
  // Abandon-confirm flow: leave via runend, new run, then end it.
  check('v0.8: debugEndRun(lost) reaches the run-end panel', (await p8.evaluate(() => window.VCS.Game.debugEndRun('lost'))) === true && (await ds(p8)).state === 'runend');
  await sleep(300);
  const meta1 = await p8.evaluate(() => window.VCS.Game.debugMeta());
  check('v0.8: essence earned after a run', meta1.essence > 0 && meta1.stats.runs === 1, JSON.stringify(meta1));
  check('v0.8: run-end panel shows essence and a tombstone', await p8.evaluate(() => /Essence \+\d+/.test(document.getElementById('runend-essence').textContent) && !document.getElementById('runend').hidden));
  const tombInk = await p8.evaluate(() => { const c = document.getElementById('tomb'); const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i] > 20) n++; return n; });
  check('v0.8: tombstone canvas is drawn', tombInk > 50, 'ink=' + tombInk);
  await p8.screenshot({ path: path.join(shots8, 'tombstone.png') });
  check('v0.8: run save removed after the run ends', await p8.evaluate(() => localStorage.getItem('vcs.run') === null));
  await p8.click('#btn-crypt', { timeout: 10000 });
  await sleep(200);
  check('v0.8: Crypt button returns to the menu', (await ds(p8)).state === 'title' && await vis('menu'));
  check('v0.8: Continue disabled again', await p8.evaluate(() => document.getElementById('btn-continue').disabled));
  // Stats, shop.
  await p8.click('#btn-stats', { timeout: 10000 });
  await waitF(p8, () => !document.getElementById('stats').hidden);
  check('v0.8: stats panel lists values', await vis('stats') && (await p8.evaluate(() => document.querySelectorAll('#stats-list dt').length)) >= 6);
  await pressUntil(p8, 'Escape', () => document.getElementById('stats').hidden && !document.getElementById('menu').hidden);
  check('v0.8: Escape in stats returns to the main menu', await vis('menu') && !(await vis('stats')));
  await p8.evaluate(() => window.VCS.Game.debugEssence(30));
  await p8.click('#btn-shop', { timeout: 10000 });
  await sleep(300);
  check('v0.8: shop shows 9 cards', await vis('shop') && (await p8.evaluate(() => document.querySelectorAll('#shop-list .card').length)) === 9);
  const shopInk = await p8.evaluate(() => { const c = document.querySelector('#shop-list canvas'); const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i] > 20) n++; return n; });
  check('v0.8: shop icon is drawn', shopInk > 30, 'ink=' + shopInk);
  await p8.screenshot({ path: path.join(shots8, 'shop.png') });
  await p8.click('#buy-far_echo', { timeout: 10000 });
  await sleep(150);
  const meta2 = await p8.evaluate(() => window.VCS.Game.debugMeta());
  check('v0.8: buying far_echo costs 5 and sets tier 1', meta2.upgrades.far_echo === 1 && meta2.essence === 25, JSON.stringify(meta2));
  // Export / import round trip through the real file input.
  const exported = await p8.evaluate(() => window.VCS.Game.debugExport());
  check('v0.8: export text is an export envelope', /"kind": "export"/.test(exported));
  await p8.click('#btn-shop-back', { timeout: 10000 });
  await p8.evaluate(() => { const l = document.getElementById('notice-list'); while (l.firstChild) l.removeChild(l.firstChild); document.getElementById('notice').hidden = true; });
  await p8.setInputFiles('#file-import', { name: 'save.json', mimeType: 'application/json', buffer: Buffer.from(exported) });
  await sleep(400);
  check('v0.8: import of a good file reports success', /Save imported/.test(await noticeText()), await noticeText());
  await p8.evaluate(() => { const l = document.getElementById('notice-list'); while (l.firstChild) l.removeChild(l.firstChild); document.getElementById('notice').hidden = true; });
  await p8.setInputFiles('#file-import', { name: 'bad.json', mimeType: 'application/json', buffer: Buffer.from('{"nope":1}') });
  await sleep(400);
  check('v0.8: import of a bad file reports failure', /Import failed \(E_SAVE_/.test(await noticeText()), await noticeText());
  check('v0.8: failed import left meta intact', (await p8.evaluate(() => window.VCS.Game.debugMeta())).upgrades.far_echo === 1);
  check('v0.8: parseImport rejects __proto__ keys', await p8.evaluate(() => VCS.Save.parseImport('{"app":"vcs","kind":"export","v":1,"game":"x","meta":null,"run":null,"__proto__":{"a":1}}').code) === 'E_SAVE_BAD_KEY');
  // Reload: the upgrade persists and shapes the next run.
  await settleReload(p8);
  await toTitle();
  check('v0.8: upgrade tier persists across reload', (await p8.evaluate(() => window.VCS.Game.debugMeta())).upgrades.far_echo === 1);
  await clickNew(p8);
  await sleep(250);
  const fx1 = await p8.evaluate(() => window.VCS.Game.debugFx());
  check('v0.8: far_echo tier 1 gives sonarRange 1.15', Math.abs(fx1.sonarRange - 1.15) < 1e-9, JSON.stringify(fx1));
  // Abandon flow needs the title with a stored run: reload (pagehide saves), then New run twice.
  await p8.evaluate(() => window.VCS.Game.debugSave());
  await settleReload(p8);
  await toTitle();
  const runsBefore = (await p8.evaluate(() => window.VCS.Game.debugMeta())).stats.runs;
  await clickNew(p8);
  await sleep(150);
  check('v0.8: New run with a saved run asks to abandon first', /Abandon run\?/.test(await p8.evaluate(() => document.getElementById('btn-menu-new').textContent)) && (await ds(p8)).state === 'title', JSON.stringify({ s: (await ds(p8)).state, t: await p8.evaluate(() => document.getElementById('btn-menu-new').textContent), run: await p8.evaluate(() => !!localStorage.getItem('vcs.run')) }));
  await clickNew(p8);
  await sleep(250);
  check('v0.8: second click abandons (records a run) and starts a new one', (await ds(p8)).state === 'playing' && (await p8.evaluate(() => window.VCS.Game.debugMeta())).stats.runs === runsBefore + 1);
  // Corrupt main meta with a valid backup: reload restores the backup and says so.
  await p8.evaluate(() => { window.VCS.Game.debugSave(); window.VCS.Game.debugSave(); const o = JSON.parse(localStorage.getItem('vcs.meta')); o.sum = 'deadbeef'; localStorage.setItem('vcs.meta', JSON.stringify(o)); });
  await settleReload(p8);
  await toTitle();
  const nt8 = await noticeText();
  check('v0.8: corrupt meta with a backup shows a restored-backup notice', /restored backup/.test(nt8), nt8);
  check('v0.8: backup meta is in effect', (await p8.evaluate(() => window.VCS.Game.debugMeta())).upgrades.far_echo === 1);
  // Corrupt run: Continue fails cleanly.
  await p8.evaluate(() => { localStorage.setItem('vcs.run', '{"broken"'); localStorage.removeItem('vcs.run.bak'); });
  await p8.evaluate(() => { const l = document.getElementById('notice-list'); while (l.firstChild) l.removeChild(l.firstChild); document.getElementById('notice').hidden = true; });
  await p8.evaluate(() => { document.getElementById('btn-continue').disabled = false; });
  await p8.click('#btn-continue', { timeout: 10000 });
  await sleep(200);
  check('v0.8: unreadable run save gives a notice and stays on the menu', /Run save could not be loaded/.test(await noticeText()) && (await ds(p8)).state === 'title' && await p8.evaluate(() => document.getElementById('btn-continue').disabled));
  check('v0.8: no page errors', errs8.length === 0, errs8.join(' | '));
  check('v0.8: no CSP violations', csp8.length === 0, csp8.join(' | '));
  console.log('screenshots: tests/shots/{menu,shop,boons,tombstone}.png');
  } catch (e) { secFail("v0.8 runs/saves", e); }
  await closeLeaked([page, pg7, p8]);
  try {
  // ---------------- v0.9 hunger: gifts, powers, fear ----------------
  {
  const p9 = await newPg(browser, { viewport: { width: 1000, height: 600 } });
  const errs9 = [];
  const csp9 = [];
  p9.on('pageerror', (e) => errs9.push(String(e && e.message ? e.message : e)));
  p9.on('console', (m) => {
    const t = m.text();
    if (t.includes('Content Security Policy')) csp9.push(t);
    else if (m.type() === 'error') errs9.push(t);
  });
  const v9 = (fn, arg) => p9.evaluate(fn, arg);
  const hg = () => v9(() => window.VCS.Game.debugHunger());
  const bl = () => v9(() => window.VCS.Game.debugState().night.blood);
  const title9 = () => p9.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
  await p9.goto(url07 + '?debug=1&seed=4242');
  await title9();
  await clickNew(p9);
  await sleep(300);
  check('v0.9: new run has fresh hunger', await v9(() => { const h = window.VCS.Game.debugHunger(); return !!h && h.fear === 0 && h.over === 0 && h.gifts.length === 0 && h.essenceBonus === 0; }));
  await v9(() => { const G = window.VCS.Game; G.debugBlood(100); });
  const taken = await v9(() => window.VCS.Game.debugOverflow(40));
  await sleep(150);
  const gs = await ds(p9);
  check('v0.9: filling overflow opens the gift state with 3 cards', taken === 40 && gs.state === 'gift' && await v9(() => !document.getElementById('boons').hidden && document.getElementById('boons-title').textContent === 'Blood gift' && document.querySelectorAll('#boon-list .card').length === 3), JSON.stringify({ taken, s: gs.state }));
  check('v0.9: pending gifts saved with the run', await v9(() => { const o = JSON.parse(localStorage.getItem('vcs.run')); return o.v === 4 && Array.isArray(o.data.run.pendingGifts) && o.data.run.pendingGifts.length === 3 && !!o.data.run.hunger; }));
  await sleep(300);
  await p9.screenshot({ path: path.join(shots8, 'gift.png') });
  const offered = await v9(() => window.VCS.Game.debugPending());
  await v9(() => window.VCS.Game.debugPickGift(0));
  const afterPick = await ds(p9);
  const h1 = await hg();
  const gdef = await v9((id) => window.VCS.HungerData.gifts.find((g) => g.id === id), offered[0]);
  const fx1 = await v9(() => window.VCS.Game.debugFx());
  check('v0.9: pick -> playing, 1 gift, essence bonus 2, over reset', afterPick.state === 'playing' && h1.gifts.length === 1 && h1.gifts[0] === offered[0] && h1.essenceBonus === 2 && h1.over === 0 && h1.giftsTonight === 1, JSON.stringify(h1));
  check('v0.9: the gift is reflected in effects', gdef.kind !== 'effect' || Math.abs(fx1[gdef.effect] - gdef.value) < 1e-6, JSON.stringify({ gdef, fx1 }));
  check('v0.9: gift panel hidden again', await v9(() => document.getElementById('boons').hidden));
  // Second gift costs 60; third is closed.
  check('v0.9: second gift is not ready at 40 overflow', (await v9(() => window.VCS.Game.debugOverflow(40))) === 40 && (await ds(p9)).state === 'playing');
  check('v0.9: second gift opens at 60', (await v9(() => window.VCS.Game.debugOverflow(40))) === 20 && (await ds(p9)).state === 'gift');
  await v9(() => window.VCS.Game.debugPickGift(1));
  check('v0.9: after 2 gifts overflow is closed', (await v9(() => window.VCS.Game.debugOverflow(10))) === 0 && (await hg()).gifts.length === 2);
  // Powers on night 1.
  await v9(() => { const G = window.VCS.Game; G.debugBlood(80); G.debugFear(0); });
  const b0 = await bl();
  const sh = await v9(() => window.VCS.Game.debugPower('shriek'));
  const b1 = await bl();
  check('v0.9: shriek costs 15 blood and adds 2 fear', sh.ok && b0 - b1 > 14.5 && b0 - b1 < 16 && (await hg()).fear === 2, JSON.stringify({ sh, b0, b1 }));
  await v9(() => window.VCS.Game.debugAdvance(0.2));
  const shs = await ds(p9);
  check('v0.9: shriek creates a shriek pulse', (shs.sounds.shriek || 0) >= 1, JSON.stringify(shs.sounds));
  check('v0.9: shriek on cooldown refuses', (await v9(() => window.VCS.Game.debugPower('shriek'))).code === 'E_COOLDOWN');
  check('v0.9: mist is locked on night 1', (await v9(() => window.VCS.Game.debugPower('mist'))).code === 'E_LOCKED');
  check('v0.9: still is locked on night 1', (await v9(() => window.VCS.Game.debugPower('still'))).code === 'E_LOCKED');
  await v9(() => window.VCS.Game.debugBlood(5));
  await v9(() => window.VCS.Game.debugAdvance(7));
  check('v0.9: shriek with too little blood is refused and shows a card', (await v9(() => window.VCS.Game.debugPower('shriek'))).code === 'E_POOR' && (await ds(p9)).card === 'Not enough blood');
  // Sleep twice (crypt bed): fear -5 each time, nights 2 and 3 unlock mist and still.
  const bed9 = await v9(() => { const rows = VCS.MapData.maps.crypt.rows; for (let y = 0; y < rows.length; y++) { const x = rows[y].indexOf('C'); if (x >= 0) return { x, y }; } return null; });
  const sleepNight = async () => {
    await v9((b) => { const G = window.VCS.Game; G.debugMap('crypt', null); G.debugTeleport(b.x - 0.5, b.y + 0.5, 0); }, bed9);
    const ok = await v9(() => window.VCS.Game.debugSleep());
    await v9(() => window.VCS.Game.debugAdvance(2.4));
    const st = (await ds(p9)).state;
    await v9(() => window.VCS.Game.debugPickBoon(0));
    return ok && st === 'boon';
  };
  await v9(() => window.VCS.Game.debugFear(7));
  check('v0.9: sleep 1 -> boon -> night 2', (await sleepNight()) && (await ds(p9)).night.n === 2);
  const hN2 = await hg();
  check('v0.9: sleep lowers fear by 5 and resets giftsTonight', hN2.fear === 2 && hN2.giftsTonight === 0 && hN2.over === 0, JSON.stringify(hN2));
  check('v0.9: night 2 card names Mist', /Night 2 .*Mist \(Shift\)/.test((await ds(p9)).card || ''), (await ds(p9)).card);
  check('v0.9: sleep 2 -> boon -> night 3', (await sleepNight()) && (await ds(p9)).night.n === 3);
  check('v0.9: night 3 card names Still', /Night 3 .*Still \(F\)/.test((await ds(p9)).card || ''));
  check('v0.9: fear after two sleeps is 0', (await hg()).fear === 0, JSON.stringify(await hg()));
  // Night 3: all three powers usable. Mist dash in the open street.
  // One synchronous evaluate: real frames cannot decay fear or cooldowns between the calls.
  const pw = await v9(() => {
    const G = window.VCS.Game;
    G.debugMap('town', null); G.debugBlood(100); G.debugFear(0);
    const pos0 = G.debugState().player;
    const pos0c = { x: pos0.x, y: pos0.y };
    const ms = G.debugPower('mist');
    const mid9 = G.debugHunger();
    const midMist = mid9.mist;
    G.debugAdvance(0.4);
    const pos1 = G.debugState().player;
    const h1 = G.debugHunger();
    const ss = G.debugPower('still');
    const hs9 = G.debugHunger();
    return { ms, midMist, mdist: Math.hypot(pos1.x - pos0c.x, pos1.y - pos0c.y), mistAfter: h1.mist, fear1: h1.fear, ss, hs9 };
  });
  check('v0.9: mist works on night 3 (costs 10, adds 1 fear, dashes up to 2 cells, ends)', pw.ms.ok && pw.midMist === true && pw.mdist > 0 && pw.mdist <= 2.05 && pw.mistAfter === false && pw.fear1 === 1, JSON.stringify(pw));
  check('v0.9: still works on night 3 (5 s, fear +1)', pw.ss.ok && pw.hs9.stillLeft > 4.5 && pw.hs9.stillLeft <= 5 && pw.hs9.fear === 2, JSON.stringify(pw.hs9));
  await v9(() => window.VCS.Game.debugAdvance(5.2));
  check('v0.9: still ends after 5 s', (await hg()).stillLeft === 0);
  // v0.10: KeyC mist, ArrowUp, whimper event, distance culling.
  await v9(() => { const G = window.VCS.Game; G.debugAdvance(8); G.debugBlood(100); });
  const pre10 = (await ds(p9)).player;
  const blood10 = await bl();
  await frames(p9, 4);
  await p9.keyboard.press('KeyC');
  await waitF(p9, (b) => window.VCS.Game.debugState().night.blood < b - 8, blood10, 2000);
  const blood10b = await bl();
  check('v0.10: KeyC triggers mist when unlocked (costs 10 blood)', blood10 - blood10b > 8, 'blood ' + blood10 + ' -> ' + blood10b + ' ' + JSON.stringify({ st: (await ds(p9)).state, c: (await ds(p9)).card, m: (await ds(p9)).map, h: await hg() }));
  await v9(() => window.VCS.Game.debugAdvance(1));
  await v9((q) => window.VCS.Game.debugTeleport(q.x, q.y, q.angle), pre10);
  const up0 = (await ds(p9)).player;
  await p9.keyboard.down('ArrowUp');
  await waitF(p9, (q) => { const p = window.VCS.Game.debugState().player; return Math.hypot(p.x - q.x, p.y - q.y) > 0.3; }, up0, 3000);
  await p9.keyboard.up('ArrowUp');
  const up1 = (await ds(p9)).player;
  check('v0.10: ArrowUp moves forward', Math.hypot(up1.x - up0.x, up1.y - up0.y) > 0.3, 'moved=' + Math.hypot(up1.x - up0.x, up1.y - up0.y).toFixed(2));
  const wh = await v9(() => {
    const G = window.VCS.Game;
    const st = G.debugPeopleState();
    const pr = st.people[0];
    if (!pr) return null;
    G.debugTeleport(pr.x - 1.5, pr.y, 0);
    st.events.push({ type: 'whimper', id: pr.id, x: pr.x, y: pr.y });
    G.debugAdvance(0.03);
    return G.debugState().sounds.whimper || 0;
  });
  check('v0.10: whimper event produces a whimper sound pulse', wh !== null && wh >= 1, 'whimper=' + wh);
  const far = await v9(() => window.VCS.Game.debugPlay('scream', 30));
  const nearPlay = await v9(() => window.VCS.Game.debugPlay('scream', 2));
  check('v0.10: a scream 30 cells away is dropped, one 2 cells away plays', far === false && nearPlay === true, JSON.stringify({ far, nearPlay }));
  // HUD screenshot: some fear, partial overflow, all powers visible and ready.
  await v9(() => { const G = window.VCS.Game; G.debugAdvance(13); G.debugBlood(100); G.debugHungerSet({ fear: 8 }); G.debugOverflow(25); G.debugAdvance(0.3); G.debugPulse(); G.debugAdvance(0.4); });
  await sleep(250);
  await p9.screenshot({ path: path.join(shots8, 'hud-powers.png') });
  check('v0.9: partial overflow kept without opening a gift', (await hg()).over === 25 && (await ds(p9)).state === 'playing');
  // Save, reload, Continue: hunger survives.
  const pre = await hg();
  await v9(() => window.VCS.Game.debugSave());
  await settleReload(p9);
  await title9();
  await sleep(300);
  await p9.click('#btn-continue', { timeout: 10000 });
  await sleep(300);
  const post = await hg();
  const cs9 = await ds(p9);
  check('v0.9: Continue restores night, fear, gifts, overflow and bonus', cs9.state === 'playing' && cs9.night.n === 3 && post.fear === pre.fear && post.gifts.length === 2 && post.over === 25 && post.essenceBonus === 4 && JSON.stringify(post.gifts) === JSON.stringify(pre.gifts), JSON.stringify({ pre, post }));
  // A v3 save (no hunger) still loads. Written from a second page (this page's pagehide would overwrite it).
  const pb = await newPg(browser, { viewport: { width: 1000, height: 600 } });
  await v9(() => window.VCS.Game.debugSave());
  const snap3 = await v9(() => { const s = window.VCS.Game.getSnapshot(); s.v = 3; delete s.run.hunger; delete s.run.pendingGifts; return s; });
  await p9.goto('about:blank');
  await pb.goto(url07 + '?seed=7&debug=1');
  await pb.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
  const v3ok = await pb.evaluate((snap) => window.VCS.Save.create(window.localStorage).write('run', 3, snap).ok, snap3);
  await pb.reload();
  await pb.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
  await sleep(300);
  await pb.click('#btn-continue', { timeout: 10000 });
  await sleep(300);
  const h3 = await pb.evaluate(() => window.VCS.Game.debugHunger());
  const st3 = await pb.evaluate(() => window.VCS.Game.debugState());
  check('v0.9: a v3 save continues with fresh hunger', v3ok && st3.state === 'playing' && !!h3 && h3.fear === 0 && h3.gifts.length === 0 && st3.night.n === 3, JSON.stringify({ h3, s: st3.state }));
  await p9.close();
  // Run end awards the gift bonus.
  await pb.evaluate(() => window.VCS.Game.debugOverflow(40));
  await pb.evaluate(() => window.VCS.Game.debugPickGift(0));
  const m0 = await pb.evaluate(() => window.VCS.Game.debugMeta().stats.essenceEarned);
  await pb.evaluate(() => window.VCS.Game.debugEndRun('lost'));
  const m1 = await pb.evaluate(() => window.VCS.Game.debugMeta().stats.essenceEarned);
  const re = await pb.evaluate(() => document.getElementById('runend-essence').textContent);
  check('v0.9: run end shows and awards the gift bonus', m1 - m0 === 2 * 4 + 2 && /Essence \+10 \(bonus \+2\)/.test(re), JSON.stringify({ m0, m1, re }));
  await pb.screenshot({ path: path.join(shots8, 'tombstone-gifts.png') });
  check('v0.9: no page errors', errs9.length === 0, errs9.join(' | '));
  check('v0.9: no CSP violations', csp9.length === 0, csp9.join(' | '));
  console.log('screenshots: tests/shots/{gift,hud-powers}.png');
  }
  check('v0.8: forced crash still shows the error screen', await (async () => {
    await p8.evaluate(() => window.VCS.Game.fatal('E_TEST', 'forced crash', null));
    return (await vis('error')) && !(await vis('menu')) && (await ds(p8)).state === 'error';
  })());

  } catch (e) { secFail("v0.9 hunger", e); }
  await closeLeaked([page, pg7, p8]);
  try {
  // ---- v0.9.1: night length setting, guide, unlock sub line ----
  {
    const urlG = INDEX_URL;
    const shotsG = path.join(tmpOut, 'shotsG');
    fs.mkdirSync(shotsG, { recursive: true });
    const errsG = [];
    const cspG = [];
    const pg = await newPg(browser, { viewport: { width: 1000, height: 600 } });
    pg.on('pageerror', (e) => errsG.push(String(e && e.message ? e.message : e)));
    pg.on('console', (m) => { const t = m.text(); if (t.includes('Content Security Policy')) cspG.push(t); });
    const dsG = () => pg.evaluate(() => window.VCS.Game.debugState());
    const titleG = () => pg.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
    const hid = (id) => pg.evaluate((i) => document.getElementById(i).hidden, id);
    await pg.goto(urlG + '?seed=7&debug=1');
    await titleG();
    check('v0.9.1: default night length is 4 on a fresh profile', await pg.evaluate(() => VCS.Config.DEFAULTS.nightLengthMin === 4 && JSON.parse(localStorage.getItem('vcs.settings') || 'null') === null));
    // Old settings (no cfgV) migrate to 4.
    await pg.evaluate(() => localStorage.setItem('vcs.settings', JSON.stringify({ nightLengthMin: 8, volume: 0.4 })));
    await pg.goto(urlG + '?seed=7&debug=1');
    await titleG();
    const mig = await pg.evaluate(() => JSON.parse(localStorage.getItem('vcs.settings')));
    check('v0.9.1: old settings without cfgV migrate to 4 and save cfgV 2', mig.nightLengthMin === 4 && mig.cfgV === 2 && mig.volume === 0.4, JSON.stringify(mig));
    await clickNew(pg);
    await sleep(300);
    const nsec0 = await pg.evaluate(() => window.VCS.Game.debugState().night);
    await escP(pg);
    check('v0.9.1: pause panel has an Abilities button', (await dsG()).state === 'paused' && !(await hid('pause')));
    await pg.click('#btn-settings');
    await pg.evaluate(() => { const el = document.getElementById('set-night'); el.value = '10'; el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); });
    const slid = await pg.evaluate(() => ({ out: document.getElementById('out-night').textContent, saved: JSON.parse(localStorage.getItem('vcs.settings')).nightLengthMin, cfg: VCS.Config.load().nightLengthMin }));
    check('v0.9.1: night length slider changes and saves the config', slid.saved === 10 && slid.cfg === 10 && /10/.test(slid.out), JSON.stringify(slid));
    check('v0.9.1: slider does not rescale the running night', (await pg.evaluate(() => window.VCS.Game.debugState().night.nightSec)) === nsec0.nightSec && nsec0.nightSec === 240, 'nightSec0=' + nsec0.nightSec);
    await pg.click('#btn-settings-back');
    // Guide from pause.
    await pg.click('#btn-abilities');
    await waitF(pg, () => !document.getElementById('guide').hidden);
    const gp = await pg.evaluate(() => ({ guide: !document.getElementById('guide').hidden, pause: !document.getElementById('pause').hidden, cards: document.querySelectorAll('#guide .gcard').length, locked: document.querySelectorAll('#guide .gcard.locked').length, txt: document.getElementById('guide').textContent }));
    check('v0.9.1: guide opens from pause with 3 power cards (2 locked on night 1)', gp.guide && !gp.pause && gp.cards === 3 && gp.locked === 2, JSON.stringify({ g: gp.guide, p: gp.pause, c: gp.cards, l: gp.locked }));
    check('v0.9.1: cards show cost, cooldown, fear and unlock text', /Cost 15 blood/.test(gp.txt) && /Cooldown 6 s/.test(gp.txt) && /Fear \+2/.test(gp.txt) && /Unlocks night 2/.test(gp.txt) && /Unlocks night 3/.test(gp.txt) && /twice as far/.test(gp.txt));
    await pg.screenshot({ path: path.join(shotsG, 'guide.png') });
    await pressUntil(pg, 'Escape', () => document.getElementById('guide').hidden && !document.getElementById('pause').hidden);
    check('v0.9.1: Esc returns from guide to pause', !(await hid('pause')) && (await hid('guide')));
    await pg.click('#btn-abilities');
    await pg.click('#btn-guide-back');
    check('v0.9.1: Back returns from guide to pause', !(await hid('pause')) && (await hid('guide')));
    await pg.click('#btn-resume');
    // Guide from menu.
    await pg.evaluate(() => window.VCS.Game.debugMenu('menu'));
    await pg.evaluate(() => { window.VCS.Game.debugEndRun('lost'); });
    await sleep(200);
    await pg.evaluate(() => window.VCS.Game.debugMenu('menu'));
    await sleep(200);
    await pg.click('#btn-guide');
    await waitF(pg, () => !document.getElementById('guide').hidden);
    const gm = await pg.evaluate(() => ({ guide: !document.getElementById('guide').hidden, menu: !document.getElementById('menu').hidden, cards: document.querySelectorAll('#guide .gcard').length, locked: document.querySelectorAll('#guide .gcard.locked').length }));
    check('v0.9.1: guide opens from the menu, nothing dimmed', gm.guide && !gm.menu && gm.cards === 3 && gm.locked === 0, JSON.stringify(gm));
    await pressUntil(pg, 'Escape', () => document.getElementById('guide').hidden && !document.getElementById('menu').hidden);
    check('v0.9.1: Esc returns from menu guide to the menu', !(await hid('menu')) && (await hid('guide')));
    await pg.click('#btn-guide');
    await pg.click('#btn-guide-back');
    check('v0.9.1: Back returns from menu guide to the menu', !(await hid('menu')) && (await hid('guide')));
    // Unlock card sub line on night 2.
    await pg.evaluate(() => localStorage.removeItem('vcs.seen'));
    await clickNew(pg);
    await sleep(300);
    const bedG = await pg.evaluate(() => { const rows = VCS.MapData.maps.crypt.rows; for (let y = 0; y < rows.length; y++) { const x = rows[y].indexOf('C'); if (x >= 0) return { x, y }; } return null; });
    await pg.evaluate((b) => { const G = window.VCS.Game; G.debugMap('crypt', null); G.debugTeleport(b.x - 0.5, b.y + 0.5, 0); }, bedG);
    await pg.evaluate(() => window.VCS.Game.debugSleep());
    await pg.evaluate(() => window.VCS.Game.debugAdvance(2.4));
    await pg.evaluate(() => window.VCS.Game.debugPickBoon(0));
    const n2 = await dsG();
    check('v0.9.1: night 2 unlock card carries the Mist how-text', n2.night.n === 2 && /Night 2/.test(n2.card || '') && /silent dash/i.test(n2.cardSub || ''), JSON.stringify({ c: n2.card, s: n2.cardSub }));
    await pg.evaluate(() => window.VCS.Game.debugAdvance(2.6));
    check('v0.9.1: first unlock shows the Esc hint after the card', (await dsG()).hint === true && await pg.evaluate(() => (JSON.parse(localStorage.getItem('vcs.seen')) || []).indexOf('mist') !== -1));
    check('v0.9.1: no page errors', errsG.length === 0, errsG.join(' | '));
    check('v0.9.1: no CSP violations', cspG.length === 0, cspG.join(' | '));
    console.log('screenshot: tests/shots/guide.png');
    await pg.close();
  }
  } catch (e) { secFail("v0.9.1 night length", e); }
  await closeLeaked([page, pg7, p8]);
  try {
  // ---- v0.10 wave B: saves, flags, audio, rules, tutorial, guide ----
  {
    const urlB = INDEX_URL;
    const errsB = [];
    const VP = { viewport: { width: 1000, height: 600 } };
    const wire = (pg) => pg.on('pageerror', (e) => errsB.push(String(e && e.message ? e.message : e)));
    const bootB = async (pg, q) => {
      wire(pg);
      await pg.goto(urlB + (q || '?seed=7&debug=1'));
      await pg.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
    };
    const startB = async (pg) => { await clickNew(pg); await sleep(350); };
    const dsB = (pg) => pg.evaluate(() => window.VCS.Game.debugState());
    const warnCount = (pg, re) => pg.evaluate((src) => VCS.Log.entries().filter((e) => new RegExp(src).test(e.message || e.msg || JSON.stringify(e))).length, re);

    // 1) validateRun gate, 2) storage failure dot + re-armed notice.
    {
      const pg = await newPg(browser, VP);
      await bootB(pg);
      await startB(pg);
      await pg.evaluate(() => { localStorage.setItem('vcs.run', 'SENTINEL'); VCS.__vr = VCS.Save.validateRun; VCS.Save.validateRun = () => ({ ok: false, code: 'E_TEST' }); });
      await escP(pg);
      const kept = await pg.evaluate(() => localStorage.getItem('vcs.run'));
      check('v0.10: invalid snapshot skips the autosave write', kept === 'SENTINEL' && (await dsB(pg)).state === 'paused', String(kept).slice(0, 40));
      check('v0.10: skipped autosave logs a warning', (await warnCount(pg, 'autosave skipped')) >= 1);
      await pg.evaluate(() => { VCS.Save.validateRun = VCS.__vr; });
      await pg.click('#btn-resume');
      await sleep(200);
      await escP(pg);
      check('v0.10: valid snapshot saves again', await pg.evaluate(() => { const r = localStorage.getItem('vcs.run'); return !!r && r !== 'SENTINEL' && JSON.parse(r).app === 'vcs'; }));
      // Storage failure: dot, one notice, re-armed after a success.
      await pg.click('#btn-resume');
      await sleep(200);
      await pg.evaluate(() => { const o = Storage.prototype.setItem; VCS.__si = o; Storage.prototype.setItem = function (k, v) { if (String(k).indexOf('vcs.run') === 0) throw new Error('quota'); return o.call(this, k, v); }; });
      const noticeN = () => pg.evaluate(() => Array.from(document.querySelectorAll('#notice-list li')).filter((li) => /Could not save/.test(li.textContent)).length);
      await escP(pg);
      const f1 = await dsB(pg);
      check('v0.10: failed write sets the not-saved flag and one notice', f1.saving.failed === true && (await noticeN()) === 1, JSON.stringify({ s: f1.saving, n: await noticeN() }));
      await pg.evaluate(() => { document.getElementById('btn-notice-ok').click(); });
      await pg.click('#btn-resume');
      await sleep(200);
      await escP(pg);
      check('v0.10: repeated failure does not repeat the notice', (await noticeN()) === 0, 'n=' + (await noticeN()));
      await pg.evaluate(() => { Storage.prototype.setItem = VCS.__si; });
      await pg.click('#btn-resume');
      await sleep(200);
      await escP(pg);
      check('v0.10: a later success clears the flag', (await dsB(pg)).saving.failed === false);
      await pg.click('#btn-resume');
      await sleep(200);
      await pg.evaluate(() => { const o = Storage.prototype.setItem; VCS.__si = o; Storage.prototype.setItem = function (k, v) { if (String(k).indexOf('vcs.run') === 0) throw new Error('quota'); return o.call(this, k, v); }; });
      await escP(pg);
      check('v0.10: the failure notice is re-armed after a success', (await noticeN()) === 1, 'n=' + (await noticeN()));
      await pg.close();
    }

    // 3) failed Continue keeps the .bak.
    {
      const pg = await newPg(browser, VP);
      await bootB(pg);
      await startB(pg);
      const badSnap = await pg.evaluate(() => { const snap = VCS.Game.getSnapshot(); snap.map = 'nowhere'; return snap; });
      await pg.goto(urlB + '?seed=7&debug=1'); // the old page saves on pagehide, so write the bad run after the reload
      await pg.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
      await pg.evaluate((snap) => {
        const st = VCS.Save.create(localStorage);
        st.write('run', VCS.Save.RUN_SCHEMA, snap);
        st.write('run', VCS.Save.RUN_SCHEMA, snap);
        VCS.Game.debugMenu('continue');
      }, badSnap);
      await sleep(250);
      const kb = await pg.evaluate(() => ({ main: localStorage.getItem('vcs.run'), bak: localStorage.getItem('vcs.run.bak') !== null, notice: document.getElementById('notice-list').textContent }));
      check('v0.10: failed Continue keeps the .bak (menu refresh may re-promote it)', kb.bak === true && /could not be loaded/.test(kb.notice), JSON.stringify({ m: kb.main && kb.main.slice(0, 20), b: kb.bak, n: kb.notice.slice(0, 60) }));
      await pg.close();
    }

    // 4) two tabs in the same context.
    {
      const a = await newPg(browser, VP);
      await bootB(a);
      await startB(a);
      const b = await a.context().newPage();
      await bootB(b);
      const rawA = await a.evaluate(() => localStorage.getItem('vcs.run'));
      const sb = await dsB(b);
      const sa = await dsB(a);
      check('v0.10: second tab sees the other tab and pauses saving', sb.saving.otherTab === true && sa.saving.otherTab === false, JSON.stringify({ a: sa.saving, b: sb.saving }));
      check('v0.10: second tab shows the notice', await b.evaluate(() => /open in another tab/.test(document.getElementById('notice-list').textContent) && !document.getElementById('notice').hidden));
      await b.evaluate(() => { document.getElementById('btn-notice-ok').click(); });
      await clickNew(b);
      await sleep(300);
      await escP(b);
      const rawB = await b.evaluate(() => localStorage.getItem('vcs.run'));
      check('v0.10: second tab does not overwrite the run save', rawA === rawB && rawA !== null);
      await b.close();
      await a.close();
    }

    // 5) frame errors: 2 are survived, 3 in a row go fatal, and the run is saved first.
    {
      const pg = await newPg(browser, VP);
      await bootB(pg);
      await startB(pg);
      await pg.evaluate(() => { VCS.__pr = VCS.Sonar.prune; let n = 0; VCS.Sonar.prune = function () { if (n++ < 2) throw new Error('boom ' + n); return VCS.__pr.apply(this, arguments); }; });
      await sleep(500);
      check('v0.10: two frame errors do not stop the game', (await dsB(pg)).state === 'playing');
      await pg.evaluate(() => { localStorage.setItem('vcs.run', 'SENTINEL'); VCS.Sonar.prune = function () { throw new Error('always'); }; });
      await sleep(600);
      const fe = await pg.evaluate(() => ({ st: VCS.Game.debugState().state, code: document.getElementById('error-code').textContent, run: localStorage.getItem('vcs.run') }));
      check('v0.10: three frame errors in a row go fatal (E_LOOP)', fe.st === 'error' && fe.code === 'E_LOOP', JSON.stringify({ st: fe.st, c: fe.code }));
      check('v0.10: fatal saves the active run first', !!fe.run && fe.run !== 'SENTINEL' && JSON.parse(fe.run).app === 'vcs');
      await pg.close();
    }

    // 6) reduce motion / large text / ambience slider.
    {
      const pg = await newPg(browser, VP);
      await bootB(pg);
      await startB(pg);
      check('v0.10: motion is not reduced by default', (await dsB(pg)).reduced === false);
      await escP(pg);
      await pg.click('#btn-settings');
      await pg.check('#set-reduce');
      await pg.check('#set-large');
      await pg.evaluate(() => { const el = document.getElementById('set-ambience'); el.value = '0.25'; el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); });
      const fl = await pg.evaluate(() => ({ red: VCS.Game.debugState().reduced, large: document.body.classList.contains('large-text'), cfg: VCS.Config.load(), out: document.getElementById('out-ambience').textContent }));
      check('v0.10: Reduce motion and Large text apply and persist', fl.red === true && fl.large === true && fl.cfg.reduceMotion === true && fl.cfg.largeText === true, JSON.stringify({ r: fl.red, l: fl.large }));
      check('v0.10: Ambience slider saves ambienceGain', fl.cfg.ambienceGain === 0.25 && /25/.test(fl.out), JSON.stringify({ g: fl.cfg.ambienceGain, o: fl.out }));
      await pg.uncheck('#set-reduce');
      await pg.uncheck('#set-large');
      const fl2 = await pg.evaluate(() => ({ red: VCS.Game.debugState().reduced, large: document.body.classList.contains('large-text') }));
      check('v0.10: unchecking turns them off again', fl2.red === false && fl2.large === false);
      await pg.close();
    }

    // 7) ambience follows room kind; none on pause.
    {
      const pg = await newPg(browser, VP);
      await bootB(pg);
      await startB(pg);
      await sleep(300);
      const a1 = (await dsB(pg)).ambience;
      await pg.evaluate(() => { const G = VCS.Game; G.debugMap('town', null); G.debugTeleport(20.5, 19.5, 0); });
      await sleep(300);
      const a2 = (await dsB(pg)).ambience;
      await escP(pg);
      await waitF(pg, () => window.VCS.Game.debugState().ambience === 'none', null, 2000);
      const a3 = (await dsB(pg)).ambience;
      await pg.click('#btn-resume');
      await sleep(300);
      const a4 = (await dsB(pg)).ambience;
      check('v0.10: ambience is indoor in the crypt, outdoor in town, none paused, back on resume', a1 === 'indoor' && a2 === 'outdoor' && a3 === 'none' && a4 === 'outdoor', JSON.stringify([a1, a2, a3, a4]));
      await pg.close();
    }

    // 8) crypt rule from night 3, far spot bonus.
    {
      const pg = await newPg(browser, VP);
      await bootB(pg);
      await startB(pg);
      const bed = await pg.evaluate(() => { const rows = VCS.MapData.maps.crypt.rows; for (let y = 0; y < rows.length; y++) { const x = rows[y].indexOf('C'); if (x >= 0) return { x, y }; } return null; });
      const ok = await pg.evaluate((b) => window.VCS.Game.applySnapshot({
        v: 2, map: 'crypt', player: { x: b.x - 0.5, y: b.y + 0.5, angle: 0 }, doors: {}, people: {},
        night: { v: 1, night: 3, min: 100, blood: 60, status: 'night', reason: '', fired: { chime: false, washout: false, dawn: false }, fedCount: 0 }
      }), bed);
      const hot = await pg.evaluate(() => window.VCS.Game.debugSleep());
      const s1 = await dsB(pg);
      check('v0.10.2: night 3 crypt bed sleeps any time (hot rule removed)', ok === true && hot === true, JSON.stringify({ ok, hot }));
      await pg.evaluate(() => window.VCS.Game.debugAdvance(1));
      await pg.close();
    }
    {
      const pg = await newPg(browser, VP);
      await bootB(pg);
      await startB(pg);
      const fs0 = (await dsB(pg)).farSpot;
      const cs = await pg.evaluate(() => VCS.Game.debugRun().closedSafe);
      const sealedFar = fs0 && (cs[fs0.map] || []).some((c) => c[0] === fs0.cx && c[1] === fs0.cy);
      check('v0.10: a far open town safe spot is chosen at run start', !!fs0 && fs0.map === 'town' && fs0.d > 20 && !sealedFar, JSON.stringify({ fs0, sealedFar }));
      const e0 = (await pg.evaluate(() => VCS.Game.debugHunger())).essenceBonus;
      await pg.evaluate((f) => { const G = VCS.Game; G.debugMap('town', null); G.debugTeleport(f.cx + 0.5, f.cy + 0.5, 0); }, fs0);
      const slp = await pg.evaluate(() => VCS.Game.debugSleep());
      const s2 = await dsB(pg);
      const e1 = (await pg.evaluate(() => VCS.Game.debugHunger())).essenceBonus;
      check('v0.10: sleeping at the far spot gives +5 Essence and shows the card', slp === true && e1 - e0 === 5 && s2.card === '+5 Essence', JSON.stringify({ slp, e0, e1, c: s2.card }));
      await pg.evaluate(() => VCS.Game.debugAdvance(1));
      check('v0.10: the bonus survives a save (valid snapshot)', await pg.evaluate(() => VCS.Save.validateRun(VCS.Game.getSnapshot()).ok));
      await pg.close();
    }

    // 9) tutorial hints (first time only).
    {
      const pg = await newPg(browser, VP, true);
      await bootB(pg);
      await startB(pg);
      await pg.evaluate(() => VCS.Game.debugBlood(80)); // runs start at 10%, which would show the vial hint first
      await pg.evaluate(() => VCS.Game.debugAdvance(2.8));
      const t1 = (await dsB(pg)).tutHint;
      check('v0.10: first hint asks the player to listen', t1 === 'Click or Space to listen', String(t1));
      await pg.evaluate(() => VCS.Game.debugPulse());
      const t2 = (await dsB(pg)).tutHint;
      check('v0.10: the first pulse retires the hint', t2 !== 'Click or Space to listen' && await pg.evaluate(() => JSON.parse(localStorage.getItem('vcs.seen')).indexOf('tut:ping') >= 0), String(t2));
      await pg.evaluate(() => { VCS.Game.debugBlood(40); VCS.Game.debugAdvance(0.2); });
      check('v0.10: vial hint the first time blood is under 50', (await dsB(pg)).tutHint === 'Vial = blood. Drink past full for gifts', String((await dsB(pg)).tutHint));
      await pg.evaluate(() => VCS.Game.debugAdvance(5.5));
      await pg.evaluate(() => { VCS.Game.debugTime(4, 30); VCS.Game.debugAdvance(0.2); });
      check('v0.10: sleep hint at 04:30 on night 1', (await dsB(pg)).tutHint === 'E at the crypt or a dark spot to sleep', JSON.stringify(await pg.evaluate(() => [VCS.Game.debugState().tutHint, VCS.Game.debugState().night.clock])));
      await settleReload(pg);
      await pg.waitForFunction(() => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, { timeout: 20000 });
      await startB(pg);
      await pg.evaluate(() => VCS.Game.debugAdvance(2.8));
      check('v0.10: hints do not repeat after a reload', (await dsB(pg)).tutHint === null);
      await pg.close();
    }

    // 10) guide: Basics first, scrollTop 0, focus Back, arrows.
    {
      const pg = await newPg(browser, VP);
      await bootB(pg);
      await pg.click('#btn-guide');
      await sleep(200);
      const g1 = await pg.evaluate(() => ({ first: document.querySelector('#guide-body h3').textContent, txt: document.getElementById('guide-body').textContent, focus: document.activeElement.id }));
      check('v0.10: guide starts with Basics (arrows, R, C) and the far spot', g1.first === 'Basics' && /arrow/i.test(g1.txt) && /\bR\b/.test(g1.txt) && /\bC\b/.test(g1.txt) && !/too hot/.test(g1.txt) && /\+5 Essence/.test(g1.txt), g1.first);
      check('v0.10: guide focuses Back', g1.focus === 'btn-guide-back', g1.focus);
      await pg.evaluate(() => { document.getElementById('guide').scrollTop = 400; document.getElementById('guide-body').scrollTop = 400; });
      await pg.click('#btn-guide-back');
      await pg.click('#btn-guide');
      await sleep(150);
      const g2 = await pg.evaluate(() => ({ a: document.getElementById('guide').scrollTop, b: document.getElementById('guide-body').scrollTop, f: document.activeElement.id }));
      check('v0.10: guide reopens scrolled to the top', g2.a === 0 && g2.b === 0 && g2.f === 'btn-guide-back', JSON.stringify(g2));
      await pg.click('#btn-guide-back');
      await pg.click('#btn-shop');
      await pg.evaluate(() => { document.getElementById('shop').scrollTop = 300; });
      await pg.click('#btn-shop-back');
      await pg.click('#btn-shop');
      check('v0.10: shop reopens scrolled to the top with Back focused', await pg.evaluate(() => document.getElementById('shop').scrollTop === 0 && document.activeElement.id === 'btn-shop-back'));
      await pg.click('#btn-shop-back');
      await pg.focus('#btn-menu-new');
      const f1 = await focusAfter(pg, 'ArrowDown', 'btn-stats');
      const f2 = await focusAfter(pg, 'ArrowLeft', 'btn-shop');
      await focusAfter(pg, 'ArrowRight', 'btn-stats');
      const f3 = await focusAfter(pg, 'ArrowUp', 'btn-menu-new');
      check('v0.10: arrow keys move focus in the menu grid', f1 === 'btn-stats' && f2 === 'btn-shop' && f3 === 'btn-menu-new', JSON.stringify([f1, f2, f3]));
      await pg.click('#btn-menu-new');
      await waitF(pg, () => window.VCS.Game.debugState().state === 'playing', null, 3000);
      await escP(pg);
      await waitF(pg, () => document.activeElement && document.activeElement.id === 'btn-resume', null, 1000);
      await pg.focus('#btn-resume');
      const p1 = await focusAfter(pg, 'ArrowDown', 'btn-abilities');
      const p2 = await focusAfter(pg, 'ArrowUp', 'btn-resume');
      check('v0.10: arrow keys move focus in the pause list', p1 === 'btn-abilities' && p2 === 'btn-resume', JSON.stringify([p1, p2]));
      await pg.close();
    }
    check('v0.10: no page errors (wave B)', errsB.length === 0, errsB.join(' | '));
  }
  } catch (e) { secFail("v0.10 wave B", e); }
  await closeLeaked([page, pg7, p8]);
  try {
  // ---------------- dev panel (modular step 1) ----------------
  {
    const pd = await newPg(browser, { viewport: { width: 1000, height: 600 } });
    const errsD = [];
    pd.on('pageerror', (e) => errsD.push(String(e && e.message ? e.message : e)));
    await pd.goto(INDEX_URL + '?seed=7&debug=1');
    await waitF(pd, () => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, 5000);
    const hid0 = await pd.evaluate(() => document.getElementById('devpanel').hidden);
    await pd.keyboard.press('F9');
    const shown = await waitF(pd, () => !document.getElementById('devpanel').hidden, null, 1500);
    await pd.click('#devpanel input[type=checkbox]');
    const flagOn = await pd.evaluate(() => window.VCS.Flags.get('dev.showFps'));
    await pd.keyboard.press('F9');
    const hid1 = await pd.evaluate(() => document.getElementById('devpanel').hidden);
    await pd.evaluate(() => window.VCS.Flags.resetAll());
    check('dev panel: hidden by default, F9 shows it, flag toggles, F9 hides', hid0 && shown && flagOn && hid1, JSON.stringify([hid0, shown, flagOn, hid1]));
    check('dev panel: no page errors', errsD.length === 0, errsD.join(' | '));
    await pd.close();
    const pn = await newPg(browser, { viewport: { width: 1000, height: 600 } });
    await pn.goto(INDEX_URL + '?seed=7');
    await waitF(pn, () => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, 5000);
    const errsN = [];
    pn.on('pageerror', (e) => errsN.push(String(e)));
    check('dev panel: closed without ?debug=1 and F9 does nothing', await pn.evaluate(() => document.getElementById('devpanel').hidden) && (await pn.keyboard.press('F9'), await pn.evaluate(() => document.getElementById('devpanel').hidden)));
    const vis = await pn.evaluate(() => getComputedStyle(document.getElementById('btn-devtool')).display !== 'none');
    await pn.click('#btn-devtool');
    const opened = await waitF(pn, () => !document.getElementById('devpanel').hidden, null, 1500);
    await pn.click('#devpanel .dp-bar button');
    await frames(pn, 3);
    await pn.keyboard.press('Escape');
    const closed = await pn.evaluate(() => document.getElementById('devpanel').hidden);
    const stillTitle = (await pn.evaluate(() => window.VCS.Game.debugState().state)) === 'title';
    check('devtool: button visible in menu, opens panel, Esc closes back to menu', vis && opened && closed && stillTitle, JSON.stringify([vis, opened, closed, stillTitle]));
    await pn.click('#btn-devtool');
    await pn.click('#devpanel .dp-bar button');
    await frames(pn, 3);
    check('devtool: copy error report works without page errors', errsN.length === 0, errsN.join(' | '));
    await pn.close();
  }
  } catch (e) { secFail("dev panel", e); }
  await closeLeaked([page, pg7, p8]);
  try {
  // ---------------- circulatory vessels (?sys=vis.vessels:on) ----------------
  {
    const pv = await newPg(browser, { viewport: { width: 640, height: 360 } });
    const errsV = [];
    pv.on('pageerror', (e) => errsV.push(String(e && e.message ? e.message : e)));
    await pv.goto(INDEX_URL + '?seed=7&debug=1&sys=vis.vessels:on');
    await waitF(pv, () => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, 5000);
    await clickNew(pv);
    await waitF(pv, () => window.VCS.Game.debugState().state === 'playing', null, 3000);
    // Pin one calm villager in a dark open spot with the player 1.3 cells away facing it, then sample every frame for 3 s.
    const vr = await pv.evaluate(() => new Promise((res) => {
      const G = window.VCS.Game;
      G.debugMap('town', null);
      const ps = G.debugPeopleState();
      const w = ps.world;
      const v = ps.people[0];
      let at = null;
      for (let y = 2; y < w.height - 2 && !at; y++) for (let x = 2; x < w.width - 3 && !at; x++) {
        const cx = x + 0.5, cy = y + 0.5;
        if (w.blocks(cx, cy, 0.3) || w.blocks(cx - 1.3, cy, 0.3) || w.blocks(cx - 0.65, cy, 0.3)) continue;
        if (w.lightAt(cx, cy) > 0.02 || w.lightAt(cx - 1.3, cy) > 0.02) continue;
        if (ps.people.some((o) => o !== v && Math.hypot(o.x - cx, o.y - cy) < 4)) continue;
        at = [cx, cy];
      }
      if (!at) { res({ none: true }); return; }
      const out = { on: window.VCS.Flags.get('vis.vessels'), frames: [], beats: {}, fps: 0 };
      // The 3 s window starts at the villager's first heartbeat echo (beats start 0.2-0.8 s after it is in range).
      const tStart = performance.now();
      let t0 = -1;
      const tick = () => {
        v.x = at[0]; v.y = at[1]; v.angle = Math.PI; v.wary = 0; v.left = v.pool;
        if (v.mode === 'flee' || v.mode === 'startle' || v.mode === 'cower') v.mode = 'path';
        G.debugTeleport(at[0] - 1.3, at[1], 0);
        if (t0 < 0) {
          if (G.debugEchoes().some((e) => e.kind === 'vheart' && e.personId === v.id) || performance.now() - tStart > 4000) t0 = performance.now() - 50;
          requestAnimationFrame(tick);
          return;
        }
        const st = G.debugVessels();
        out.frames.push([performance.now() - t0, st ? st.heart : 0, st ? st.feet : 0]);
        for (const e of G.debugEchoes()) if (e.kind === 'vheart' && e.personId === v.id) out.beats[e.t.toFixed(3)] = 1;
        if (performance.now() - t0 < 3000) requestAnimationFrame(tick);
        else {
          out.fps = G.debugState().fps;
          res(out);
        }
      };
      requestAnimationFrame(tick);
    }));
    // Lub onsets: the heart rises by > 0.3 within 150 ms (the lub attack is 0.06 s; the dub adds only ~0.15). After each
    // onset with a full 0.9 s window sampled, the brightest foot frame must come 0.15-0.9 s later (feet ~0.4 s after the chest).
    const fr = vr.frames || [];
    const lags = [];
    let onsets = 0;
    let lastOn = -1e9;
    for (let i = 1; i < fr.length; i++) {
      let lo = fr[i][1];
      for (let j = i - 1; j >= 0 && fr[j][0] >= fr[i][0] - 150; j--) if (fr[j][1] < lo) lo = fr[j][1];
      if (!(fr[i][1] - lo > 0.3) || fr[i][0] - lastOn < 400) continue;
      lastOn = fr[i][0];
      onsets++;
      if (fr[i][0] + 900 > fr[fr.length - 1][0]) continue;
      let best = i;
      for (let j = i; j < fr.length && fr[j][0] <= fr[i][0] + 900; j++) if (fr[j][2] > fr[best][2]) best = j;
      lags.push({ lag: +((fr[best][0] - fr[i][0]) / 1000).toFixed(3), feet: +fr[best][2].toFixed(3), atOnset: +fr[i][2].toFixed(3) });
    }
    const drawn = fr.filter((f) => f[1] > 0.02).length;
    const beats = Object.keys(vr.beats || {}).length;
    check('vessels: flag on from ?sys, villager heartbeat echoes drawn as vessels', vr.on === true && beats >= 2 && drawn > 10 && onsets >= 1, JSON.stringify({ on: vr.on, none: vr.none, beats, drawn, onsets, frames: fr.length }));
    check('vessels: the foot lights after the chest (brightest foot 0.15-0.9 s after each lub)', lags.length >= 1 && lags.every((l) => l.lag > 0.15 && l.lag < 0.9 && l.feet > l.atOnset), JSON.stringify(lags));
    check('vessels: fps sanity (>= 10 headless) and no page errors', vr.fps >= 10 && errsV.length === 0, JSON.stringify({ fps: vr.fps, errs: errsV }));
    await pv.close();
    // P7: on by default; ?sys=vis.vessels:off turns it off for the load.
    const dflt = [];
    for (const q of ['', '&sys=vis.vessels:off']) {
      const pq = await newPg(browser, { viewport: { width: 640, height: 360 } });
      await pq.goto(INDEX_URL + '?seed=7' + q);
      await waitF(pq, () => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, 5000);
      dflt.push(await pq.evaluate(() => window.VCS.Flags.get('vis.vessels')));
      await pq.close();
    }
    check('vessels: vis.vessels on by default, ?sys=vis.vessels:off turns it off', dflt[0] === true && dflt[1] === false, JSON.stringify(dflt));
  }
  } catch (e) { secFail("vessels", e); }
  try {
  // ---------------- W4: listening at a lit window ----------------
  {
    const pl = await newPg(browser, { viewport: { width: 640, height: 360 } });
    const errsL = [];
    pl.on('pageerror', (e) => errsL.push(String(e && e.message ? e.message : e)));
    pl.on('console', (m) => { if (m.type() === 'error') errsL.push(m.text()); });
    await pl.goto(INDEX_URL + '?seed=7&debug=1');
    await waitF(pl, () => window.VCS && window.VCS.Game && window.VCS.Game.debugState().state === 'title', null, 5000);
    await clickNew(pl);
    await waitF(pl, () => window.VCS.Game.debugState().state === 'playing', null, 3000);
    const spot = await pl.evaluate(() => {
      const G = window.VCS.Game;
      G.debugMap('town', null);
      const w = G.debugPeopleState().world;
      let best = null;
      for (let cy = 0; cy < w.height; cy++) for (let cx = 0; cx < w.width; cx++) {
        if (w.tileAt(cx, cy) !== 'w') continue;
        for (const [dx, dy] of [[0, -1], [0, 1], [-1, 0], [1, 0]]) {
          const px = cx + 0.5 + dx * 0.7, py = cy + 0.5 + dy * 0.7;
          if (w.kindAt(px, py) !== 'outdoor' || w.kindAt(cx + 0.5 - dx, cy + 0.5 - dy) !== 'indoor') continue;
          const lit = Math.max(w.lightAt(cx + 0.5, cy + 0.5), w.lightAt(cx + 0.5 - dx, cy + 0.5 - dy));
          if (!best || lit > best.lit) best = { px, py, ang: Math.atan2(-dy, -dx), lit };
        }
      }
      if (best) G.debugTeleport(best.px, best.py, best.ang);
      return best;
    });
    check('listen smoke: found a window to stand at', !!spot, JSON.stringify(spot));
    if (spot) {
      await pl.keyboard.down('KeyE');
      await waitF(pl, () => window.VCS.Game.debugState().listen && window.VCS.Game.debugState().listen.active, null, 4000).catch(() => {});
      await pl.waitForTimeout(3500);
      const ds = await pl.evaluate(() => { const d = window.VCS.Game.debugState(); return { listen: d.listen, voices: d.voices, errors: d.errors }; });
      await pl.keyboard.up('KeyE');
      check('listen smoke: holding E at the window starts listening', !!(ds.listen && ds.listen.active), JSON.stringify(ds.listen));
      check('listen smoke: headcount is a number (HUD "Voices inside")', !!(ds.listen && typeof ds.listen.count === 'number' && ds.listen.count >= 0), JSON.stringify(ds.listen));
      check('listen smoke: voice count <= 96', ds.voices <= 96, String(ds.voices));
      check('listen smoke: subtitle, when present, has a line (lit: ' + (spot.lit > 0.15) + ')', !ds.listen || !ds.listen.sub || (typeof ds.listen.sub.de === 'string' && ds.listen.sub.de.length > 0), JSON.stringify(ds.listen && ds.listen.sub));
      await pl.waitForTimeout(300);
      const off = await pl.evaluate(() => { const d = window.VCS.Game.debugState(); return d.listen && d.listen.active; });
      check('listen smoke: releasing E stops listening', !off, String(off));
    }
    check('listen smoke: no console or page errors', errsL.length === 0, JSON.stringify(errsL));
    await pl.close();
  }
  } catch (e) { secFail("listen", e); }
  await closeLeaked([page, pg7, p8]);
} catch (e) {
  check('smoke run completed', false, e && e.stack ? e.stack : String(e));
} finally {
  await browser.close();
}

if (failures.length) {
  console.log('SMOKE FAILED (' + failures.length + ')');
  process.exit(1);
}
console.log('SMOKE PASSED');
if (httpServer) httpServer.close();
process.exit(0);
