// Real installed-service consumers. No application modules, response stubs or state injection.
const args = {};
for (let i = 0; i < Deno.args.length; i += 2) {
  if (!Deno.args[i].startsWith("--") || Deno.args[i + 1] === undefined) throw Error("Expected --key value");
  args[Deno.args[i].slice(2)] = Deno.args[i + 1];
}
const { origin, cdp, phase, evidence } = args;
const label = args.label ?? phase;
if (!/^[A-Za-z0-9-]+$/.test(label)) throw Error("Invalid evidence label");
if (origin !== "http://globnotes.home" || cdp !== "http://127.0.0.1:9335") throw Error("Native local HTTP origin / loopback CDP required");
if (!["first-run", "finish-settings", "restart", "update", "verify", "http-consent", "http-before", "http-after", "http-force", "all-before", "all-after"].includes(phase)) throw Error("Unknown browser phase");
if (!evidence?.startsWith("/var/lib/scripts-underground/globnotes-deno-refresh/artifacts/")) throw Error("Owned disk-backed evidence required");
if (!Deno.env.get("TMPDIR")?.startsWith("/var/lib/scripts-underground/globnotes-deno-refresh/")) throw Error("Disk TMPDIR required");
await Deno.mkdir(evidence, { recursive: true, mode: 0o700 });
const record = { phase, origin, checks: [], exceptions: [], network: [] };
const assert = (ok, message) => { if (!ok) throw Error(message); record.checks.push(message); console.log(`ok: ${message}`); };
const json = value => JSON.stringify(value);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function save(path, value, createNew = false) {
  await Deno.writeTextFile(path, JSON.stringify(value, null, 2), { mode: 0o600, createNew });
}
async function socket(url) {
  const ws = new WebSocket(url), pending = new Map();
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
    } else {
      if (message.method === "Runtime.exceptionThrown") record.exceptions.push(message.params.exceptionDetails);
      if (message.method === "Network.responseReceived") {
        const { url, status, mimeType } = message.params.response;
        if (url.startsWith(origin)) record.network.push({ url, status, mimeType });
      }
    }
  };
  return {
    send(method, params = {}) {
      const id = ++seq;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { pending.delete(id); reject(Error(`CDP deadline: ${method}`)); }, 15000);
        pending.set(id, { resolve, reject, timer });
        ws.send(JSON.stringify({ id, method, params }));
      });
    },
    close() { for (const entry of pending.values()) { clearTimeout(entry.timer); entry.reject(Error("CDP closed")); } pending.clear(); ws.close(); },
  };
}
async function discovery(path) {
  const response = await fetch(cdp + path, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw Error(`CDP discovery ${response.status}`);
  return response.json();
}
const version = await discovery("/json/version");
const browser = await socket(version.webSocketDebuggerUrl);
const { browserContextId } = await browser.send("Target.createBrowserContext");
const { targetId } = await browser.send("Target.createTarget", { url: "about:blank", browserContextId });
const target = (await discovery("/json/list")).find(entry => entry.id === targetId);
const page = await socket(target.webSocketDebuggerUrl);
Object.assign(record, { browserContextId, targetId, browserVersion: version.Browser });
await save(`${evidence}/${label}-ownership.json`, record, true);
await page.send("Page.enable"); await page.send("Runtime.enable"); await page.send("Network.enable");
await page.send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
async function evaluate(expression) {
  const response = await page.send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  if (response.exceptionDetails) throw Error(response.exceptionDetails.exception?.description ?? response.exceptionDetails.text);
  return response.result.value;
}
async function poll(expression, timeout = 15000) {
  const end = Date.now() + timeout;
  do { if (await evaluate(expression)) return; await sleep(75); } while (Date.now() < end);
  throw Error(`Consumer deadline: ${expression}`);
}
async function goto(path) {
  await page.send("Page.navigate", { url: origin + path });
  await poll(`location.origin===${json(origin)} && document.readyState==='complete'`);
  assert(await evaluate(`location.origin===${json(origin)} && isSecureContext===false`), "Regular globnotes.home HTTP origin has isSecureContext false");
}
async function click(selector) {
  await poll(`(()=>{const e=document.querySelector(${json(selector)});return e&&!e.disabled&&!e.closest('[inert]')&&e.getBoundingClientRect().width>0})()`);
  const point = await evaluate(`(()=>{const e=document.querySelector(${json(selector)});e.scrollIntoView({block:'center',inline:'center'});const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);
  for (const type of ["mousePressed", "mouseReleased"]) await page.send("Input.dispatchMouseEvent", { type, ...point, button: "left", clickCount: 1 });
}
async function button(label, scope = "body") {
  const pointExpression = `(()=>{const e=[...document.querySelectorAll(${json(scope + " button")})].find(e=>e.textContent.trim()===${json(label)}&&!e.disabled&&e.getBoundingClientRect().width>0);if(!e)return false;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`;
  await poll(pointExpression);
  const point = await evaluate(pointExpression);
  for (const type of ["mousePressed", "mouseReleased"]) await page.send("Input.dispatchMouseEvent", { type, ...point, button: "left", clickCount: 1 });
}
async function key(key, code, windowsVirtualKeyCode, modifiers = 0) {
  for (const type of ["keyDown", "keyUp"]) await page.send("Input.dispatchKeyEvent", { type, key, code, windowsVirtualKeyCode, modifiers });
}
async function fill(selector, value) {
  await click(selector);
  await key("a", "KeyA", 65, 2);
  await page.send("Input.insertText", { text: value });
}
async function api(path, method = "GET", body) {
  // Observe the actual browser-owned login token. Never manufacture/inject credentials.
  return evaluate(`(async()=>{const token=sessionStorage.getItem('token')||localStorage.getItem('token');const r=await fetch(${json(path)},{method:${json(method)},headers:{...(token?{authorization:'Bearer '+token}:{}),${body === undefined ? "" : "'content-type':'application/json'"}},${body === undefined ? "" : "body:" + json(JSON.stringify(body))}});if(!r.ok)throw Error('API observation '+r.status+': '+await r.text());return r.json()})()`);
}
async function note(path) { return api("/_/api/notes/" + encodeURIComponent(path)); }
async function settingsOpen() {
  if (await evaluate(`!!document.querySelector('[title="Open sidebar"]')`)) await click('[title="Open sidebar"]');
  await click('[aria-label="Settings"]'); await poll("!!document.querySelector('#settings-modal-title')");
  if (args["expected-version"] === "2.3.3") await button("Backups", 'nav[aria-label="Settings pages"]');
  else await click('[data-settings-nav-id="plugin:globnotes-backup"]');
  await poll("!!document.querySelector('#settings-field-retention') && !document.querySelector('#settings-field-retention').disabled");
}
async function settingsClose() {
  await click('[aria-label="Close settings"]'); await poll("!document.querySelector('#settings-modal-title')");
  if (await evaluate(`!!document.querySelector('[title="Close sidebar"]')`)) {
    await click('[title="Close sidebar"]');
    await poll(`!!document.querySelector('[title="Open sidebar"]')`);
  }
}
const httpPermissionRoute = "/_/api/plugin-host/native-http-cache/permissions";
function permittedHttp(view) {
  return view.allowNetwork === true && view.approvedNetwork.length === 0 &&
    view.approvedImports.length === 1 && view.approvedImports[0].type === "host" &&
    view.approvedImports[0].authority === "10.248.24.1:8242" &&
    view.rows.some(row => row.kind === "imports" && row.scope.authority === "10.248.24.1:8242" && row.effective);
}
async function consentHttp() {
  let view = await api(httpPermissionRoute);
  record.httpPermissionBefore = view;
  if (!permittedHttp(view)) {
    assert(args["expected-version"] === "2.3.3", "Initial HTTP-module consent belongs to the original release");
    if (await evaluate(`!!document.querySelector('[title="Open sidebar"]')`)) await click('[title="Open sidebar"]');
    await click('[aria-label="Settings"]'); await poll("!!document.querySelector('#settings-modal-title')");
    await click('[data-permission-page="native-http-cache"]');
    await poll("!!document.querySelector('[data-plugin-permission-panel]')");
    if (!view.allowNetwork) {
      await button("Allow network", "[data-plugin-permission-panel]");
      await poll(`fetch(${json(httpPermissionRoute)},{headers:{authorization:'Bearer '+sessionStorage.getItem('token')}}).then(r=>r.json()).then(v=>v.allowNetwork===true)`);
    }
    view = await api(httpPermissionRoute);
    if (!view.approvedImports.some(scope => scope.type === "host" && scope.authority === "10.248.24.1:8242")) {
      await button("Approve", '[data-permission-kind="imports"][data-permission-scope="host:10.248.24.1:8242"]');
      await poll(`fetch(${json(httpPermissionRoute)},{headers:{authorization:'Bearer '+sessionStorage.getItem('token')}}).then(r=>r.json()).then(v=>v.rows.some(row=>row.kind==='imports'&&row.scope.authority==='10.248.24.1:8242'&&row.effective))`);
    }
    await settingsClose();
  }
  record.httpPermissionAfter = await api(httpPermissionRoute);
  assert(permittedHttp(record.httpPermissionAfter), "Normal UI consent grants only the declared HTTP import host; data-network approval stays empty");
}
const fixturePath = `${evidence}/fixture.json`;
let fixture;
try { fixture = JSON.parse(await Deno.readTextFile(fixturePath)); }
catch (error) {
  if (!(error instanceof Deno.errors.NotFound) || phase !== "first-run") throw error;
  const marker = "Native" + crypto.randomUUID().replaceAll("-", "");
  fixture = { username: "native-operator", password: crypto.randomUUID(), marker, folder: "Acceptance/Nested", source: marker + "Source", wysiwyg: marker + "Rich", sourceContent: `# ${marker}\n\nSource edited ${marker}\n`, richContent: `Rich edited ${marker}\n` };
  await save(fixturePath, fixture, true);
}
let success = false;
async function finishSettings() {
  const current = await api("/_/api/plugin-host/globnotes-backup/settings/backup");
  if (current.values.retention !== 3) {
    assert(current.values.retention === 2 && current.revision === 0 && !fixture.settingsAttempted, "Only untouched settings can receive the initial UI commit");
    await settingsOpen();
    fixture.settingsAttempted = true; await save(fixturePath, fixture);
    await click("#settings-field-retention"); await key("Home", "Home", 36);
    await key("ArrowRight", "ArrowRight", 39); await key("ArrowRight", "ArrowRight", 39); await key("Enter", "Enter", 13);
    await poll("fetch('/_/api/plugin-host/globnotes-backup/settings/backup',{headers:{authorization:'Bearer '+sessionStorage.getItem('token')}}).then(r=>r.json()).then(s=>s.values.retention===3)");
    await settingsClose();
  }
  fixture.firstRunComplete = true; await save(fixturePath, fixture);
}
try {
  await goto("/");
  if (phase === "first-run") {
    const setup = await (await fetch(origin + "/_/api/setup", { signal: AbortSignal.timeout(5000) })).json();
    assert(setup.setupRequired === true && !fixture.setupAttempted, "Untouched first-run wizard required; no onboarding replay");
    await poll("!!document.querySelector('#setup-title')");
    await fill("#setup-username", fixture.username); await fill("#setup-password", fixture.password);
    fixture.setupAttempted = true; await save(fixturePath, fixture);
    await button("Finish setup");
  }
  await poll("!!document.querySelector('#username')");
  await fill("#username", fixture.username); await fill("#password", fixture.password); await button("Log In");
  await poll("!location.pathname.includes('/_/login') && !!document.querySelector('[title=\"New note\"]')");
  assert((await api("/_/api/auth-check")) !== null, "Actual wizard credentials authenticate after this phase");
  const config = await api("/_/api/config");
  assert(config.version === args["expected-version"] && config.revision === args["expected-revision"], "Installed API reports the selected VERSION and peeled commit");
  assert(await evaluate("document.querySelector('meta[name=globnotes-prefix]')?.content === ''"), "Production startup stamped globnotes-prefix HTML meta");
  if (args["expected-brand"]) assert(config.brand.name === args["expected-brand"], "Operator environment branding reaches the API consumer");
  if (phase === "first-run") {
    assert(!fixture.notesAttempted, "No replay of initial note/settings mutations");
    fixture.notesAttempted = true; await save(fixturePath, fixture);
    async function create(title, mode, content) {
      await click('[title="New note"]'); await poll("!!document.querySelector('input[placeholder=Title]')");
      await fill('input[placeholder="Title"]', title); await fill('input[placeholder="Folder (root)"]', fixture.folder);
      await button(mode, ".content-column");
      const editor = mode === "Source" ? ".cm-content[contenteditable=true]" : ".ProseMirror[contenteditable=true]";
      await fill(editor, content); await button("Save", ".content-column");
      await poll(`decodeURIComponent(location.pathname).endsWith(${json("/" + fixture.folder + "/" + title)}) && !!document.querySelector('.toast-viewer')`);
    }
    await create(fixture.source, "Source", `# ${fixture.marker}\n\nSource initial ${fixture.marker}\n`);
    await button("Edit", ".content-column"); await button("Source", ".content-column");
    await fill(".cm-content[contenteditable=true]", fixture.sourceContent); await button("Save", ".content-column");
    await poll(`fetch(${json("/_/api/notes/" + encodeURIComponent(fixture.folder + "/" + fixture.source))},{headers:{authorization:'Bearer '+sessionStorage.getItem('token')}}).then(r=>r.json()).then(n=>n.content===${json(fixture.sourceContent)})`);
    await goto("/" + fixture.folder + "/" + fixture.source);
    await create(fixture.wysiwyg, "WYSIWYG", "Rich initial " + fixture.marker);
    await button("Edit", ".content-column"); await button("WYSIWYG", ".content-column");
    await fill(".ProseMirror[contenteditable=true]", "Rich edited " + fixture.marker); await button("Save", ".content-column");
    await poll(`fetch(${json("/_/api/notes/" + encodeURIComponent(fixture.folder + "/" + fixture.wysiwyg))},{headers:{authorization:'Bearer '+sessionStorage.getItem('token')}}).then(r=>r.json()).then(n=>n.content===${json(fixture.richContent)})`);
    await goto("/" + fixture.folder + "/" + fixture.wysiwyg);
    await finishSettings();
  } else if (phase === "finish-settings") {
    assert(fixture.notesAttempted && fixture.setupAttempted, "Resume only the original configured note fixture");
    assert((await note(fixture.folder + "/" + fixture.source)).content === fixture.sourceContent && (await note(fixture.folder + "/" + fixture.wysiwyg)).content === fixture.richContent, "Both original saves already completed; no note replay");
    await finishSettings();
  } else assert(fixture.firstRunComplete === true, "Preservation fixture completed its original UI mutations");
  record.notes = [];
  for (const [title, expected] of [[fixture.source, fixture.sourceContent], [fixture.wysiwyg, fixture.richContent]]) {
    const path = fixture.folder + "/" + title;
    const observed = await note(path);
    assert(observed.content === expected, `Exact saved API bytes: ${title}`);
    await goto("/" + path);
    const rendered = title === fixture.source
      ? `document.querySelector('.toast-viewer h1')?.textContent===${json(fixture.marker)} && document.querySelector('.toast-viewer p')?.textContent===${json("Source edited " + fixture.marker)}`
      : `document.querySelector('.toast-viewer p')?.textContent===${json("Rich edited " + fixture.marker)}`;
    await poll(rendered);
    assert(await evaluate(rendered), `Exact saved content is rendered: ${title}`);
    record.notes.push({ path, content: observed.content, ui: await evaluate("document.querySelector('.toast-viewer').innerText") });
  }
  await goto("/_/search?term=" + fixture.marker);
  const link = `a[href="/${fixture.folder}/${fixture.source}"]`;
  await poll(`!!document.querySelector(${json(link)})`); await click(link);
  await poll(`decodeURIComponent(location.pathname)===${json("/" + fixture.folder + "/" + fixture.source)} && document.querySelector('.toast-viewer')?.textContent.includes(${json(fixture.marker)})`);
  assert(true, "Unique-marker search finds and opens the saved nested note");
  record.backupSettings = await api("/_/api/plugin-host/globnotes-backup/settings/backup");
  assert(record.backupSettings.values.retention === 3, "Persisted plugin setting reaches the API consumer");
  await settingsOpen();
  assert(await evaluate("document.querySelector('#settings-field-retention').value==='3'"), "Persisted plugin setting reaches the reopened UI control");
  await settingsClose();
  record.backupWorker = await api("/_/api/plugins/globnotes-backup/status");
  assert(record.backupWorker !== null, "Actual backup plugin Worker round trip returns a status");
  if (phase === "http-consent") {
    await consentHttp();
    fixture.httpConsentComplete = true; await save(fixturePath, fixture);
  }
  if (phase === "http-before" || phase === "http-after" || phase === "http-force") {
    const before = phase === "http-before", forced = phase === "http-force", key = forced ? "httpForceAttempted" : before ? "httpBeforeAttempted" : "httpAfterAttempted";
    assert(fixture.httpConsentComplete && !fixture[key], "HTTP-module command is admitted once after normal consent");
    if (!before) assert(fixture.httpBeforeComplete, "Offline baseline exists before the actual release transition");
    if (forced) assert(fixture.httpAfterComplete && !fixture.httpForceComplete, "One separately recorded current-version rebuild follows the original completed transition");
    record.httpPermission = await api(httpPermissionRoute);
    assert(permittedHttp(record.httpPermission), "Previously approved HTTP-module rights remain effective without permission edits");
    fixture[key] = true; await save(fixturePath, fixture);
    record.httpDependency = await api("/_/api/plugin-host/native-http-cache/commands/consume", "POST", {});
    const result = record.httpDependency.result;
    assert(result.moduleIdentity === "su-native-http-module-v2" && result.value === "cache-value-42", "Actual cached-only Worker imports the unavailable provider's original HTTP module");
    assert(result.checks === (forced ? 3 : before ? 1 : 2), "HTTP plugin private data continues across the recorded operation");
    fixture[forced ? "httpForceComplete" : before ? "httpBeforeComplete" : "httpAfterComplete"] = true; await save(fixturePath, fixture);
  }
  if (phase === "all-after" && args["expected-http"] === "yes") {
    assert(fixture.httpAfterComplete, "Post-update cached import was already observed");
    record.httpDependencyReadback = await api("/_/api/plugin-host/native-http-cache/commands/observe", "POST", {});
    assert(record.httpDependencyReadback.result.checks === (fixture.httpForceComplete ? 3 : 2) && record.httpDependencyReadback.result.value === "cache-value-42", "Persisted HTTP dependency result reaches a fresh authenticated Worker consumer");
    record.httpPermission = await api(httpPermissionRoute);
    assert(permittedHttp(record.httpPermission), "HTTP module consent remains unchanged at the final consumer");
  }
  assert(record.exceptions.length === 0, "No uncaught browser runtime exceptions");
  assert(record.network.some(row => row.url.includes("/_/assets/") && row.status === 200), "Installed production assets reached the browser");
  if (phase === "all-after") {
    await poll("(()=>{const e=document.querySelector('.toast-viewer p');if(!e)return false;const r=e.getBoundingClientRect();const hit=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return r.width>0&&r.height>0&&r.x>=0&&r.right<=innerWidth&&e.contains(hit)})()");
    assert(true, "Final saved note is unobscured and inside the real browser viewport");
    await evaluate("document.fonts.ready.then(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))))");
    const { data } = await page.send("Page.captureScreenshot", { format: "png" });
    await Deno.writeFile(`${evidence}/${label}.png`, Uint8Array.from(atob(data), char => char.charCodeAt(0)), { createNew: true, mode: 0o600 });
    record.screenshot = `${label}.png`;
  }
  record.completed = true;
  await save(`${evidence}/${label}-consumers.json`, record, true);
  success = true;
  console.log(`NATIVE BROWSER ${phase} CONSUMERS OBSERVED`);
} catch (error) {
  record.failure = error.message;
  record.page = await evaluate("({url:location.href,body:document.body.innerText,source:document.querySelector('.cm-content')?.textContent,rich:document.querySelector('.ProseMirror')?.textContent})").catch(() => null);
  await save(`${evidence}/${label}-failure.json`, record, true);
  throw error;
} finally {
  page.close();
  if (success) { await browser.send("Target.closeTarget", { targetId }); await browser.send("Target.disposeBrowserContext", { browserContextId }); }
  browser.close();
}
