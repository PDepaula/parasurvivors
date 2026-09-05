// Drives the touch controls in shell_minimal.html through the Chrome DevTools Protocol,
// on an emulated phone. Node 22+ only (global fetch and WebSocket, no dependencies).
//
//   nimble build -d:release -d:emscripten -d:noaudio
//   python3 -m http.server 8000 --directory web &
//   chromium --headless=new --disable-gpu --enable-unsafe-swiftshader \
//            --remote-debugging-port=9222 about:blank &
//   node tools/touch_test.js http://localhost:8000/
//
// Exits non-zero on the first failed check.

const URL = process.argv[2] || 'http://localhost:8000/';
const PORT = process.argv[3] || 9222;
const WIDTH = 740, HEIGHT = 360, DPR = 3; // a phone in landscape, 3x screen

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failures = 0;

function check(name, ok, detail) {
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name}${detail === undefined ? '' : `  (${detail})`}`);
  if (!ok) failures++;
}

async function connect() {
  const targets = await (await fetch(`http://localhost:${PORT}/json/list`)).json();
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => (ws.onopen = r));

  let id = 0;
  const pending = new Map();
  const consoleLines = [];
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    } else if (msg.method === 'Runtime.consoleAPICalled') {
      consoleLines.push(msg.params.args.map((a) => a.value).join(' '));
    }
  };
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const n = ++id;
      pending.set(n, (m) => (m.error ? reject(new Error(`${method}: ${m.error.message}`)) : resolve(m.result)));
      ws.send(JSON.stringify({ id: n, method, params }));
    });
  return { send, consoleLines };
}

// One finger: press, drag to the offset, hold, read, release.
async function swipe(send, dx, dy) {
  const x = WIDTH / 2, y = HEIGHT / 2;
  await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
  await send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x + dx, y: y + dy }] });
  await sleep(60);
  const held = await evaluate(send, 'JSON.stringify(window.__psHeld || [])');
  await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await sleep(60);
  return JSON.parse(held);
}

async function tap(send) {
  const x = WIDTH / 2, y = HEIGHT / 2;
  await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
  await sleep(40);
  await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await sleep(200);
}

async function evaluate(send, expr) {
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
  return r.result.value;
}

async function screenshot(send) {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  return Buffer.from(r.data, 'base64');
}

(async () => {
  const { send, consoleLines } = await connect();
  await send('Page.enable');
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', {
    width: WIDTH, height: HEIGHT, deviceScaleFactor: DPR, mobile: true,
  });
  await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
  await send('Page.navigate', { url: URL });

  for (let i = 0; i < 100 && !consoleLines.includes('module loaded'); i++) await sleep(200);
  check('wasm module loads', consoleLines.includes('module loaded'));
  await sleep(1500);

  // The shell caps devicePixelRatio at 2, so a 3x phone renders 740*2 wide.
  const fb = await evaluate(send, 'canvas.width + "x" + canvas.height');
  check('framebuffer is devicePixelRatio-scaled, capped at 2x', fb === `${WIDTH * 2}x${HEIGHT * 2}`, fb);

  const exported = await evaluate(send, 'typeof Module._psKeyDown + "," + typeof Module._psKeyUp');
  check('key entry points are exported from the wasm', exported === 'function,function', exported);

  // GLFW codes: 262 right, 263 left, 264 down, 265 up.
  const cases = [
    ['up', 0, -60, [265]],
    ['down', 0, 60, [264]],
    ['left', -60, 0, [263]],
    ['right', 60, 0, [262]],
    ['down-right', 50, 50, [262, 264]],
    ['up-left', -50, -50, [263, 265]],
    ['inside the deadzone holds nothing', 6, 6, []],
  ];
  for (const [name, dx, dy, want] of cases) {
    const got = await swipe(send, dx, dy);
    check(`stick ${name}`, JSON.stringify(got.sort()) === JSON.stringify(want.sort()), JSON.stringify(got));
  }

  const afterRelease = await evaluate(send, 'JSON.stringify(window.__psHeld || [])');
  check('lifting the finger releases every key', afterRelease === '[]', afterRelease);

  // Title -> character select -> running, by tapping. Then a drag has to move the world.
  await tap(send);
  await tap(send);
  await sleep(600);
  const before = await screenshot(send);
  await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: WIDTH / 2, y: HEIGHT / 2 }] });
  await send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: WIDTH / 2 + 70, y: HEIGHT / 2 }] });
  await sleep(1200);
  const after = await screenshot(send);
  await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  check('dragging moves the world', !before.equals(after), `${before.length} vs ${after.length} bytes`);

  require('fs').writeFileSync(process.env.SHOT || 'tmp/touch.png', after);
  console.log(`\nscreenshot: ${process.env.SHOT || 'tmp/touch.png'}`);
  console.log(failures === 0 ? 'all checks passed' : `${failures} check(s) failed`);
  process.exit(failures === 0 ? 0 : 1);
})();
