## Pure data: enums, definition tables, curves, constants. No engine imports.

import strutils

type
  CharacterKind* = enum
    Otto, Imma, Lina, Gino
  WeaponKind* = enum
    DragonSpear, ArcaneStaff, Longbow, WarAxe, Boomerang, Garlic, RoundShield
  Motion* = enum
    ## How a weapon's projectiles spawn and move (see systems.attackPlan, rules.moveProjectiles).
    Lunge,    ## stationary hitbox along the faced direction (Dragon Spear)
    Straight, ## flies in the faced direction (Longbow)
    Homing,   ## aimed at the nearest enemy (Arcane Staff)
    Arc,      ## thrown up, falls under gravity (War Axe)
    Return,   ## flies out, curves back to the player (Boomerang)
    Orbit,    ## circles the player (Round Shield)
    Aura      ## ring centred on the player (Garlic)
  BodyAnim* = enum
    ## LPC attack animation the player's body plays when their starter weapon fires.
    NoAnim, AnimThrust, AnimSlash, AnimShoot, AnimCast
  SheetId* = enum
    ## Batches flush in this order, so enemies come first and the survivors draw on top.
    ShZombie, ShSkeleton, ShMudman, ShGhost, ShReaper, ShBat, ShKoalio, ShParakeet,
    ShOtto, ShOttoAttack, ShImma, ShImmaAttack, ShLina, ShLinaAttack, ShGino, ShGinoAttack
  Sprite* = enum
    ## Icons in assets/items.png; manifest name = enum name without "Spr", lower-cased.
    SprSpear, SprBolt, SprArrow, SprAxe, SprBoomerang, SprShield, SprGarlic, SprAura, SprSpark,
    SprGemBlue, SprGemGreen, SprGemRed, SprCoin, SprChicken, SprChest, SprVacuum,
    SprSpinach, SprArmor, SprHollowHeart, SprPummarola, SprEmptyTome, SprWings, SprAttractorb
  PassiveKind* = enum
    Spinach, Armor, HollowHeart, Pummarola, EmptyTome, Wings, Attractorb
  EnemyKind* = enum
    Bat, Zombie, Skeleton, Mudman, Ghost, Parakeet, Koalio, Reaper
  PickupKind* = enum
    GemBlue, GemGreen, GemRed, Chicken, Coin, Chest, Vacuum
  Dir* = enum
    Up, Left, Down, Right ## LPC sheet row order
  Vec2* = tuple[x, y: float] ## one position fact per entity (see rules.nim)
  Rect* = tuple[x, y, w, h: int]

  Stats* = object
    might*, armor*, regen*, cooldownMul*, speedMul*, magnet*, area*, projSpeed*, duration*: float
    amount*: int

  CharacterDef* = object
    name*, perk*: string
    sheet*, attackSheet*: SheetId
    weapon*: WeaponKind
    maxHp*: float
    base*: Stats

  WeaponDef* = object
    name*, desc*: string
    cooldown*, damage*, speed*, ttl*, size*: float
    amount*, pierce*: int
    sprite*: Sprite
    uiSprite*: Sprite    ## HUD / level-up icon; the projectile sprite unless a weapon needs a clearer one
    motion*: Motion
    anim*: BodyAnim      ## body animation when this is the hero's starter weapon
    spin*: float         ## icon rotation speed, rad/s
    drawScale*: float    ## icon width = size * drawScale

  WeaponUpgrade* = object ## additive deltas applied when reaching that level
    damage*, cooldown*, size*, speed*, ttl*: float
    amount*, pierce*: int
    text*: string

  PassiveDef* = object
    name*, desc*: string
    sprite*: Sprite

  EnemyDef* = object
    hp*, speed*, damage*, size*: float
    gem*: PickupKind
    sheet*: SheetId
    boss*: bool

  SheetDef* = object
    file*: string
    cellW*, cellH*: int

  AnimDef* = object
    frames*: int
    secs*: float

  Wave* = object
    minute*: int
    kinds*: seq[EnemyKind]
    interval*: float
    minCount*: int

  BossSpawn* = object
    minute*: int
    kind*: EnemyKind
    count*: int

const
  maxWeaponLevel* = 8
  maxPassiveLevel* = 5
  maxWeaponSlots* = 6
  maxPassiveSlots* = 6
  maxEnemies* = 300
  maxPickups* = 400
  runLengthSecs* = 30 * 60
  zoom* = 1.0 ## world units per screen pixel
  playerBaseSpeed* = 160.0
  playerRadius* = 14.0
  pickupRadius* = 24.0
  baseMagnet* = 48.0
  gemFlySpeed* = 420.0
  axeGravity* = 900.0
  orbitRadius* = 90.0
  lungeHalfWidth* = 24.0       ## half-width of a Lunge hitbox across its direction
  boomerangAccel* = 300.0      ## px/s² pull toward the player for Return projectiles
  boomerangCatchRadius* = 20.0 ## a returning boomerang this close to the player is caught
  chickenHeal* = 30.0
  coinValue* = 10
  chestGoldFallback* = 50
  chickenChance* = 0.015
  coinChance* = 0.025
  vacuumChance* = 0.005
  hitFlashSecs* = 0.12
  despawnMargin* = 400.0
  spawnMargin* = 80.0
  clockScale* = when defined(fastclock): 10.0 else: 1.0

  # GLFW key codes (kept here so rules.nim stays free of glfw)
  KeyLeft* = 263
  KeyRight* = 262
  KeyDown* = 264
  KeyUp* = 265
  KeyEnter* = 257
  KeyEscape* = 256
  KeySpace* = 32
  KeyA* = 65
  KeyD* = 68
  KeyP* = 80
  KeyR* = 82
  KeyS* = 83
  KeyW* = 87
  Key1* = 49
  Key2* = 50
  Key3* = 51

  defaultStats* = Stats(might: 1.0, armor: 0.0, regen: 0.0, cooldownMul: 1.0, speedMul: 1.0,
                        magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)

  sheetDefs*: array[SheetId, SheetDef] = [
    ShZombie: SheetDef(file: "zombie.png", cellW: 64, cellH: 64),
    ShSkeleton: SheetDef(file: "skeleton.png", cellW: 64, cellH: 64),
    ShMudman: SheetDef(file: "mudman.png", cellW: 64, cellH: 64),
    ShGhost: SheetDef(file: "ghost.png", cellW: 64, cellH: 64),
    ShReaper: SheetDef(file: "reaper.png", cellW: 64, cellH: 64),
    ShBat: SheetDef(file: "bat.png", cellW: 32, cellH: 32),
    ShKoalio: SheetDef(file: "koalio.png", cellW: 18, cellH: 26),
    ShParakeet: SheetDef(file: "parakeet.png", cellW: 70, cellH: 100),
    ShOtto: SheetDef(file: "otto.png", cellW: 64, cellH: 64),
    ShOttoAttack: SheetDef(file: "otto_attack.png", cellW: 192, cellH: 192),
    ShImma: SheetDef(file: "imma.png", cellW: 64, cellH: 64),
    ShImmaAttack: SheetDef(file: "imma_attack.png", cellW: 64, cellH: 64),
    ShLina: SheetDef(file: "lina.png", cellW: 64, cellH: 64),
    ShLinaAttack: SheetDef(file: "lina_attack.png", cellW: 192, cellH: 192),
    ShGino: SheetDef(file: "gino.png", cellW: 64, cellH: 64),
    ShGinoAttack: SheetDef(file: "gino_attack.png", cellW: 64, cellH: 64),
  ]

  animDefs*: array[BodyAnim, AnimDef] = [
    NoAnim: AnimDef(frames: 1, secs: 0.0),
    AnimThrust: AnimDef(frames: 8, secs: 0.4),
    AnimSlash: AnimDef(frames: 6, secs: 0.3),
    AnimShoot: AnimDef(frames: 13, secs: 0.5),
    AnimCast: AnimDef(frames: 7, secs: 0.35),
  ]

  characterDefs*: array[CharacterKind, CharacterDef] = [
    Otto: CharacterDef(name: "Otto", perk: "+10% Might", sheet: ShOtto, attackSheet: ShOttoAttack, weapon: DragonSpear, maxHp: 120,
      base: Stats(might: 1.1, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)),
    Imma: CharacterDef(name: "Imma", perk: "-10% Cooldown", sheet: ShImma, attackSheet: ShImmaAttack, weapon: ArcaneStaff, maxHp: 100,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 0.9, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 0)),
    Lina: CharacterDef(name: "Lina", perk: "+20% Projectile speed", sheet: ShLina, attackSheet: ShLinaAttack, weapon: WarAxe, maxHp: 90,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.2, duration: 1.0, amount: 0)),
    Gino: CharacterDef(name: "Gino", perk: "+1 Projectile", sheet: ShGino, attackSheet: ShGinoAttack, weapon: Longbow, maxHp: 100,
      base: Stats(might: 1.0, armor: 0, regen: 0, cooldownMul: 1.0, speedMul: 1.0, magnet: 1.0, area: 1.0, projSpeed: 1.0, duration: 1.0, amount: 1)),
  ]

  weaponDefs*: array[WeaponKind, WeaponDef] = [
    DragonSpear: WeaponDef(name: "Dragon Spear", desc: "Lunges in the faced direction, passes through enemies",
      cooldown: 1.35, damage: 10, speed: 0, ttl: 0.15, size: 100, amount: 1, pierce: 999,
      sprite: SprSpear, uiSprite: SprSpear, motion: Lunge, anim: AnimThrust, spin: 0, drawScale: 1.0),
    ArcaneStaff: WeaponDef(name: "Arcane Staff", desc: "Fires at the nearest enemy",
      cooldown: 1.2, damage: 10, speed: 300, ttl: 2.5, size: 10, amount: 1, pierce: 0,
      sprite: SprBolt, uiSprite: SprBolt, motion: Homing, anim: AnimCast, spin: 0, drawScale: 3.5),
    Longbow: WeaponDef(name: "Longbow", desc: "Arrows fly in the faced direction",
      cooldown: 1.0, damage: 6.5, speed: 450, ttl: 1.5, size: 8, amount: 1, pierce: 1,
      sprite: SprArrow, uiSprite: SprArrow, motion: Straight, anim: AnimShoot, spin: 0, drawScale: 5.0),
    WarAxe: WeaponDef(name: "War Axe", desc: "High damage, arcs overhead",
      cooldown: 4.0, damage: 20, speed: 300, ttl: 2.5, size: 20, amount: 1, pierce: 3,
      sprite: SprAxe, uiSprite: SprAxe, motion: Arc, anim: AnimSlash, spin: 10, drawScale: 1.4),
    Boomerang: WeaponDef(name: "Boomerang", desc: "Flies out and comes back, hits both ways",
      cooldown: 3.0, damage: 10, speed: 320, ttl: 3.0, size: 10, amount: 1, pierce: 999,
      sprite: SprBoomerang, uiSprite: SprBoomerang, motion: Return, anim: NoAnim, spin: 12, drawScale: 1.6),
    Garlic: WeaponDef(name: "Garlic", desc: "Damages nearby enemies",
      cooldown: 1.3, damage: 5, speed: 0, ttl: 0.05, size: 80, amount: 1, pierce: 999,
      sprite: SprAura, uiSprite: SprGarlic, motion: Aura, anim: NoAnim, spin: 0, drawScale: 2.0),
    RoundShield: WeaponDef(name: "Round Shield", desc: "Orbits around the character",
      cooldown: 3.0, damage: 10, speed: 2.5, ttl: 3.0, size: 14, amount: 1, pierce: 999,
      sprite: SprShield, uiSprite: SprShield, motion: Orbit, anim: NoAnim, spin: 0, drawScale: 1.6),
  ]

  weaponUpgrades*: array[WeaponKind, array[2 .. maxWeaponLevel, WeaponUpgrade]] = [
    DragonSpear: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      4: WeaponUpgrade(damage: 5, size: 10, text: "Damage +5, area +10%"),
      5: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      6: WeaponUpgrade(damage: 5, size: 10, text: "Damage +5, area +10%"),
      7: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      8: WeaponUpgrade(damage: 5, text: "Base damage up by 5")],
    ArcaneStaff: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(cooldown: -0.2, text: "Cooldown reduced by 0.2s"),
      4: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      5: WeaponUpgrade(damage: 10, text: "Base damage up by 10"),
      6: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      7: WeaponUpgrade(pierce: 1, text: "Passes through 1 more enemy"),
      8: WeaponUpgrade(damage: 10, text: "Base damage up by 10")],
    Longbow: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      4: WeaponUpgrade(damage: 5, text: "Base damage up by 5"),
      5: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      6: WeaponUpgrade(pierce: 1, text: "Passes through 1 more enemy"),
      7: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      8: WeaponUpgrade(damage: 5, text: "Base damage up by 5")],
    WarAxe: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(damage: 20, text: "Base damage up by 20"),
      4: WeaponUpgrade(pierce: 2, text: "Passes through 2 more enemies"),
      5: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      6: WeaponUpgrade(damage: 20, text: "Base damage up by 20"),
      7: WeaponUpgrade(pierce: 2, text: "Passes through 2 more enemies"),
      8: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile")],
    Boomerang: [ # ttl bumps come before the speed bumps they pay for (see test_data)
      2: WeaponUpgrade(ttl: 0.5, text: "Lasts 0.5s longer"),
      3: WeaponUpgrade(speed: 50, damage: 5, text: "Speed +50, damage +5"),
      4: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      5: WeaponUpgrade(ttl: 0.3, text: "Lasts 0.3s longer"),
      6: WeaponUpgrade(speed: 50, damage: 5, text: "Speed +50, damage +5"),
      7: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      8: WeaponUpgrade(damage: 5, ttl: 0.3, text: "Damage +5, lasts 0.3s longer")],
    Garlic: [
      2: WeaponUpgrade(size: 20, damage: 2, text: "Area +20, damage +2"),
      3: WeaponUpgrade(cooldown: -0.1, damage: 1, text: "Faster pulse, damage +1"),
      4: WeaponUpgrade(size: 20, damage: 1, text: "Area +20, damage +1"),
      5: WeaponUpgrade(cooldown: -0.1, damage: 2, text: "Faster pulse, damage +2"),
      6: WeaponUpgrade(size: 20, damage: 1, text: "Area +20, damage +1"),
      7: WeaponUpgrade(cooldown: -0.1, damage: 1, text: "Faster pulse, damage +1"),
      8: WeaponUpgrade(size: 20, damage: 1, text: "Area +20, damage +1")],
    RoundShield: [
      2: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      3: WeaponUpgrade(speed: 0.3, size: 3, text: "Spins faster, bigger"),
      4: WeaponUpgrade(ttl: 0.5, text: "Lasts 0.5s longer"),
      5: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile"),
      6: WeaponUpgrade(speed: 0.3, size: 3, text: "Spins faster, bigger"),
      7: WeaponUpgrade(ttl: 0.5, text: "Lasts 0.5s longer"),
      8: WeaponUpgrade(amount: 1, text: "Fires 1 more projectile")],
  ]

  passiveDefs*: array[PassiveKind, PassiveDef] = [
    Spinach: PassiveDef(name: "Spinach", desc: "+10% damage per level", sprite: SprSpinach),
    Armor: PassiveDef(name: "Armor", desc: "-1 incoming damage per level", sprite: SprArmor),
    HollowHeart: PassiveDef(name: "Hollow Heart", desc: "+20% max health per level", sprite: SprHollowHeart),
    Pummarola: PassiveDef(name: "Pummarola", desc: "+0.2 HP/s regen per level", sprite: SprPummarola),
    EmptyTome: PassiveDef(name: "Empty Tome", desc: "-8% cooldown per level", sprite: SprEmptyTome),
    Wings: PassiveDef(name: "Wings", desc: "+10% move speed per level", sprite: SprWings),
    Attractorb: PassiveDef(name: "Attractorb", desc: "+50% pickup range per level", sprite: SprAttractorb),
  ]

  enemyDefs*: array[EnemyKind, EnemyDef] = [
    Bat: EnemyDef(hp: 1, speed: 90, damage: 3, size: 32, gem: GemBlue, sheet: ShBat, boss: false),
    Zombie: EnemyDef(hp: 3, speed: 55, damage: 4, size: 64, gem: GemBlue, sheet: ShZombie, boss: false),
    Skeleton: EnemyDef(hp: 8, speed: 70, damage: 5, size: 64, gem: GemGreen, sheet: ShSkeleton, boss: false),
    Mudman: EnemyDef(hp: 15, speed: 45, damage: 6, size: 64, gem: GemGreen, sheet: ShMudman, boss: false),
    Ghost: EnemyDef(hp: 20, speed: 80, damage: 6, size: 64, gem: GemGreen, sheet: ShGhost, boss: false),
    Parakeet: EnemyDef(hp: 150, speed: 100, damage: 12, size: 150, gem: GemRed, sheet: ShParakeet, boss: true),
    Koalio: EnemyDef(hp: 400, speed: 60, damage: 15, size: 104, gem: GemRed, sheet: ShKoalio, boss: true),
    Reaper: EnemyDef(hp: 65535, speed: 200, damage: 999, size: 192, gem: GemRed, sheet: ShReaper, boss: true),
  ]

  waves*: seq[Wave] = @[
    Wave(minute: 0, kinds: @[Bat], interval: 1.0, minCount: 10),
    Wave(minute: 1, kinds: @[Bat, Zombie], interval: 0.8, minCount: 20),
    Wave(minute: 3, kinds: @[Skeleton, Bat], interval: 0.6, minCount: 30),
    Wave(minute: 5, kinds: @[Zombie, Mudman], interval: 0.5, minCount: 40),
    Wave(minute: 8, kinds: @[Bat, Skeleton], interval: 0.4, minCount: 60),
    Wave(minute: 12, kinds: @[Ghost, Mudman], interval: 0.35, minCount: 80),
    Wave(minute: 16, kinds: @[Skeleton, Ghost, Bat], interval: 0.3, minCount: 100),
    Wave(minute: 20, kinds: @[Zombie, Skeleton, Mudman, Ghost], interval: 0.25, minCount: 140),
    Wave(minute: 25, kinds: @[Mudman, Ghost, Skeleton, Bat], interval: 0.2, minCount: 200),
    Wave(minute: 30, kinds: @[Ghost, Bat], interval: 0.2, minCount: 200),
  ]

  bosses*: seq[BossSpawn] = @[
    BossSpawn(minute: 3, kind: Parakeet, count: 1),
    BossSpawn(minute: 8, kind: Koalio, count: 1),
    BossSpawn(minute: 12, kind: Parakeet, count: 2),
    BossSpawn(minute: 15, kind: Koalio, count: 1),
    BossSpawn(minute: 20, kind: Parakeet, count: 2),
    BossSpawn(minute: 25, kind: Koalio, count: 2),
    BossSpawn(minute: 30, kind: Reaper, count: 1),
  ]

# ---------------------------------------------------------------- atlas (assets/items.txt)

proc spriteManifestName(s: Sprite): string =
  ## SprGemBlue -> "gemblue"
  toLowerAscii(($s)[3 .. ^1])

proc parseAtlas(manifest: string): tuple[size: (int, int), rects: array[Sprite, Rect]] =
  var seen: set[Sprite]
  for line in manifest.splitLines:
    let f = line.splitWhitespace
    if f.len == 0:
      continue
    if f[0] == "size":
      result.size = (parseInt(f[1]), parseInt(f[2]))
      continue
    doAssert f.len == 5, "bad items.txt line: " & line
    var found = false
    for s in Sprite:
      if spriteManifestName(s) == f[0]:
        result.rects[s] = (parseInt(f[1]), parseInt(f[2]), parseInt(f[3]), parseInt(f[4]))
        seen.incl s
        found = true
    doAssert found, "items.txt names an unknown sprite: " & f[0]
  for s in Sprite:
    doAssert s in seen, "sprite missing from items.txt: " & spriteManifestName(s) & " (run `nimble assets`)"

const
  atlasParsed = parseAtlas(staticRead("assets/items.txt"))
  atlasSize* = atlasParsed.size
  atlas* = atlasParsed.rects

proc pickupSprite*(kind: PickupKind): Sprite =
  case kind
  of GemBlue: SprGemBlue
  of GemGreen: SprGemGreen
  of GemRed: SprGemRed
  of Chicken: SprChicken
  of Coin: SprCoin
  of Chest: SprChest
  of Vacuum: SprVacuum

proc animActive*(anim: BodyAnim, start, now: float): bool =
  ## Compares against the end time rather than the elapsed time, so the
  ## animation ends exactly at `start + secs` in floating point.
  anim != NoAnim and now < start + animDefs[anim].secs

proc animFrame*(anim: BodyAnim, start, now: float): int =
  ## Column of the attack sheet for the elapsed time, clamped to the last frame.
  let a = animDefs[anim]
  if a.secs <= 0:
    return 0
  min(a.frames - 1, max(0, int((now - start) / a.secs * float(a.frames))))

proc weaponAt*(kind: WeaponKind, level: int): WeaponDef =
  ## Base definition plus every upgrade from level 2 up to `level`.
  result = weaponDefs[kind]
  for lvl in 2 .. min(level, maxWeaponLevel):
    let u = weaponUpgrades[kind][lvl]
    result.damage += u.damage
    result.cooldown += u.cooldown
    result.size += u.size
    result.speed += u.speed
    result.ttl += u.ttl
    result.amount += u.amount
    result.pierce += u.pierce

proc computeStats*(hero: CharacterKind, passives: openArray[(PassiveKind, int)]): Stats =
  result = characterDefs[hero].base
  for (kind, level) in passives:
    let l = float(level)
    case kind
    of Spinach: result.might += 0.1 * l
    of Armor: result.armor += 1.0 * l
    of HollowHeart: discard # handled by maxHpFor
    of Pummarola: result.regen += 0.2 * l
    of EmptyTome: result.cooldownMul *= (1.0 - 0.08 * l)
    of Wings: result.speedMul += 0.1 * l
    of Attractorb: result.magnet += 0.5 * l

proc maxHpFor*(hero: CharacterKind, passives: openArray[(PassiveKind, int)]): float =
  result = characterDefs[hero].maxHp
  for (kind, level) in passives:
    if kind == HollowHeart:
      result *= 1.0 + 0.2 * float(level)

proc hpScale*(minute: int): float =
  1.0 + 0.12 * float(minute)

proc waveFor*(minute: int): Wave =
  result = waves[0]
  for w in waves:
    if w.minute <= minute:
      result = w

proc xpForLevel*(level: int): int =
  ## XP needed to go from `level` to `level + 1` (Vampire Survivors curve).
  if level < 20:
    5 + 10 * (level - 1)
  elif level < 40:
    5 + 10 * 19 + 13 * (level - 20)
  else:
    5 + 10 * 19 + 13 * 20 + 16 * (level - 40)

proc gemValue*(kind: PickupKind): int =
  case kind
  of GemBlue: 1
  of GemGreen: 3
  of GemRed: 5
  else: 0

proc isGem*(kind: PickupKind): bool =
  kind in {GemBlue, GemGreen, GemRed}

proc clockText*(secs: float): string =
  let total = int(secs)
  align($(total div 60), 2, '0') & ":" & align($(total mod 60), 2, '0')
