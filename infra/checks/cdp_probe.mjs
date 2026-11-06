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
  if (message.method === "Network.requestWillBeSent") {
    const url = message.params?.request?.url || "";
    // Reading the chosen .zip goes through FileReader and Chrome reports the
    // read as a `blob:` request. It never leaves the page, so counting it would
    // make TC-OFF-003 ("no request during a session") depend on timing.
    if (!url.startsWith("blob:") && !url.startsWith("data:")) requestsSeen += 1;
  }
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
// The notice belongs to the first visit only, so it has to be read on the first
// load. The later reloads are the evidence that it does not come back.
let firstNotice = "";
for (let run = 0; run < reloads; run += 1) {
  loaded = false;
  await onSession("Page.navigate", { url });
  for (let attempt = 0; attempt < 80 && !loaded; attempt += 1) await sleep(250);
  const settled = loaded ? await settle() : null;
  if (settled !== null) bootSamples.push(settled);
  if (run === 0) {
    await waitState((state) => state.screen === "landing" && typeof state.notice === "string", 240);
    firstNotice = String((((await appState()) || {}).notice) || "");
  }
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
  savingSeen: false,
  asked: false,
  installed: null,
  offline: false,
  pictures: [],
  hitsInside: false,
  notice: "",
  cacheControlled: false,
};

if (landingScreen === "landing") {
  // A first visit has to say what is being downloaded; the same profile must not
  // say it twice. Both facts are read from the shell's own state, so a rebuild
  // that drops the sentence fails here rather than passing quietly (REQ-031).
  await waitState((state) => typeof state.notice === "string", 240);
  interaction.notice = firstNotice;
  const cacheReady = await waitState(
    (state) => Boolean(state.cache && state.cache.controlled),
    480
  );
  interaction.cacheControlled = Boolean(cacheReady);
  const stories = ((await appState()) || {}).stories || [];
  interaction.plugins = stories.length > 0;
  // A story may declare no pictures at all, and then the band is empty on
  // purpose. Open one that declares a picture when the assertion is about a
  // picture reaching the screen.
  const picturedStory = stories.find((story) => Number(story.pictures || 0) > 0) || stories[0];
  if (interaction.plugins) {
    // `New game` → story list → the story itself: the same two clicks a player
    // takes, so the measured time is the path they actually walk.
    await clickLabel("New game");
    const onPlugins = await waitState((state) => state.screen === "plugins");
    interaction.session =
    onPlugins && (await clickLabel(String((picturedStory || stories[0] || {}).title || ""))) !== null;
    if (interaction.session && (await waitState((state) => state.screen === "session"))) {
      clickToSceneMs = Math.round((await evaluate("performance.now()")) - clickStarted);
      // The desktop suite decodes a PNG in a headless renderer; the browser is a
      // separate decoder. Reporting the filled slots here is what makes "the
      // picture really reached the screen" a check instead of a screenshot.
      interaction.pictures = await evaluate(
        "(window.lethebarState && window.lethebarState.pictures) || []"
      );
      // A picture band that is too tall pushes the last button below the fold.
      // Every published hit box has to be wholly inside the viewport for the
      // scene to count as reachable.
      const hits = await evaluate("window.lethebarHits || []");
      interaction.hitsOutside = hits
        .filter((hit) => {
          const halfW = (hit.fw ?? 0) / 2;
          const halfH = (hit.fh ?? 0) / 2;
          return (
            hit.fx - halfW < -0.001 ||
            hit.fx + halfW > 1.001 ||
            hit.fy - halfH < -0.001 ||
            hit.fy + halfH > 1.001
          );
        })
        .map((hit) => hit.label);
      interaction.hitsInside =
        hits.length > 0 &&
        hits.every(
          (hit) =>
            hit.fx - hit.fw / 2 >= -0.001 &&
            hit.fx + hit.fw / 2 <= 1.001 &&
            hit.fy - hit.fh / 2 >= -0.001 &&
            hit.fy + hit.fh / 2 <= 1.001
        );
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
        // The shell does not say saved until the engine had frames to fold the
        // write into IndexedDB; the state carries both halves, so the probe waits
        // for the answer instead of sleeping through a guess.
        // Wait for the write to start, then for it to settle. Waiting only for
        // "settled and the slot is filled" is a race: the previous screen's state
        // already says not-saving, so it would return before the write began.
        const started = Boolean(await waitState((state) => state.saving === true, 60));
        // Evidence that the shell told the player it was writing. Without this
        // the only proof that the wait exists is the absence of a sleep.
        interaction.savingSeen = started;
        const finished = Boolean(
          await waitState(
            (state) => state.saving === false && (state.slots || []).some((slot) => slot.length > 0),
            240,
          ),
        );
        interaction.saved = started && finished;
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
    // The first visit is over once the browser has seen the notice; a reload in
    // the same profile must not show it again (REQ-031).
    interaction.noticeAfterReload = String((((await appState()) || {}).notice) || "");

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
  persisted: false,
  persistTries: 0,
  sessions: false,
  slotsRestored: 0,
  continued: false,
  loadsListed: false,
  resumed: false,
};

if (interaction.saved) {
  offline.attempted = true;
  // The install is written through the same gate as a save, so wait until the
  // shell stops saying it is writing before treating the reload as a player one.
  await waitState((state) => state.saving === false, 240);
  // Nothing sleeps here. The save click already waited for the shell to stop
  // saying "saving", which it does only after the engine had frames to fold the
  // write in, so this reload fires when a player would reload. If the pack is
  // missing, the write did not land — that is the finding, not a timing accident.
  offline.persistTries = 0;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    offline.persistTries = attempt + 1;
    await onSession("Page.navigate", { url });
    const back = await waitState((state) => state.screen === "landing", 100);
    trace(`persist try ${attempt + 1}: ${JSON.stringify(back && back.packs)}`);
    if (back && interaction.installed && (back.packs || []).includes(interaction.installed)) {
      offline.persisted = true;
      break;
    }
    await sleep(500);
  }
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
    // The saved slot may belong to any pack, so count the cross-pack list the
    // landing screen publishes instead of this pack's three slots.
    offline.slotsRestored = (back.saves || []).length;
    offline.sessions = await openFirstPack();
    if (offline.sessions) {
      await clickLabel("Saves");
      const saves = await waitState((state) => state.screen === "saves", 30);
      // The save screen of a pack that never saved is empty on purpose; this
      // only proves the screen still opens offline.
      if (saves) offline.packSlots = (saves.slots || []).length;
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
// REQ-031: the first visit says what is coming and the browser told the page it
// kept the payload; the reload that proves the language choice also proves the
// notice does not come back.
const bootOk =
  String(interaction.notice || "").length > 0 &&
  interaction.cacheControlled === true &&
  String(interaction.noticeAfterReload || "") === "";

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
  bootOk &&
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
