// The settings page, at /settings: accounts, secrets, the system, and
// moving this machine's setup to another one (`agency export` and `agency
// import`, see cli/agency.py).
//
// An export is a job; when it is done the file waits on the server to be
// downloaded. An import is an upload first (with progress), then a job.

let state = null; // /api/state
let job = null;
let info = null; // /api/transfer
let uploading = null; // { sent, total } while a file goes up
let chosen = null; // the File picked or dropped, not sent yet

const running = () => !!(job && job.state === "running");

const size = (n) => {
  for (const unit of ["bytes", "KB", "MB", "GB"]) {
    if (n < 1000 || unit === "GB") return unit === "bytes" ? `${n} bytes` : `${n.toFixed(1)} ${unit}`;
    n /= 1000;
  }
};

function made(stamp) {
  return new Date(stamp * 1000).toLocaleString(undefined, { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });
}

// ---------------------------------------------------------------- drawing

// GitHub and T3 Code sign in with a short code shown here; the others in
// the terminal on the home page. logins[id] mirrors the server's sign-in state (idle,
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
    const label = a.signedIn ? "Sign in again" : "Sign in";
    const look = a.signedIn ? "button" : "button button--solid";
    // GitHub and T3 Code sign in here; the rest in the home page's terminal.
    const button = !a.installed || busy ? ""
      : a.id in CODE_LOGINS ? `<button type="button" class="${look}" data-signin="${a.id}">${label}</button>`
      : `<a class="${look}" href="/?signin=${encodeURIComponent(a.id)}">${label}</a>`;
    return `<div class="row">
      <div><p class="row-name">${esc(a.label)}</p><p class="row-detail">${a.signedIn ? `<span class="on">${esc(a.detail)}</span>` : esc(a.detail)}</p></div>
      ${button}
    </div>${a.id in CODE_LOGINS ? loginPanel(a.id) : ""}`;
  }).join(""));
}

// When each secret was added and last set, from the repo's history.
function when(stamp) {
  if (!stamp) return `<span class="muted">Unknown</span>`;
  const d = new Date(stamp * 1000);
  return `<time datetime="${d.toISOString()}" title="${esc(d.toLocaleString())}">${esc(d.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" }))}</time>`;
}

function drawSecrets(list) {
  const dis = running() ? "disabled" : "";
  setHTML($("#secret-list"), list.length ? `<table class="table">
    <thead><tr><th>Name</th><th class="wide">Added</th><th class="wide">Last changed</th><th><span class="sr-only">Actions</span></th></tr></thead>
    <tbody>${list.map((x) => `<tr>
      <td><span class="mono">${esc(x.name)}</span>${x.added ? `<span class="narrow">Added ${when(x.added)}</span>` : ""}</td>
      <td class="wide">${when(x.added)}</td>
      <td class="wide">${when(x.changed)}</td>
      <td><div class="buttons table-actions">
        <button type="button" class="button" data-secret-replace="${esc(x.name)}" ${dis}>Replace</button>
        <button type="button" class="button button--danger" data-secret-remove="${esc(x.name)}" ${dis}>Remove</button>
      </div></td>
    </tr>`).join("")}</tbody>
  </table>` : `<p class="row muted">No secrets yet.</p>`);
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


function drawExportFile() {
  const f = info?.export;
  const busy = running() && job.kind === "export";
  setHTML($("#export-file"), f && !busy
    ? `<div class="row file">
        <div class="row-main"><p class="row-name mono">${esc(f.name)}</p><p class="row-detail">${size(f.size)}, made ${esc(made(f.made))}</p></div>
        <div class="row-end">
          <a class="button button--solid" href="/api/export/download" download>Download</a>
          <button type="button" class="button button--danger" data-action="export-delete">Delete</button>
        </div>
      </div>`
    : "");
}

// The drop zone: empty, a file chosen here, a file going up, or one
// uploaded before (from an import that has not finished yet).
const ICON = `<svg class="drop-icon" viewBox="0 0 8 8" shape-rendering="crispEdges" aria-hidden="true">
  <path d="M3 0h2v1h1v1h1v1h-2v3h-2v-3h-2v-1h1v-1h1zM0 7h8v1h-8z"/></svg>`;

function drawUpload() {
  const drop = $("#drop");
  let html;
  if (uploading) {
    const pct = uploading.total ? Math.floor((100 * uploading.sent) / uploading.total) : 0;
    html = `${ICON}<span class="drop-text"><strong>Uploading ${pct}%</strong>
      <span>${size(uploading.sent)} of ${size(uploading.total)}</span>
      <span class="drop-bar"><span style="width:${pct}%"></span></span></span>`;
  } else if (chosen) {
    html = `${ICON}<span class="drop-text"><strong class="mono">${esc(chosen.name)}</strong><span>${size(chosen.size)}</span></span>
      <button type="button" class="button" data-action="file-clear">Remove</button>`;
  } else if (info?.upload) {
    html = `${ICON}<span class="drop-text"><strong>Export uploaded</strong><span>${size(info.upload.size)}, ready to import</span></span>
      <button type="button" class="button" data-action="import-discard">Discard</button>`;
  } else {
    html = `${ICON}<span class="drop-text"><strong>Choose an export file</strong><span>or drop it here</span></span>`;
  }
  drop.classList.toggle("is-chosen", !!(uploading || chosen || info?.upload));
  drop.classList.toggle("is-empty", !(uploading || chosen || info?.upload));
  setHTML(drop, html);
}

function draw() {
  if (state) {
    drawAccounts(state.accounts);
    drawSecrets(state.secrets);
    drawSystem(state.system);
    drawUpdates(state.updates, running());
  }
  drawExportFile();
  drawUpload();
  for (const b of document.querySelectorAll("[data-job]")) b.disabled = running() || !!uploading;
}

// ---------------------------------------------------------------- server

let timer = null;

async function refresh() {
  clearTimeout(timer);
  try {
    const [s, t] = await Promise.all([api("/api/state"), api("/api/transfer")]);
    if (s.error) {
      showNotice(s.error);
    } else {
      drawHeader(s);
      document.title = "Settings - agency";
      state = s;
      job = s.job;
      drawDock(job);
      remember("state", { ...s, job: null });
    }
    if (!t.error) {
      info = t;
      remember("transfer", t);
    }
    draw();
  } catch {
    // The dashboard restarts during some rebuilds. Try again shortly.
  }
  document.body.classList.remove("is-waiting");
  timer = setTimeout(refresh, running() ? 1500 : 6000);
}

// The raw file as the request body, so the server can write it straight to
// disk. XMLHttpRequest, because fetch cannot report upload progress.
function upload(file) {
  return new Promise((resolve) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", "/api/import/upload");
    xhr.setRequestHeader("Content-Type", "application/octet-stream");
    xhr.upload.onprogress = (ev) => {
      uploading = { sent: ev.loaded, total: ev.total || file.size };
      drawUpload();
    };
    xhr.onload = () => {
      let data = {};
      try { data = JSON.parse(xhr.responseText); } catch {}
      resolve(xhr.status === 200 && data.ok ? { ok: true } : { ok: false, error: data.error || `The server said ${xhr.status}.` });
    };
    xhr.onerror = () => resolve({ ok: false, error: "The upload stopped before it finished." });
    uploading = { sent: 0, total: file.size };
    draw();
    xhr.send(file);
  });
}

// ---------------------------------------------------------------- actions

$("#export-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const form = ev.target;
  const passphrase = form.elements.passphrase.value;
  const min = info?.minPassphrase || 10;
  if (passphrase.length < min) return showNotice(`Use a passphrase of at least ${min} characters.`);
  if (passphrase !== form.elements.again.value) return showNotice("The two passphrases differ.");
  if (await startJob("/api/export", { passphrase, home: form.elements.home.checked })) {
    form.elements.passphrase.value = "";
    form.elements.again.value = "";
  }
});

$("#import-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const form = ev.target;
  const file = chosen;
  if (!file && !info?.upload) return showNotice("Choose the export file first.");
  if (file && info && file.size > info.free) return showNotice("There is not enough free disk space for that file.");
  const home = form.elements.home.checked;
  if (!confirm(`Set this machine up like the one in the export?${home ? " Files in the home folder with the same name are replaced." : ""} This machine keeps its name.`)) return;
  showNotice("");
  if (file) {
    const result = await upload(file);
    uploading = null;
    if (!result.ok) {
      showNotice(result.error);
      return refresh();
    }
    chosen = null;
    form.elements.file.value = "";
    drawUpload();
  }
  if (await startJob("/api/import", { passphrase: form.elements.passphrase.value, home })) {
    form.elements.passphrase.value = "";
  }
});

$("#import-file").addEventListener("change", (ev) => {
  chosen = ev.target.files[0] || null;
  drawUpload();
});

// Drag a file onto the drop zone.
const drop = $("#drop");
for (const type of ["dragenter", "dragover"]) {
  drop.addEventListener(type, (ev) => {
    ev.preventDefault();
    if (!uploading) drop.classList.add("is-over");
  });
}
for (const type of ["dragleave", "drop"]) drop.addEventListener(type, () => drop.classList.remove("is-over"));
drop.addEventListener("drop", (ev) => {
  ev.preventDefault();
  const file = ev.dataTransfer.files[0];
  if (file && !uploading) {
    chosen = file;
    drawUpload();
  }
});

// Add a secret, or replace one: the same form, with the name filled in.
function secretForm(name) {
  const form = $("#secret-form");
  form.reset();
  form.hidden = false;
  form.elements.name.value = name || "";
  form.elements.name.readOnly = !!name;
  form.elements[name ? "value" : "name"].focus();
}

$("#secret-form [name=name]").addEventListener("input", (ev) => {
  ev.target.value = ev.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, "_");
});

$("#secret-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const form = ev.target;
  const name = form.elements.name.value;
  if (!form.elements.name.readOnly && state?.secrets.some((x) => x.name === name)
      && !confirm(`There is already a secret called ${name}. Replace its value?`)) return;
  if (await startJob("/api/secrets/set", { name, value: form.elements.value.value })) {
    form.reset();
    form.hidden = true;
  }
});

document.addEventListener("click", async (ev) => {
  const t = ev.target.closest("button");
  if (!t) return;
  if (t.closest("#drop")) ev.preventDefault(); // not the label's file dialog
  if (t.dataset.signin) {
    const id = t.dataset.signin;
    logins[id] = await api(`${CODE_LOGINS[id]}/start`, {});
    clearTimeout(loginTimers[id]);
    return pollLogin(id);
  }
  if (t.dataset.loginCancel) {
    const id = t.dataset.loginCancel;
    logins[id] = await api(`${CODE_LOGINS[id]}/cancel`, {});
    clearTimeout(loginTimers[id]);
    return drawAccounts(state.accounts);
  }
  if (t.dataset.secretReplace) return secretForm(t.dataset.secretReplace);
  if (t.dataset.secretRemove) {
    const name = t.dataset.secretRemove;
    if (!confirm(`Remove the secret ${name}? Agents can no longer read it.`)) return;
    return startJob("/api/secrets/remove", { name });
  }
  switch (t.dataset.action) {
    case "secret-add":
      return secretForm();
    case "secret-cancel":
      $("#secret-form").reset();
      $("#secret-form").hidden = true;
      return;
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
    case "file-clear":
      chosen = null;
      $("#import-file").value = "";
      return drawUpload();
    case "export-delete": {
      if (!confirm("Delete the export from this machine? Download it first if you need it.")) return;
      const r = await api("/api/export/delete", {});
      if (!r.ok) showNotice(r.error);
      return refresh();
    }
    case "import-discard":
      await api("/api/import/discard", {});
      return refresh();
    case "job-dismiss":
      await api("/api/job/dismiss", {});
      return refresh();
    case "notice-close":
      return showNotice("");
  }
});

addEventListener("beforeunload", (ev) => {
  if (uploading) ev.preventDefault();
});

// Draw what the last visit saw until the server answers, so the sections
// have their size from the start. The pill says Loading until then.
state = recall("state");
info = recall("transfer");
if (state) drawHeader({ ...state, state: null });
// A first visit has nothing to draw from: the sections wait for the
// server (two seconds at most), rather than grow while being read.
else {
  document.body.classList.add("is-waiting");
  setTimeout(() => document.body.classList.remove("is-waiting"), 2000);
}
draw();
refresh();
// A sign-in may already be under way, from before a reload or another tab.
for (const id of Object.keys(CODE_LOGINS)) pollLogin(id).catch(() => {});
