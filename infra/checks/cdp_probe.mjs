// Drive an already-running headless Chrome over the DevTools protocol.
//
// Usage: node cdp_probe.mjs <ws-endpoint> <url>
//
// Prints one JSON object: page title, canvas count, whether localStorage
// round-trips, recent console lines and uncaught exceptions. Exit code 0 when
// the page reached a loaded state with no uncaught exception, 1 otherwise.
//
// The browser is started and stopped by infra/verify_web.py, so this file never
// spawns a process; Node 22 ships a global WebSocket, so no package is needed.

const [endpoint, url] = process.argv.slice(2);
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
  console.log(JSON.stringify({ ok: false, error: "probe timed out after 90 s" }));
  process.exit(1);
}, 90000);
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
trace(`attached with session ${sessionId}`);
const onSession = (method, params = {}) => send(method, params, sessionId);

await onSession("Runtime.enable");
await onSession("Log.enable");
await onSession("Page.enable");

let loaded = false;
socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.method === "Page.loadEventFired") loaded = true;
});

await onSession("Page.navigate", { url });
for (let attempt = 0; attempt < 80 && !loaded; attempt += 1) await sleep(250);
// The wasm module keeps working after the load event; give it time to report.
await sleep(4000);

async function evaluate(expression) {
  const { result } = await onSession("Runtime.evaluate", {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  return result.value;
}

const title = await evaluate("document.title");
const canvases = await evaluate("document.querySelectorAll('canvas').length");
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

const ok = loaded && typeof title === "string" && title.length > 0 && exceptions.length === 0;

console.log(
  JSON.stringify(
    {
      ok,
      loaded,
      title,
      canvases,
      storageWorks: storage === true,
      storageDetail: storage,
      console: consoleLines.slice(-25),
      exceptions,
      dialogs,
    },
    null,
    2,
  ),
);
process.exit(ok ? 0 : 1);
