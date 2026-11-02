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
import { readFileSync, writeFileSync } from "node:fs";

const [endpoint, url, reloadsArg, importZip] = process.argv.slice(2);
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
  // `New game` leads to the story list, and the story is clicked by the name a
  // player reads — the probe takes it from `lethebarState.stories` rather than
  // guessing at button order.
  const stories = ((await appState()) || {}).stories || [];
  if (stories.length === 0) return false;
  await clickLabel("New game");
  if (!(await waitState((state) => state.screen === "plugins"))) return false;
  await clickLabel(String(stories[0].title));
  return Boolean(await waitState((state) => state.screen === "session"));
}

// The install button opens the page's file input. The picker itself cannot be
// driven headlessly, so the chooser is intercepted (a native dialog would block
// the page) and the file is handed to the input afterwards: the `change` handler
// that runs is the one a player's own file would run.
let chooserNode = null;
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.method === "Page.fileChooserOpened") chooserNode = message.params.backendNodeId;
});

async function feedFile(zipPath) {
  const base64 = readFileSync(zipPath).toString("base64");
  return await evaluate(`(() => {
    const binary = atob(${JSON.stringify(base64)});
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    const input = document.getElementById("lethebar-import");
    if (!input) return "no input";
    const file = new File([bytes], "smoke-pack.zip", { type: "application/zip" });
    const transfer = new DataTransfer();
    transfer.items.add(file);
    input.files = transfer.files;
    input.dispatchEvent(new Event("change"));
    return "attached " + input.files.length;
  })()`);
}

async function installPack(zipPath) {
  const before = ((await appState()) || {}).packs || [];
  chooserNode = null;
  await onSession("Page.setInterceptFileChooserDialog", { enabled: true });
  const askedBefore = await evaluate("window.lethebarAsked || 0");
  const clicked = await clickLabel("Install a pack (.zip)…");
  if (clicked === null) {
    await onSession("Page.setInterceptFileChooserDialog", { enabled: false });
    return null;
  }
  for (let attempt = 0; attempt < 40 && chooserNode === null; attempt += 1) await sleep(100);
  await onSession("Page.setInterceptFileChooserDialog", { enabled: false });
  const askedAfter = await evaluate("window.lethebarAsked || 0");
  if (chooserNode === null) return null;
  // The click proves the button reached the injected bridge; the rest is the
  // same read → decode → validate path a player's own file takes.
  interactionAsked = askedAfter > askedBefore;
  const fed = await feedFile(zipPath);
  const state = await waitState((value) => (value.packs || []).length > before.length, 60);
  trace(`install: ${fed}, imported ${state === null ? "nothing" : "a pack"}`);
  if (state === null) return null;
  return (state.packs || []).find((id) => !before.includes(id)) || null;
}

const landingScreen = await screenName();
const clickStarted = Math.round(await evaluate("performance.now()"));
let clickToSceneMs = null;
let interactionAsked = false;
const requestsBeforeInteraction = requestsSeen;
const interaction = {
  landing: landingScreen,
  plugins: false,
  session: false,
  saved: false,
  imported: false,
  asked: false,
  installed: null,
  offline: false,
};

if (landingScreen === "landing") {
  const stories = ((await appState()) || {}).stories || [];
  interaction.plugins = stories.length > 0;
  if (interaction.plugins) {
    // `New game` → story list → the story itself: the same two clicks a player
    // takes, so the measured time is the path they actually walk.
    await clickLabel("New game");
    const onPlugins = await waitState((state) => state.screen === "plugins");
    interaction.session = onPlugins && (await clickLabel(String(stories[0].title))) !== null;
    if (interaction.session && (await waitState((state) => state.screen === "session"))) {
      clickToSceneMs = Math.round((await evaluate("performance.now()")) - clickStarted);
      // PROBE_SHOT=path writes the first scene as a PNG. The probe cannot judge
      // whether glyphs drew, so the picture is the evidence a person reads.
      if (process.env.PROBE_SHOT) {
        const shot = await onSession("Page.captureScreenshot", { format: "png" });
        writeFileSync(process.env.PROBE_SHOT, Buffer.from(shot.data, "base64"));
        trace(`shot: ${process.env.PROBE_SHOT}`);
      }
      // Save a slot so the offline reload has something to prove came back.
      await clickLabel("Saves");
      if (await waitState((state) => state.screen === "saves")) {
        await clickLabel("Save");
        interaction.saved = Boolean(
          await waitState((state) => (state.slots || []).some((slot) => slot.length > 0), 30),
        );
        // The slots screen is where a narrow window used to push Save and Load
        // off the right edge, so it gets a picture of its own next to the first
        // scene one: `<shot>-saves.png`.
        if (process.env.PROBE_SHOT) {
          const slotsShot = process.env.PROBE_SHOT.replace(/\.png$/i, "-saves.png");
          const image = await onSession("Page.captureScreenshot", { format: "png" });
          writeFileSync(slotsShot, Buffer.from(image.data, "base64"));
          trace(`shot: ${slotsShot}`);
        }
      }
    }
  }
}

// TC-PKG-001/TC-OFF-004: a pack the player installs must be accepted by the
// same validation as a built-in one, and must still be installed after a
// reload. Both halves start from this click.
if (interaction.saved && importZip) {
  await clickLabel("Back");
  await waitState((state) => state.screen === "session");
  await clickLabel("Back to packs");
  if (await waitState((state) => state.screen === "plugins")) {
    interaction.installed = await installPack(importZip);
    interaction.imported = interaction.installed !== null;
    interaction.asked = interactionAsked;
  }
}
const interactionRequests = requestsSeen - requestsBeforeInteraction;
trace(`interaction: ${JSON.stringify(interaction)} in ${clickToSceneMs} ms`);

// --- the interface speaks two languages -----------------------------------------
// The build follows `navigator.language`; the driver pins English so every other
// label in this file is stable. This stage starts from a fresh page load, clicks
// the switch, checks the state changed, reloads to prove the choice survived,
// and switches back so the stages below read English again.
let language = { attempted: false, switched: false, persisted: false, restored: false };
{
  language.attempted = true;
  const size = await evaluate("[window.innerWidth, window.innerHeight]");

  const pressSwitch = async () => {
    const hit = (await visibleHits()).find((item) => item.label.includes(": "));
    if (!hit) return false;
    await clickAt(Math.round(hit.fx * size[0]), Math.round(hit.fy * size[1]));
    await sleep(500);
    return true;
  };

  await onSession("Page.navigate", { url });
  await waitState((state) => state.screen === "landing");
  const before = ((await appState()) || {}).locale;

  if (await pressSwitch()) {
    const after = ((await appState()) || {}).locale;
    language.switched = Boolean(after) && after !== before;

    await onSession("Page.navigate", { url });
    await waitState((state) => state.screen === "landing");
    language.persisted = ((await appState()) || {}).locale === after;

    if (await pressSwitch()) {
      language.restored = ((await appState()) || {}).locale === before;
    }
  }
}
trace(`language: ${JSON.stringify(language)}`);

// --- offline reload ---------------------------------------------------------
// TC-OFF-001/002: cut the network, reload, and expect the same shell with the
// packs and the saved slot still there. Everything must come from the service
// worker's cache; a missing file shows up as a page that never reaches landing.
let offline = {
  attempted: false,
  landing: false,
  packs: 0,
  packIds: [],
  importedRestored: null,
  sessions: false,
  slotsRestored: 0,
  continued: false,
  loadsListed: false,
  resumed: false,
};

if (interaction.saved) {
  offline.attempted = true;
  // The engine persists `user://` to IndexedDB in a scheduled background sync, so
  // a reload fired in the same tick as an import aborts that transaction and the
  // pack is lost. Wait long enough for the write to land before cutting the
  // network; a player who reloads inside that window loses the import too, which
  // is recorded as a known limitation rather than papered over here.
  await sleep(2000);
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
    offline.packIds = back.packs || [];
    offline.packs = offline.packIds.length;
    // TC-OFF-004: the pack the player installed is in the same store as the
    // saves, so it either comes back from IndexedDB or it was never really there.
    offline.importedRestored = interaction.installed ? offline.packIds.includes(interaction.installed) : null;
    offline.sessions = await openFirstPack();
    if (offline.sessions) {
      await clickLabel("Saves");
      const saves = await waitState((state) => state.screen === "saves", 30);
      if (saves) offline.slotsRestored = (saves.slots || []).filter((slot) => slot.length > 0).length;
    }
    // `Continue` exists only because a slot is saved, and it lists the saves
    // themselves: one click, then the run is back where it stopped. This walks
    // the button the player would press after a reload, not just the slot list.
    await clickLabel("Back");
    await waitState((state) => state.screen === "session", 30);
    await clickLabel("Back to packs");
    await waitState((state) => state.screen === "plugins", 30);
    await clickLabel("Back");
    if (await waitState((state) => state.screen === "landing", 30)) {
      const listed = await waitState((state) => (state.saves || []).length > 0, 30);
      offline.continued = listed !== null && (await clickLabel("Continue")) !== null;
      if (offline.continued) {
        const onLoads = await waitState((state) => state.screen === "loads", 30);
        offline.loadsListed = Boolean(onLoads && (onLoads.saves || []).length > 0);
        const first = ((onLoads || {}).saves || [{}])[0];
        if (offline.loadsListed) {
          offline.resumed = (await clickLabel(String(first.title || ""))) !== null;
          if (offline.resumed) {
            offline.resumed = (await waitState((state) => state.screen === "session", 30)) !== null;
          }
        }
      }
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

// --- a file URL is not the game -------------------------------------------------
// The document fallback that makes TC-OFF-001 pass also caught every other top
// level navigation, so opening a download link (`/lethebar/test-pack.zip`) showed
// the game instead of the file. The file need not exist here: a 404 proves the
// request reached the network, which is what a download needs.
let directFile = { attempted: false, servedGame: null };
{
  directFile.attempted = true;
  const fileUrl = `${url.replace(/index\.html$/, "")}missing-file.zip`;
  await onSession("Page.navigate", { url: fileUrl });
  await sleep(1500);
  const screen = await screenName();
  directFile.servedGame = screen !== null;
  if (process.env.PROBE_SHOT) {
    const shot = await onSession("Page.captureScreenshot", { format: "png" });
    const target = process.env.PROBE_SHOT.replace(/\.png$/i, "-file.png");
    writeFileSync(target, Buffer.from(shot.data, "base64"));
    trace(`shot: ${target}`);
  }
}
trace(`direct file navigation: ${JSON.stringify(directFile)}`);

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
const offlineOk =
  offline.landing &&
  offline.packs >= 2 &&
  offline.sessions &&
  offline.slotsRestored >= 1 &&
  // `Continue` is the returning player's path: it has to be there after a
  // reload, list the saved runs, and put the session back on the saved scene.
  offline.continued &&
  offline.loadsListed &&
  offline.resumed;
const importOk = importZip ? interaction.imported && offline.importedRestored === true : true;
// A download link must reach the network. When the document fallback answered
// every navigation, `/lethebar/test-pack.zip` opened the game instead of the file.
const directFileOk = directFile.servedGame === false;

const ok =
  loaded &&
  typeof title === "string" &&
  title.length > 0 &&
  exceptions.length === 0 &&
  dialogs.length === 0 &&
  bootSamples.length === reloads &&
  interacted &&
  sessionQuiet &&
  offlineOk &&
  importOk &&
  directFileOk &&
  language.attempted &&
  language.switched &&
  language.persisted &&
  language.restored;

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
      language,
      clickToSceneMs,
      interactionRequests,
      offline,
      directFile,
      console: consoleLines.slice(-25),
      exceptions,
      dialogs,
    },
    null,
    2,
  ),
);
process.exit(ok ? 0 : 1);
