// Published native HTTP UI consumers over CDP. No app imports, process spawning,
// production responses, internal-store writes or direct database mutation.
const args = {};
for (let i = 0; i < Deno.args.length; i += 2) {
  const key = Deno.args[i], value = Deno.args[i + 1];
  if (!key.startsWith("--") || value === undefined || Object.hasOwn(args, key.slice(2))) throw Error("Expected unique --key value arguments");
  args[key.slice(2)] = value;
}
const { origin, phase, evidence } = args;
const endpoint = args["cdp-endpoint"];
if (origin !== "http://kosmozoo.home" || endpoint !== "http://127.0.0.1:9335") throw Error("Ordinary HTTP origin and explicit loopback CDP required");
if (!["smoke", "first-run", "finish-first-run", "verify", "verify-recovery", "activity", "output"].includes(phase)) throw Error("Unknown browser phase");
const guard = JSON.parse(await Deno.readTextFile(args["guard-manifest"]));
const W = guard.workspace?.path;
if (!W || !W.startsWith("/var/lib/scripts-underground/") || W.includes("..") || Deno.env.get("TMPDIR") !== `${W}/tmp`) throw Error("Admitted disk workspace required");
// The invoking --lxc owner checks actual DMI UUID, disk serial, MAC and mounted
// filesystem before effects. Deno2.9.6 reserves special /sys reads for --allow-all,
// which would also grant process execution. This observer retains only regular
// file access and independently checks machine-id plus the issued source hashes.
if ((await Deno.readTextFile("/etc/machine-id")).trim() !== guard.guest.machine_id) throw Error("Wrong execution guest");
const ct = guard.native?.containers?.find(c => String(c.id) === args.ctid);
if (!ct || !/^10\.248\.26\.(20|21|22)$/.test(ct.ip)) throw Error("Undeclared CT");
if (ct.id === 2122 && ct.role !== "failure") throw Error("Undeclared failure owner");
if (!evidence?.startsWith(`${W}/artifacts/`) || evidence.includes("..")) throw Error("Owned disk evidence required");
const label = args.label ?? `${args.ctid}-${phase}`;
if (!/^[a-zA-Z0-9-]+$/.test(label)) throw Error("Invalid evidence label");
const sha = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), b => b.toString(16).padStart(2, "0")).join("");
for (const file of guard.source.files) {
  if (file.path.includes("..") || file.path.startsWith("/")) throw Error("Invalid guarded source");
  if (await sha(await Deno.readFile(`${W}/repo/${file.path}`)) !== file.sha256) throw Error(`Source mismatch: ${file.path}`);
}
await Deno.mkdir(evidence, { recursive: true, mode: 0o700 });
const record = { phase, label, origin, ctid: ct.id, source: guard.source, started: new Date().toISOString(), checks: [], exceptions: [], network: [], failedRequests: [] };
const save = (path, value, createNew = true) => Deno.writeTextFile(path, JSON.stringify(value, null, 2), { mode: 0o600, createNew });
const assert = (ok, text) => { if (!ok) throw Error(text); record.checks.push(text); console.log(`PASS ${text}`); };
const j = JSON.stringify, sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function discovery(path) {
  const response = await fetch(endpoint + path, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw Error(`CDP discovery ${response.status}`);
  return response.json();
}
const target = (await discovery("/json/list")).find(t => t.type === "page");
if (!target || !target.webSocketDebuggerUrl.startsWith("ws://127.0.0.1:9335/")) throw Error("Owned page target absent");
const ws = new WebSocket(target.webSocketDebuggerUrl), pending = new Map(), requests = new Map();
let lastClick = null;
let seq = 0;
await new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(Error("CDP connection deadline")), 10000);
  ws.onopen = () => { clearTimeout(timer); resolve(); };
  ws.onerror = () => { clearTimeout(timer); reject(Error("CDP connection failed")); };
});
ws.onmessage = event => {
  const message = JSON.parse(event.data);
  if (message.id) {
    const entry = pending.get(message.id);
    if (!entry) return;
    pending.delete(message.id); clearTimeout(entry.timer);
    message.error ? entry.reject(Error(message.error.message)) : entry.resolve(message.result);
    return;
  }
  const p = message.params;
  if (message.method === "Runtime.exceptionThrown") record.exceptions.push(p.exceptionDetails);
  if (message.method === "Network.requestWillBeSent") requests.set(p.requestId, p.request.url);
  if (message.method === "Network.responseReceived" && p.response.url.startsWith(origin)) record.network.push({ url: p.response.url, status: p.response.status, mimeType: p.response.mimeType });
  if (message.method === "Network.loadingFailed" && requests.get(p.requestId)?.startsWith(origin)) record.failedRequests.push({ url: requests.get(p.requestId), error: p.errorText, canceled: p.canceled ?? false });
};
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = ++seq;
  const timer = setTimeout(() => { pending.delete(id); reject(Error(`CDP deadline: ${method}`)); }, 15000);
  pending.set(id, { resolve, reject, timer }); ws.send(j({ id, method, params }));
});
async function evaluate(expression) {
  const response = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  if (response.exceptionDetails) throw Error(response.exceptionDetails.exception?.description ?? response.exceptionDetails.text);
  return response.result.value;
}
async function poll(expression, timeout = 30000) {
  const deadline = Date.now() + timeout;
  do { const value = await evaluate(expression); if (value) return value; await sleep(100); } while (Date.now() < deadline);
  throw Error(`Consumer deadline: ${expression.slice(0, 200)}`);
}
async function click(selector) {
  const expression = `(()=>{const e=document.querySelector(${j(selector)});if(!e||e.disabled||e.closest('[inert]'))return false;e.scrollIntoView({block:'center',inline:'nearest'});const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&{x:r.x+r.width/2,y:r.y+r.height/2}})()`;
  const point = await poll(expression);
  lastClick = { selector, ...point, hit: await evaluate(`document.elementFromPoint(${point.x},${point.y})?.outerHTML`) };
  for (const type of ["mousePressed", "mouseReleased"]) await send("Input.dispatchMouseEvent", { type, ...point, button: "left", buttons: type === "mousePressed" ? 1 : 0, clickCount: 1 });
}
async function fill(selector, text) {
  await click(selector);
  for (const type of ["rawKeyDown", "keyUp"]) await send("Input.dispatchKeyEvent", { type, key: "a", code: "KeyA", windowsVirtualKeyCode: 65, modifiers: 2 });
  await send("Input.insertText", { text });
}
async function api(path) {
  return evaluate(`(async()=>{const r=await fetch(${j(path)},{signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('API read '+r.status+' '+${j(path)});return r.json()})()`);
}
async function addSource(name, address) {
  await click("#hostBtn"); await fill("#hostName", name); await fill("#hostAddr", address); await click("#hostAdd");
  await poll(`(async()=>Object.hasOwn(await (await fetch('/api/collections')).json(),${j(name)}))()`);
  if (await evaluate("!document.querySelector('#hostDrop').hidden")) await click("#hostBtn");
}
async function selectSource(name) {
  // Header controls mount before asynchronous source adoption settles. A toggle
  // is not an "open" command: wait for the source owner, observe current menu
  // state, then confirm both transitions instead of assuming the CDP ack did it.
  const row = `.hostpick[data-source="${name}"] .hname`;
  await poll(`(()=>{const target=document.querySelector(${j(row)});const current=document.querySelector('#hostList .hostpick.current');const label=document.querySelector('#hostBtn > span:nth-child(2)')?.textContent;return !!target&&!!current&&label===current.dataset.source})()`);
  if (await evaluate(`document.querySelector('#hostList .hostpick.current')?.dataset.source===${j(name)}`)) return;
  if (await evaluate("document.querySelector('#hostDrop').hidden")) await click("#hostBtn");
  await poll("!document.querySelector('#hostDrop').hidden");
  await click(row);
  await poll(`document.querySelector('#hostBtn').textContent.includes(${j(name)})&&document.querySelector('#hostDrop').hidden`);
}
async function image(source, name, select = true) {
  if (select) await selectSource(source);
  const selector = `.card[data-name="${name}"] img`;
  const loaded = await poll(`(()=>{const e=document.querySelector(${j(selector)});return e&&e.complete&&e.naturalWidth>0&&e.naturalHeight>0&&{width:e.naturalWidth,height:e.naturalHeight,url:e.currentSrc}})()`, 60000);
  const entryPath = `/api/collections/${encodeURIComponent(source)}/entries/${encodeURIComponent(name)}`;
  const row = await api(entryPath);
  assert(row.extracted && row.hash && row.meta, `${source}/${name}: ingested hash and extracted metadata`);
  const bytes = await evaluate(`(async()=>{const r=await fetch(${j(entryPath + "/bytes")});if(!r.ok)throw Error('Image bytes '+r.status);return Array.from(new Uint8Array(await r.arrayBuffer()))})()`);
  const digest = await sha(Uint8Array.from(bytes));
  assert(digest === row.hash, `${source}/${name}: API cached bytes match content SHA256`);
  assert(loaded.width === row.width && loaded.height === row.height, `${source}/${name}: LOADED browser natural dimensions match native entry`);
  record.media ??= []; record.media.push({ source, name, ...loaded, digest, bytes: bytes.length, entry: row });
  return row;
}
const baseline = args.baseline ?? `${evidence}/${ct.id}-accepted.json`;
if (!baseline.startsWith(`${W}/artifacts/`) || baseline.includes("..")) throw Error("Owned consumer baseline required");
if (args.baseline) {
  if (!/^[0-9a-f]{64}$/.test(args["baseline-sha256"] ?? "") || await sha(await Deno.readFile(baseline)) !== args["baseline-sha256"]) throw Error("Consumer baseline binding mismatch");
}
try {
  await send("Page.enable"); await send("Runtime.enable"); await send("Network.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  if (args["keep-page"] !== "yes") await send("Page.navigate", { url: origin });
  await poll(`location.origin===${j(origin)}&&document.readyState==='complete'&&!!document.querySelector('#hostBtn')`);
  assert(await evaluate(`location.origin===${j(origin)}&&isSecureContext===false`), "Ordinary nonloopback kosmozoo.home HTTP, insecure context");
  const runtime = await api("/api/runtime"); record.runtime = runtime;
  assert(runtime.protocol === "kosmozoo-runtime" && runtime.version === 1 && runtime.mode === "serve" && runtime.status === "ready", "Native runtime protocol1 serve/ready");
  if (args["expected-version"]) assert(runtime.app.version === args["expected-version"], "Actual expected app release, distinct from protocol version");
  assert(await poll("(()=>{const e=document.querySelector('img.logo');return e&&e.complete&&e.naturalWidth>0})()"), "Embedded VFS logo loaded in browser");
  const sources = await api("/api/collections");
  if (phase === "smoke") {
    assert(ct.hosts === "" ? Object.keys(sources).length === 0 : sources.remote?.address === "10.248.26.1:8188", "Fresh actual source state matches default empty or explicit HOSTS seed");
  } else if (phase === "first-run" || phase === "finish-first-run") {
    try { await Deno.stat(baseline); throw Error("Accepted baseline exists; first-run mutations must not replay"); } catch (error) { if (!(error instanceof Deno.errors.NotFound)) throw error; }
    const rows = {};
    if (phase === "finish-first-run") {
      assert(ct.resume?.phase === "local-judged" && Object.keys(sources).length === 2 && sources.local?.address === "folder:/sources/images" && sources.remote?.address === "10.248.26.1:8188", "Explicit continuation guard matches original source additions");
      rows.local = await image("local", "flux-basic.png");
      assert(j(rows.local.judgment) === j(ct.resume.local_judgment) && rows.local.hash === ct.resume.hash, "Prior authorized local UI writes match explicit expected provenance; no replay");
      assert(await evaluate(`document.querySelector('.card[data-name="flux-basic.png"] button.up').getAttribute('aria-pressed')==='true'&&document.querySelector('.card[data-name="flux-basic.png"] button.favorite').getAttribute('aria-pressed')==='false'&&document.querySelector('.card[data-name="flux-basic.png"] button.bookmark').getAttribute('aria-pressed')==='true'&&document.querySelector('.card[data-name="flux-basic.png"] textarea.pos').value===${j(ct.resume.local_judgment.notes.pos)}`), "Prior local controls and blur-saved note render after native restart");
      const remote = await api("/api/collections/remote/entries/flux-basic.png");
      assert(remote.judgment === null && sources.remote.pinned === false && sources.remote.autoRefresh === false, "Only untouched remote controls and settings remain");
    } else {
      assert(ct.hosts === "" ? Object.keys(sources).length === 0 : Object.keys(sources).length === 1 && sources.remote?.address === "10.248.26.1:8188", "First-run admission is original empty/seeded state, never adopted partial mutations");
      if (!Object.hasOwn(sources, "remote")) await addSource("remote", "10.248.26.1:8188");
      if (!Object.hasOwn(sources, "local")) await addSource("local", "folder:/sources/images");
    }
    for (const source of phase === "finish-first-run" ? ["remote"] : ["local", "remote"]) {
      await image(source, "flux-basic.png");
      const card = '.card[data-name="flux-basic.png"]';
      await click(`${card} button.up`); await poll(`document.querySelector(${j(card + " button.up")}).getAttribute('aria-pressed')==='true'`);
      await click(`${card} button.favorite`); await poll(`document.querySelector(${j(card + " button.favorite")}).getAttribute('aria-pressed')==='true'`);
      await click(`${card} button.bookmark`); await poll(`document.querySelector(${j(card + " button.bookmark")}).getAttribute('aria-pressed')==='true'`);
      await click(`${card} button.favorite`); await poll(`document.querySelector(${j(card + " button.favorite")}).getAttribute('aria-pressed')==='false'&&document.querySelector(${j(card + " button.bookmark")}).getAttribute('aria-pressed')==='true'`);
      assert(true, `${source}: actual favorite toggle does not clear independent bookmark`);
      const note = `native-${ct.id}-${source}-browser-blur`;
      await fill(`${card} textarea.pos`, note); await click(`${card} .copyable`);
      const path = `/api/collections/${source}/entries/flux-basic.png`;
      await poll(`(async()=>{const r=await (await fetch(${j(path)})).json();return r.judgment?.notes?.pos===${j(note)}&&r.judgment?.vote==='up'&&r.judgment?.favorite==null&&r.judgment?.bookmark===true})()`);
      rows[source] = await api(path);
    }
    await click("#hostBtn"); await click('.hostpick[data-source="remote"] button.pin');
    await poll("document.querySelector('.hostpick[data-source=\"remote\"] button.pin').getAttribute('aria-pressed')==='true'");
    await click('.hostpick[data-source="remote"] button.auto-refresh');
    await poll("document.querySelector('.hostpick[data-source=\"remote\"] button.auto-refresh').getAttribute('aria-pressed')==='true'");
    await click('.hostpick[data-source="remote"] button.auto-refresh');
    await poll("document.querySelector('.hostpick[data-source=\"remote\"] button.auto-refresh').getAttribute('aria-pressed')==='false'");
    await click('.hostpick[data-source="remote"] button.auto-refresh');
    await poll("document.querySelector('.hostpick[data-source=\"remote\"] button.auto-refresh').getAttribute('aria-pressed')==='true'");
    await click("#hostBtn"); await click("#menuBtn");
    await click('#menuRows label[title^="thumbs-down"]');
    await poll("(async()=> (await (await fetch('/api/settings/core.judgment')).json()).downvoteHides===false)()");
    await click("#menuBtn");
    await save(baseline, { rows, sources: await api("/api/collections"), settings: await api("/api/settings/core.judgment"), runtime });
  } else if (phase === "verify") {
    const accepted = JSON.parse(await Deno.readTextFile(baseline));
    for (const source of ["local", "remote"]) {
      const row = await image(source, "flux-basic.png");
      assert(j(row.judgment) === j(accepted.rows[source].judgment), `${source}: consumer judgments survived restart/update`);
      const exported = await api(`/api/collections/${source}/feedback.json`);
      assert(j(exported.entries["flux-basic.png"]) === j({ hash: row.hash, ...row.judgment }), `${source}: generated feedback export agrees with native/UI judgment`);
      const card = '.card[data-name="flux-basic.png"]';
      assert(await evaluate(`document.querySelector(${j(card + " button.up")}).getAttribute('aria-pressed')==='true'&&document.querySelector(${j(card + " button.favorite")}).getAttribute('aria-pressed')==='false'&&document.querySelector(${j(card + " button.bookmark")}).getAttribute('aria-pressed')==='true'&&document.querySelector(${j(card + " textarea.pos")}).value===${j(row.judgment.notes.pos)}`), `${source}: rendered controls and saved notes agree with API`);
    }
    const current = await api("/api/collections");
    for (const [id, source] of Object.entries(accepted.sources)) assert(current[id]?.address === source.address && current[id]?.pinned === source.pinned && current[id]?.autoRefresh === source.autoRefresh, `${id}: source address and independent flags preserved`);
    assert(j(await api("/api/settings/core.judgment")) === j(accepted.settings), "Engine settings preserved");
    assert(runtime.instance !== accepted.runtime.instance, "Restarted native instance has fresh public nonce");
  } else if (phase === "verify-recovery") {
    const expected = ct.acceptance.recovery;
    assert(ct.role === "failure" && Object.keys(sources).length === 1 && sources.recovery?.address === "folder:/sources/images", "Scratch recovery source is still the declared actual folder");
    const row = await image("recovery", "flux-basic.png");
    assert(row.hash === expected.hash && row.judgment?.bookmark === true && row.judgment?.notes?.pos === expected.note, "Current recovery API retains the latest authorized native failure write");
    const exported = await api("/api/collections/recovery/feedback.json");
    assert(exported.entries["flux-basic.png"]?.hash === expected.hash && exported.entries["flux-basic.png"]?.bookmark === true && exported.entries["flux-basic.png"]?.notes?.pos === expected.note, "Current recovery export agrees with the authorized native write");
    assert(await evaluate(`document.querySelector('.card[data-name="flux-basic.png"] button.bookmark').getAttribute('aria-pressed')==='true'&&document.querySelector('.card[data-name="flux-basic.png"] textarea.pos').value===${j(expected.note)}`), "Current recovery bookmark and note actually render without toggling or typing");
  } else if (phase === "activity") {
    await poll("document.querySelector('.pinned-source[data-source=\"remote\"] .source-progress')?.getAttribute('data-state')==='running'", 60000);
    record.activity = await evaluate("(()=>{const e=document.querySelector('.pinned-source[data-source=\"remote\"] .source-progress');return {state:e.getAttribute('data-state'),label:e.getAttribute('aria-label')}})()");
    assert(record.activity.state === "running", "Native browser re-observes independently running upstream work");
  } else {
    if (!args.output || !/^[a-zA-Z0-9._-]+\.png$/.test(args.output)) throw Error("Explicit remote output filename required");
    const row = await image("remote", args.output, args["keep-page"] !== "yes");
    assert(/^[0-9a-f]{64}$/.test(args["output-sha256"] ?? "") && row.hash === args["output-sha256"], "Final remote output matches independently fetched provider bytes");
    assert(row.meta.nodes?.some(n => n.type === "SaveImage" && n.inputs?.filename_prefix === args["output-prefix"]), "Final output extracted graph metadata matches actual producer input");
  }
  await sleep(300);
  assert(record.exceptions.length === 0, "No uncaught browser exceptions");
  // The frozen fake lists this intentional missing entry. No broader error
  // suppression: every other failed HTTP resource remains a failing observation.
  const intentionalMissing = `${origin}/api/collections/remote/entries/missing-404.png/bytes`;
  const bad = record.network.filter(r => r.status >= 400 && !(r.status === 404 && r.url === intentionalMissing));
  assert(bad.length === 0, `No unexpected failed HTTP resources (${j(bad)})`);
  assert(record.failedRequests.length === 0, `No unexpected failed network requests (${j(record.failedRequests)})`);
  record.finished = new Date().toISOString(); record.status = "passed";
  await save(`${evidence}/${label}.json`, record);
  console.log(`0 failure(s); Kosmozoo browser phase=${phase}; ${record.checks.length} consumer checks`);
} catch (error) {
  record.status = "failed"; record.error = String(error); record.finished = new Date().toISOString();
  record.lastClick = lastClick;
  try { record.dom = await evaluate(`({hostButton:document.querySelector('#hostBtn')?.outerHTML,hostDrop:document.querySelector('#hostDrop')?.outerHTML,body:document.body.innerText.slice(0,5000),active:document.activeElement?.outerHTML})`); } catch { record.dom = "CDP unavailable after failure"; }
  await save(`${evidence}/${label}-failed-${Date.now()}.json`, record);
  throw error;
} finally {
  for (const entry of pending.values()) { clearTimeout(entry.timer); entry.reject(Error("Observer closed")); }
  pending.clear(); ws.close();
}
