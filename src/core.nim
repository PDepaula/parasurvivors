import paranim/opengl
import paranim/gl
import pararules
import sets, random
when not defined(emscripten):
  import times
import data, systems, rules, render, audio

type
  Game* = object of RootGame
    deltaTime*: float
    totalTime*: float

proc onKeyPress*(key: int) =
  var (keys) = session.query(gameRules.getKeys)
  keys.incl(key)
  session.insert(Global, PressedKeys, keys)
  var (just) = session.query(gameRules.getJustPressed)
  just.incl(key)
  session.insert(Global, JustPressed, just)

proc onKeyRelease*(key: int) =
  var (keys) = session.query(gameRules.getKeys)
  keys.excl(key)
  session.insert(Global, PressedKeys, keys)

proc onWindowResize*(windowWidth, windowHeight, worldWidth, worldHeight: int) =
  if windowWidth == 0 or windowHeight == 0:
    return
  session.insert(Global, WindowWidth, windowWidth)
  session.insert(Global, WindowHeight, windowHeight)
  session.insert(Global, WorldWidth, float(worldWidth) / zoom)
  session.insert(Global, WorldHeight, float(worldHeight) / zoom)

when defined(emscripten):
  # gettimeofday (what epochTime uses) is backed by Date.now() under emscripten, so it
  # quantises to 1 ms and the overlay's sim time reads 0/1/2. performance.now() does not.
  proc emscripten_get_now(): float64 {.importc.}
  proc nowSecs(): float = emscripten_get_now() / 1000.0
else:
  proc nowSecs(): float = epochTime()

proc init*(game: var Game) =
  doAssert glInit()
  randomize()
  initRender(game)
  initAudio()

var musicOn = false

proc pressed(just: HashSet[int], keys: varargs[int]): bool =
  for k in keys:
    if just.contains(k):
      return true
  false

proc moveSelection(just: HashSet[int], count: int) =
  let m = session.query(gameRules.getMenu)
  var sel = m.selected
  if just.pressed(KeyUp, KeyW): sel = (sel + count - 1) mod count
  if just.pressed(KeyDown, KeyS): sel = (sel + 1) mod count
  if sel != m.selected:
    session.insert(Global, SelectedIndex, sel)

proc finishChoice(index: int) =
  let m = session.query(gameRules.getMenu)
  if m.choices == nil or index >= m.choices[].len:
    return
  session.applyChoice(m.choices[][index])
  let pending = m.pending - 1
  session.insert(Global, PendingLevelUps, pending)
  if pending > 0:
    session.prepareChoices()
  else:
    session.insert(Global, Phase, Running)

proc tick*(game: var Game) =
  let tickStart = nowSecs()
  session.insert(Global, TotalTime, game.totalTime)
  let (phase) = session.query(gameRules.getPhase)
  let (just) = session.query(gameRules.getJustPressed)
  if just.pressed(KeyF3):
    toggleStats()
  case phase
  of Title:
    when defined(autoplay): # test aid: skip the menus (nim c -d:autoplay -d:fastclock ...)
      session.startRun(Otto)
      startMusic()
      musicOn = true
    else:
      if just.pressed(KeyEnter, KeySpace):
        session.insert(Global, SelectedIndex, 0)
        session.insert(Global, Phase, CharSelect)
  of CharSelect:
    moveSelection(just, 4)
    if just.pressed(KeyEnter, KeySpace):
      let m = session.query(gameRules.getMenu)
      session.startRun(CharacterKind(m.selected))
      startMusic()
      musicOn = true
  of Running:
    if just.pressed(KeyEscape, KeyP):
      session.insert(Global, Phase, Paused)
    else:
      session.insert(Global, DeltaTime, game.deltaTime)
      session.fireRules()
      let ev = session.stepSystems(game.deltaTime)
      when defined(autoplay): # test aid: immortal, so a fastclock run reaches the late waves
        session.insert(Player, Hp, session.query(gameRules.getPlayer).maxHp)
      session.fireRules()
      if ev.hits > 0: play(SfxHit)
      if ev.gems > 0: play(SfxGem)
      if ev.hurt: play(SfxHurt)
      if ev.chest: play(SfxChest)
      if ev.bossKilled: play(SfxBoss)
      let m = session.query(gameRules.getMenu)
      if m.pending > 0:
        session.prepareChoices()
        session.insert(Global, Phase, LevelUp)
        play(SfxLevelUp)
  of LevelUp:
    moveSelection(just, 3)
    when defined(autoplay):
      finishChoice(0)
    else:
      if just.pressed(Key1): finishChoice(0)
      elif just.pressed(Key2): finishChoice(1)
      elif just.pressed(Key3): finishChoice(2)
      elif just.pressed(KeyEnter, KeySpace): finishChoice(session.query(gameRules.getMenu).selected)
  of Paused:
    if just.pressed(KeyEscape, KeyP):
      session.insert(Global, Phase, Running)
  of GameOver:
    if musicOn:
      stopMusic()
      musicOn = false
    if just.pressed(KeyR, KeyEnter):
      session = session.resetSession()
      session.insert(Global, Phase, CharSelect)
  when defined(perf):
    let (tt, gameTime) = session.query(gameRules.getTime)
    if int(gameTime) mod 5 == 0 and game.deltaTime > 0:
      let work = (nowSecs() - tickStart) * 1000
      echo "t=", clockText(gameTime), " dt=", game.deltaTime * 1000, "ms work=", work, "ms enemies=", session.query(gameRules.getTargeting).enemyCount
  session.insert(Global, JustPressed, initHashSet[int]())
  # Timed before drawFrame, so "sim" is the tick's own work, not the draw.
  recordStats(game.deltaTime, nowSecs() - tickStart,
              session.query(gameRules.getTargeting).enemyCount)
  drawFrame(game)
