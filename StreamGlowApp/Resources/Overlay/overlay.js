(function () {
  const shell = document.querySelector(".overlay-shell");
  const art = document.querySelector(".artwork-image");
  const fallback = document.querySelector(".artwork-fallback");
  const dot = document.querySelector(".state-dot");
  const badge = document.querySelector(".source-badge");
  const title = document.querySelector(".track-title");
  const artist = document.querySelector(".track-artist");
  const album = document.querySelector(".track-album");
  const fill = document.querySelector(".progress-fill");
  const time = document.querySelector(".time-text");
  const visualizer = document.querySelector(".visualizer");

  let lastTrackKey = "";

  art.addEventListener("error", () => {
    art.removeAttribute("src");
    art.style.display = "none";
    fallback.style.display = "grid";
  });

  function formatTime(milliseconds) {
    if (!milliseconds || milliseconds <= 0) {
      return "0:00";
    }

    const totalSeconds = Math.floor(milliseconds / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = String(totalSeconds % 60).padStart(2, "0");
    return `${minutes}:${seconds}`;
  }

  function trackKey(track) {
    return [track.source, track.title, track.artist, track.album].join("::");
  }

  function applyTheme(theme) {
    const root = document.documentElement.style;

    if (theme.accent_hex) {
      root.setProperty("--accent", theme.accent_hex);
    }

    if (theme.glow_hex) {
      root.setProperty("--glow", theme.glow_hex);
    }

    if (theme.surface_hex) {
      root.setProperty("--surface", theme.surface_hex);
    }

    if (theme.panel_opacity != null) {
      root.setProperty("--panel-opacity", String(theme.panel_opacity));
    }

    if (theme.glow_strength != null) {
      root.setProperty("--glow-strength", String(theme.glow_strength));
    }

    if (theme.text_scale != null) {
      root.setProperty("--text-scale", String(theme.text_scale));
    }

    if (theme.music_tile_scale != null) {
      root.setProperty("--tile-scale", String(theme.music_tile_scale));
    }

    if (theme.compactness != null) {
      root.setProperty("--compactness", String(theme.compactness));
    }

    shell.classList.toggle("full-width", Boolean(theme.fill_obs_width));
  }

  function updateTrack(track) {
    const visible = track.available && track.state !== "stopped";
    shell.classList.toggle("visible", visible);

    if (!visible) {
      return;
    }

    const key = trackKey(track);
    if (key !== lastTrackKey) {
      lastTrackKey = key;
      shell.classList.remove("bump");
      void shell.offsetWidth;
      shell.classList.add("bump");
    }

    dot.classList.toggle("paused", track.state === "paused");
    badge.textContent = (track.source || "music").toUpperCase();
    shell.setAttribute("data-source", (track.source || "music").toLowerCase());
    title.textContent = track.title || "Now Playing";
    artist.textContent = track.artist || "";
    album.textContent = track.album ? `from ${track.album}` : "";

    if (track.artwork_url) {
      if (art.src !== track.artwork_url) {
        art.src = track.artwork_url;
      }
      art.style.display = "block";
      fallback.style.display = "none";
    } else {
      art.removeAttribute("src");
      art.style.display = "none";
      fallback.style.display = "grid";
    }

    const progress = track.duration_ms > 0
      ? Math.max(0, Math.min(100, (track.position_ms / track.duration_ms) * 100))
      : 0;

    fill.style.width = `${progress}%`;
    time.textContent = `${formatTime(track.position_ms)} / ${formatTime(track.duration_ms)}`;
    visualizer.classList.toggle("playing", track.state === "playing");
  }

  async function poll() {
    try {
      const [trackResponse, themeResponse] = await Promise.all([
        fetch("./api/now-playing", { cache: "no-store" }),
        fetch("./api/settings", { cache: "no-store" })
      ]);

      if (themeResponse.ok) {
        applyTheme(await themeResponse.json());
      }

      if (trackResponse.ok) {
        updateTrack(await trackResponse.json());
      }
    } catch (error) {
      shell.classList.remove("visible");
    }
  }

  poll();
  setInterval(poll, 1000);
})();
