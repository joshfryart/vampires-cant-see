(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  const TWO_PI = Math.PI * 2;
  const DEFAULT_CFG = { mouseSensitivity: 0.0025, invertMouse: false, moveSpeed: 3.0, turnSpeedKeys: 2.4, keyTurnSpeed: 3.2 };

  function num(v, d) {
    return typeof v === 'number' && isFinite(v) ? v : d;
  }

  function normAngle(a) {
    let r = a % TWO_PI;
    if (r < 0) r += TWO_PI;
    if (r >= TWO_PI || !isFinite(r)) r = 0;
    return r;
  }

  /** Create a player at start (x,y) facing angle radians. */
  function create(start, angle) {
    return { x: start.x, y: start.y, angle: normAngle(num(angle, 0)), radius: 0.2 };
  }

  function blocked(world, x, y, r) {
    if (typeof world.blocks === 'function') return world.blocks(x, y, r);
    return world.isSolid(x - r, y - r) || world.isSolid(x + r, y - r) ||
      world.isSolid(x - r, y + r) || world.isSolid(x + r, y + r);
  }

  /** Advance the player by dt seconds given input; mutates and returns p. */
  function update(p, world, input, dt, config) {
    const cfg = config || DEFAULT_CFG;
    const inp = input || {};
    let d = num(dt, 0);
    if (d < 0) d = 0;
    if (d > 0.1) d = 0.1;

    const sens = num(cfg.mouseSensitivity, DEFAULT_CFG.mouseSensitivity);
    const speed = num(cfg.moveSpeed, DEFAULT_CFG.moveSpeed);
    const turnSpeed = num(cfg.keyTurnSpeed, num(cfg.turnSpeedKeys, DEFAULT_CFG.keyTurnSpeed));
    const inv = cfg.invertMouse ? -1 : 1;

    p.angle = normAngle(p.angle + num(inp.mouseDx, 0) * sens * inv + num(inp.turn, 0) * turnSpeed * d);

    const f = num(inp.forward, 0);
    const s = num(inp.strafe, 0);
    let mx = f * Math.cos(p.angle) + s * Math.cos(p.angle + Math.PI / 2);
    let my = f * Math.sin(p.angle) + s * Math.sin(p.angle + Math.PI / 2);
    const len = Math.sqrt(mx * mx + my * my);
    if (len > 0 && d > 0) {
      mx = (mx / len) * speed * d;
      my = (my / len) * speed * d;
      const nx = p.x + mx;
      if (!blocked(world, nx, p.y, p.radius)) p.x = nx;
      const ny = p.y + my;
      if (!blocked(world, p.x, ny, p.radius)) p.y = ny;
    }
    return p;
  }

  /** Teleport p to (x,y) facing angle (normalised); non-finite inputs are ignored. Returns p. */
  function place(p, x, y, angle) {
    if (!p) return p;
    if (typeof x === 'number' && isFinite(x)) p.x = x;
    if (typeof y === 'number' && isFinite(y)) p.y = y;
    if (typeof angle === 'number' && isFinite(angle)) p.angle = normAngle(angle);
    return p;
  }

  /** Map a set of key codes plus mouse delta to a plain input object. */
  function inputFromKeys(keySet, mouseDx) {
    const has = function (c) { return !!(keySet && typeof keySet.has === 'function' && keySet.has(c)); };
    return {
      forward: (has('KeyW') || has('ArrowUp') ? 1 : 0) - (has('KeyS') || has('ArrowDown') ? 1 : 0),
      strafe: (has('KeyD') ? 1 : 0) - (has('KeyA') ? 1 : 0),
      turn: (has('ArrowRight') ? 1 : 0) - (has('ArrowLeft') ? 1 : 0),
      mouseDx: num(mouseDx, 0)
    };
  }

  const Player = { create: create, update: update, inputFromKeys: inputFromKeys, place: place };
  VCS.Player = Player;
  if (typeof module !== 'undefined' && module.exports) module.exports = Player;
})(typeof window !== 'undefined' ? window : globalThis);
