(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // NPC archetypes (v0.14): data only. The 11 legacy rows reproduce v0.13.2 exactly (voice via VoiceData.presetFor,
  // talk via VoiceData.groupOf, schedule tuples copied verbatim from schedule.js ROLES). js/forge.js reads this.
  // schedule: null | 'watch' | [[[placeToken...], until, act], ...]. extras: number = fixed, [min, span] = drawn.

  function deepFreeze(o) {
    if (o && typeof o === 'object' && !Object.isFrozen(o)) {
      Object.freeze(o);
      Object.keys(o).forEach(function (k) { deepFreeze(o[k]); });
    }
    return o;
  }

  function hasOwn(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
  function bad(k) { return typeof k !== 'string' || k === '__proto__' || k === 'constructor' || k === 'prototype'; }

  const ACCESSORIES = ['tophat', 'nightcap', 'bonnet', 'cane', 'scarf', 'lantern', 'hood', 'umbrella', 'cap', 'basket'];
  const BODIES = ['bean', 'pear', 'stick', 'round', 'box'];
  const HEADS = ['round', 'egg', 'square', 'long'];
  const HAIRS = ['none', 'tuft', 'bun', 'spiky', 'curls', 'bob'];

  const LOOK_KEYS = ['height', 'build', 'stride', 'acc', 'body', 'head', 'hat', 'hair', 'beard', 'nose', 'coat', 'prop',
    'v', 'archetype', 'outfit', 'roleHat', 'extra', 'stoop', 'shoulder', 'hem', 'skin'];

  const LOOK_ENUMS = {
    acc: ACCESSORIES.concat(['none']),
    body: BODIES.slice(),
    head: HEADS.slice(),
    hat: ['none', 'tophat', 'nightcap', 'bonnet', 'cap', 'hood'],
    hair: HAIRS.slice(),
    prop: ['none', 'cane', 'lantern', 'umbrella', 'basket'],
    outfit: ['plain', 'mail', 'robe', 'apron', 'smock', 'cloak'],
    roleHat: ['none', 'kettle', 'biretta'],
    extra: ['none', 'shovel', 'bundle', 'ledger', 'bow']
  };

  const LOOK_RANGES = {
    height: [0.5, 1.2], build: [0.7, 1.4], stride: [0.7, 1.4], nose: [0.5, 1.6],
    stoop: [0, 0.4], shoulder: [0.8, 1.25], hem: [0, 1], skin: [0, 1]
  };

  const LEGACY_RECIPE = {
    height: [0.9, 0.15], build: [0.9, 0.25], stride: [0.9, 0.25],
    bodies: BODIES.slice(), heads: HEADS.slice(), hairs: HAIRS.slice(),
    beardP: 0.3, nose: [0.7, 0.7], coatP: 0.45, acc: 'cycle'
  };

  function recipe(over) {
    const r = {};
    Object.keys(LEGACY_RECIPE).forEach(function (k) {
      const v = LEGACY_RECIPE[k];
      r[k] = Array.isArray(v) ? v.slice() : v;
    });
    Object.keys(over || {}).forEach(function (k) { r[k] = over[k]; });
    return r;
  }

  function ex(outfit, roleHat, extra, stoop, hem, shoulder) {
    return { outfit: outfit, roleHat: roleHat, extra: extra, stoop: stoop, shoulder: shoulder || [0.95, 0.1], hem: hem, skin: [0.35, 0.3] };
  }

  function arch(id, role, legacy, voice, talk, schedule, watch, feedable, gait, speed, rcp, extras, label) {
    return { id: id, role: role, label: label || id, legacy: legacy, voice: voice, talk: talk, schedule: schedule, watch: watch, feedable: feedable, gait: gait, speed: speed, recipe: rcp, extras: extras };
  }

  const list = [
    arch('patron', '', true, 'man', 'villager', null, false, true, 'walk', 1.0, recipe(), ex('plain', 'none', 'none', 0, 0), 'Patron'),
    arch('innkeeper', 'innkeeper', true, 'woman', 'innkeeper',
      [[['tavern_a'], 0.30, 'work'], [['tavern_b'], 0.45, 'work'], [['tavern_c'], 0.52, 'work'], [['@hearth'], 0.60, 'cook'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe(), ex('apron', 'none', 'none', 0, 0.6), 'Innkeeper'),
    arch('drunk', 'drunk', true, 'man', 'drunk',
      [[['tavern_c', 'tavern_b'], 0.26, 'drink'], [['square'], 0.32, 'sing'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe(), ex('plain', 'none', 'none', 0, 0), 'Drunk'),
    arch('regular', 'regular', true, 'man', 'innkeeper',
      [[['tavern_t'], 0.16, 'drink'], [['@table'], 0.50, 'eat'], [['@work'], 0.66, 'mend'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe(), ex('plain', 'none', 'none', 0, 0), 'Regular'),
    arch('priest', 'priest', true, 'elder', 'priest',
      [[['church_a'], 0.25, 'pray'], [['church_c'], 0.45, 'read'], [['church_b'], 0.58, 'pray'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe(), ex('robe', 'biretta', 'none', 0, 1, [1.05, 0.1]), 'Priest'),
    arch('elder', 'elder', true, 'elder', 'elder',
      [[['church_c'], 0.20, 'pray'], [['square'], 0.30, 'rest'], [['@hearth'], 0.54, 'sit'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe(), ex('plain', 'none', 'none', 0.25, 0.5), 'Elder'),
    arch('farmer', 'farmer', true, 'man', 'farmer',
      [[['barn_b'], 0.08, 'work'], [['barn'], 0.13, 'work'], [['well'], 0.20, 'draw water'], [['@hearth'], 0.30, 'cook'], [['@table'], 0.48, 'eat'], [['@work'], 0.62, 'mend'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe(), ex('smock', 'none', 'none', 0, 0.3), 'Farmer'),
    arch('mother', 'mother', true, 'woman', 'mother',
      [[['well'], 0.06, 'draw water'], [['@hearth'], 0.26, 'cook'], [['@table'], 0.48, 'eat'], [['@work'], 0.64, 'spin'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe(), ex('apron', 'none', 'bundle', 0, 0.8), 'Mother'),
    arch('insomniac', 'insomniac', true, 'man', 'villager',
      [[['lane_s'], 0.22, 'pace'], [['street_mid'], 0.40, 'pace'], [['well'], 0.56, 'sit'], [['@work'], 0.68, 'whittle'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe(), ex('plain', 'none', 'none', 0, 0), 'Insomniac'),
    arch('gravedigger', 'gravedigger', true, 'man', 'gravedigger',
      [[['grave'], 0.30, 'dig'], [['road_s'], 0.45, 'rest'], [['grave'], 0.66, 'dig'], [['@hearth'], 0.76, 'cook'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe(), ex('smock', 'none', 'shovel', 0.05, 0.2), 'Gravedigger'),
    arch('guard', 'guard', true, 'man', 'guard', 'watch', true, true, 'mail', 1.3, recipe(), ex('mail', 'kettle', 'none', 0, 0.3, [1.05, 0.1]), 'Guard'),
    arch('child', 'child', false, 'child', 'child',
      [[['@table'], 0.06, 'eat'], [['@hearth'], 0.14, 'play'], [['@bed'], 1, 'sleep']],
      false, false, 'walk', 1.0, recipe({ height: [0.58, 0.08], build: [0.85, 0.15], beardP: 0 }), ex('plain', 'none', 'none', 0, 0), 'Child'),
    arch('merchant', 'merchant', false, 'man', 'villager',
      [[['square'], 0.18, 'sell'], [['tavern_t'], 0.34, 'drink'], [['@bed'], 1, 'sleep']],
      false, true, 'walk', 1.0, recipe({ coatP: 0.9 }), ex('cloak', 'none', 'ledger', 0, 0.7), 'Merchant'),
    arch('hunter', 'hunter', false, 'man', 'guard', 'watch', true, true, 'walk', 1.3, recipe(), ex('cloak', 'none', 'bow', 0, 0.4), 'Hunter')
  ];

  const REINFORCE = [
    { fear: 6, archetype: 'guard', card: 'The watch is doubled' },
    { fear: 10, archetype: 'hunter', card: 'A hunter walks the lanes' }
  ];

  const byIdMap = Object.create(null);
  const byRoleMap = Object.create(null);
  list.forEach(function (a) { byIdMap[a.id] = a; byRoleMap[a.role] = a; });

  function byId(id) { return !bad(id) && hasOwn(byIdMap, id) ? byIdMap[id] : null; }
  function byRole(role) {
    return !bad(role) && hasOwn(byRoleMap, role) ? byRoleMap[role] : null;
  }

  const ArchetypeData = deepFreeze({ LOOK_KEYS: LOOK_KEYS, LOOK_ENUMS: LOOK_ENUMS, LOOK_RANGES: LOOK_RANGES, LEGACY_RECIPE: LEGACY_RECIPE, REINFORCE: REINFORCE, list: list, byId: byId, byRole: byRole });

  VCS.ArchetypeData = ArchetypeData;
  if (typeof module !== 'undefined' && module.exports) module.exports = ArchetypeData;
})(typeof window !== 'undefined' ? window : globalThis);
