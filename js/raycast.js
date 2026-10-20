(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const TWO_PI = Math.PI * 2;

  /** Core DDA; writes result into out. Returns out. */
  function trace(world, x, y, rayAngle, maxDist, out) {
    const dx = Math.cos(rayAngle);
    const dy = Math.sin(rayAngle);
    let cx = Math.floor(x);
    let cy = Math.floor(y);
    out.rayAngle = rayAngle;
    if (world.isSolid(cx, cy)) {
      out.hit = true; out.dist = 0; out.rayDist = 0; out.cellX = cx; out.cellY = cy;
      out.side = 0; out.hitX = x; out.hitY = y; out.wallX = 0; out.nx = -dx; out.ny = -dy;
      return out;
    }
    const ddx = dx === 0 ? Infinity : Math.abs(1 / dx);
    const ddy = dy === 0 ? Infinity : Math.abs(1 / dy);
    const stepX = dx < 0 ? -1 : 1;
    const stepY = dy < 0 ? -1 : 1;
    let sdx = dx === 0 ? Infinity : (dx < 0 ? (x - cx) : (cx + 1 - x)) * ddx;
    let sdy = dy === 0 ? Infinity : (dy < 0 ? (y - cy) : (cy + 1 - y)) * ddy;
    const cap = 4 * ((world.width || 64) + (world.height || 64));
    let side = 0;
    for (let i = 0; i < cap; i++) {
      let d;
      if (sdx < sdy) { d = sdx; sdx += ddx; cx += stepX; side = 0; }
      else { d = sdy; sdy += ddy; cy += stepY; side = 1; }
      if (d > maxDist) break;
      if (world.isSolid(cx, cy)) {
        const hx = x + dx * d;
        const hy = y + dy * d;
        out.hit = true; out.dist = d; out.rayDist = d; out.cellX = cx; out.cellY = cy;
        out.side = side; out.hitX = hx; out.hitY = hy;
        out.wallX = side === 0 ? hy - Math.floor(hy) : hx - Math.floor(hx);
        // Surface normal facing the ray origin (the cell face that was crossed).
        if (side === 0) { out.nx = dx > 0 ? -1 : 1; out.ny = 0; } else { out.nx = 0; out.ny = dy > 0 ? -1 : 1; }
        return out;
      }
    }
    out.hit = false; out.nx = 0; out.ny = 0; out.dist = maxDist; out.rayDist = maxDist;
    out.hitX = x + dx * maxDist; out.hitY = y + dy * maxDist;
    return out;
  }

  function blank() {
    return { hit: false, dist: 0, rayDist: 0, rayAngle: 0, cellX: 0, cellY: 0, side: 0, hitX: 0, hitY: 0, wallX: 0, nx: 0, ny: 0, mat: 'stone' };
  }

  const scratch = blank();

  /**
   * Cast one ray into out (reusable, see blank()) and fill out.mat with the hit surface material (world.materialAt) and out.nx/ny with
   * the surface normal (v0.11). No allocation. Returns out.
   */
  function hitOne(world, x, y, rayAngle, maxDist, out) {
    trace(world, x, y, rayAngle, maxDist, out);
    out.mat = 'stone';
    if (out.hit && typeof world.materialAt === 'function') out.mat = world.materialAt(out.cellX, out.cellY) || 'stone';
    return out;
  }

  /** Cast one ray; returns a hit object (dist === rayDist). */
  function castOne(world, x, y, rayAngle, maxDist) {
    return trace(world, x, y, rayAngle, maxDist, blank());
  }

  /** Distance-only helper for visibility profiles (no allocation). */
  function distOne(world, x, y, rayAngle, maxDist) {
    return trace(world, x, y, rayAngle, maxDist, scratch).rayDist;
  }

  /** Cast one ray per screen column; returns array of hit objects. */
  function cast(world, x, y, angle, fov, columns, maxDist) {
    const res = new Array(columns);
    const tanHalf = Math.tan(fov / 2);
    for (let i = 0; i < columns; i++) {
      const off = Math.atan((2 * (i + 0.5) / columns - 1) * tanHalf);
      const h = trace(world, x, y, angle + off, maxDist, blank());
      if (h.hit) h.dist = h.rayDist * Math.cos(off);
      res[i] = h;
    }
    return res;
  }

  const Raycast = { cast: cast, castOne: castOne, distOne: distOne, hitOne: hitOne, blank: blank, TWO_PI: TWO_PI };
  VCS.Raycast = Raycast;
  if (typeof module !== 'undefined' && module.exports) module.exports = Raycast;
})(typeof window !== 'undefined' ? window : globalThis);
