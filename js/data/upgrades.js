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

  const COSTS = [5, 12, 25];
  function up(id, name, icon, effect, op, tiers, desc) {
    return { id: id, name: name, icon: icon, effect: effect, op: op, tiers: tiers, costs: COSTS.slice(), desc: desc };
  }
  function boon(id, name, icon, effect, op, value, repeat, desc) {
    return { id: id, name: name, icon: icon, effect: effect, op: op, value: value, repeat: repeat, desc: desc };
  }

  const UpgradeData = {
    EFFECT_DEFAULTS: {
      sonarRange: 1, sonarFade: 1, sonarCooldown: 1, startBlood: 0, drain: 1,
      drinkRate: 1, noise: 1, nightLen: 1, warmRadius: 0
    },
    EFFECT_LIMITS: {
      sonarRange: [0.5, 2.5], sonarFade: [0.5, 2.5], sonarCooldown: [0.5, 1.5], startBlood: [0, 40],
      drain: [0.4, 1.5], drinkRate: [0.5, 2.5], noise: [0.3, 1.5], nightLen: [0.5, 2], warmRadius: [0, 10]
    },
    upgrades: [
      up('far_echo', 'Far Echo', 'ear', 'sonarRange', 'mul', [1.15, 1.3, 1.45],
        ['Rings reach 15% further', 'Rings reach 30% further', 'Rings reach 45% further']),
      up('lingering_echo', 'Lingering Echo', 'hourglass', 'sonarFade', 'mul', [1.2, 1.4, 1.6],
        ['Rings fade 20% slower', 'Rings fade 40% slower', 'Rings fade 60% slower']),
      up('quick_call', 'Quick Call', 'bat', 'sonarCooldown', 'mul', [0.9, 0.8, 0.7],
        ['Call again 10% sooner', 'Call again 20% sooner', 'Call again 30% sooner']),
      up('full_veins', 'Full Veins', 'vial', 'startBlood', 'add', [10, 20, 30],
        ['Start each run with 10 more blood', 'Start each run with 20 more blood', 'Start each run with 30 more blood']),
      up('slow_thirst', 'Slow Thirst', 'drop', 'drain', 'mul', [0.9, 0.8, 0.7],
        ['Blood drains 10% slower', 'Blood drains 20% slower', 'Blood drains 30% slower']),
      up('deep_draw', 'Deep Draw', 'fang', 'drinkRate', 'mul', [1.15, 1.3, 1.45],
        ['Drink 15% faster', 'Drink 30% faster', 'Drink 45% faster']),
      up('soft_step', 'Soft Step', 'paw', 'noise', 'mul', [0.85, 0.7, 0.55],
        ['Sounds startle 15% less far', 'Sounds startle 30% less far', 'Sounds startle 45% less far']),
      up('long_night', 'Long Night', 'moon', 'nightLen', 'mul', [1.1, 1.2, 1.3],
        ['Nights last 10% longer', 'Nights last 20% longer', 'Nights last 30% longer']),
      up('warm_sense', 'Warm Sense', 'heart', 'warmRadius', 'add', [3, 5, 7],
        ['Feel warmth 3 cells away', 'Feel warmth 5 cells away', 'Feel warmth 7 cells away'])
    ],
    boons: [
      boon('bats_ear', "Bat's Ear", 'ear', 'sonarRange', 'mul', 1.1, false, 'Rings reach 10% further'),
      boon('echo_memory', 'Echo Memory', 'hourglass', 'sonarFade', 'mul', 1.15, false, 'Rings fade 15% slower'),
      boon('quick_ping', 'Quick Ping', 'bat', 'sonarCooldown', 'mul', 0.9, false, 'Call again 10% sooner'),
      boon('cold_blood', 'Cold Blood', 'drop', 'drain', 'mul', 0.85, false, 'Blood drains 15% slower'),
      boon('fast_fangs', 'Fast Fangs', 'fang', 'drinkRate', 'mul', 1.2, false, 'Drink 20% faster'),
      boon('hush', 'Hush', 'paw', 'noise', 'mul', 0.8, false, 'Sounds startle 20% less far'),
      boon('moonlit', 'Moonlit', 'moon', 'nightLen', 'mul', 1.1, false, 'Nights last 10% longer'),
      boon('warm_hint', 'Warm Hint', 'heart', 'warmRadius', 'add', 2, false, 'Feel warmth 2 cells away'),
      boon('full_belly', 'Full Belly', 'vial', 'bloodNow', 'add', 25, true, 'Gain 25 blood right now')
    ]
  };

  deepFreeze(UpgradeData);
  VCS.UpgradeData = UpgradeData;
  if (typeof module !== 'undefined' && module.exports) module.exports = UpgradeData;
})(typeof window !== 'undefined' ? window : globalThis);
