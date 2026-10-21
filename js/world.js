(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Enumerable TILES keeps the v0.5 shape (tests compare it); v0.6 chars are non-enumerable extras.
  const TILES = { WALL: '#', FLOOR: '.', START: '@', DOOR: 'D', CRYPT: 'C', SAFE: 'S', PERSON: 'P' };
  const EXTRA_TILES = { BRICK: 'B', WOODWALL: 'W', IRON: 'I', WINDOW: 'w', WOODFLOOR: ',', GRASS: 'g', GATE: 'G' };
  Object.keys(EXTRA_TILES).forEach(function (k) {
    Object.defineProperty(TILES, k, { value: EXTRA_TILES[k], enumerable: false });
  });

  const WALLS = '#BWIw';
  const FLOORS = '.,g';
  const DOORS = 'DG';
  const MARKERS = '@CSP';
  const VALID = WALLS + FLOORS + DOORS + MARKERS;
  const MATERIAL = {
    '#': 'stone', B: 'brick', W: 'wood', I: 'iron', w: 'glass',
    '.': 'stone', ',': 'wood', g: 'grass', D: 'wood', G: 'iron'
  };
  const FLOOR_MATS = ['stone', 'wood', 'grass', 'cobble', 'roughStone'];
  // Every surface material the acoustics know (walls, floors, doors); see SoundData.acoustics.mat.
  const MATERIALS = ['stone', 'brick', 'roughStone', 'cobble', 'wood', 'glass', 'iron', 'grass'];
  const PROP_TYPES = ['gravestone', 'cross', 'barrel', 'table', 'chair', 'bench', 'well', 'torch', 'brazier'];
  const NON_SOLID = { cross: true, torch: true };
  const DEFAULT_LIGHT = { torch: 3, brazier: 3.5 };
  const LIGHT_SCALE = 0.39; // v0.10.14: light radius x0.39 (0.6 in v0.10.9; -35%)
  const PROP_R = 0.3;
  const MAX_W = 64;
  const MAX_H = 48;
  const FACING = { n: [0, -1, -Math.PI / 2], s: [0, 1, Math.PI / 2], e: [1, 0, 0], w: [-1, 0, Math.PI] };

  function logger() {
    try {
      return root.VCS && root.VCS.Log ? root.VCS.Log.get('world') : null;
    } catch (e) {
      return null;
    }
  }

  function isInt(n) { return typeof n === 'number' && isFinite(n) && Math.floor(n) === n; }
  function isWallCh(ch) { return WALLS.indexOf(ch) >= 0; }
  function isFloorCh(ch) { return FLOORS.indexOf(ch) >= 0 || MARKERS.indexOf(ch) >= 0; }
  function isDoorCh(ch) { return ch === 'D' || ch === 'G'; }
  function chAt(rows, c, r) {
    return r >= 0 && r < rows.length && c >= 0 && c < rows[r].length ? rows[r][c] : '#';
  }

  /** Validate a map definition; never throws. Returns {ok, errors}. opts.requireStart defaults to true. */
  function validate(mapDef, allMapNames, links, opts) {
    const errors = [];
    let name = 'unknown';
    try {
      name = mapDef && mapDef.name !== undefined ? String(mapDef.name) : 'unknown';
      const names = Array.isArray(allMapNames) ? allMapNames : [name];
      const lks = Array.isArray(links) ? links : [];
      const requireStart = !(opts && opts.requireStart === false);
      const rows = mapDef && Array.isArray(mapDef.rows) ? mapDef.rows : [];
      const where = function (r, c) { return 'map ' + name + ' row ' + r + ' col ' + c; };
      const add = function (code, message, extra) {
        const e = { code: code, message: message, map: name };
        if (extra) for (const k in extra) e[k] = extra[k];
        errors.push(e);
      };
      let rect = false;

      if (rows.length === 0) {
        add('E_MAP_EMPTY', 'map ' + name + ' has no rows');
      } else {
        const w = typeof rows[0] === 'string' ? rows[0].length : -1;
        rect = true;
        for (let r = 0; r < rows.length; r++) {
          if (typeof rows[r] !== 'string' || rows[r].length !== w || w === 0) {
            rect = false;
            add('E_MAP_NOT_RECT', 'map ' + name + ' row ' + r + ' has wrong width', { row: r });
          }
        }
        if (w === 0 && rect) {
          rect = false;
          add('E_MAP_EMPTY', 'map ' + name + ' has empty rows');
        }
        if (rect && (w > MAX_W || rows.length > MAX_H)) {
          add('E_MAP_TOO_BIG', 'map ' + name + ' is ' + w + 'x' + rows.length + ' (max ' + MAX_W + 'x' + MAX_H + ')');
        }
        let starts = 0;
        for (let r = 0; r < rows.length; r++) {
          const row = rows[r];
          if (typeof row !== 'string') continue;
          for (let c = 0; c < row.length; c++) {
            const ch = row[c];
            if (VALID.indexOf(ch) < 0) {
              add('E_MAP_BAD_TILE', where(r, c) + ' has invalid tile ' + JSON.stringify(ch), { row: r, col: c, char: ch });
              continue;
            }
            if (ch === TILES.START) starts++;
            const edge = r === 0 || r === rows.length - 1 || c === 0 || c === row.length - 1;
            if (edge && !isWallCh(ch)) {
              add('E_MAP_OPEN_EDGE', where(r, c) + ' is a non-wall on the border', { row: r, col: c });
            }
          }
        }
        if (requireStart) {
          if (starts === 0) {
            add('E_MAP_NO_START', 'map ' + name + ' has no start tile @');
          } else if (starts > 1) {
            add('E_MAP_MULTI_START', 'map ' + name + ' has ' + starts + ' start tiles @');
          }
        } else if (starts > 1) {
          add('E_MAP_MULTI_START', 'map ' + name + ' has ' + starts + ' start tiles @');
        }
      }

      if (rect && mapDef.zones !== undefined) {
        const zs = mapDef.zones;
        const zw = rows[0].length;
        const zh = rows.length;
        if (!Array.isArray(zs)) {
          add('E_MAP_BAD_ZONE', 'map ' + name + ' zones must be an array');
        } else {
          const names = {};
          for (let i = 0; i < zs.length; i++) {
            const z = zs[i];
            const tag = 'map ' + name + ' zone ' + i;
            if (!z || typeof z !== 'object') { add('E_MAP_BAD_ZONE', tag + ' is not an object'); continue; }
            if (typeof z.name !== 'string' || !z.name) { add('E_MAP_BAD_ZONE', tag + ' has no name'); continue; }
            if (names[z.name]) add('E_MAP_BAD_ZONE', tag + ' duplicates name ' + z.name);
            names[z.name] = true;
            if (z.kind !== 'indoor' && z.kind !== 'outdoor') { add('E_MAP_BAD_ZONE', tag + ' (' + z.name + ') has bad kind ' + JSON.stringify(z.kind)); continue; }
            if (!isInt(z.x0) || !isInt(z.y0) || !isInt(z.x1) || !isInt(z.y1) ||
                z.x0 < 0 || z.y0 < 0 || z.x1 >= zw || z.y1 >= zh || z.x0 > z.x1 || z.y0 > z.y1) {
              add('E_MAP_BAD_ZONE', tag + ' (' + z.name + ') rect is out of bounds or inverted');
            }
          }
        }
      }

      if (rect) {
        // Props first (doors and paths consult the solid ones).
        const solidCells = new Set();
        const propCells = new Set();
        const props = mapDef.props;
        if (props !== undefined && !Array.isArray(props)) {
          add('E_MAP_BAD_PROP', 'map ' + name + ' props must be an array');
        } else if (Array.isArray(props)) {
          const solids = [];
          for (let i = 0; i < props.length; i++) {
            const p = props[i];
            const tag = 'map ' + name + ' prop ' + i;
            if (!p || typeof p !== 'object') { add('E_MAP_BAD_PROP', tag + ' is not an object'); continue; }
            if (PROP_TYPES.indexOf(p.type) < 0) { add('E_MAP_BAD_PROP', tag + ' has unknown type ' + JSON.stringify(p.type)); continue; }
            if (!isInt(p.col) || !isInt(p.row) || p.col < 0 || p.row < 0 || p.col >= rows[0].length || p.row >= rows.length) {
              add('E_MAP_BAD_PROP', tag + ' (' + p.type + ') is out of bounds'); continue;
            }
            if (!isFloorCh(chAt(rows, p.col, p.row))) {
              add('E_MAP_BAD_PROP', tag + ' (' + p.type + ') at ' + p.col + ',' + p.row + ' is not on a floor cell'); continue;
            }
            if (p.light !== undefined && !(typeof p.light === 'number' && isFinite(p.light) && p.light >= 0)) {
              add('E_MAP_BAD_PROP', tag + ' (' + p.type + ') has bad light radius'); continue;
            }
            const key = p.row * 4096 + p.col;
            propCells.add(key);
            if (!NON_SOLID[p.type]) {
              if (solidCells.has(key)) add('E_MAP_BAD_PROP', tag + ' (' + p.type + ') shares cell ' + p.col + ',' + p.row + ' with another solid prop');
              solidCells.add(key);
              solids.push(p);
            }
          }
        }

        // Doors.
        const doors = mapDef.doors;
        if (doors !== undefined && !Array.isArray(doors)) {
          add('E_MAP_BAD_DOOR', 'map ' + name + ' doors must be an array');
        } else if (Array.isArray(doors)) {
          const ids = {};
          const cells = {};
          for (let i = 0; i < doors.length; i++) {
            const d = doors[i];
            const tag = 'map ' + name + ' door ' + (d && d.id !== undefined ? d.id : '#' + i);
            if (!d || typeof d !== 'object') { add('E_MAP_BAD_DOOR', tag + ' is not an object'); continue; }
            const did = typeof d.id === 'string' && d.id ? d.id : null;
            if (!did) { add('E_MAP_BAD_DOOR', tag + ' has no string id', { door: d.id }); continue; }
            if (ids[did]) add('E_MAP_BAD_DOOR', tag + ' has a duplicate id', { door: did });
            ids[did] = true;
            if (!isInt(d.col) || !isInt(d.row) || d.col < 0 || d.row < 0 || d.col >= rows[0].length || d.row >= rows.length) {
              add('E_MAP_BAD_DOOR', tag + ' is out of bounds', { door: did }); continue;
            }
            if (!isDoorCh(chAt(rows, d.col, d.row))) {
              add('E_MAP_BAD_DOOR', tag + ' at ' + d.col + ',' + d.row + ' is not on a D or G cell', { door: did }); continue;
            }
            const ck = d.row * 4096 + d.col;
            if (cells[ck]) add('E_MAP_BAD_DOOR', tag + ' shares its cell with door ' + cells[ck], { door: did });
            cells[ck] = did;
            if (!Object.prototype.hasOwnProperty.call(FACING, d.facing)) {
              add('E_MAP_BAD_DOOR', tag + ' has bad facing ' + JSON.stringify(d.facing), { door: did }); continue;
            }
            const f = FACING[d.facing];
            const ac = d.col + f[0];
            const ar = d.row + f[1];
            if (!isFloorCh(chAt(rows, ac, ar))) {
              add('E_MAP_BAD_DOOR', tag + ' arrival cell ' + ac + ',' + ar + ' is not walkable floor', { door: did });
            } else if (solidCells.has(ar * 4096 + ac)) {
              add('E_MAP_BAD_DOOR', tag + ' arrival cell ' + ac + ',' + ar + ' holds a solid prop', { door: did });
            }
          }
        }

        // Hides: optional [[col,row],...] of in-bounds floor cells people can flee to.
        if (mapDef.hides !== undefined) {
          if (!Array.isArray(mapDef.hides)) {
            add('E_MAP_BAD_HIDE', 'map ' + name + ' hides must be an array');
          } else {
            for (let i = 0; i < mapDef.hides.length; i++) {
              const h = mapDef.hides[i];
              const ok = Array.isArray(h) && h.length >= 2 && isInt(h[0]) && isInt(h[1]) &&
                h[0] >= 0 && h[1] >= 0 && h[0] < rows[0].length && h[1] < rows.length && isFloorCh(chAt(rows, h[0], h[1]));
              if (!ok) add('E_MAP_BAD_HIDE', 'map ' + name + ' hide ' + i + ' is not an in-bounds floor cell', { hide: i });
            }
          }
        }

        // Paths: every segment clear of walls and solid props.
        const paths = mapDef.paths;
        if (Array.isArray(paths)) {
          const solidList = [];
          if (Array.isArray(mapDef.props)) {
            for (let i = 0; i < mapDef.props.length; i++) {
              const p = mapDef.props[i];
              if (p && PROP_TYPES.indexOf(p.type) >= 0 && !NON_SOLID[p.type] && isInt(p.col) && isInt(p.row)) solidList.push(p);
            }
          }
          const blockedAt = function (x, y) {
            const ch = chAt(rows, Math.floor(x), Math.floor(y));
            if (isWallCh(ch)) return true;
            for (let k = 0; k < solidList.length; k++) {
              const dx = x - (solidList[k].col + 0.5);
              const dy = y - (solidList[k].row + 0.5);
              if (dx * dx + dy * dy < PROP_R * PROP_R) return true;
            }
            return false;
          };
          for (let i = 0; i < paths.length; i++) {
            const pts = paths[i] && Array.isArray(paths[i].points) ? paths[i].points : null;
            if (!pts || pts.length === 0) continue;
            let okPts = true;
            for (let k = 0; k < pts.length; k++) {
              const q = pts[k];
              if (!Array.isArray(q) || q.length < 2 || !isFinite(q[0]) || !isFinite(q[1])) {
                add('E_MAP_BAD_PATH', 'map ' + name + ' path ' + i + ' point ' + k + ' is invalid', { path: i });
                okPts = false;
                break;
              }
            }
            if (!okPts) continue;
            for (let k = 0; k < pts.length; k++) {
              const a = pts[k];
              const b = pts[(k + 1) % pts.length];
              const ax = a[0] + 0.5, ay = a[1] + 0.5, bx = b[0] + 0.5, by = b[1] + 0.5;
              const len = Math.hypot(bx - ax, by - ay);
              const n = Math.max(1, Math.ceil(len / 0.1));
              let bad = false;
              for (let s = 0; s <= n && !bad; s++) {
                const f = s / n;
                if (blockedAt(ax + (bx - ax) * f, ay + (by - ay) * f)) bad = true;
              }
              if (bad) {
                add('E_MAP_BAD_PATH', 'map ' + name + ' path ' + i + ' segment ' + k + ' crosses a wall or solid prop', { path: i, segment: k });
                break;
              }
            }
          }
        }
      }

      for (const l of lks) {
        if (l && typeof l === 'object' && names.indexOf(l.to) < 0) {
          add('E_MAP_BAD_LINK', 'map ' + name + ' link from ' + l.from + ' targets missing map ' + l.to);
        }
      }
    } catch (e) {
      errors.push({ code: 'E_MAP_EMPTY', message: 'map could not be validated: ' + (e && e.message), map: name });
    }
    return { ok: errors.length === 0, errors: errors };
  }

  function mapsOf(mapData) {
    return mapData && mapData.maps && typeof mapData.maps === 'object' ? mapData.maps : {};
  }

  /** Names of maps reachable from startName through link doors (startName first). */
  function reachable(mapData, startName) {
    const maps = mapsOf(mapData);
    const out = [];
    if (!Object.prototype.hasOwnProperty.call(maps, startName)) return out;
    const seen = {};
    seen[startName] = true;
    const queue = [startName];
    while (queue.length) {
      const n = queue.shift();
      out.push(n);
      const ds = maps[n] && Array.isArray(maps[n].doors) ? maps[n].doors : [];
      for (let i = 0; i < ds.length; i++) {
        const t = ds[i] && ds[i].toMap;
        if (typeof t === 'string' && !seen[t] && Object.prototype.hasOwnProperty.call(maps, t)) {
          seen[t] = true;
          queue.push(t);
        }
      }
    }
    return out;
  }

  /** Validate every map plus the link graph. Returns {ok, errors}; each error {code, message, map, door?}. */
  function validateAll(mapData) {
    const errors = [];
    try {
      const maps = mapsOf(mapData);
      const names = Object.keys(maps);
      const startMap = mapData ? mapData.startMap : undefined;
      const push = function (code, message, map, door) {
        const e = { code: code, message: message, map: map };
        if (door !== undefined) e.door = door;
        errors.push(e);
      };
      if (typeof startMap !== 'string' || !Object.prototype.hasOwnProperty.call(maps, startMap)) {
        push('E_MAP_NO_STARTMAP', 'startMap ' + JSON.stringify(startMap) + ' is not a defined map', typeof startMap === 'string' ? startMap : 'unknown');
      }
      for (let i = 0; i < names.length; i++) {
        const n = names[i];
        const def = maps[n];
        const res = validate(def, names, null, { requireStart: n === startMap || n === 'test' });
        for (let k = 0; k < res.errors.length; k++) {
          const e = res.errors[k];
          if (!e.map || e.map === 'unknown') e.map = n;
          errors.push(e);
        }
        const ds = def && Array.isArray(def.doors) ? def.doors : [];
        for (let k = 0; k < ds.length; k++) {
          const d = ds[k];
          if (!d || typeof d !== 'object' || typeof d.id !== 'string') continue;
          const tag = 'map ' + n + ' door ' + d.id;
          if (typeof d.toMap !== 'string' || typeof d.toDoor !== 'string') {
            push('E_MAP_BAD_LINK', tag + ' has no toMap/toDoor', n, d.id);
            continue;
          }
          if (d.toMap === n) {
            push('E_MAP_SELF_LINK', tag + ' links to its own map', n, d.id);
            continue;
          }
          if (!Object.prototype.hasOwnProperty.call(maps, d.toMap)) {
            push('E_MAP_BAD_LINK', tag + ' targets missing map ' + d.toMap, n, d.id);
            continue;
          }
          const tds = Array.isArray(maps[d.toMap].doors) ? maps[d.toMap].doors : [];
          let target = null;
          for (let j = 0; j < tds.length; j++) if (tds[j] && tds[j].id === d.toDoor) { target = tds[j]; break; }
          if (!target) {
            push('E_MAP_BAD_LINK', tag + ' targets missing door ' + d.toMap + '.' + d.toDoor, n, d.id);
            continue;
          }
          if (target.toMap !== n || target.toDoor !== d.id) {
            push('E_MAP_ONEWAY', tag + ' -> ' + d.toMap + '.' + d.toDoor + ' does not link back', n, d.id);
          }
        }
      }
      if (typeof startMap === 'string' && Object.prototype.hasOwnProperty.call(maps, startMap)) {
        const reach = reachable(mapData, startMap);
        for (let i = 0; i < names.length; i++) {
          if (names[i] !== 'test' && reach.indexOf(names[i]) < 0) {
            push('E_MAP_UNREACHABLE', 'map ' + names[i] + ' is not reachable from ' + startMap, names[i]);
          }
        }
      }
    } catch (e) {
      errors.push({ code: 'E_MAP_INVALID', message: 'map data could not be validated: ' + (e && e.message), map: 'unknown' });
    }
    return { ok: errors.length === 0, errors: errors };
  }

  function invalid(errors, log) {
    const err = new Error('Invalid map: ' + errors.map(function (e) { return e.message; }).join('; '));
    err.code = 'E_MAP_INVALID';
    err.details = errors;
    if (log) log.error(err.message, err);
    return err;
  }

  /** Validate and build a world object; throws Error with code E_MAP_INVALID on failure. */
  function load(mapDef, opts) {
    const res = validate(mapDef, undefined, undefined, opts);
    const log = logger();
    if (!res.ok) throw invalid(res.errors, log);
    const rows = mapDef.rows;
    const height = rows.length;
    const width = rows[0].length;
    const kind = mapDef.kind === 'outdoor' ? 'outdoor' : 'indoor';
    const kindGrid = new Array(width * height);
    const zoneGrid = new Array(width * height);
    for (let i = 0; i < kindGrid.length; i++) { kindGrid[i] = kind; zoneGrid[i] = null; }
    const zoneDefs = Array.isArray(mapDef.zones) ? mapDef.zones : [];
    for (let i = 0; i < zoneDefs.length; i++) {
      const z = zoneDefs[i];
      for (let zy = z.y0; zy <= z.y1; zy++) {
        for (let zx = z.x0; zx <= z.x1; zx++) { kindGrid[zy * width + zx] = z.kind; zoneGrid[zy * width + zx] = z.name; }
      }
    }
    function kindAt(x, y) {
      const cx = Math.floor(x);
      const cy = Math.floor(y);
      if (!(cx >= 0 && cy >= 0 && cx < width && cy < height)) return kind;
      return kindGrid[cy * width + cx];
    }
    function zoneAt(x, y) {
      const cx = Math.floor(x);
      const cy = Math.floor(y);
      if (!(cx >= 0 && cy >= 0 && cx < width && cy < height)) return null;
      return zoneGrid[cy * width + cx];
    }
    const floor = FLOOR_MATS.indexOf(mapDef.floor) >= 0 ? mapDef.floor : 'stone';
    const spots = { crypt: [], safe: [], people: [], doors: [] };
    let start = null;
    for (let r = 0; r < height; r++) {
      for (let c = 0; c < width; c++) {
        const p = { x: c + 0.5, y: r + 0.5 };
        switch (rows[r][c]) {
          case TILES.START: start = p; break;
          case TILES.CRYPT: spots.crypt.push(p); break;
          case TILES.SAFE: spots.safe.push(p); break;
          case TILES.PERSON: spots.people.push(p); break;
          case TILES.DOOR: spots.doors.push(p); break;
          default: break;
        }
      }
    }
    function tileAt(x, y) {
      const cx = Math.floor(x);
      const cy = Math.floor(y);
      if (!(cx >= 0 && cy >= 0 && cx < width && cy < height)) return TILES.WALL;
      return rows[cy][cx];
    }
    const open = new Set();
    function doorKey(cx, cy) { return cy * width + cx; }
    function isDoorOpen(cx, cy) {
      return open.has(doorKey(Math.floor(cx), Math.floor(cy)));
    }
    function isSolid(x, y) {
      const t = tileAt(x, y);
      if (WALLS.indexOf(t) >= 0) return true;
      return (t === 'D' || t === 'G') && !open.has(doorKey(Math.floor(x), Math.floor(y)));
    }

    // Doors.
    const doorsById = {};
    const doorGrid = new Array(width * height).fill(null);
    const doorList = Array.isArray(mapDef.doors) ? mapDef.doors : [];
    for (let i = 0; i < doorList.length; i++) {
      const d = doorList[i];
      const entry = { id: d.id, col: d.col, row: d.row, toMap: d.toMap, toDoor: d.toDoor, facing: d.facing };
      doorsById[d.id] = entry;
      doorGrid[doorKey(d.col, d.row)] = entry;
    }
    function doorAt(cx, cy) {
      cx = Math.floor(cx);
      cy = Math.floor(cy);
      if (!(cx >= 0 && cy >= 0 && cx < width && cy < height)) return null;
      return doorGrid[doorKey(cx, cy)];
    }
    function isLinkDoor(cx, cy) { return doorAt(cx, cy) !== null; }
    function arrival(doorId) {
      const d = typeof doorId === 'string' && Object.prototype.hasOwnProperty.call(doorsById, doorId) ? doorsById[doorId] : null;
      if (!d) return null;
      const f = FACING[d.facing];
      return { x: d.col + 0.5 + f[0], y: d.row + 0.5 + f[1], angle: f[2] };
    }

    // A map may re-skin a tile character (mapDef.materials, e.g. '#' -> 'roughStone'); unknown names are ignored.
    const matTable = Object.assign({}, MATERIAL);
    if (mapDef.materials && typeof mapDef.materials === 'object') {
      Object.keys(mapDef.materials).forEach(function (ch) {
        if (Object.prototype.hasOwnProperty.call(MATERIAL, ch) && MATERIALS.indexOf(mapDef.materials[ch]) >= 0) matTable[ch] = mapDef.materials[ch];
      });
    }
    function materialAt(x, y) {
      const m = matTable[tileAt(x, y)];
      return m || floor;
    }
    /** Roughness 0..1 of the surface at (x,y) (SoundData.acoustics.rough by material; 0.2 without data). */
    function roughnessAt(x, y) {
      const sd = root.VCS && root.VCS.SoundData;
      return sd && sd.acoustics ? sd.acoustics.roughOf(materialAt(x, y)) : 0.2;
    }

    // Props.
    const props = [];
    const lights = [];
    const propCells = new Array(width * height).fill(null); // solid props per cell
    const pl = Array.isArray(mapDef.props) ? mapDef.props : [];
    for (let i = 0; i < pl.length; i++) {
      const d = pl[i];
      const solid = !NON_SOLID[d.type];
      let light = typeof d.light === 'number' ? d.light : (DEFAULT_LIGHT[d.type] || 0);
      if (!(light > 0)) light = 0;
      const p = { type: d.type, x: d.col + 0.5, y: d.row + 0.5, solid: solid, r: PROP_R, light: light };
      props.push(p);
      if (solid) {
        const k = doorKey(d.col, d.row);
        (propCells[k] || (propCells[k] = [])).push(p);
      }
      if (light > 0) lights.push({ x: p.x, y: p.y, radius: light * LIGHT_SCALE, type: p.type });
    }
    const nearBuf = [];
    function propsNear(x, y, r) {
      nearBuf.length = 0;
      if (!(isFinite(x) && isFinite(y) && isFinite(r))) return nearBuf;
      const r2 = r * r;
      for (let i = 0; i < props.length; i++) {
        const dx = props[i].x - x;
        const dy = props[i].y - y;
        if (dx * dx + dy * dy <= r2) nearBuf.push(props[i]);
      }
      return nearBuf;
    }
    function blocks(x, y, r) {
      if (!(isFinite(x) && isFinite(y))) return true;
      if (!(r > 0)) r = 0;
      if (isSolid(x - r, y - r) || isSolid(x + r, y - r) || isSolid(x - r, y + r) || isSolid(x + r, y + r)) return true;
      const reach = r + PROP_R;
      const c0 = Math.max(0, Math.floor(x - reach));
      const c1 = Math.min(width - 1, Math.floor(x + reach));
      const r0 = Math.max(0, Math.floor(y - reach));
      const r1 = Math.min(height - 1, Math.floor(y + reach));
      for (let cy = r0; cy <= r1; cy++) {
        for (let cx = c0; cx <= c1; cx++) {
          const list = propCells[cy * width + cx];
          if (!list) continue;
          for (let i = 0; i < list.length; i++) {
            const dx = x - list[i].x;
            const dy = y - list[i].y;
            const rr = r + list[i].r;
            if (dx * dx + dy * dy < rr * rr) return true;
          }
        }
      }
      return false;
    }

    // Light grid: per-cell max falloff, recomputed whenever a door changes.
    const lightGrid = new Float32Array(width * height);
    /** Outer halo: same falloff shape out to OUTER_K x the core radius. */
    const OUTER_K = 1.8;
    const outerGrid = new Float32Array(width * height);
    /** True when a solid tile lies strictly between the cell of (x0,y0) and the cell of (x1,y1) (DDA). */
    function lineBlocked(x0, y0, x1, y1) {
      let cx = Math.floor(x0);
      let cy = Math.floor(y0);
      const ex = Math.floor(x1);
      const ey = Math.floor(y1);
      if (cx === ex && cy === ey) return false;
      const dx = x1 - x0;
      const dy = y1 - y0;
      const stepX = dx < 0 ? -1 : 1;
      const stepY = dy < 0 ? -1 : 1;
      const tdx = dx === 0 ? Infinity : Math.abs(1 / dx);
      const tdy = dy === 0 ? Infinity : Math.abs(1 / dy);
      let tx = dx === 0 ? Infinity : (dx < 0 ? (x0 - cx) : (cx + 1 - x0)) * tdx;
      let ty = dy === 0 ? Infinity : (dy < 0 ? (y0 - cy) : (cy + 1 - y0)) * tdy;
      for (let i = 0; i < 256; i++) {
        if (tx < ty) { tx += tdx; cx += stepX; } else { ty += tdy; cy += stepY; }
        if (cx === ex && cy === ey) return false;
        // Glass lets light through (it still blocks movement and sonar).
        if (isSolid(cx, cy) && tileAt(cx, cy) !== 'w') return true;
      }
      return true;
    }
    function recomputeLights() {
      lightGrid.fill(0);
      outerGrid.fill(0);
      for (let i = 0; i < lights.length; i++) {
        const L = lights[i];
        const R = L.radius;
        const RO = R * OUTER_K;
        const c0 = Math.max(0, Math.floor(L.x - RO));
        const c1 = Math.min(width - 1, Math.floor(L.x + RO));
        const r0 = Math.max(0, Math.floor(L.y - RO));
        const r1 = Math.min(height - 1, Math.floor(L.y + RO));
        for (let cy = r0; cy <= r1; cy++) {
          for (let cx = c0; cx <= c1; cx++) {
            if (isSolid(cx + 0.5, cy + 0.5)) continue;
            const px = cx + 0.5;
            const py = cy + 0.5;
            const d = Math.hypot(px - L.x, py - L.y);
            if (d >= RO) continue;
            const k = cy * width + cx;
            const vo = d <= 0.5 * RO ? 1 : 2 - 2 * d / RO;
            const needO = vo > outerGrid[k];
            const v = d >= R ? 0 : d <= 0.5 * R ? 1 : 2 - 2 * d / R;
            const needC = v > lightGrid[k];
            if (!needO && !needC) continue;
            if (lineBlocked(L.x, L.y, px, py)) continue;
            if (needO) outerGrid[k] = vo;
            if (needC) lightGrid[k] = v;
          }
        }
      }
    }
    function outerAt(x, y) {
      const cx = Math.floor(x);
      const cy = Math.floor(y);
      if (!(cx >= 0 && cy >= 0 && cx < width && cy < height)) return 0;
      return outerGrid[cy * width + cx];
    }
    /** Read-only copy of the light sources (core radius). */
    function lightSources() {
      const out = [];
      for (let i = 0; i < lights.length; i++) out.push({ x: lights[i].x, y: lights[i].y, radius: lights[i].radius });
      return out;
    }
    function lightAt(x, y) {
      const cx = Math.floor(x);
      const cy = Math.floor(y);
      if (!(cx >= 0 && cy >= 0 && cx < width && cy < height)) return 0;
      return lightGrid[cy * width + cx];
    }

    /** Open or close the door in cell (cx,cy); false if that cell is not a door. */
    function setDoor(cx, cy, isOpen) {
      cx = Math.floor(cx);
      cy = Math.floor(cy);
      if (!isDoorCh(tileAt(cx, cy))) return false;
      const k = doorKey(cx, cy);
      const was = open.has(k);
      if (isOpen) open.add(k); else open.delete(k);
      if (was !== !!isOpen && lights.length) recomputeLights();
      return true;
    }

    const world = {
      name: String(mapDef.name),
      kind: kind,
      kindAt: kindAt,
      zoneAt: zoneAt,
      zones: zoneDefs,
      floor: floor,
      width: width,
      height: height,
      tileAt: tileAt,
      materialAt: materialAt,
      roughnessAt: roughnessAt,
      isSolid: isSolid,
      lineBlocked: lineBlocked,
      isDoorOpen: isDoorOpen,
      setDoor: setDoor,
      doorsById: doorsById,
      doorAt: doorAt,
      isLinkDoor: isLinkDoor,
      arrival: arrival,
      props: props,
      propsNear: propsNear,
      blocks: blocks,
      lights: lights,
      lightAt: lightAt,
      outerAt: outerAt,
      lightSources: lightSources,
      start: start,
      spots: spots
    };
    recomputeLights();
    if (log) log.info('loaded map ' + world.name + ' ' + kind + ' ' + width + 'x' + height + ' props ' + props.length + ' lights ' + lights.length);
    return world;
  }

  /** Validate all maps up front and build every world. Throws E_MAP_INVALID (err.details = errors). */
  function loadAll(mapData) {
    const res = validateAll(mapData);
    if (!res.ok) throw invalid(res.errors, logger());
    const maps = mapsOf(mapData);
    const worlds = {};
    const names = Object.keys(maps);
    for (let i = 0; i < names.length; i++) {
      const n = names[i];
      worlds[n] = load(maps[n], { requireStart: n === mapData.startMap || n === 'test' });
    }
    return { worlds: worlds, startMap: mapData.startMap };
  }

  const World = {
    TILES: TILES, MATERIAL: MATERIAL, MATERIALS: MATERIALS, WALLS: WALLS, FLOORS: FLOORS, DOORS: DOORS,
    validate: validate, validateAll: validateAll, reachable: reachable, load: load, loadAll: loadAll
  };
  VCS.World = World;
  if (typeof module !== 'undefined' && module.exports) module.exports = World;
})(typeof window !== 'undefined' ? window : globalThis);
