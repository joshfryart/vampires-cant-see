(function (root) {
  'use strict';
  const VCS = (root.VCS = root.VCS || {});

  // Sound levels in one place. range in cells, strength 0..1 (visual), z = source height (floor 0, ceiling 1, eye 0.5), fade = seconds, gain 0..1 (audio), hearDist = audible cells.
  const SoundData = {
    levels: {
      step: { range: 1.1, strength: 0.3, z: 0, fade: 0.8, bounces: 0, gain: 0.08, interval: 0.48, footOffset: 0.15, footSide: 0.12 },
      personStep: { range: 0.4, strength: 0.25, z: 0, fade: 0.6, bounces: 0, gain: 0.12, hearDist: 9 },
      door: { range: 5, strength: 0.5, z: 0.5, fade: 2.5, bounces: 1, gain: 0.25, hearDist: 18 },
      interact: { range: 3, strength: 0.35, z: 0.3, fade: 1.8, bounces: 1, gain: 0.15 },
      ping: { range: null, strength: 1, z: 0.62, fade: null, bounces: 2, gain: null },
      scream: { range: 7, strength: 0.6, z: 0.85, fade: 2.2, bounces: 1, gain: 0.3, hearDist: 25 },
      startle: { range: 1.5, strength: 0.3, z: 0.8, fade: 1.0, bounces: 0, gain: 0.1, hearDist: 12 },
      creak: { range: 3, strength: 0.4, z: 0.5, fade: 1.5, bounces: 0, gain: 0.2, hearDist: 12 },
      chime: { range: 0, strength: 0, z: 0.9, fade: 1, bounces: 0, gain: 0.22 },
      heartbeat: { range: 2.2, strength: 0.45, z: 0.6, fade: 1.2, bounces: 0, gain: 0.25 },
      feed: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.15 },
      gulp: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.2 },
      struggle: { range: 2.8, strength: 0.4, z: 0.5, fade: 1.0, bounces: 0, gain: 0.16, hearDist: 10 },
      clatter: { range: 7, strength: 0.55, z: 0.05, fade: 1.6, bounces: 1, gain: 0.26, hearDist: 22 },
      scuffle: { range: 1.4, strength: 0.28, z: 0.1, fade: 0.7, bounces: 0, gain: 0.1, hearDist: 8 },
      gasp: { range: 4, strength: 0.4, z: 0.8, fade: 1.2, bounces: 0, gain: 0.2, hearDist: 12 },
      miss: { range: 0, strength: 0, z: 0.5, fade: 0.5, bounces: 0, gain: 0.12 },
      yawn: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.15 },
      shriek: { range: null, strength: 1, z: 0.6, fade: null, bounces: 2, gain: 0.35 },
      mist: { range: 0.8, strength: 0.2, z: 0.3, fade: 0.5, bounces: 0, gain: 0.12 },
      still: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.12 },
      gift: { range: 0, strength: 0, z: 0.6, fade: 1, bounces: 0, gain: 0.18 },
      whimper: { range: 2, strength: 0.25, z: 0.6, fade: 1, bounces: 0, gain: 0.1, hearDist: 6 },
      overflow: { range: 0, strength: 0, z: 0.5, fade: 0.4, bounces: 0, gain: 0.06 },
      // ambience beds (gain = level at level01 1, volume 1; wind stays under -30 dBFS) and far/near atmosphere
      wind: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.025 },
      room: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.02 },
      dog: { range: 0, strength: 0, z: 0.5, fade: 1, bounces: 0, gain: 0.2, hearDist: 60 },
      bell: { range: 0, strength: 0, z: 0.9, fade: 1, bounces: 0, gain: 0.3, hearDist: 80 },
      breath: { range: 0, strength: 0, z: 0.7, fade: 1, bounces: 0, gain: 0.05, hearDist: 6 }
    },
    // Villager step scaling (multipliers on the personStep row): gait x floor. Room (indoor/outdoor) scaling is applied on top by the game.
    stepScaleTable: {
      gait: {
        sneak: { range: 0.6, strength: 0.6, fade: 0.8, gain: 0.55 },
        walk: { range: 1, strength: 1, fade: 1, gain: 1 },
        run: { range: 1.8, strength: 1.6, fade: 1.2, gain: 1.8 }
      },
      floor: {
        grass: { range: 0.6, strength: 0.6, fade: 0.8, gain: 0.7 },
        wood: { range: 1, strength: 1, fade: 1, gain: 1 },
        stone: { range: 1.3, strength: 1.2, fade: 1.2, gain: 1.1 }
      }
    },
    rooms: {
      indoor: { rangeMul: 1, bounceCap: 2, fadeMul: 1 },
      outdoor: { rangeMul: 1.3, bounceCap: 1, fadeMul: 0.8 }
    },
    react: {
      startleDist: 3, seeDist: 8, seeCone: 2.0944, bumpDist: 1, fleeMul: 1.6, calmAfter: 10,
      screamGap: 2, startleTime: 1, arriveGrace: 1, lightSeen: 0.3, shriekMul: 2.5,
      bumpArc: 1.7453, bumpBackDist: 0.5, bumpFreeze: 0.4, waryTime: 20
    },
    reach: 1.3,
    reachArc: Math.PI / 3,
    maxBounceEchoes: 4
  };

  /**
   * Multipliers {range, strength, fade, gain} for one villager step from gait (sneak|walk|run), floor (grass|wood|stone)
   * and pace (stride speed / default, clamped 0.8..1.25: slow elders are quieter, brisk walkers louder). Unknown names act as walk / stone.
   */
  SoundData.stepScale = function (gait, floor, pace) {
    const g = SoundData.stepScaleTable.gait[gait] || SoundData.stepScaleTable.gait.walk;
    const f = SoundData.stepScaleTable.floor[floor] || SoundData.stepScaleTable.floor.stone;
    let k = typeof pace === 'number' && isFinite(pace) ? pace : 1;
    k = k < 0.8 ? 0.8 : k > 1.25 ? 1.25 : k;
    return { range: g.range * f.range * k, strength: g.strength * f.strength * k, fade: g.fade * f.fade, gain: g.gain * f.gain * k };
  };

  VCS.SoundData = SoundData;
  if (typeof module !== 'undefined' && module.exports) module.exports = SoundData;
})(typeof window !== 'undefined' ? window : globalThis);
