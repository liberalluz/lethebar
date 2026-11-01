// Drive an already-running headless Chrome over the DevTools protocol.
//
// Usage: node cdp_probe.mjs <ws-endpoint> <url> [reloads]
//
// Prints one JSON object: page title, canvas count, whether localStorage
// round-trips, how long the first screen took to settle (one sample per reload),
// recent console lines and uncaught exceptions. Exit code 0 when every run
// loaded with no uncaught exception and no dialog, 1 otherwise.
//
// The browser is started and stopped by infra/verify_web.py, so this file never
// spawns a process; Node 22 ships a global WebSocket, so no package is needed.
//
// "Settled" means two screenshots 200 ms apart hash the same: the boot splash is
// gone and the shell has drawn its first screen. It is a proxy for REQ-008 —
// a real click is not simulated, so the measured span is load → first screen,
// not click → first scene. The gap is recorded in the batch exit record.

import { createHash } from "node:crypto";

const [endpoint, url, reloadsArg] = process.argv.slice(2);
const reloads = Math.max(1, Number(reloadsArg ?? 1));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const socket = new WebSocket(endpoint);
let nextId = 1;
const pending = new Map();
const consoleLines = [];
const exceptions = [];
const dialogs = [];

socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
    return;
  }
  if (message.method === "Runtime.consoleAPICalled") {
    const text = (message.params.args || [])
      .map((arg) => arg.value ?? arg.description ?? arg.type)
      .join(" ");
    consoleLines.push(`${message.params.type}: ${text}`);
  }
  if (message.method === "Runtime.exceptionThrown") {
    const detail = message.params.exceptionDetails;
    exceptions.push(detail.exception?.description || detail.text);
  }
  if (message.method === "Log.entryAdded" && message.params.entry.level === "error") {
    consoleLines.push(`log: ${message.params.entry.text}`);
  }
  if (message.method === "Page.javascriptDialogOpening") {
    // A modal dialog blocks the renderer, so every later command would hang.
    dialogs.push(`${message.params.type}: ${message.params.message}`);
    socket.send(
      JSON.stringify({
        id: nextId++,
        method: "Page.handleJavaScriptDialog",
        params: { accept: true },
        sessionId: message.sessionId,
      }),
    );
  }
});

const trace = (message) => process.stderr.write(`[probe] ${message}\n`);

function send(method, params = {}, sessionId) {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`${method} did not answer within 15 s`));
    }, 15000);
    pending.set(id, {
      resolve: (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      reject: (error) => {
        clearTimeout(timer);
        reject(error);
      },
    });
    socket.send(JSON.stringify({ id, method, params, sessionId }));
  });
}

// A hung probe is worse than a failed one: it leaves a browser and a port behind.
const watchdog = setTimeout(() => {
  console.log(JSON.stringify({ ok: false, error: "probe timed out after 120 s" }));
  process.exit(1);
}, 120000);
watchdog.unref();

const connected = await new Promise((resolve) => {
  socket.addEventListener("open", () => resolve(true), { once: true });
  socket.addEventListener("error", () => resolve(false), { once: true });
});
if (!connected) {
  console.log(JSON.stringify({ ok: false, error: "cannot open the DevTools socket" }));
  process.exit(1);
}

trace("creating a target");
const { targetId } = await send("Target.createTarget", { url: "about:blank" });
trace(`attaching to ${targetId}`);
const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
const onSession = (method, params = {}) => send(method, params, sessionId);

await onSession("Runtime.enable");
await onSession("Log.enable");
await onSession("Page.enable");

let loaded = false;
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.method === "Page.loadEventFired") loaded = true;
});

async function evaluate(expression) {
  const { result } = await onSession("Runtime.evaluate", {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  return result.value;
}

async function frameHash() {
  const { data } = await onSession("Page.captureScreenshot", { format: "jpeg", quality: 20 });
  return createHash("sha1").update(data).digest("hex").slice(0, 12);
}

async function settle() {
  // Two identical frames 200 ms apart mean the splash is gone and the shell has
  // drawn its first screen; the clock stops at the second one.
  let previous = "";
  let stable = 0;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const hash = await frameHash();
    stable = hash === previous ? stable + 1 : 0;
    previous = hash;
    if (stable >= 2) return Math.round(await evaluate("performance.now()"));
    await sleep(200);
  }
  return null;
}

const bootSamples = [];
for (let run = 0; run < reloads; run += 1) {
  loaded = false;
  await onSession("Page.navigate", { url });
  for (let attempt = 0; attempt < 80 && !loaded; attempt += 1) await sleep(250);
  const settled = loaded ? await settle() : null;
  if (settled !== null) bootSamples.push(settled);
  trace(`run ${run + 1}/${reloads}: ${settled === null ? "no settled frame" : `${settled} ms`}`);
}

const title = await evaluate("document.title");
const canvases = await evaluate("document.querySelectorAll('canvas').length");

// --- scripted click ---------------------------------------------------------
// The scene is one canvas: button labels are pixels, so the probe cannot ask
// the DOM where "New game" is. It pokes the centre column instead — every button
// spans the full content width — and stops as soon as the shell reports a new
// screen through `window.lethebarScreen`. A hit is a hit only if the screen
// changed; a miss costs one more click and changes nothing.

async function screenName() {
  return await evaluate("window.lethebarScreen || null");
}

async function clickAt(x, y) {
  await onSession("Input.dispatchMouseEvent", {
    type: "mousePressed",
    x,
    y,
    button: "left",
    buttons: 1,
    clickCount: 1,
  });
  await onSession("Input.dispatchMouseEvent", {
    type: "mouseReleased",
    x,
    y,
    button: "left",
    buttons: 0,
    clickCount: 1,
  });
}

async function pokeUntil(target, limit) {
  // `limit` is the number of vertical steps tried, not a timeout: the loop is
  // bounded so a broken build fails fast instead of poking for a minute.
  const size = await evaluate("[window.innerWidth, window.innerHeight]");
  const x = Math.round(size[0] / 2);
  let clicks = 0;
  for (let y = 60; y < size[1] - 40; y += 24) {
    await clickAt(x, y);
    clicks += 1;
    await sleep(150);
    const screen = await screenName();
    if (screen === target) return { found: true, clicks };
    if (clicks >= limit) break;
  }
  return { found: false, clicks };
}

const landingScreen = await screenName();
const clickStarted = Math.round(await evaluate("performance.now()"));
let clickToSceneMs = null;
let interaction = { landing: landingScreen, plugins: { found: false, clicks: 0 }, session: { found: false, clicks: 0 } };

if (landingScreen === "landing") {
  interaction.plugins = await pokeUntil("plugins", 24);
  if (interaction.plugins.found) {
    interaction.session = await pokeUntil("session", 12);
    if (interaction.session.found) {
      clickToSceneMs = Math.round((await evaluate("performance.now()")) - clickStarted);
    }
  }
}
trace(`interaction: ${JSON.stringify(interaction)} in ${clickToSceneMs} ms`);

const storage = await evaluate(`(() => {
  try {
    localStorage.setItem("lethebar-probe", "ok");
    const value = localStorage.getItem("lethebar-probe");
    localStorage.removeItem("lethebar-probe");
    return value === "ok";
  } catch (error) {
    return String(error);
  }
})()`);

const sorted = [...bootSamples].sort((left, right) => left - right);
const bootMedianMs = sorted.length ? sorted[Math.floor(sorted.length / 2)] : null;

const interacted = interaction.plugins.found && interaction.session.found;

const ok =
  loaded &&
  typeof title === "string" &&
  title.length > 0 &&
  exceptions.length === 0 &&
  dialogs.length === 0 &&
  bootSamples.length === reloads &&
  interacted;

console.log(
  JSON.stringify(
    {
      ok,
      loaded,
      title,
      canvases,
      storageWorks: storage === true,
      storageDetail: storage,
      bootSamples,
      bootMedianMs,
      interaction,
      clickToSceneMs,
      console: consoleLines.slice(-25),
      exceptions,
      dialogs,
    },
    null,
    2,
  ),
);
process.exit(ok ? 0 : 1);
