// The app catalog, at /apps: every app in apps.nix, by group, with a button
// to add or remove it.
//
// A click never moves the page. The card shows what is happening to its
// app, and a bar at the bottom of the window shows the running change and
// its log. Clicks while a change runs wait in a queue; when the change
// finishes, everything queued goes as one change (one rebuild at most).

let catalog = null; // { apps: [...], error }
let job = null; // the server's current job, or null
let lastFinished = null; // id of the last job we saw finish
let group = "All";
let query = "";
let logOpen = false;
const queue = new Map(); // app id -> "add" | "remove"

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
    <p class="app-text">${esc(a.description)}</p>
    <div class="app-foot"><span class="tag">${a.kind === "npm" ? "npm" : "System"}</span><span class="app-action">${cardAction(a)}</span></div>
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

// The bar at the bottom: the running (or just finished) change, what is
// queued after it, and the log on request.
function drawDock() {
  const adds = [...queue].filter(([, v]) => v === "add").map(([k]) => k);
  const removes = [...queue].filter(([, v]) => v === "remove").map(([k]) => k);
  const next = [adds.length && `add ${listed(adds)}`, removes.length && `remove ${listed(removes)}`].filter(Boolean).join(", ");
  const show = job || queue.size || $("#notice").innerHTML;
  $("#dock").hidden = !show;
  document.body.classList.toggle("has-dock", !!show);
  if (!show) return setHTML($("#dock-body"), "");

  let mark = "", title = "", detail = "";
  const lastLine = job?.log?.filter((l) => l.trim()).at(-1) || "";
  if (running()) {
    mark = "is-running";
    title = esc(job.title);
    detail = lastLine ? `<span class="mono">${esc(lastLine)}</span>` : "Starting.";
  } else if (job?.state === "done") {
    mark = "is-done";
    title = `Done: ${esc(job.title.replace(/^./, (c) => c.toLowerCase()))}`;
  } else if (job?.state === "failed") {
    mark = "is-failed";
    title = `It failed: ${esc(job.title.replace(/^./, (c) => c.toLowerCase()))}`;
    detail = "The log says why.";
  } else {
    title = "Starting the change.";
  }
  const then = next ? `<p class="dock-next">${running() ? "Next" : "Waiting to"}: ${esc(next)}</p>` : "";
  const buttons = [
    job ? `<button type="button" class="button" data-action="log">${logOpen ? "Hide the log" : "Show the log"}</button>` : "",
    job && !running() ? `<button type="button" class="button" data-action="job-dismiss">Close</button>` : "",
  ].join("");
  setHTML($("#dock-body"), `<div class="dock-row">
      <span class="job-mark dock-mark ${mark}"></span>
      <div class="dock-text">
        <p class="dock-title">${title}</p>
        ${detail ? `<p class="dock-detail">${detail}</p>` : ""}
        ${then}
      </div>
      <div class="buttons">${buttons}</div>
    </div>`);
  $("#dock").classList.toggle("is-running", running());

  const log = $("#dock-log");
  log.hidden = !(logOpen && job);
  if (!log.hidden) {
    const atEnd = log.scrollHeight - log.scrollTop - log.clientHeight < 24;
    if (setHTML(log, esc(job.log.join("\n")) || "Starting.") && atEnd) log.scrollTop = log.scrollHeight;
  }
}

function drawAll() {
  drawCatalog();
  drawDock();
}

// ---------------------------------------------------------------- server

async function loadCatalog() {
  try {
    catalog = await api("/api/apps");
  } catch {
    catalog = { apps: [], error: "the server did not answer" };
  }
  drawGroups();
  drawAll();
}

// Send everything queued as one change. Only when nothing is running.
let flushing = false;
async function flushQueue() {
  if (flushing || running() || !queue.size) return;
  flushing = true;
  const sent = new Map(queue);
  const add = [...sent].filter(([, v]) => v === "add").map(([k]) => k);
  const remove = [...sent].filter(([, v]) => v === "remove").map(([k]) => k);
  showNotice("");
  let result;
  try {
    result = await api("/api/apps/change", { add, remove });
  } catch {
    result = { ok: false, error: "The server did not answer." };
  }
  const forget = () => {
    // Only what was sent: clicks made meanwhile stay queued.
    for (const [id, v] of sent) if (queue.get(id) === v) queue.delete(id);
  };
  if (result.ok) {
    await refresh(); // the cards show the running job before leaving the queue
    forget();
  } else if (!result.busy) {
    // busy: another change started first; the queue goes when it ends.
    showNotice(result.error || "That did not start.");
    forget();
  }
  flushing = false;
  drawAll();
  if (!result.ok) await refresh();
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
      job = s.job;
      // A change finished: reload which apps are on, then send the queue.
      if (job && !running() && job.id !== lastFinished) {
        lastFinished = job.id;
        if (wasRunning || job.kind === "apps") await loadCatalog();
        if (job.state === "failed") logOpen = true;
      }
      drawAll();
      if (!running() && queue.size) return flushQueue();
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
    queue.set(id, on ? "remove" : "add");
    drawAll();
    return flushQueue();
  }
  if (t.dataset.undo) {
    queue.delete(t.dataset.undo);
    return drawAll();
  }
  switch (t.dataset.action) {
    case "log":
      logOpen = !logOpen;
      return drawDock();
    case "job-dismiss":
      await api("/api/job/dismiss", {});
      logOpen = false;
      return refresh();
    case "notice-close":
      showNotice("");
      return drawDock();
  }
});

$("#search").addEventListener("input", (ev) => {
  query = ev.target.value;
  drawCatalog();
});

// Queued changes live only in this page until they are sent.
addEventListener("beforeunload", (ev) => {
  if (queue.size) ev.preventDefault();
});

refresh();
loadCatalog();
