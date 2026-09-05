import unittest
import data

proc pngSize(path: string): (int, int) =
  ## Width/height from the IHDR chunk; tests run from the repo root.
  let s = readFile(path)
  doAssert s.len > 24 and s[1 .. 3] == "PNG", path & " is not a PNG"
  proc be(i: int): int =
    (int(s[i].uint8) shl 24) or (int(s[i + 1].uint8) shl 16) or (int(s[i + 2].uint8) shl 8) or int(s[i + 3].uint8)
  (be(16), be(20))

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
    check weaponAt(DragonSpear, 2).amount == 2
    check weaponAt(DragonSpear, 3).damage == 15.0
    check weaponAt(ArcaneStaff, 3).cooldown < weaponAt(ArcaneStaff, 1).cooldown

  test "a boomerang always comes back before its ttl runs out":
    # round trip under constant pull = 2*v/a; must fit the ttl at every level,
    # including Lina's +20% projectile speed
    for lvl in 1 .. maxWeaponLevel:
      let w = weaponAt(Boomerang, lvl)
      for projSpeed in [1.0, 1.2]:
        check 2 * w.speed * projSpeed / boomerangAccel <= w.ttl * 0.9 # slack for a retreating player

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

  test "weapon names and starters follow the LPC art":
    check weaponDefs[DragonSpear].name == "Dragon Spear"
    check weaponDefs[ArcaneStaff].name == "Arcane Staff"
    check weaponDefs[Longbow].name == "Longbow"
    check weaponDefs[WarAxe].name == "War Axe"
    check weaponDefs[Boomerang].name == "Boomerang"
    check weaponDefs[RoundShield].name == "Round Shield"
    check characterDefs[Lina].weapon == WarAxe
    check characterDefs[Otto].weapon == DragonSpear
    check weaponDefs[DragonSpear].motion == Lunge
    check weaponDefs[Boomerang].motion == Return
    for k in WeaponKind:
      check weaponDefs[k].drawScale > 0

  test "starter weapons have a body animation, others none":
    for c in CharacterKind:
      check weaponDefs[characterDefs[c].weapon].anim != NoAnim
    check weaponDefs[Boomerang].anim == NoAnim
    check weaponDefs[RoundShield].anim == NoAnim
    check weaponDefs[Garlic].anim == NoAnim

  test "atlas rects lie inside the atlas image":
    let (aw, ah) = atlasSize
    check pngSize("src/assets/items.png") == (aw, ah)
    for s in Sprite:
      let r = atlas[s]
      check r.w > 0 and r.h > 0
      check r.x >= 0 and r.y >= 0
      check r.x + r.w <= aw
      check r.y + r.h <= ah
    for k in PassiveKind:
      check atlas[passiveDefs[k].sprite].w > 0
    for k in WeaponKind:
      check atlas[weaponDefs[k].sprite].w > 0 and atlas[weaponDefs[k].uiSprite].w > 0
    check weaponDefs[Garlic].uiSprite == SprGarlic
    check pickupSprite(GemBlue) == SprGemBlue
    check pickupSprite(Chest) == SprChest

  test "sheets exist and attack sheets match their animation":
    for id in SheetId:
      let (w, h) = pngSize("src/assets/" & sheetDefs[id].file)
      check w >= sheetDefs[id].cellW
      check h >= sheetDefs[id].cellH
    for c in CharacterKind:
      let d = characterDefs[c]
      let a = animDefs[weaponDefs[d.weapon].anim]
      let sh = sheetDefs[d.attackSheet]
      check pngSize("src/assets/" & sh.file) == (a.frames * sh.cellW, 4 * sh.cellH)
      check pngSize("src/assets/" & sheetDefs[d.sheet].file) == (9 * 64, 4 * 64)

  test "animation timing":
    check not animActive(NoAnim, 0.0, 0.0)
    check animActive(AnimThrust, 1.0, 1.1)
    check not animActive(AnimThrust, 1.0, 1.0 + animDefs[AnimThrust].secs)
    check animFrame(AnimThrust, 1.0, 1.0) == 0
    check animFrame(AnimThrust, 1.0, 1.0 + animDefs[AnimThrust].secs * 0.99) == animDefs[AnimThrust].frames - 1
    check animFrame(AnimThrust, 1.0, 5.0) == animDefs[AnimThrust].frames - 1
