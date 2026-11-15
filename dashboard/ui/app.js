// agency dashboard. Plain JavaScript; the server is dashboard/server.py.
//
// The page asks for /api/state every few seconds and draws each section
// from it. Changes (update, apps, secrets, desktops, rollback) start a job
// on the server; while one runs, the others wait and its log shows at the top.

let state = null;
let appList = null;
let jobRunning = false;
let appsAfterJob = null;
const shots = {}; // desktop number -> object URL of its newest picture

// ----------------------------------------------------------------- pieces

const gb = (bytes) => {
  const n = bytes / 1e9;
  return n >= 100 ? n.toFixed(0) : n.toFixed(1).replace(/\.0$/, "");
};

function day(stamp) {
  if (!stamp) return "";
  const then = new Date(stamp * 1000);
  const days = Math.round((new Date().setHours(0, 0, 0, 0) - new Date(then).setHours(0, 0, 0, 0)) / 864e5);
  if (days === 0) return "today";
  if (days === 1) return "yesterday";
  return "on " + then.toLocaleDateString(undefined, { day: "numeric", month: "short" });
}

function ago(stamp) {
  const s = Math.max(0, Date.now() / 1000 - stamp);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  return day(stamp);
}

const dis = () => (jobRunning ? "disabled" : "");

// --------------------------------------------------------------- sections

function drawUpdates(u) {
  let text;
  let button = "";
  const repo = esc(u.repo || "the agency repo");
  // u.status is the server's: unlinked, behind, error, current or unchecked.
  if (u.status === "unlinked") {
    text = "This machine is not linked to the agency repo yet. Update links it and gets the newest version.";
    button = `<button type="button" class="button button--primary" data-action="update" ${dis()}>Update</button>`;
  } else if (u.status === "behind") {
    const list = u.subjects.map((s) => `<li>${esc(s)}</li>`).join("");
    text = `<strong>${u.behind} update${u.behind === 1 ? "" : "s"}</strong> from ${repo}.<ul>${list}</ul>`;
    button = `<button type="button" class="button button--primary" data-action="update" ${dis()}>Update</button>`;
  } else if (u.status === "error") {
    text = esc(u.error);
    button = `<button type="button" class="button" data-action="check">Check again</button>`;
  } else if (u.status === "current") {
    text = `Up to date with ${repo}. <span class="muted">Checked ${ago(u.checked)}.</span>`;
    button = `<button type="button" class="button" data-action="check">Check again</button>`;
  } else {
    text = "Not checked for updates yet.";
    button = `<button type="button" class="button" data-action="check">Check now</button>`;
  }
  setHTML($("#updates"), `<div>${text}</div>${button}`);
}

function drawDesktops(list) {
  const host = location.hostname;
  const last = list.length;
  const html = list.map((d) => {
    const detail = !d.running ? "Stopped"
      : d.windows === null ? "Running"
      : d.windows === 0 ? "No windows open"
      : `${d.windows} window${d.windows === 1 ? "" : "s"} open`;
    const remove = d.n === last && d.n > 1
      ? `<button type="button" class="button button--danger" data-action="desktop-remove" ${dis()}>Remove</button>` : "";
    return `<article class="card">
      <div class="shot" data-shot="${d.n}">${d.running ? `<img alt="What desktop :${d.n} shows" hidden>` : "Stopped"}</div>
      <div class="card-foot">
        <div><p class="card-name">Desktop :${d.n}</p><p class="card-detail">${detail}</p></div>
        <div class="buttons">${remove}
          <a class="button button--solid" href="${location.protocol}//${esc(host)}:${d.port}/" target="_blank" rel="noopener">Open</a>
        </div>
      </div>
    </article>`;
  }).join("");
  if (setHTML($("#desktop-list"), html)) {
    for (const img of document.querySelectorAll("[data-shot] img")) {
      const n = img.parentElement.dataset.shot;
      if (shots[n]) showShot(img, shots[n]);
    }
  }
}

// GitHub and T3 Code sign in with a short code shown here; the others in
// the terminal. logins[id] mirrors the server's sign-in state (idle,
// starting, waiting, done, failed), polled while starting or waiting.
const CODE_LOGINS = { github: "/api/github", t3: "/api/login/t3" };
const logins = { github: { state: "idle" }, t3: { state: "idle" } };
const loginTimers = {};
const busyLogin = (id) => ["starting", "waiting"].includes(logins[id]?.state);

async function pollLogin(id) {
  logins[id] = await api(CODE_LOGINS[id]);
  if (state) drawAccounts(state.accounts);
  if (busyLogin(id)) {
    loginTimers[id] = setTimeout(() => pollLogin(id), 2000);
  } else {
    loginTimers[id] = null;
    if (logins[id].state === "done") refresh();
  }
}

function loginPanel(id) {
  const l = logins[id];
  if (!l || l.state === "idle" || l.state === "done") return "";
  if (l.state === "starting") return `<div class="device"><p class="row-detail">Getting a sign-in code.</p></div>`;
  if (l.state === "failed") return `<div class="device"><p class="row-detail">${esc(l.error)}</p></div>`;
  const shown = l.url.replace(/^https:\/\//, "").replace(/\?.*$/, "");
  return `<div class="device">
    <div class="device-text">
      ${l.code
        ? `<p>Open <a href="${esc(l.url)}" target="_blank" rel="noopener">${esc(shown)}</a> and enter:</p>
      <p class="device-code mono">${esc(l.code)}</p>`
        : `<p>Open <a href="${esc(l.url)}" target="_blank" rel="noopener">${esc(shown)}</a> and finish signing in there.</p>`}
      <p class="row-detail">This updates by itself when you are done.</p>
    </div>
    <button type="button" class="button" data-login-cancel="${id}">Cancel</button>
  </div>`;
}

function drawAccounts(list) {
  setHTML($("#account-list"), list.map((a) => {
    const busy = busyLogin(a.id);
    const button = !a.installed || busy ? ""
      : a.signedIn ? `<button type="button" class="button" data-signin="${a.id}">Sign in again</button>`
      : `<button type="button" class="button button--solid" data-signin="${a.id}">Sign in</button>`;
    return `<div class="row">
      <div><p class="row-name">${esc(a.label)}</p><p class="row-detail">${a.signedIn ? `<span class="on">${esc(a.detail)}</span>` : esc(a.detail)}</p></div>
      ${button}
    </div>${a.id in CODE_LOGINS ? loginPanel(a.id) : ""}`;
  }).join(""));
}

// The home page lists the apps that are on; the catalog (/apps) has the rest.
function drawApps() {
  if (!appList) return;
  if (appList.error) {
    setHTML($("#app-list"), `<p class="row muted">The list did not load: ${esc(appList.error)}</p>`);
    return;
  }
  const on = appList.apps.filter((a) => a.on);
  setHTML($("#app-list"), on.map((a) => `<div class="row row--app">
      ${appLogo(a)}
      <div class="row-main"><p class="row-name">${esc(a.label)}</p><p class="row-detail">${esc(a.group)}</p></div>
    </div>`).join("") || `<p class="row muted">No apps yet.</p>`);
}

function drawSecrets(names) {
  const chips = names.map((n) => `<span class="chip"><span>${esc(n)}</span><button type="button" data-secret-remove="${esc(n)}" aria-label="Remove ${esc(n)}" title="Remove" ${dis()}>×</button></span>`).join("");
  const add = $("#secret-form").hidden ? `<button type="button" class="button chips-end" data-action="secret-add">Add a secret</button>` : "";
  setHTML($("#secret-list"), (chips || `<span class="muted">No secrets yet.</span>`) + add);
}

function drawSystem(s) {
  const rows = [];
  const made = day(s.generationTime);
  rows.push(["Version", s.generation ? `Generation ${s.generation}${made ? `, updated ${made}` : ""}` : "Unknown"]);
  rows.push(["Disk", `${gb(s.disk.used)} of ${gb(s.disk.total)} GB used`]);
  if (s.memory) rows.push(["Memory", `${gb(s.memory.used)} of ${gb(s.memory.total)} GB used`]);
  rows.push(["Recovery key", s.recoveryKey
    ? "Still on the disk. To save it and delete it, run <code>agency recovery-key</code> over SSH."
    : `<span class="on">Removed from the disk</span>`]);
  setHTML($("#system-facts"), rows.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join(""));
}

function draw(s) {
  state = s;
  const wasRunning = jobRunning;
  jobRunning = !!(s.job && s.job.state === "running");
  drawHeader(s);
  drawJob(s.job);
  drawUpdates(s.updates);
  drawDesktops(s.desktops);
  drawAccounts(s.accounts);
  drawSecrets(s.secrets);
  drawSystem(s.system);
  drawApps();
  for (const b of document.querySelectorAll("[data-job]")) b.disabled = jobRunning;
  // A job ended: the app list may have changed.
  if (s.job && !jobRunning && s.job.id !== appsAfterJob) {
    appsAfterJob = s.job.id;
    if (wasRunning) loadApps();
  }
}

// ---------------------------------------------------------------- polling

let timer = null;

async function refresh() {
  clearTimeout(timer);
  try {
    const s = await api("/api/state");
    if (s.error) showNotice(s.error);
    else draw(s);
  } catch {
    // The dashboard restarts during some rebuilds. Try again shortly.
  }
  timer = setTimeout(refresh, jobRunning ? 1500 : 6000);
}

async function loadApps() {
  try {
    appList = await api("/api/apps");
  } catch {
    appList = { apps: [], error: "the server did not answer" };
  }
  drawApps();
}

// Desktop pictures: a new one every few seconds while the section is on screen.
let desktopsVisible = false;
new IntersectionObserver((entries) => {
  desktopsVisible = entries.some((e) => e.isIntersecting);
}).observe($("#desktops"));

function showShot(img, url) {
  img.onload = () => { img.hidden = false; };
  img.onerror = () => { img.hidden = true; };
  img.src = url;
}

async function refreshShots() {
  if (desktopsVisible && !document.hidden && state) {
    for (const d of state.desktops.filter((x) => x.running)) {
      try {
        const r = await fetch(`/api/desktops/${d.n}/shot`, { cache: "no-store" });
        if (!r.ok) continue;
        const url = URL.createObjectURL(await r.blob());
        if (shots[d.n]) URL.revokeObjectURL(shots[d.n]);
        shots[d.n] = url;
        const img = document.querySelector(`[data-shot="${d.n}"] img`);
        if (img) showShot(img, url);
      } catch {
        // Skip this round.
      }
    }
  }
  setTimeout(refreshShots, 4000);
}

// The terminal starts a shell, so load it only once it is near the screen.
function openTerminal(src) {
  const frame = $("#term");
  if (frame.getAttribute("src") !== src) frame.src = src;
}
new IntersectionObserver((entries, obs) => {
  if (entries.some((e) => e.isIntersecting)) {
    if (!$("#term").getAttribute("src")) openTerminal("/terminal/");
    obs.disconnect();
  }
}, { rootMargin: "200px" }).observe($("#terminal"));

// The nav marks the section in view: the last one whose top has passed a
// line near the top of the window. Sections side by side count as the first.
const links = [...document.querySelectorAll(".nav a")];
let picked = null; // a section chosen in the nav wins while it is on screen
function markNav() {
  let current = links[0];
  let lastTop = null;
  for (const a of links) {
    const top = Math.round(document.getElementById(a.getAttribute("href").slice(1)).getBoundingClientRect().top);
    if (top <= innerHeight * 0.3 && top !== lastTop) current = a;
    lastTop = top;
  }
  if (picked) {
    const r = document.getElementById(picked.getAttribute("href").slice(1)).getBoundingClientRect();
    if (r.top < innerHeight && r.bottom > 0) current = picked;
    else picked = null;
  }
  for (const a of links) a.classList.toggle("is-current", a === current);
}
let navQueued = false;
addEventListener("scroll", () => {
  if (navQueued) return;
  navQueued = true;
  requestAnimationFrame(() => { navQueued = false; markNav(); });
}, { passive: true });
for (const a of links) a.addEventListener("click", () => { picked = a; setTimeout(markNav, 50); });

// ---------------------------------------------------------------- actions

const NAMES = { github: "GitHub", claude: "Claude Code", codex: "Codex", opencode: "OpenCode", t3: "T3 Code" };

document.addEventListener("click", async (ev) => {
  const t = ev.target.closest("button");
  if (!t) return;
  const action = t.dataset.action;

  if (t.dataset.signin in CODE_LOGINS) {
    const id = t.dataset.signin;
    logins[id] = await api(`${CODE_LOGINS[id]}/start`, {});
    clearTimeout(loginTimers[id]);
    pollLogin(id);
    return;
  }
  if (t.dataset.loginCancel) {
    const id = t.dataset.loginCancel;
    logins[id] = await api(`${CODE_LOGINS[id]}/cancel`, {});
    clearTimeout(loginTimers[id]);
    drawAccounts(state.accounts);
    return;
  }
  if (t.dataset.signin) {
    const tool = t.dataset.signin;
    openTerminal(`/terminal/?arg=${encodeURIComponent(tool)}`);
    $("#term-note").innerHTML = `Signing in to ${esc(NAMES[tool] || tool)}. Follow the steps in the terminal. <button type="button" class="button" data-action="term-shell">Back to the shell</button>`;
    $("#terminal").scrollIntoView();
    return;
  }
  if (t.dataset.secretRemove) {
    const name = t.dataset.secretRemove;
    if (!confirm(`Remove the secret ${name}? Agents can no longer read it.`)) return;
    return startJob("/api/secrets/remove", { name });
  }

  switch (action) {
    case "update":
      return startJob("/api/update");
    case "check":
      t.disabled = true;
      t.textContent = "Checking";
      await api("/api/update/check", {});
      return refresh();
    case "rollback":
      if (!confirm("Go back to the previous system? /etc/nixos does not change, so the next rebuild brings this one back.")) return;
      return startJob("/api/rollback");
    case "desktop-add":
      return startJob("/api/desktops/add");
    case "desktop-remove":
      if (!confirm(`Remove desktop :${state.desktops.length}? Apps open on it close.`)) return;
      return startJob("/api/desktops/remove");
    case "job-dismiss":
      await api("/api/job/dismiss", {});
      return refresh();
    case "notice-close":
      return showNotice("");
    case "secret-add":
      $("#secret-form").hidden = false;
      drawSecrets(state.secrets);
      $("#secret-form [name=name]").focus();
      return;
    case "secret-cancel":
      $("#secret-form").reset();
      $("#secret-form").hidden = true;
      return drawSecrets(state.secrets);
    case "term-shell":
      openTerminal("/terminal/");
      $("#term-note").textContent = "A shell on the machine, in your browser. Start an agent here, or attach to your tmux sessions.";
      return;
  }
});

$("#secret-form [name=name]").addEventListener("input", (ev) => {
  ev.target.value = ev.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, "_");
});

$("#secret-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const form = ev.target;
  const name = form.elements.name.value;
  const value = form.elements.value.value;
  if (await startJob("/api/secrets/set", { name, value })) {
    form.reset();
    form.hidden = true;
    drawSecrets(state.secrets);
  }
});

refresh();
loadApps();
refreshShots();
// A sign-in may already be under way, from before a reload or another tab.
for (const id of Object.keys(CODE_LOGINS)) pollLogin(id).catch(() => {});
