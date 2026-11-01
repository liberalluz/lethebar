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
await onSession("Network.enable");

// Requests are counted for the interaction window only: loading the page is
// allowed to fetch the build, playing a session is not allowed to fetch
// anything (TC-OFF-003).
let requestsSeen = 0;
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.method === "Network.requestWillBeSent") requestsSeen += 1;
});

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
// the DOM where "New game" is. The shell publishes the centre of every visible
// button as `window.lethebarHits`, and the probe clicks those coordinates. The
// box is only a convenience: every step is proven by a change in
// `window.lethebarState`, so a wrong box makes the click miss and the step
// fail — it can never make a broken screen pass.

async function screenName() {
  return await evaluate("(window.lethebarState && window.lethebarState.screen) || null");
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

async function appState() {
  return await evaluate("window.lethebarState || null");
}

async function visibleHits() {
  return (await evaluate("window.lethebarHits || []")) || [];
}

async function clickLabel(label, limit = 40) {
  // The hit list is republished one frame after a screen changes, hence the
  // retry loop: the first read can still describe the previous screen.
  for (let attempt = 0; attempt < limit; attempt += 1) {
    const list = await visibleHits();
    const hit =
      list.find((item) => item.label === label) ||
      list.find((item) => item.label.startsWith(label));
    if (hit) {
      // The shell publishes viewport fractions; the driver turns them into
      // window pixels, so a different window size changes nothing.
      const size = await evaluate("[window.innerWidth, window.innerHeight]");
      await clickAt(Math.round(hit.fx * size[0]), Math.round(hit.fy * size[1]));
      await sleep(250);
      return hit.label;
    }
    await sleep(150);
  }
  return null;
}

async function waitState(predicate, limit = 60) {
  for (let attempt = 0; attempt < limit; attempt += 1) {
    const value = await appState();
    if (value && predicate(value)) return value;
    await sleep(200);
  }
  return null;
}

async function openFirstPack() {
  await clickLabel("New game");
  if (!(await waitState((state) => state.screen === "plugins"))) return false;
  const packs = (await appState()).packs || [];
  if (packs.length === 0) return false;
  await clickLabel(String(packs[0]));
  return Boolean(await waitState((state) => state.screen === "session"));
}

const landingScreen = await screenName();
const clickStarted = Math.round(await evaluate("performance.now()"));
let clickToSceneMs = null;
const requestsBeforeInteraction = requestsSeen;
const interaction = { landing: landingScreen, plugins: false, session: false, saved: false, offline: false };

if (landingScreen === "landing") {
  interaction.plugins = (await clickLabel("New game")) !== null;
  if (interaction.plugins) {
    const packs = (await appState()).packs || [];
    interaction.session = packs.length > 0 && (await clickLabel(String(packs[0]))) !== null;
    if (interaction.session && (await waitState((state) => state.screen === "session"))) {
      clickToSceneMs = Math.round((await evaluate("performance.now()")) - clickStarted);
      // Save a slot so the offline reload has something to prove came back.
      await clickLabel("Saves");
      if (await waitState((state) => state.screen === "saves")) {
        await clickLabel("Save");
        interaction.saved = Boolean(
          await waitState((state) => (state.slots || []).some((slot) => slot.length > 0), 30),
        );
      }
    }
  }
}
const interactionRequests = requestsSeen - requestsBeforeInteraction;
trace(`interaction: ${JSON.stringify(interaction)} in ${clickToSceneMs} ms`);

// --- offline reload ---------------------------------------------------------
// TC-OFF-001/002: cut the network, reload, and expect the same shell with the
// packs and the saved slot still there. Everything must come from the service
// worker's cache; a missing file shows up as a page that never reaches landing.
let offline = {
  attempted: false,
  landing: false,
  packs: 0,
  sessions: false,
  slotsRestored: 0,
};

if (interaction.saved) {
  offline.attempted = true;
  await onSession("Network.emulateNetworkConditions", {
    offline: true,
    latency: 0,
    downloadThroughput: 0,
    uploadThroughput: 0,
  });
  await onSession("Page.navigate", { url });
  const back = await waitState((state) => state.screen === "landing", 100);
  offline.landing = back !== null;
  if (back) {
    offline.packs = (back.packs || []).length;
    offline.sessions = await openFirstPack();
    if (offline.sessions) {
      await clickLabel("Saves");
      const saves = await waitState((state) => state.screen === "saves", 30);
      if (saves) offline.slotsRestored = (saves.slots || []).filter((slot) => slot.length > 0).length;
    }
  }
  await onSession("Network.emulateNetworkConditions", {
    offline: false,
    latency: 0,
    downloadThroughput: -1,
    uploadThroughput: -1,
  });
}
trace(`offline: ${JSON.stringify(offline)}`);

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

const interacted = interaction.plugins && interaction.session && interaction.saved;
// TC-OFF-003: once the app is running, a session must not reach the network.
// Counting `Network.requestWillBeSent` is the real measure; the source scan in
// the unit tests only proves the engine code has no HTTP API in it.
const sessionQuiet = interactionRequests === 0;
const offlineOk = offline.landing && offline.packs >= 2 && offline.sessions && offline.slotsRestored >= 1;

const ok =
  loaded &&
  typeof title === "string" &&
  title.length > 0 &&
  exceptions.length === 0 &&
  dialogs.length === 0 &&
  bootSamples.length === reloads &&
  interacted &&
  sessionQuiet &&
  offlineOk;

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
      interactionRequests,
      offline,
      console: consoleLines.slice(-25),
      exceptions,
      dialogs,
    },
    null,
    2,
  ),
);
process.exit(ok ? 0 : 1);
