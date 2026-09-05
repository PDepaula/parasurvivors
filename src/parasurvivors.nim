import paranim/glfw
import core

proc keyCallback(window: GLFWWindow, key: int32, scancode: int32, action: int32, mods: int32) {.cdecl.} =
  if action == GLFW_PRESS:
    onKeyPress(key)
  elif action == GLFW_RELEASE:
    onKeyRelease(key)

var density: int

proc frameSizeCallback(window: GLFWWindow, width: int32, height: int32) {.cdecl.} =
  onWindowResize(width, height, int(width / density), int(height / density))

var
  game: Game
  window: GLFWWindow

when defined(keyscript):
  # test aid: scripted input for screenshots/demos (nim c -d:keyscript ...).
  # PS_KEYS="1:enter,2:down,3:enter,3.2:d:2.5" = press at 1s, ..., hold `d` from 3.2s for 2.5s.
  import os, strutils, tables
  import data
  const keyNames = {"enter": KeyEnter, "space": KeySpace, "esc": KeyEscape, "up": KeyUp, "down": KeyDown,
                    "left": KeyLeft, "right": KeyRight, "w": KeyW, "a": KeyA, "s": KeyS, "d": KeyD,
                    "p": KeyP, "r": KeyR, "1": Key1, "2": Key2, "3": Key3}.toTable
  type ScriptedKey = object
    key: int
    at, until: float
    pressed, released: bool
  var script: seq[ScriptedKey]
  for item in getEnv("PS_KEYS").split(','):
    let parts = item.strip.split(':')
    if parts.len < 2: continue
    let at = parseFloat(parts[0])
    let hold = if parts.len > 2: parseFloat(parts[2]) else: 0.05
    script.add ScriptedKey(key: keyNames[parts[1].toLowerAscii], at: at, until: at + hold)

  proc runScript(ts: float) =
    for k in script.mitems:
      if not k.pressed and ts >= k.at:
        k.pressed = true
        onKeyPress(k.key)
      if k.pressed and not k.released and ts >= k.until:
        k.released = true
        onKeyRelease(k.key)

proc mainLoop() =
  let ts = glfwGetTime()
  when defined(keyscript):
    runScript(ts)
  game.deltaTime = min(ts - game.totalTime, 0.1) # never simulate a huge step after a stall
  game.totalTime = ts
  game.tick()
  window.swapBuffers()
  glfwPollEvents()

when isMainModule:
  doAssert glfwInit()

  glfwWindowHint(GLFWContextVersionMajor, 3)
  glfwWindowHint(GLFWContextVersionMinor, 3)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE) # Used for Mac
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
  glfwWindowHint(GLFWResizable, GLFW_TRUE)

  window = glfwCreateWindow(1024, 768, "Parasurvivors")
  if window == nil:
    quit(-1)

  window.makeContextCurrent()
  glfwSwapInterval(1)

  discard window.setKeyCallback(keyCallback)
  discard window.setFramebufferSizeCallback(frameSizeCallback)

  var width, height: int32
  window.getFramebufferSize(width.addr, height.addr)

  var windowWidth, windowHeight: int32
  window.getWindowSize(windowWidth.addr, windowHeight.addr)

  density = max(1, int(width / windowWidth))
  window.frameSizeCallback(width, height)

  game.init()
  game.totalTime = glfwGetTime()

  while not window.windowShouldClose:
    mainLoop()

  window.destroyWindow()
  glfwTerminate()
