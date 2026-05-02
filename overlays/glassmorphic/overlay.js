/**
 * StreamGlow Overlay – Shared polling engine.
 * Works with all templates.
 */
(function () {
  const POLL_MS = 1000;
  const API = "./api/now-playing";
  const SETTINGS = "./api/settings";

  const $ = (sel) => document.querySelector(sel);

  let lastTrackKey = "";
  let hideTimer = null;

  function formatTime(ms) {
    if (!ms || ms <= 0) return "0:00";
    const s = Math.floor(ms / 1000);
    const m = Math.floor(s / 60);
    return m + ":" + String(s % 60).padStart(2, "0");
  }

  function trackKey(d) {
    return [d.source, d.title, d.artist, d.album].join("::");
  }

  function applyTheme(s) {
    const r = document.documentElement.style;
    if (s.accent_hex)     r.setProperty("--accent", s.accent_hex);
    if (s.glow_opacity != null)  r.setProperty("--glow-opacity", s.glow_opacity);
    if (s.card_opacity != null)  r.setProperty("--card-opacity", s.card_opacity);
    if (s.blur_radius != null)   r.setProperty("--blur", s.blur_radius + "px");
    if (s.corner_radius != null) r.setProperty("--radius", s.corner_radius + "px");
  }

  function update(data) {
    const overlay = $(".overlay");
    if (!overlay) return;

    const showPaused = new URLSearchParams(location.search).get("show_paused") === "1";
    const visible = data.available && (data.state === "playing" || (data.state === "paused" && showPaused));

    if (visible) {
      clearTimeout(hideTimer);
      overlay.classList.add("visible");
    } else {
      if (overlay.classList.contains("visible")) {
        hideTimer = setTimeout(() => overlay.classList.remove("visible"), 400);
      }
      if (!data.available) return;
    }

    // State indicator
    const dot = $(".state-dot");
    if (dot) dot.classList.toggle("paused", data.state === "paused");

    // Source badge
    const badge = $(".source-badge");
    if (badge) {
      badge.textContent = data.source || "";
      badge.setAttribute("data-source", (data.source || "").toLowerCase());
    }
    overlay.setAttribute("data-source", (data.source || "").toLowerCase());

    // Metadata
    const title = $(".track-title");
    if (title) title.textContent = data.title || "";
    const artist = $(".track-artist");
    if (artist) artist.textContent = data.artist || "";
    const album = $(".track-album");
    if (album) album.textContent = data.album || "";

    // Artwork
    const art = $(".artwork-img");
    if (art) {
      const src = data.artwork_url ? data.artwork_url : "";
      if (src && art.getAttribute("src") !== src) {
        art.setAttribute("src", src);
        art.style.display = "";
      } else if (!src) {
        art.removeAttribute("src");
        art.style.display = "none";
      }
    }

    // Ambient glow
    const glow = $(".artwork-glow");
    if (glow && data.artwork_url) {
      glow.style.backgroundImage = `url(${data.artwork_url})`;
    }

    // Progress bar
    const fill = $(".progress-fill");
    if (fill && data.duration_ms > 0) {
      fill.style.width = Math.min(100, (data.position_ms / data.duration_ms) * 100) + "%";
    } else if (fill) {
      fill.style.width = "0%";
    }

    // Timecodes
    const cur = $(".time-current");
    if (cur) cur.textContent = formatTime(data.position_ms);
    const dur = $(".time-duration");
    if (dur) dur.textContent = formatTime(data.duration_ms);

    // Visualizer bars
    const bars = document.querySelectorAll(".viz-bar");
    bars.forEach((bar) => {
      bar.classList.toggle("active", data.state === "playing");
    });

    // Track change animation
    const key = trackKey(data);
    if (key !== lastTrackKey && data.available) {
      lastTrackKey = key;
      overlay.classList.remove("bump");
      void overlay.offsetWidth;
      overlay.classList.add("bump");
    }
  }

  async function poll() {
    try {
      const [trackRes, settingsRes] = await Promise.all([
        fetch(API),
        fetch(SETTINGS).catch(() => null),
      ]);
      const trackData = await trackRes.json();
      if (settingsRes && settingsRes.ok) {
        const settings = await settingsRes.json();
        applyTheme(settings);
      }
      update(trackData);
    } catch (e) {
      // Server not ready yet – hide overlay
      const overlay = $(".overlay");
      if (overlay) overlay.classList.remove("visible");
    }
  }

  setInterval(poll, POLL_MS);
  poll();
})();
