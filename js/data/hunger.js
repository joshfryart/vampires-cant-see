(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  function deepFreeze(o) {
    if (o && typeof o === 'object' && !Object.isFrozen(o)) {
      Object.freeze(o);
      Object.keys(o).forEach(function (k) { deepFreeze(o[k]); });
    }
    return o;
  }

  function power(id, name, icon, key, unlock, cost, cooldown, fear, desc, how, tip) {
    return { id: id, name: name, icon: icon, key: key, unlock: unlock, cost: cost, cooldown: cooldown, fear: fear, desc: desc, how: how, tip: tip };
  }
  function gift(id, name, icon, kind, effect, op, value, desc) {
    const g = { id: id, name: name, icon: icon, kind: kind, value: value, desc: desc };
    if (effect) { g.effect = effect; g.op = op; }
    return g;
  }

  const HungerData = {
    RAMP: 0.12,
    GIFT_COSTS: [40, 60],
    GIFTS_PER_NIGHT: 2,
    GIFT_ESSENCE: 2,
    FEAR_MAX: 15,
    FEAR: { grab: 1, sleep: -5 },
    FEAR_STARTLE: [0.04, 0.6],
    FEAR_FLEE: [0.015, 0.2],
    FEAR_CALM: [0.04, 0.6],
    powers: [
      power('shriek', 'Shriek', 'shriek', ['KeyQ'], 1, 15, 6, 2, 'A loud call that reaches twice as far',
        'A pulse that reaches twice as far; everyone within a wide radius startles and may flee, and Still does not hide it.',
        'Use it to map a big room or street at once, or to scatter a crowd so one person is left alone.'),
      power('mist', 'Mist', 'mist', ['ShiftLeft', 'ShiftRight'], 2, 10, 3, 1, 'Dash a short way, unheard',
        'A silent dash of 2 cells in the direction you move (or face): no footsteps, nobody notices a bump during it, and it stops at walls.',
        'Use it to slip past someone, cross open ground quickly, or escape a startled person.'),
      power('still', 'Still', 'still', ['KeyF'], 3, 10, 12, 1, 'Five quiet seconds, no one notices',
        'For 5 seconds your pulses, doors and steps startle no one, and bumping into people goes unnoticed.',
        'Use it to creep up on a target, or to pulse and open doors in a crowded place.')
    ],
    gifts: [
      gift('g_far', 'Keener Ear', 'ear', 'effect', 'sonarRange', 'mul', 1.05, 'Rings reach 5% further'),
      gift('g_fade', 'Longer Echo', 'hourglass', 'effect', 'sonarFade', 'mul', 1.05, 'Rings fade 5% slower'),
      gift('g_quick', 'Quicker Call', 'bat', 'effect', 'sonarCooldown', 'mul', 0.95, 'Call again 5% sooner'),
      gift('g_thirst', 'Slower Thirst', 'drop', 'effect', 'drain', 'mul', 0.95, 'Blood drains 5% slower'),
      gift('g_draw', 'Deeper Draw', 'fang', 'effect', 'drinkRate', 'mul', 1.08, 'Drink 8% faster'),
      gift('g_quiet', 'Quieter', 'paw', 'effect', 'noise', 'mul', 0.95, 'Sounds startle 5% less far'),
      gift('g_calm', 'Calm Town', 'eye', 'fear', null, null, -2, 'The town is less jumpy'),
      gift('g_reserve', 'Reserve', 'vial', 'nextBlood', null, null, 10, 'Start next night with 10 more blood')
    ]
  };

  deepFreeze(HungerData);
  VCS.HungerData = HungerData;
  if (typeof module !== 'undefined' && module.exports) module.exports = HungerData;
})(typeof window !== 'undefined' ? window : globalThis);
