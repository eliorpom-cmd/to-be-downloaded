import Foundation

enum WebUI {
    /// Manifest PWA : permet « Ajouter à l'écran d'accueil » en plein écran.
    static func manifestJSON(appName: String) -> String {
        """
        {
          "name": "\(appName)",
          "short_name": "\(appName)",
          "start_url": "/",
          "display": "standalone",
          "background_color": "#0B0B0C",
          "theme_color": "#0B0B0C",
          "icons": [
            { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" }
          ]
        }
        """
    }

    /// Page unique servie aux appareils du réseau. Autonome (CSS + JS inline).
    /// Design system monochrome strict, aligné sur les tokens de l'app native
    /// (Theme.swift) : hiérarchie par typo/espace, aucune couleur d'accent.
    static func indexHTML(appName: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="light dark">
        <title>\(appName)</title>
        <link rel="manifest" href="/manifest.webmanifest">
        <link rel="icon" href="/icon-512.png">
        <link rel="apple-touch-icon" href="/icon-512.png">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-title" content="\(appName)">
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
        <meta name="theme-color" content="#0B0B0C">
        <style>
          :root {
            --canvas:#F2F2F4; --surface:#FFFFFF; --fill:#E8E8EC;
            --ink:#0A0A0A; --ink-inverse:#FFFFFF; --muted:#8E8E93;
            --radius-card:22px; --radius-ctrl:13px;
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --canvas:#0B0B0C; --surface:#1C1C1E; --fill:#2C2C2E;
              --ink:#F5F5F5; --ink-inverse:#0A0A0A; --muted:#8E8E93;
            }
          }
          * { box-sizing:border-box; }
          body {
            margin:0; background:var(--canvas); color:var(--ink);
            font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
            -webkit-font-smoothing:antialiased; line-height:1.5;
          }
          .wrap {
            max-width:640px; margin:0 auto;
            padding:max(28px,env(safe-area-inset-top)) max(20px,env(safe-area-inset-right))
                    calc(64px + env(safe-area-inset-bottom)) max(20px,env(safe-area-inset-left));
          }
          header { margin-bottom:24px; }
          h1 { font-size:30px; font-weight:700; letter-spacing:-0.02em; margin:0; }
          .sub { color:var(--muted); font-size:15px; margin-top:4px; }
          .card {
            background:var(--surface); border-radius:var(--radius-card); padding:18px;
          }
          input[type=url] {
            width:100%; padding:14px; font-size:16px; color:var(--ink);
            background:var(--fill); border:1px solid transparent; border-radius:var(--radius-ctrl);
            outline:none; -webkit-appearance:none;
          }
          input[type=url]:focus { border-color:var(--ink); }
          .hint { font-size:13px; color:var(--muted); margin-top:8px; display:none; }
          .hint.show { display:block; }

          /* Aperçu du média */
          .preview { display:none; gap:12px; margin-top:12px; padding:10px;
                     background:var(--fill); border-radius:var(--radius-ctrl); align-items:center; }
          .preview.show { display:flex; }
          .preview img, .preview .ph {
            width:104px; height:59px; border-radius:9px; object-fit:cover; flex:none;
            background:var(--canvas);
          }
          .preview .pt { font-size:13px; font-weight:600; line-height:1.35;
                         display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; }
          .preview .pm { font-size:12px; color:var(--muted); margin-top:3px; }

          .row { display:flex; gap:10px; margin-top:14px; flex-wrap:wrap; align-items:center; }
          .seg { display:flex; background:var(--fill); border-radius:var(--radius-ctrl); padding:3px; }
          .seg button {
            border:0; background:transparent; color:var(--muted); font-size:14px; font-weight:600;
            padding:9px 15px; border-radius:10px; cursor:pointer; transition:background .15s,color .15s;
          }
          .seg button.active { background:var(--ink); color:var(--ink-inverse); }
          select {
            padding:11px 13px; font-size:14px; color:var(--ink); background:var(--fill);
            border:1px solid transparent; border-radius:var(--radius-ctrl); outline:none; -webkit-appearance:none;
          }
          .go {
            margin-left:auto; border:0; background:var(--ink); color:var(--ink-inverse);
            font-size:15px; font-weight:700; padding:12px 22px; border-radius:999px; cursor:pointer;
          }
          .go:disabled { opacity:.4; cursor:default; }

          .jobs-head { display:flex; align-items:center; justify-content:space-between; margin:34px 4px 12px; }
          h2 { font-size:13px; text-transform:uppercase; letter-spacing:.06em; color:var(--muted); margin:0; }
          #clear { border:0; background:transparent; color:var(--ink); font-size:13px; font-weight:600;
                   text-decoration:underline; cursor:pointer; display:none; }

          .job { background:var(--surface); border-radius:16px; padding:14px; margin-bottom:10px;
                 display:flex; gap:12px; }
          .job img.th, .job .th.ph { width:72px; height:41px; border-radius:8px; object-fit:cover; flex:none;
                                     background:var(--fill); }
          .job .body { min-width:0; flex:1; }
          .job .t { font-size:15px; font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
          .job .m { font-size:12.5px; color:var(--muted); margin-top:2px;
                    overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
          .bar { height:6px; background:var(--fill); border-radius:99px; overflow:hidden; margin-top:10px; }
          .bar > i { display:block; height:100%; width:0; background:var(--ink); transition:width .3s ease; }
          .bar.indet > i { width:35%; animation:slide 1.1s infinite ease-in-out; }
          @keyframes slide { 0%{margin-left:-35%} 100%{margin-left:100%} }
          .stats { font-size:12px; color:var(--muted); margin-top:7px; display:flex; gap:8px; flex-wrap:wrap; }
          .fetch { display:inline-block; margin-top:11px; background:var(--ink); color:var(--ink-inverse);
                   text-decoration:none; font-weight:700; font-size:14px; padding:10px 18px; border-radius:999px; }
          .cancel { border:0; background:var(--fill); color:var(--ink);
                    font-size:13px; font-weight:600; padding:8px 15px; border-radius:999px; cursor:pointer; margin-top:10px; }
          .cancel:active { opacity:.6; }
          .err { color:var(--ink); font-weight:500; font-size:13px; margin-top:6px; word-break:break-word; }
          .empty { color:var(--muted); text-align:center; padding:40px 0; }
          .pill { font-size:11px; font-weight:700; padding:2px 9px; border-radius:99px;
                  background:var(--fill); color:var(--muted); margin-left:6px; vertical-align:middle; }
        </style>
        </head>
        <body>
        <div class="wrap">
          <header>
            <h1>\(appName)</h1>
            <div class="sub">Paste a link, pick a format, get the file.</div>
          </header>

          <div class="card">
            <input id="url" type="url" placeholder="https://…" autocomplete="off" autocapitalize="off" spellcheck="false" inputmode="url">
            <div class="hint" id="hint">Enter a valid YouTube link (youtube.com or youtu.be).</div>

            <div class="preview" id="preview">
              <img id="pvImg" alt="" hidden>
              <div class="ph" id="pvPh"></div>
              <div style="min-width:0">
                <div class="pt" id="pvTitle"></div>
                <div class="pm" id="pvMeta"></div>
              </div>
            </div>

            <div class="row">
              <div class="seg" id="kind">
                <button data-kind="video" class="active">Video MP4</button>
                <button data-kind="audio">Audio MP3</button>
              </div>
              <select id="quality"></select>
              <button class="go" id="go" disabled>Download</button>
            </div>
          </div>

          <div class="jobs-head">
            <h2>Downloads</h2>
            <button id="clear">Clear completed</button>
          </div>
          <div id="jobs"><div class="empty">No downloads yet.</div></div>
        </div>

        <script>
          const VQ = [["1080","1080p"],["720","720p"],["480","480p"],["360","360p"],["max","Max"]];
          const AQ = [["320","320 kbps"],["192","192 kbps"],["128","128 kbps"]];
          const HOSTS = ["youtube.com","www.youtube.com","m.youtube.com","music.youtube.com","youtu.be","www.youtu.be"];

          // Préférences persistées
          let kind = localStorage.getItem("kind") || "video";
          const savedQ = { video: localStorage.getItem("vq"), audio: localStorage.getItem("aq") };

          const q = document.getElementById("quality");
          function fillQuality() {
            const opts = kind === "video" ? VQ : AQ;
            q.innerHTML = opts.map(o => `<option value="${o[0]}">${o[1]}</option>`).join("");
            const want = kind === "video" ? savedQ.video : savedQ.audio;
            if (want && opts.some(o => o[0] === want)) q.value = want;
          }
          document.querySelectorAll("#kind button").forEach(b => {
            if (b.dataset.kind === kind) b.classList.add("active"); else b.classList.remove("active");
          });
          fillQuality();

          q.onchange = () => localStorage.setItem(kind === "video" ? "vq" : "aq", q.value);

          document.querySelectorAll("#kind button").forEach(b => b.onclick = () => {
            document.querySelectorAll("#kind button").forEach(x => x.classList.remove("active"));
            b.classList.add("active");
            kind = b.dataset.kind;
            localStorage.setItem("kind", kind);
            fillQuality();
          });

          function isValidURL(v) {
            try { return HOSTS.includes(new URL(v.trim()).host.toLowerCase()); } catch { return false; }
          }

          const go = document.getElementById("go");
          const urlEl = document.getElementById("url");
          const hint = document.getElementById("hint");

          function human(n) {
            if (n == null) return "—";
            const u = ["B","KB","MB","GB"]; let i = 0;
            while (n >= 1024 && i < u.length-1) { n/=1024; i++; }
            return n.toFixed(i ? 1 : 0) + " " + u[i];
          }
          function eta(s) {
            if (s == null || s <= 0) return "";
            const m = Math.floor(s/60), r = Math.floor(s%60);
            return m ? `${m} min ${r} s` : `${r} s`;
          }
          function dur(s) {
            if (s == null || s <= 0) return "";
            s = Math.floor(s);
            const h = Math.floor(s/3600), m = Math.floor((s%3600)/60), r = s%60;
            const p = n => String(n).padStart(2,"0");
            return h ? `${h}:${p(m)}:${p(r)}` : `${m}:${p(r)}`;
          }
          const esc = s => (s||"").replace(/[&<>]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));

          // --- Aperçu du média (debounce) ---
          const pv = document.getElementById("preview");
          const pvImg = document.getElementById("pvImg"), pvPh = document.getElementById("pvPh");
          const pvTitle = document.getElementById("pvTitle"), pvMeta = document.getElementById("pvMeta");
          let pvTimer = null, pvToken = 0;

          function hidePreview() { pv.classList.remove("show"); }
          function showPreview(meta) {
            pvTitle.textContent = meta.title || "";
            const bits = [];
            if (meta.channel) bits.push(meta.channel);
            if (dur(meta.duration)) bits.push(dur(meta.duration));
            pvMeta.textContent = bits.join(" · ");
            if (meta.thumbnail) { pvImg.src = meta.thumbnail; pvImg.hidden = false; pvPh.style.display = "none"; }
            else { pvImg.hidden = true; pvPh.style.display = "block"; }
            pv.classList.add("show");
          }
          async function loadPreview(url) {
            const token = ++pvToken;
            try {
              const r = await fetch("/api/metadata?url=" + encodeURIComponent(url));
              if (!r.ok || token !== pvToken) return;
              const meta = await r.json();
              if (token === pvToken) showPreview(meta);
            } catch(e) {}
          }

          function onInput() {
            const v = urlEl.value.trim();
            const valid = isValidURL(v);
            go.disabled = !valid;
            hint.classList.toggle("show", v.length > 0 && !valid);
            pvToken++;                       // invalide toute réponse en vol
            clearTimeout(pvTimer);
            if (!valid) { hidePreview(); return; }
            pvTimer = setTimeout(() => loadPreview(v), 400);
          }
          urlEl.addEventListener("input", onInput);

          go.onclick = async () => {
            const url = urlEl.value.trim();
            if (!isValidURL(url)) return;
            go.disabled = true;
            try {
              await fetch("/api/download", {
                method:"POST", headers:{"Content-Type":"application/json"},
                body: JSON.stringify({ url, kind, quality: q.value })
              });
              urlEl.value = "";
              hint.classList.remove("show");
              hidePreview();
              refresh();
            } finally { onInput(); }
          };
          urlEl.addEventListener("keydown", e => { if (e.key === "Enter" && !go.disabled) go.click(); });

          function render(jobs) {
            const box = document.getElementById("jobs");
            if (!jobs.length) { box.innerHTML = `<div class="empty">No downloads yet.</div>`; return; }
            box.innerHTML = jobs.map(j => {
              let mid = "";
              if (j.state === "downloading" || j.state === "queued") {
                const pct = j.fraction != null ? Math.round(j.fraction*100) : null;
                const indet = pct == null ? "indet" : "";
                const w = pct != null ? pct+"%" : "0%";
                const stats = j.state === "downloading"
                  ? `<div class="stats"><span>${human(j.downloaded)} / ${human(j.total)}</span>`
                    + (j.speed ? `<span>· ${human(j.speed)}/s</span>`:"")
                    + (eta(j.eta) ? `<span>· ${eta(j.eta)}</span>`:"") + `</div>`
                  : `<div class="stats"><span>Queued…</span></div>`;
                mid = `<div class="bar ${indet}"><i style="width:${w}"></i></div>${stats}`
                    + `<button class="cancel" onclick="cancelJob('${j.id}')">Cancel</button>`;
              } else if (j.state === "completed") {
                const size = j.fileSize ? ` · ${human(j.fileSize)}` : "";
                mid = `<div class="stats"><span>Ready${size}</span></div>`
                    + (j.canFetch ? `<a class="fetch" href="/api/file/${j.id}">Get file</a>` : "");
              } else if (j.state === "failed") {
                mid = `<div class="err">${esc(j.error) || "Failed"}</div>`;
              } else if (j.state === "cancelled") {
                mid = `<div class="stats"><span>Cancelled</span></div>`;
              }
              const pill = (j.state === "completed") ? `<span class="pill">done</span>`
                        : (j.state === "failed") ? `<span class="pill">failed</span>` : "";
              const thumb = j.thumbnail
                ? `<img class="th" src="${esc(j.thumbnail)}" alt="">`
                : `<div class="th ph"></div>`;
              const meta = [j.channel, j.format].filter(Boolean).map(esc).join(" · ");
              return `<div class="job">${thumb}<div class="body">`
                   + `<div class="t">${esc(j.title)}${pill}</div>`
                   + `<div class="m">${meta}</div>${mid}</div></div>`;
            }).join("");
            document.getElementById("clear").style.display =
              jobs.some(j => ["completed","failed","cancelled"].includes(j.state)) ? "block" : "none";
          }

          async function cancelJob(id) {
            try { await fetch("/api/cancel/" + id, { method:"POST" }); refresh(); } catch(e) {}
          }
          document.getElementById("clear").onclick = async () => {
            try { await fetch("/api/clear", { method:"POST" }); refresh(); } catch(e) {}
          };

          async function refresh() {
            try { const r = await fetch("/api/jobs"); render(await r.json()); } catch(e) {}
          }
          // Polling intelligent : suspendu quand l'onglet est masqué (batterie),
          // reprise immédiate au retour au premier plan.
          let pollTimer = null;
          function startPolling() {
            if (pollTimer) return;
            refresh();
            pollTimer = setInterval(refresh, 1200);
          }
          function stopPolling() {
            if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
          }
          document.addEventListener("visibilitychange", () => {
            document.hidden ? stopPolling() : startPolling();
          });
          startPolling();

          // Deep-link : /?url=… (ex. Raccourci iOS « Partager vers … »).
          const initialURL = new URLSearchParams(location.search).get("url");
          if (initialURL) { urlEl.value = initialURL; onInput(); }
        </script>
        </body>
        </html>
        """
    }
}
