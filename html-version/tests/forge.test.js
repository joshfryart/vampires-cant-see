'use strict';
const { describe } = require('node:test');

describe('forge.test.js', () => {
  const test = require('node:test');
  const assert = require('node:assert');
  const Log = require('../js/log.js');
  const AD = require('../js/data/archetypes.js');
  const Forge = require('../js/forge.js');
  const People = require('../js/people.js');

  Log.setConsole(false);

  const CTX = { stateSeed: 4242, index: 3, accOffset: 5 };
  const LEGACY_KEYS = ['height', 'build', 'stride', 'acc', 'body', 'head', 'hat', 'hair', 'beard', 'nose', 'coat', 'prop'];

  function fakeStorage() {
    const m = {};
    return {
      getItem: (k) => (Object.prototype.hasOwnProperty.call(m, k) ? m[k] : null),
      setItem: (k, v) => { m[k] = String(v); },
      raw: m
    };
  }

  function customArch(id, extra) {
    return Object.assign({ id: id, role: 'x' + id, voice: 'man', talk: 'villager', schedule: null }, extra || {});
  }

  test('legacyLook matches People.makeLook bit for bit', () => {
    for (let seed = 0; seed < 6; seed++) {
      for (let id = 0; id < 40; id++) {
        for (let off = 0; off < 10; off += 3) {
          assert.deepStrictEqual(Forge.legacyLook(seed * 977 + 11, id, off), People.makeLook(seed * 977 + 11, id, off));
        }
      }
    }
    assert.deepStrictEqual(Forge.legacyLook(123456, 7, 2), People.makeLook(123456, 7, 2));
    assert.deepStrictEqual(Forge.legacyLook(NaN, 'x', undefined), People.makeLook(NaN, 'x', undefined));
    assert.notStrictEqual(Forge.legacyLook(1, 2, 3), Forge.legacyLook(1, 2, 3));
  });

  test('legacy archetypes generate the legacy look when entrySeed equals index', () => {
    AD.list.filter((a) => a.legacy).forEach((a) => {
      for (let i = 0; i < 20; i++) {
        const r = Forge.generate({ archetype: a.id, seed: i }, { stateSeed: 99, index: i, accOffset: 3 });
        assert.ok(r.ok, a.id);
        const want = Forge.legacyLook(99, i, 3);
        LEGACY_KEYS.forEach((k) => assert.strictEqual(r.person.look[k], want[k], a.id + ' ' + k));
      }
    });
    assert.strictEqual(Forge.lookSeed(11, 3), ((11 >>> 0) * 2654435761 + 4 * 40503 + 977) >>> 0);
  });

  test('determinism', () => {
    const spec = { archetype: 'merchant', seed: 5 };
    assert.deepStrictEqual(Forge.generate(spec, CTX), Forge.generate(spec, CTX));
    const a = Forge.generate({ archetype: 'patron', seed: 1 }, CTX).person.look;
    const b = Forge.generate({ archetype: 'patron', seed: 2 }, CTX).person.look;
    assert.notDeepStrictEqual(a, b);
    // entrySeed outside 0..65535 falls back to ctx.index
    const big = Forge.generate({ archetype: 'patron', seed: 1e9 }, CTX).person.look;
    assert.deepStrictEqual(big, Forge.generate({ archetype: 'patron', seed: CTX.index }, CTX).person.look);
  });

  test('every built-in generates inside ranges and enums', () => {
    const R = AD.LOOK_RANGES;
    const E = AD.LOOK_ENUMS;
    AD.list.forEach((a) => {
      for (let s = 0; s < 20; s++) {
        const r = Forge.generate({ archetype: a.id, seed: s }, { stateSeed: 7 + s, index: s, accOffset: s });
        assert.ok(r.ok && r.code === 'OK', a.id);
        const look = r.person.look;
        Object.keys(R).forEach((k) => {
          assert.ok(look[k] >= R[k][0] && look[k] <= R[k][1], a.id + ' ' + k + ' ' + look[k]);
        });
        Object.keys(E).forEach((k) => assert.ok(E[k].indexOf(look[k]) >= 0, a.id + ' ' + k + ' ' + look[k]));
        assert.strictEqual(typeof look.beard, 'boolean');
        assert.strictEqual(typeof look.coat, 'boolean');
        assert.strictEqual(look.archetype, a.id);
        assert.strictEqual(look.v, 1);
        assert.strictEqual(r.person.role, a.role);
        const v = Forge.validate('look', look);
        assert.ok(v.ok, a.id);
        assert.deepStrictEqual(v.value, look);
      }
    });
  });

  test('built-in archetypes pass archetype validation', () => {
    AD.list.forEach((a) => {
      const v = Forge.validate('archetype', JSON.parse(JSON.stringify(a)));
      assert.ok(v.ok, a.id + ' ' + v.errors.join(','));
    });
  });

  test('person fields follow the archetype', () => {
    const g = Forge.generate({ archetype: 'guard', home: 'h1' }, CTX).person;
    assert.strictEqual(g.watch, true);
    assert.strictEqual(g.gait, 'mail');
    assert.strictEqual(g.schedRole, 'guard');
    assert.strictEqual(g.home, 'h1');
    const p = Forge.generate({ archetype: 'patron' }, CTX).person;
    assert.strictEqual(p.role, '');
    assert.strictEqual(p.schedRole, null);
    assert.strictEqual(Forge.generate({ archetype: 'child' }, CTX).person.feedable, false);
  });

  test('unknown archetype falls back to patron with E_FORGE_UNKNOWN', () => {
    const r = Forge.generate({ archetype: 'nope' }, CTX);
    assert.strictEqual(r.ok, false);
    assert.strictEqual(r.code, 'E_FORGE_UNKNOWN');
    assert.strictEqual(r.person.archetype, 'patron');
  });

  test('hat, prop and hair rules hold', () => {
    const HATS = ['tophat', 'nightcap', 'bonnet', 'cap', 'hood'];
    const PROPS = ['cane', 'lantern', 'umbrella', 'basket'];
    for (let i = 0; i < 60; i++) {
      const l = Forge.generate({ archetype: 'patron', seed: i }, { stateSeed: 1, index: i, accOffset: 2 }).person.look;
      assert.strictEqual(l.hat, HATS.indexOf(l.acc) >= 0 ? l.acc : 'none');
      assert.strictEqual(l.prop, PROPS.indexOf(l.acc) >= 0 ? l.acc : 'none');
      if (['tophat', 'nightcap', 'hood'].indexOf(l.hat) >= 0) assert.strictEqual(l.hair, 'none');
    }
    const base = Forge.generate({ archetype: 'patron', seed: 2 }, CTX).person.look;
    const a1 = Forge.alter(base, { acc: 'hood' });
    assert.ok(a1.ok);
    assert.strictEqual(a1.look.hat, 'hood');
    assert.strictEqual(a1.look.prop, 'none');
    assert.strictEqual(a1.look.hair, 'none');
    const a2 = Forge.alter(base, { acc: 'lantern' });
    assert.strictEqual(a2.look.prop, 'lantern');
    assert.strictEqual(a2.look.hat, 'none');
    assert.ok(a2.changed.indexOf('acc') >= 0);
    const o = Forge.generate({ archetype: 'patron', seed: 2, overrides: { acc: 'tophat', hair: 'bob' } }, CTX).person.look;
    assert.strictEqual(o.hat, 'tophat');
    assert.strictEqual(o.hair, 'none');
    assert.strictEqual(o.archetype, 'patron');
  });

  test('alter builds a new object and leaves the old look untouched', () => {
    const base = Forge.generate({ archetype: 'guard' }, CTX).person.look;
    const snap = JSON.stringify(base);
    const r = Forge.alter(base, { height: 99, acc: 'lantern' });
    assert.notStrictEqual(r.look, base);
    assert.strictEqual(JSON.stringify(base), snap);
    assert.strictEqual(r.look.height, 1.2);
    assert.strictEqual(Forge.alter(base, {}).changed.length, 0);
    assert.strictEqual(Forge.alter('x', {}).ok, false);
    assert.strictEqual(Forge.alter(base, JSON.parse('{"__proto__":{"a":1}}')).code, 'E_FORGE_BAD_KEY');
    assert.strictEqual(Object.isFrozen(r.look), false);
  });

  test('validate rejects bad keys, clamps and types', () => {
    ['__proto__', 'constructor', 'prototype'].forEach((k) => {
      const r = Forge.validate('look', JSON.parse('{"' + k + '":{"x":1}}'));
      assert.strictEqual(r.ok, false);
      assert.strictEqual(r.code, 'E_FORGE_BAD_KEY');
      assert.strictEqual(({}).x, undefined);
    });
    assert.strictEqual(Forge.validate('look', { zzz: 1 }).code, 'E_FORGE_BAD_KEY');
    const c = Forge.validate('look', { height: 99, body: 'cube', beard: 'yes', nose: NaN });
    assert.ok(c.ok);
    assert.strictEqual(c.value.height, 1.2);
    assert.strictEqual(c.value.body, 'bean');
    assert.strictEqual(c.value.beard, false);
    assert.strictEqual(c.value.nose, 1);
    assert.ok(c.errors.length >= 3);
    const p = Forge.validate('look', { height: 0, body: 'cube' }, { partial: true });
    assert.deepStrictEqual(p.value, { height: 0.5 });
    [null, undefined, 5, 'str', [], true].forEach((v) => {
      ['look', 'archetype', 'spec', 'library'].forEach((kind) => {
        assert.strictEqual(Forge.validate(kind, v).code, 'E_FORGE_TYPE', kind + ' ' + String(v));
      });
    });
    assert.strictEqual(Forge.validate('nope', {}).ok, false);
    assert.ok(Forge.validate('spec', { archetype: 'guard', seed: 3, overrides: { height: 5 } }).ok);
    assert.strictEqual(Forge.validate('spec', { archetype: 'guard', extra: 1 }).code, 'E_FORGE_BAD_KEY');
    assert.strictEqual(Forge.validate('archetype', JSON.parse('{"id":"abc","__proto__":1,"voice":"man","talk":"t"}')).code, 'E_FORGE_BAD_KEY');
  });

  test('register refuses built-ins and a 17th custom; library round trip', () => {
    assert.strictEqual(Forge.register(customArch('guard')).ok, false);
    assert.strictEqual(Forge.register({ id: 'Bad Id' }).ok, false);
    assert.strictEqual(Forge.register(customArch('c_one')).ok, true);
    assert.strictEqual(Forge.register(customArch('c_one')).ok, true); // replace does not count twice
    assert.ok(Forge.list().indexOf('c_one') >= 0);
    assert.strictEqual(Forge.list()[0], AD.list[0].id);
    assert.strictEqual(Forge.archetype('c_one').legacy, false);
    assert.strictEqual(Forge.byRole('xc_one').id, 'c_one');
    assert.strictEqual(Forge.byRole('guard').id, 'guard');
    assert.strictEqual(Forge.archetype('__proto__'), null);
    const g = Forge.generate({ archetype: 'c_one', seed: 1 }, CTX);
    assert.ok(g.ok);
    assert.ok(Forge.validate('look', g.person.look).ok);

    // library round trip while the overlay is small
    const text = Forge.exportLibrary();
    const parsed = JSON.parse(text);
    assert.strictEqual(parsed.v, 1);
    assert.strictEqual(parsed.list.length, 1);
    const st = fakeStorage();
    assert.deepStrictEqual(Forge.saveLibrary(st), { ok: true, code: 'OK' });
    assert.ok(Object.prototype.hasOwnProperty.call(st.raw, 'vcs.forge'));
    assert.strictEqual(Forge.loadLibrary(st).ok, true);
    assert.strictEqual(Forge.importLibrary(text).n, 1);
    assert.strictEqual(Forge.loadLibrary(fakeStorage()).ok, true);
    // oversize
    st.raw['vcs.forge'] = ' '.repeat(20000);
    assert.strictEqual(Forge.loadLibrary(st).code, 'E_FORGE_LIMIT');
    assert.strictEqual(Forge.importLibrary('x'.repeat(20000)).code, 'E_FORGE_LIMIT');
    // garbage
    assert.strictEqual(Forge.importLibrary('not json {').code, 'E_FORGE_PARSE');
    st.raw['vcs.forge'] = 'garbage';
    assert.strictEqual(Forge.loadLibrary(st).code, 'E_FORGE_PARSE');
    assert.strictEqual(Forge.importLibrary('{"v":2,"list":[]}').ok, false);
    assert.strictEqual(Forge.importLibrary('{"v":1,"list":[{"id":"guard"}]}').ok, false);
    assert.strictEqual(Forge.importLibrary('{"__proto__":{"v":1},"v":1,"list":[]}').ok, false);
    assert.strictEqual(Forge.saveLibrary(null).ok, false);

    // fill to the cap
    for (let i = 2; i <= 16; i++) assert.strictEqual(Forge.register(customArch('c_' + i)).ok, true, 'c_' + i);
    const over = Forge.register(customArch('c_17'));
    assert.strictEqual(over.ok, false);
    assert.strictEqual(over.code, 'E_FORGE_LIMIT');
    assert.strictEqual(Forge.archetype('c_17'), null);
    const lib = JSON.parse(Forge.exportLibrary());
    lib.list.push(JSON.parse(JSON.stringify(customArch('c_17'))));
    assert.strictEqual(Forge.importLibrary(JSON.stringify(lib)).code, 'E_FORGE_LIMIT');
  });

  test('reinforcement fires at fear 6 and 10 in order and is deterministic', () => {
    assert.strictEqual(Forge.reinforcement({ fear: 5.9, night: 1, runSeed: 7, fired: 0 }), null);
    const a = Forge.reinforcement({ fear: 6, night: 2, runSeed: 7, fired: 0 });
    assert.strictEqual(a.archetype, 'guard');
    assert.strictEqual(a.card, 'The watch is doubled');
    assert.strictEqual(a.seed, (7 * 31 + 2 * 977 + 0) >>> 0);
    assert.deepStrictEqual(a, Forge.reinforcement({ fear: 6, night: 2, runSeed: 7, fired: 0 }));
    assert.strictEqual(Forge.reinforcement({ fear: 9, night: 2, runSeed: 7, fired: 1 }), null);
    const b = Forge.reinforcement({ fear: 10, night: 2, runSeed: 7, fired: 1 });
    assert.strictEqual(b.archetype, 'hunter');
    assert.strictEqual(b.seed, (7 * 31 + 2 * 977 + 7919) >>> 0);
    assert.strictEqual(Forge.reinforcement({ fear: 99, night: 2, runSeed: 7, fired: 2 }), null);
  });

  test('LOOK_FIELDS is a frozen editor table', () => {
    const f = Forge.LOOK_FIELDS;
    assert.ok(Object.isFrozen(f));
    const h = f.find((x) => x.key === 'height');
    assert.deepStrictEqual([h.type, h.min, h.max], ['num', 0.5, 1.2]);
    assert.ok(f.find((x) => x.key === 'hat').values.indexOf('tophat') >= 0);
    assert.strictEqual(f.find((x) => x.key === 'beard').type, 'bool');
  });

  test('no call throws on junk input', () => {
    const cyc = {};
    cyc.self = cyc;
    cyc.look = cyc;
    cyc.overrides = cyc;
    cyc.archetype = cyc;
    const junk = [undefined, null, NaN, Infinity, 'str', 5, [], {}, cyc, () => 1, Symbol('s')];
    junk.forEach((j) => {
      assert.doesNotThrow(() => {
        Forge.lookSeed(j, j);
        Forge.legacyLook(j, j, j);
        Forge.generate(j, j);
        Forge.generate({ archetype: j, seed: j, overrides: j, home: j }, { stateSeed: j, index: j, accOffset: j });
        Forge.alter(j, j);
        Forge.alter({}, j);
        ['look', 'archetype', 'spec', 'library', j].forEach((k) => {
          Forge.validate(k, j);
          Forge.validate(k, j, j);
        });
        Forge.archetype(j);
        Forge.byRole(j);
        Forge.register(j);
        Forge.loadLibrary(j);
        Forge.saveLibrary(j);
        Forge.importLibrary(j);
        Forge.reinforcement(j);
        Forge.reinforcement({ fear: j, night: j, runSeed: j, fired: j });
      });
    });
    const boom = { getItem() { throw new Error('x'); }, setItem() { throw new Error('x'); } };
    assert.doesNotThrow(() => { Forge.loadLibrary(boom); Forge.saveLibrary(boom); });
    assert.strictEqual(Forge.generate(cyc, cyc).ok, true);
  });
});
