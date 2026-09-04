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

proc mainLoop() =
  let ts = glfwGetTime()
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
