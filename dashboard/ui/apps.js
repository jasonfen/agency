// The app catalog, at /apps: every app in apps.nix, by group, with a button
// to add or remove it. Adding or removing starts a job, as on the home page.

let catalog = null; // { apps: [...], error }
let jobRunning = false;
let lastJob = null;
let group = "All";
let query = "";

const kindNote = (a) => (a.kind === "npm" ? "npm" : "System");

function drawGroups() {
  if (!catalog || catalog.error) return;
  const names = ["All", ...new Set(catalog.apps.map((a) => a.group))];
  setHTML($("#groups"), names.map((g) =>
    `<button type="button" class="filter ${g === group ? "is-current" : ""}" data-group="${esc(g)}" aria-pressed="${g === group}">${esc(g)}</button>`).join(""));
}

function card(a) {
  const button = a.on
    ? `<button type="button" class="button" data-app="${esc(a.id)}" data-on="1" ${jobRunning ? "disabled" : ""}>Remove</button>`
    : `<button type="button" class="button button--solid" data-app="${esc(a.id)}" data-on="0" ${jobRunning ? "disabled" : ""}>Add</button>`;
  return `<article class="app ${a.on ? "is-on" : ""}">
    <div class="app-head">
      ${appLogo(a)}
      <div class="app-title">
        <p class="app-name">${esc(a.label)}</p>
        <p class="app-id mono">${esc(a.id)}</p>
      </div>
      ${a.on ? `<span class="on">On</span>` : ""}
    </div>
    <p class="app-text">${esc(a.description)}</p>
    <div class="app-foot"><span class="tag">${kindNote(a)}</span>${button}</div>
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

async function loadCatalog() {
  try {
    catalog = await api("/api/apps");
  } catch {
    catalog = { apps: [], error: "the server did not answer" };
  }
  drawGroups();
  drawCatalog();
}

// ---------------------------------------------------------------- polling

let timer = null;

async function refresh() {
  clearTimeout(timer);
  try {
    const s = await api("/api/state");
    if (s.error) {
      showNotice(s.error);
    } else {
      const wasRunning = jobRunning;
      jobRunning = !!(s.job && s.job.state === "running");
      drawHeader(s);
      document.title = `Apps - ${s.hostname} - agency`;
      drawJob(s.job);
      // A job ended: which apps are on may have changed.
      if (s.job && !jobRunning && s.job.id !== lastJob) {
        lastJob = s.job.id;
        if (wasRunning) loadCatalog();
      }
      if (wasRunning !== jobRunning) drawCatalog();
    }
  } catch {
    // The dashboard restarts during some rebuilds. Try again shortly.
  }
  timer = setTimeout(refresh, jobRunning ? 1500 : 6000);
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
    const on = t.dataset.on === "1";
    const app = catalog.apps.find((a) => a.id === t.dataset.app);
    if (on && !confirm(`Remove ${app ? app.label : t.dataset.app}?`)) return;
    const started = await startJob(on ? "/api/apps/remove" : "/api/apps/add", { id: t.dataset.app });
    if (started) scrollTo({ top: 0 });
    return;
  }
  switch (t.dataset.action) {
    case "job-dismiss":
      await api("/api/job/dismiss", {});
      return refresh();
    case "notice-close":
      return showNotice("");
  }
});

$("#search").addEventListener("input", (ev) => {
  query = ev.target.value;
  drawCatalog();
});

refresh();
loadCatalog();
