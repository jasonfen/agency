// The app catalog, at /apps: every app in apps.nix, by group, with a button
// to add or remove it.
//
// A click never moves the page. The card shows what is happening to its
// app, and the bar at the bottom of the window (common.js) shows the
// running change and its log. Clicks while a change runs wait in a queue on
// the server; when the change finishes, the server sends everything queued as
// one change (one rebuild at most), whether or not this page is still open.

let catalog = null; // { apps: [...], error }
let job = null; // the server's current job, or null
let lastFinished = null; // id of the last job we saw finish
let group = "All";
let query = "";
let queue = new Map(); // app id -> "add" | "remove", as the server last said

const running = () => !!(job && job.state === "running");
const byId = (id) => catalog?.apps.find((a) => a.id === id);
const label = (id) => byId(id)?.label || id;
const listed = (ids) => {
  const names = ids.map(label);
  return names.length < 2 ? names.join("") : names.slice(0, -1).join(", ") + " and " + names.at(-1);
};

// What is happening to an app now: "adding", "removing", "queued-add",
// "queued-remove", or "".
function appState(id) {
  if (running() && job.apps) {
    if (job.apps.add?.includes(id)) return "adding";
    if (job.apps.remove?.includes(id)) return "removing";
  }
  if (queue.has(id)) return `queued-${queue.get(id)}`;
  return "";
}

// ---------------------------------------------------------------- drawing

function drawGroups() {
  if (!catalog || catalog.error) return;
  const names = ["All", ...new Set(catalog.apps.map((a) => a.group))];
  setHTML($("#groups"), names.map((g) =>
    `<button type="button" class="filter ${g === group ? "is-current" : ""}" data-group="${esc(g)}" aria-pressed="${g === group}">${esc(g)}</button>`).join(""));
}

function cardAction(a) {
  const st = appState(a.id);
  if (st === "adding") return `<span class="busy"><span class="spinner"></span>Installing</span>`;
  if (st === "removing") return `<span class="busy"><span class="spinner"></span>Removing</span>`;
  if (st.startsWith("queued")) {
    return `<span class="queued">${st === "queued-add" ? "Will be added" : "Will be removed"}</span>
      <button type="button" class="button" data-undo="${esc(a.id)}">Undo</button>`;
  }
  return a.on
    ? `<button type="button" class="button button--danger" data-app="${esc(a.id)}" data-on="1">Remove</button>`
    : `<button type="button" class="button button--solid" data-app="${esc(a.id)}" data-on="0">Add</button>`;
}

function card(a) {
  const st = appState(a.id);
  return `<article class="app ${a.on ? "is-on" : ""} ${st ? "is-busy" : ""}">
    <div class="app-head">
      ${appLogo(a)}
      <div class="app-title">
        <p class="app-name">${esc(a.label)}</p>
        <p class="app-id mono">${esc(a.id)}</p>
      </div>
      ${a.on ? `<span class="on">Installed</span>` : ""}
    </div>
    <p class="app-text">${esc(a.description)}${a.on && a.signin ? `<br>Sign in with <code>${esc(a.signin)}</code>` : ""}</p>
    <div class="app-foot"><span class="tag">${a.kind === "npm" ? "Bun" : "System"}</span><span class="app-action">${cardAction(a)}</span></div>
  </article>`;
}

function drawCatalog() {
  if (!catalog) return;
  if (catalog.error) {
    setHTML($("#catalog"), `<p class="muted">The catalog did not load: ${esc(catalog.error)}</p>`);
    return;
  }
  const q = query.trim().toLowerCase();
  const shown = catalog.apps.filter((a) =>
    (group === "All" || a.group === group) &&
    (!q || [a.label, a.id, a.description, a.group].some((s) => s.toLowerCase().includes(q))));
  const groups = [...new Set(shown.map((a) => a.group))];
  setHTML($("#catalog"), groups.map((g) => `<section class="section">
      <h3>${esc(g)}</h3>
      <div class="apps">${shown.filter((a) => a.group === g).map(card).join("")}</div>
    </section>`).join("") || `<p class="muted">No app matches.</p>`);
}

// The bar at the bottom (common.js), with what is queued after the job.
// The catalog's notices show in it too.
function drawCatalogDock() {
  const adds = [...queue].filter(([, v]) => v === "add").map(([k]) => k);
  const removes = [...queue].filter(([, v]) => v === "remove").map(([k]) => k);
  const next = [adds.length && `add ${listed(adds)}`, removes.length && `remove ${listed(removes)}`].filter(Boolean).join(", ");
  drawDock(job, { next, keep: queue.size || !!$("#notice").innerHTML });
}

function drawAll() {
  drawCatalog();
  drawCatalogDock();
}

// ---------------------------------------------------------------- server

async function loadCatalog() {
  try {
    catalog = await api("/api/apps");
    if (!catalog.error) remember("apps", catalog);
  } catch {
    catalog = { apps: [], error: "the server did not answer" };
  }
  drawGroups();
  drawAll();
}

// Put an app in the server's queue (want "add" or "remove"), or take it out
// (want null). The server starts it at once if nothing is running.
async function enqueue(id, want) {
  if (want) queue.set(id, want);
  else queue.delete(id);
  drawAll();
  showNotice("");
  let result;
  try {
    result = await api("/api/apps/queue", { id, want });
  } catch {
    result = { ok: false, error: "The server did not answer." };
  }
  if (!result.ok) showNotice(result.error || "That did not start.");
  return refresh();
}

let timer = null;

async function refresh() {
  clearTimeout(timer);
  try {
    const s = await api("/api/state");
    if (s.error) {
      showNotice(s.error);
    } else {
      drawHeader(s);
      document.title = "Apps - agency";
      const wasRunning = running();
      const lastId = job?.id;
      job = s.job;
      queue = new Map(Object.entries(s.queue || {}));
      // A change finished: reload which apps are on. The server may have
      // started the queued one already, so a new job id counts too.
      if (job && !running() && job.id !== lastFinished) {
        lastFinished = job.id;
        if (wasRunning || job.kind === "apps") await loadCatalog();
      } else if (wasRunning && job?.id !== lastId) {
        await loadCatalog();
      }
      drawAll();
    }
  } catch {
    // The dashboard restarts during some rebuilds. Try again shortly.
  }
  timer = setTimeout(refresh, running() || queue.size ? 1500 : 6000);
}

// ---------------------------------------------------------------- actions

document.addEventListener("click", async (ev) => {
  const t = ev.target.closest("button");
  if (!t) return;
  if (t.dataset.group) {
    group = t.dataset.group;
    drawGroups();
    return drawCatalog();
  }
  if (t.dataset.app) {
    const id = t.dataset.app;
    const on = t.dataset.on === "1";
    if (on && !confirm(`Remove ${label(id)}?`)) return;
    return enqueue(id, on ? "remove" : "add");
  }
  if (t.dataset.undo) {
    return enqueue(t.dataset.undo, null);
  }
  switch (t.dataset.action) {
    case "job-dismiss":
      await api("/api/job/dismiss", {});
      return refresh();
    case "notice-close":
      showNotice("");
      return drawCatalogDock();
  }
});

$("#search").addEventListener("input", (ev) => {
  query = ev.target.value;
  drawCatalog();
});

// Draw the catalog the last visit saw until the server answers, so the
// page has its size from the start. The bar waits for the server.
const last = recall("apps");
if (last && !last.error) {
  catalog = last;
  drawGroups();
  drawCatalog();
}
const lastState = recall("state");
if (lastState) drawHeader({ ...lastState, state: null });

refresh();
loadCatalog();
