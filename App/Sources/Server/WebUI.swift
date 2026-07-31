// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import Foundation

enum WebUI {
    /// PWA manifest: enables "Add to Home Screen" in full screen.
    ///
    /// `shortName` is the label under the icon once the page is added to the home screen:
    /// iOS truncates it beyond a dozen characters.
    static func manifestJSON(appName: String, shortName: String) -> String {
        """
        {
          "name": "\(appName)",
          "short_name": "\(shortName)",
          "start_url": "/",
          "display": "standalone",
          "background_color": "#FFFFFF",
          "theme_color": "#FFFFFF",
          "icons": [
            { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" }
          ]
        }
        """
    }

    /// Single page served to network devices. Self-contained (CSS + JS inline).
    ///
    /// Mirrors the native app's grammar EXACTLY: the same color tokens (copied
    /// from Figma variables, cf. Theme.swift), the same logo, the same capsule
    /// field with its round button, the same Video/Audio toggle, and above all
    /// the same capsules whose BACKGROUND fills as progress advances — not a
    /// separate bar. Strict monochrome: hierarchy comes from typography and
    /// spacing, never color.
    /// `audioBitrateSelectable` reflects the app's setting: in M4A the source
    /// track is kept, so there is no bitrate to choose. The web page was still
    /// offering the bitrate list when the app had stopped showing it — two
    /// interfaces promising different things.
    ///
    /// The footer is not a courtesy: this page IS the app being used through a
    /// network, the case AGPL §13 is written for, and it requires offering the
    /// source to whoever uses it that way. Settings names the license for the
    /// person at the Mac; nobody on a phone ever sees that screen.
    static func indexHTML(appName: String, shortName: String,
                          audioBitrateSelectable: Bool) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="light dark">
        <title>\(appName)</title>
        <link rel="manifest" href="/manifest.webmanifest">
        <link rel="icon" type="image/png" sizes="64x64" href="/favicon.png">
        <link rel="apple-touch-icon" href="/icon-512.png">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <meta name="mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-title" content="\(shortName)">
        <meta name="apple-mobile-web-app-status-bar-style" content="default">
        <meta name="theme-color" content="#FFFFFF" media="(prefers-color-scheme: light)">
        <meta name="theme-color" content="#1E1E1E" media="(prefers-color-scheme: dark)">
        <style>
          /* Tokens: copy of Figma file variables, like Theme.swift. */
          :root {
            --window:#FFFFFF; --card:#FFFFFF;
            --fill-1:rgba(120,120,128,.20); --fill-2:rgba(120,120,128,.12);
            --fill-3:rgba(118,118,128,.08); --fill-4:rgba(118,118,128,.05);
            --row-hover:rgba(120,120,128,.18);
            --label:rgba(0,0,0,.85); --label-2:rgba(0,0,0,.50); --label-3:rgba(0,0,0,.26);
            --ink:#0A0A0A; --on-ink:#FFFFFF;
            --separator:rgba(0,0,0,.10); --emphasis:rgba(0,0,0,.34);
            --r-ctrl:6px; --r-field:8px; --r-row:8px; --r-card:10px; --r-pill:999px;
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --window:#1E1E1E; --card:#2A2A2C;
              --fill-1:rgba(120,120,128,.36); --fill-2:rgba(120,120,128,.32);
              --fill-3:rgba(118,118,128,.24); --fill-4:rgba(118,118,128,.18);
              --row-hover:rgba(120,120,128,.34);
              --label:#FFFFFF; --label-2:rgba(255,255,255,.55); --label-3:rgba(255,255,255,.25);
              --ink:#F5F5F5; --on-ink:#0A0A0A;
              --separator:rgba(255,255,255,.12); --emphasis:rgba(255,255,255,.38);
            }
          }
          * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
          html { height:100%; }
          body {
            margin:0; min-height:100%; background:var(--window); color:var(--label);
            font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,sans-serif;
            font-size:15px; line-height:1.45; -webkit-font-smoothing:antialiased;
            letter-spacing:-0.01em;
          }
          .wrap {
            max-width:520px; margin:0 auto; min-height:100vh; display:flex; flex-direction:column;
            padding:max(24px,env(safe-area-inset-top)) max(20px,env(safe-area-inset-right))
                    calc(28px + env(safe-area-inset-bottom)) max(20px,env(safe-area-inset-left));
          }

          /* --- Header: logo, field, controls (like the Download screen) --- */
          .hero { display:flex; flex-direction:column; align-items:center; padding:22px 0 6px; }
          /* The logo is the app's ICON, tile included — the same as the tab's
             favicon and the icon added to the home screen. It is a path painted in
             currentColor: it inverts itself in dark theme, where a PNG would stay
             black on black. The hollowed out space lets the page background through,
             like in the app. */
          /* Square: 56px per side, a solid tile heavier than a hollowed glyph
             of the same height. */
          .logo { width:56px; color:var(--ink); margin-bottom:26px; }
          .logo svg { width:100%; height:auto; display:block; fill:currentColor; }

          .field {
            display:flex; align-items:center; gap:8px; width:100%;
            background:var(--fill-3); border-radius:var(--r-pill);
            padding:4px 4px 4px 18px; transition:box-shadow .15s ease;
          }
          .field:focus-within { box-shadow:0 0 0 3px rgba(0,0,0,.10); }
          @media (prefers-color-scheme: dark) {
            .field:focus-within { box-shadow:0 0 0 3px rgba(255,255,255,.14); }
          }
          .field.invalid { box-shadow:inset 0 0 0 1px var(--emphasis); }
          input[type=url] {
            flex:1; min-width:0; border:0; outline:0; background:transparent;
            color:var(--label); font:inherit; font-size:16px; padding:12px 0;
          }
          input[type=url]::placeholder { color:var(--label-3); }
          .go {
            flex:none; width:40px; height:40px; border:0; border-radius:50%;
            background:var(--fill-1); color:var(--label-2);
            display:grid; place-items:center; cursor:pointer; transition:background .15s,color .15s,transform .1s;
          }
          .go.on { background:var(--ink); color:var(--on-ink); }
          .go:active { transform:scale(.94); }
          .go svg { width:17px; height:17px; }

          .note { font-size:13px; color:var(--label-2); margin-top:12px; display:none; }
          .note.show { display:block; }

          .controls { display:flex; gap:8px; margin-top:18px; align-items:center; }
          .seg { display:flex; gap:2px; background:var(--fill-3); border-radius:8px; padding:2px; }
          .seg button {
            border:0; background:transparent; color:var(--label-2);
            font:inherit; font-size:14px; padding:5px 14px; border-radius:var(--r-ctrl);
            cursor:pointer; transition:background .15s,color .15s;
          }
          .seg button.active {
            background:var(--card); color:var(--label);
            box-shadow:0 1px 2px rgba(0,0,0,.14);
          }
          select {
            font:inherit; font-size:14px; color:var(--label); background:var(--fill-3);
            border:0; border-radius:var(--r-ctrl); padding:6px 28px 6px 11px; outline:0;
            -webkit-appearance:none; appearance:none; cursor:pointer;
            background-image:linear-gradient(45deg,transparent 50%,var(--label-2) 50%),
                             linear-gradient(135deg,var(--label-2) 50%,transparent 50%);
            background-position:calc(100% - 14px) 52%, calc(100% - 10px) 52%;
            background-size:4px 4px, 4px 4px; background-repeat:no-repeat;
          }

          /* --- List: capsules whose background fills --- */
          .list { margin-top:34px; flex:1; }
          .head {
            display:flex; align-items:baseline; justify-content:space-between;
            margin:0 4px 10px; height:16px;
          }
          .head h2 {
            margin:0; font-size:11px; font-weight:600; letter-spacing:.5px;
            text-transform:uppercase; color:var(--label-2);
          }
          #clear {
            border:0; background:transparent; color:var(--label-2);
            font:inherit; font-size:13px; cursor:pointer; padding:0; display:none;
          }

          .cap {
            position:relative; overflow:hidden; display:flex; align-items:center; gap:10px;
            min-height:52px; padding:6px 14px 6px 6px; margin-bottom:8px;
            background:var(--fill-3); border-radius:var(--r-pill);
            text-decoration:none; color:inherit;
          }
          .cap .fill {
            position:absolute; inset:0 auto 0 0; width:0; background:var(--fill-1);
            transition:width .35s cubic-bezier(.25,.1,.25,1);
          }
          .cap.failed { box-shadow:inset 0 0 0 1px var(--emphasis); }
          .cap > *:not(.fill) { position:relative; }
          .av {
            flex:none; width:40px; height:40px; border-radius:50%;
            background:var(--fill-1); object-fit:cover;
          }
          .cap .t {
            flex:1; min-width:0; font-size:14px;
            overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
          }
          .cap .skeleton {
            display:block; height:9px; width:60%; border-radius:4px; background:var(--fill-2);
          }
          .cap .m {
            flex:none; font-size:12px; color:var(--label-2);
            font-variant-numeric:tabular-nums;
          }
          .act {
            flex:none; width:28px; height:28px; margin-left:2px; border:0; border-radius:50%;
            background:transparent; color:var(--label-2);
            display:grid; place-items:center; cursor:pointer;
          }
          .act:active { opacity:.5; }
          .act svg { width:15px; height:15px; }
          .err { font-size:12px; color:var(--label-2); margin:-2px 4px 10px 60px; word-break:break-word; }

          /* --- Source offer (AGPL §13) --- */
          .legal {
            margin-top:28px; padding-top:14px; border-top:1px solid var(--separator);
            font-size:11px; line-height:1.5; color:var(--label-3); text-align:center;
          }
          .legal a { color:var(--label-2); text-decoration:none; }
          .legal a:hover { text-decoration:underline; }
        </style>
        </head>
        <body>
        <div class="wrap">
          <div class="hero">
            <div class="logo">
              <svg viewBox="\(MascotImage.iconSvgViewBox)" role="img" aria-label="\(appName)">
                <path fill-rule="nonzero" d="\(MascotImage.iconSvgPathData())"/>
              </svg>
            </div>

            <div class="field" id="field">
              <input id="url" type="url" placeholder="Paste a YouTube link…"
                     autocomplete="off" autocapitalize="off" spellcheck="false" inputmode="url">
              <button class="go" id="go" aria-label="Download">
                <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2"
                     stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 2.5v10M3.5 8.5 8 13l4.5-4.5"/>
                </svg>
              </button>
            </div>
            <div class="note" id="note">Only YouTube links are supported.</div>

            <div class="controls">
              <div class="seg" id="kind">
                <button data-kind="video">Video</button>
                <button data-kind="audio">Audio</button>
              </div>
              <select id="quality" aria-label="Quality"></select>
            </div>
          </div>

          <div class="list">
            <div class="head">
              <h2 id="headTitle"></h2>
              <button id="clear">Clear</button>
            </div>
            <div id="jobs"></div>
          </div>

          <footer class="legal">
            \(appName) is free software under the
            <a href="\(AppConfig.Credits.license.absoluteString)" target="_blank" rel="noopener">AGPL-3.0</a>.
            <a href="\(AppConfig.Credits.source.absoluteString)" target="_blank" rel="noopener">Get the source</a>.
          </footer>
        </div>

        <script>
          const VQ = [["1080","1080p"],["720","720p"],["480","480p"],["360","360p"],["max","Best"]];
          const AQ = \(audioBitrateSelectable
              ? #"[["320","320 kbps"],["192","192 kbps"],["128","128 kbps"]]"#
              : #"[["", "Original quality"]]"#);
          const HOSTS = ["youtube.com","www.youtube.com","m.youtube.com","music.youtube.com","youtu.be","www.youtu.be"];

          const ICON = {
            cancel: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4.5 4.5l7 7M11.5 4.5l-7 7"/></svg>',
            get:    '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2.5v8M4.5 7 8 10.5 11.5 7M3 13h10"/></svg>',
            retry:  '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 8a5 5 0 1 1-1.6-3.7M13 2.5V6h-3.5"/></svg>'
          };

          let kind = localStorage.getItem("kind") || "video";
          const savedQ = { video: localStorage.getItem("vq"), audio: localStorage.getItem("aq") };
          const q = document.getElementById("quality");
          const go = document.getElementById("go");
          const urlEl = document.getElementById("url");
          const field = document.getElementById("field");
          const note = document.getElementById("note");

          function fillQuality() {
            const opts = kind === "video" ? VQ : AQ;
            q.innerHTML = opts.map(o => `<option value="${o[0]}">${o[1]}</option>`).join("");
            const want = kind === "video" ? savedQ.video : savedQ.audio;
            if (want && opts.some(o => o[0] === want)) q.value = want;
          }
          function syncKind() {
            document.querySelectorAll("#kind button").forEach(b =>
              b.classList.toggle("active", b.dataset.kind === kind));
          }
          syncKind(); fillQuality();

          q.onchange = () => localStorage.setItem(kind === "video" ? "vq" : "aq", q.value);
          document.querySelectorAll("#kind button").forEach(b => b.onclick = () => {
            kind = b.dataset.kind;
            localStorage.setItem("kind", kind);
            syncKind(); fillQuality();
          });

          const isValidURL = v => {
            try { return HOSTS.includes(new URL(v.trim()).host.toLowerCase()); } catch { return false; }
          };
          const esc = s => (s||"").replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

          function human(n) {
            if (n == null) return "";
            const u = ["B","KB","MB","GB"]; let i = 0;
            while (n >= 1024 && i < u.length-1) { n/=1024; i++; }
            return n.toFixed(i ? 1 : 0) + " " + u[i];
          }
          function eta(s) {
            if (s == null || s <= 0) return "";
            const m = Math.floor(s/60), r = Math.floor(s%60);
            return m ? `${m} min left` : `${r} s left`;
          }

          function onInput() {
            const v = urlEl.value.trim();
            const valid = isValidURL(v);
            go.classList.toggle("on", valid);
            field.classList.toggle("invalid", v.length > 0 && !valid);
            note.classList.toggle("show", v.length > 0 && !valid);
          }
          urlEl.addEventListener("input", onInput);
          urlEl.addEventListener("keydown", e => { if (e.key === "Enter") go.click(); });

          go.onclick = async () => {
            const url = urlEl.value.trim();
            if (!isValidURL(url)) return;
            try {
              await fetch("/api/download", {
                method:"POST", headers:{"Content-Type":"application/json"},
                body: JSON.stringify({ url, kind, quality: q.value })
              });
              urlEl.value = "";
              urlEl.blur();
              refresh();
            } finally { onInput(); }
          };

          // One capsule = one line. Background fills, exactly like in the app:
          // never a separate bar, never going backwards.
          function capsule(j) {
            const active = ["queued","downloading","paused","merging"].includes(j.state);
            const pct = Math.round((j.progress || 0) * 100);
            let meta = "", action = "", href = "";

            if (j.state === "downloading")   meta = eta(j.eta) || `${pct}%`;
            else if (j.state === "queued")   meta = "Preparing…";
            else if (j.state === "paused")   meta = `Paused · ${pct}%`;
            else if (j.state === "merging")  meta = "Finishing up…";
            // On the phone, file size doesn't help: what matters is that you can
            // fetch it HERE, with one gesture.
            else if (j.state === "completed") meta = "Save · " + human(j.fileSize);
            else if (j.state === "failed")   meta = "Failed";
            else if (j.state === "cancelled") meta = "Cancelled";

            if (active) {
              action = `<button class="act" aria-label="Cancel" onclick="cancelJob(event,'${j.id}')">${ICON.cancel}</button>`;
            } else if (j.state === "completed" && j.canFetch) {
              // The entire capsule becomes a download link: any video from the
              // Mac's session can be fetched to the device.
              action = `<span class="act">${ICON.get}</span>`;
              href = `/api/file/${j.id}`;
            } else if (j.state === "failed" || j.state === "cancelled") {
              action = `<span class="act">${ICON.retry}</span>`;
            }

            const title = j.title && j.title !== j.id
              ? `<span class="t">${esc(j.title)}</span>`
              : `<span class="t"><i class="skeleton"></i></span>`;
            const avatar = j.thumbnail
              ? `<img class="av" src="${esc(j.thumbnail)}" alt="">`
              : `<span class="av"></span>`;

            const inner = `<span class="fill" style="width:${active || j.state === "completed" ? pct : 0}%"></span>`
                        + avatar + title
                        + `<span class="m">${esc(meta)}</span>` + action;

            const cls = "cap" + (j.state === "failed" ? " failed" : "");
            const body = href
              ? `<a class="${cls}" href="${href}">${inner}</a>`
              : `<div class="${cls}">${inner}</div>`;
            return body + (j.state === "failed" && j.error ? `<div class="err">${esc(j.error)}</div>` : "");
          }

          function render(jobs) {
            document.getElementById("jobs").innerHTML = jobs.map(capsule).join("");
            const done = jobs.some(j => ["completed","failed","cancelled"].includes(j.state));
            document.getElementById("clear").style.display = done ? "block" : "none";
            // No message when there is nothing: the absence speaks for itself.
            document.getElementById("headTitle").textContent = jobs.length ? "Downloads" : "";
          }

          async function cancelJob(e, id) {
            e.preventDefault(); e.stopPropagation();
            try { await fetch("/api/cancel/" + id, { method:"POST" }); refresh(); } catch(_) {}
          }
          document.getElementById("clear").onclick = async () => {
            try { await fetch("/api/clear", { method:"POST" }); refresh(); } catch(_) {}
          };

          async function refresh() {
            try { const r = await fetch("/api/jobs"); render(await r.json()); } catch(_) {}
          }
          // Polling suspended when the tab is hidden: no point waking the phone's
          // radio for nothing.
          let pollTimer = null;
          function startPolling() {
            if (pollTimer) return;
            refresh();
            pollTimer = setInterval(refresh, 1200);
          }
          function stopPolling() {
            if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
          }
          document.addEventListener("visibilitychange", () =>
            document.hidden ? stopPolling() : startPolling());
          startPolling();

          // Deep-link: /?url=… (iOS Shortcut "Share to …").
          const initialURL = new URLSearchParams(location.search).get("url");
          if (initialURL) { urlEl.value = initialURL; onInput(); }
        </script>
        </body>
        </html>
        """
    }
}
