// agency dashboard. Plain JavaScript; the server is dashboard/server.py.
//
// The page asks for /api/state every few seconds and draws each section
// from it: the system's vitals, desktops, the terminal and the apps that are on. Accounts,
// secrets and the system are in Settings (settings.js). Changes start a job
// on the server; while one runs, the others wait and it shows in the bar at
// the bottom (common.js).

let state = null;
let appList = null;
let jobRunning = false;
let appsAfterJob = null;
const shots = {}; // desktop number -> object URL of its newest picture

// ----------------------------------------------------------------- pieces

const dis = () => (jobRunning ? "disabled" : "");

// --------------------------------------------------------------- sections

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

// System: CPU and memory over the last ten minutes, and every disk.

const pct = (n) => `${Math.round(n)}%`;

function uptimeText(sec) {
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  return d ? `${d} d ${h} h` : h ? `${h} h ${m} min` : `${m} min`;
}

// A chart of percentages, 0 to 100, over a fixed window that ends at the
// newest sample. points: [[time, percent, text for the tooltip], ...].
const charts = {};

function chart(el, points, span) {
  let c = charts[el.id];
  if (!c) {
    el.innerHTML = `<svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
        <line class="spark-grid" x1="0" x2="100" y1="50" y2="50" vector-effect="non-scaling-stroke"/>
        <line class="spark-grid" x1="0" x2="100" y1="0" y2="0" vector-effect="non-scaling-stroke"/>
        <path class="spark-area"/><path class="spark-line" vector-effect="non-scaling-stroke"/>
      </svg>
      <span class="spark-tick" style="top:0">100%</span><span class="spark-tick" style="top:50%">50%</span>
      <span class="spark-axis spark-axis--start">${Math.round(span / 60)} min ago</span>
      <span class="spark-axis spark-axis--end">now</span>
      <div class="spark-cross" hidden></div><div class="spark-dot" hidden></div><div class="spark-tip" hidden></div>`;
    c = charts[el.id] = { points: [], at: null, span };
    const move = (x) => {
      const r = el.getBoundingClientRect();
      c.at = Math.min(1, Math.max(0, (x - r.left) / r.width));
      hover(el, c);
    };
    el.addEventListener("pointermove", (e) => move(e.clientX));
    el.addEventListener("pointerdown", (e) => move(e.clientX));
    el.addEventListener("pointerleave", () => { c.at = null; hover(el, c); });
  }
  c.points = points;
  c.end = points.length ? points[points.length - 1][0] : 0;
  const x = (t) => 100 - ((c.end - t) / span) * 100;
  const y = (v) => 100 - Math.min(100, Math.max(0, v));
  const shown = points.filter((p) => c.end - p[0] <= span);
  const line = shown.map((p, i) => `${i ? "L" : "M"}${x(p[0]).toFixed(2)} ${y(p[1]).toFixed(2)}`).join("");
  el.querySelector(".spark-line").setAttribute("d", line);
  el.querySelector(".spark-area").setAttribute("d", shown.length
    ? `${line}L${x(shown[shown.length - 1][0]).toFixed(2)} 100L${x(shown[0][0]).toFixed(2)} 100Z` : "");
  const last = shown[shown.length - 1];
  el.setAttribute("role", "img");
  el.setAttribute("aria-label", last ? `${el.dataset.label} over the last ${Math.round(span / 60)} minutes, now ${pct(last[1])}` : el.dataset.label);
  hover(el, c);
}

// The crosshair and tooltip at the sample nearest the pointer.
function hover(el, c) {
  const [cross, dot, tip] = [".spark-cross", ".spark-dot", ".spark-tip"].map((s) => el.querySelector(s));
  const t = c.at === null ? null : c.end - (1 - c.at) * c.span;
  let best = null;
  if (t !== null) for (const p of c.points) if (!best || Math.abs(p[0] - t) < Math.abs(best[0] - t)) best = p;
  cross.hidden = dot.hidden = tip.hidden = !best;
  if (!best) return;
  const left = 100 - ((c.end - best[0]) / c.span) * 100;
  cross.style.left = dot.style.left = `${left}%`;
  dot.style.top = `${100 - Math.min(100, best[1])}%`;
  const when = c.end - best[0] < 5 ? "now"
    : new Date(best[0] * 1000).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit", second: "2-digit" });
  tip.innerHTML = `<strong>${esc(best[2])}</strong> · ${esc(when)}`;
  // Keep the tooltip inside the card at the edges.
  tip.style.left = `${Math.min(85, Math.max(15, left))}%`;
}

function drawSystem(v) {
  if (!v) return;
  const span = 600;
  const h = v.history || [];
  const now = h[h.length - 1];
  const mem = v.memory;

  $("#cpu-now").textContent = now ? pct(now[1]) : "–";
  chart($("#cpu-chart"), h.map((p) => [p[0], p[1], pct(p[1])]), span);
  const cpuBits = [`${v.cores} cores`];
  if (v.load) cpuBits.push(`load ${v.load[0].toFixed(2)}`);
  if (v.temp) cpuBits.push(`${v.temp} °C`);
  if (v.uptime) cpuBits.push(`up ${uptimeText(v.uptime)}`);
  $("#cpu-detail").textContent = cpuBits.join(" · ");

  if (mem) {
    $("#mem-now").textContent = pct((100 * mem.used) / mem.total);
    chart($("#mem-chart"), h.filter((p) => p[2] !== null)
      .map((p) => [p[0], (100 * p[2]) / mem.total, `${gb(p[2])} GB`]), span);
    const bits = [`${gb(mem.used)} of ${gb(mem.total)} GB used`];
    if (v.swap) bits.push(`swap ${gb(v.swap.used)} of ${gb(v.swap.total)} GB`);
    $("#mem-detail").textContent = bits.join(" · ");
  }

  const disks = v.disks || [];
  setHTML($("#disk-list"), disks.length ? disks.map((d) => {
    const kind = [d.kind, d.removable ? "removable" : "", `${gb(d.size)} GB`].filter(Boolean).join(" · ");
    const where = d.system ? "System disk" : d.mounts.length ? `Mounted at ${d.mounts[0]}` : "Not mounted";
    const share = d.fsSize ? (100 * d.used) / d.fsSize : 0;
    const full = share >= 90;
    return `<div class="row disk">
      <div class="row-main">
        <p class="row-name">${esc(d.model || d.name)}</p>
        <p class="row-detail"><span class="mono">${esc(d.name)}</span> · ${esc(kind)} · ${esc(where)}</p>
      </div>
      <div class="disk-end">
        <p class="disk-use">${d.fsSize ? `${gb(d.used)} of ${gb(d.fsSize)} GB used${full ? " · <strong>almost full</strong>" : ""}` : `<span class="muted">Nothing mounted from it</span>`}</p>
        <div class="meter${full ? " is-full" : ""}${d.fsSize ? "" : " is-empty"}" role="meter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(share)}" aria-label="${esc(d.model || d.name)} space used"><div class="meter-fill" style="width:${share.toFixed(1)}%"></div></div>
      </div>
    </div>`;
  }).join("") : `<p class="row muted">No disks found.</p>`);
}

// The home page lists the apps that are on; the catalog (/apps) has the rest.
function drawApps() {
  if (!appList) return;
  if (appList.error) {
    setHTML($("#app-list"), `<p class="row muted">The list did not load: ${esc(appList.error)}</p>`);
    return;
  }
  // A compact grid of names, so a long list stays short. Past a dozen,
  // the rest is a link to the catalog, which has them all.
  const on = appList.apps.filter((a) => a.on);
  if (!on.length) {
    setHTML($("#app-list"), `<p class="row muted">No apps yet.</p>`);
    return;
  }
  const max = on.length > 12 ? 11 : 12;
  const more = on.length - max;
  setHTML($("#app-list"), `<div class="app-grid">${on.slice(0, max).map((a) => `<div class="app-tile" title="${esc(a.label)}, ${esc(a.group)}">
      ${appLogo(a)}<span>${esc(a.label)}</span>
    </div>`).join("")}${more > 0 ? `<a class="app-tile app-more" href="/apps">${more} more</a>` : ""}</div>`);
}

function draw(s) {
  state = s;
  const wasRunning = jobRunning;
  jobRunning = !!(s.job && s.job.state === "running");
  drawHeader(s);
  drawDock(s.job);
  // Here only when there is something to do; Settings has the rest.
  drawUpdates(["behind", "unlinked"].includes(s.updates.status) ? s.updates : null, jobRunning);
  drawSystem(s.vitals);
  drawDesktops(s.desktops);
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
    else {
      draw(s);
      remember("state", { ...s, job: null });
    }
  } catch {
    // The dashboard restarts during some rebuilds. Try again shortly.
  }
  timer = setTimeout(refresh, jobRunning ? 1500 : 6000);
}

async function loadApps() {
  try {
    appList = await api("/api/apps");
    if (!appList.error) remember("apps", appList);
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
// In tmux, xterm.js turns the wheel into arrow keys, which walk the shell's
// history. Keep the wheel from xterm.js; with nothing to scroll in the
// frame, the browser scrolls this page, at its usual speed. The frame is
// same-origin.
$("#term").addEventListener("load", (ev) => {
  let win;
  try { win = ev.target.contentWindow; win.document; } catch { return; }
  win.addEventListener("wheel", (e) => e.stopImmediatePropagation(), { capture: true, passive: true });
});
whenShown(() => new IntersectionObserver((entries, obs) => {
  if (entries.some((e) => e.isIntersecting)) {
    if (!$("#term").getAttribute("src")) openTerminal("/terminal/");
    obs.disconnect();
  }
}, { rootMargin: "200px" }).observe($("#terminal")));

// ---------------------------------------------------------------- actions

// Sign-ins that run in the terminal come here from Settings: /?signin=<tool>.
function signInHere(tool) {
  openTerminal(`/terminal/?arg=${encodeURIComponent(tool)}`);
  $("#term-note").innerHTML = `Signing in to ${esc(NAMES[tool] || tool)}. Follow the steps in the terminal. <button type="button" class="button" data-action="term-shell">Back to the shell</button>`;
  $("#terminal").scrollIntoView();
}

document.addEventListener("click", async (ev) => {
  const t = ev.target.closest("button");
  if (!t) return;
  const action = t.dataset.action;

  switch (action) {
    case "update":
      return startJob("/api/update");
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
    case "term-shell":
      openTerminal("/terminal/");
      $("#term-note").textContent = "A tmux shell, in your browser—how cool!";
      return;
  }
});

// Draw what the last visit saw until the server answers, so the sections
// have their size from the start. The pill says Loading until then.
const last = recall("state");
if (last) {
  drawHeader({ ...last, state: null });
  drawUpdates(["behind", "unlinked"].includes(last.updates?.status) ? last.updates : null);
  drawSystem(last.vitals);
  drawDesktops(last.desktops || []);
}
appList = recall("apps");
drawApps();

refresh();
loadApps();
whenShown(refreshShots);
const signin = new URLSearchParams(location.search).get("signin");
if (signin) {
  history.replaceState(null, "", "/#terminal");
  whenShown(() => signInHere(signin));
}
