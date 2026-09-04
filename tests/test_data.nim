import unittest
import data

suite "data":
  test "xp curve matches VS shape":
    check xpForLevel(1) == 5
    check xpForLevel(2) == 15
    check xpForLevel(19) == 185
    check xpForLevel(20) == 195
    check xpForLevel(21) == 208
    check xpForLevel(40) == 455
    check xpForLevel(41) == 471

  test "every weapon has upgrades for levels 2..8 and grows":
    for k in WeaponKind:
      let base = weaponAt(k, 1)
      let top = weaponAt(k, maxWeaponLevel)
      check top.damage + float(top.amount) + top.size + top.speed + top.ttl > base.damage + float(base.amount) + base.size + base.speed + base.ttl
      for lvl in 2 .. maxWeaponLevel:
        check weaponUpgrades[k][lvl].text.len > 0

  test "weaponAt is cumulative":
    check weaponAt(Whip, 2).amount == 2
    check weaponAt(Whip, 3).damage == 15.0
    check weaponAt(MagicWand, 3).cooldown < weaponAt(MagicWand, 1).cooldown

  test "passives change stats":
    let none = computeStats(Otto, [])
    check none.might == 1.1
    let spinach = computeStats(Otto, [(Spinach, 2)])
    check abs(spinach.might - 1.3) < 1e-9
    let tome = computeStats(Imma, [(EmptyTome, 1)])
    check tome.cooldownMul < computeStats(Imma, []).cooldownMul
    check maxHpFor(Otto, [(HollowHeart, 1)]) == 144.0

  test "waves cover the whole run":
    check waveFor(0).minute == 0
    check waveFor(2).minute == 1
    check waveFor(31).minute == 30
    for w in waves:
      check w.kinds.len > 0
      check w.interval > 0

  test "bosses are unique per minute and kind":
    var seen: seq[(int, EnemyKind)]
    for b in bosses:
      check (b.minute, b.kind) notin seen
      seen.add (b.minute, b.kind)

  test "clock text":
    check clockText(0) == "00:00"
    check clockText(65) == "01:05"
    check clockText(1800) == "30:00"
