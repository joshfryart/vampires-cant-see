#!/usr/bin/env node
// Tiny static server for the JS reference page, plus POST /save?name=X to store a PNG under out/jsref/.
// Usage: node tools/ref-server.mjs [port]     (serves the repo root; the page is /___VERSION__GODOT___VERSION___/tools/js-ref.html)
// The JS game is only read, never modified.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PORT_DIR = path.resolve(HERE, '..');
const ROOT = path.resolve(PORT_DIR, '..');
const OUT = path.join(PORT_DIR, 'out', 'jsref');
const PORT = Number(process.argv[2]) || 8766;
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png' };

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (req.method === 'POST' && url.pathname === '/save') {
    const name = (url.searchParams.get('name') || 'shot').replace(/[^A-Za-z0-9_.-]/g, '_');
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      const b64 = body.replace(/^data:image\/png;base64,/, '');
      fs.mkdirSync(OUT, { recursive: true });
      fs.writeFileSync(path.join(OUT, name + '.png'), Buffer.from(b64, 'base64'));
      res.writeHead(200, { 'access-control-allow-origin': '*' });
      res.end('saved ' + name);
    });
    return;
  }
  let p = decodeURIComponent(url.pathname);
  if (p.endsWith('/')) p += 'index.html';
  const file = path.normalize(path.join(ROOT, p));
  if (!file.startsWith(ROOT)) { res.writeHead(403); res.end('no'); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
}).listen(PORT, () => console.log('ref server on http://localhost:' + PORT));
