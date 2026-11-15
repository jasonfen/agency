// The settings page, at /settings. For now: moving this machine's setup to
// another one (`agency export` and `agency import`, see cli/agency.py).
//
// An export is a job; when it is done the file waits on the server to be
// downloaded. An import is an upload first (with progress), then a job.

let job = null;
let info = null; // /api/transfer
let uploading = null; // { sent, total } while a file goes up

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

function drawUpload() {
  let html = "";
  if (uploading) {
    const pct = uploading.total ? Math.floor((100 * uploading.sent) / uploading.total) : 0;
    html = `<p class="note">Uploading: ${pct}% of ${size(uploading.total)}.</p>`;
  } else if (info?.upload && !$("#import-form [name=file]").files.length) {
    html = `<p class="note">An export of ${size(info.upload.size)} is uploaded and ready.
      <button type="button" class="button" data-action="import-discard">Discard it</button></p>`;
  }
  setHTML($("#upload"), html);
}

function draw() {
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
      job = s.job;
      drawJob(job);
    }
    if (!t.error) info = t;
    draw();
  } catch {
    // The dashboard restarts during some rebuilds. Try again shortly.
  }
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
  const file = form.elements.file.files[0];
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
    form.elements.file.value = "";
  }
  if (await startJob("/api/import", { passphrase: form.elements.passphrase.value, home })) {
    form.elements.passphrase.value = "";
  }
});

$("#import-form [name=file]").addEventListener("change", drawUpload);

document.addEventListener("click", async (ev) => {
  const t = ev.target.closest("button");
  if (!t) return;
  switch (t.dataset.action) {
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

refresh();
