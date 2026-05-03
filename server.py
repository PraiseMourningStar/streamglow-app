#!/usr/bin/env python3
"""
StreamGlow – Cross-platform Now Playing overlay server for OBS.

Detects currently playing music from Spotify and Apple Music / iTunes
on both macOS and Windows, then serves a browser-source overlay that
OBS can consume.

Zero external dependencies – stdlib only.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import platform
import re
import sys
import tempfile
import threading
import time
import urllib.parse
import webbrowser
from dataclasses import asdict, dataclass, field
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from subprocess import DEVNULL, CalledProcessError, run
from typing import Any

# ─── Constants ───────────────────────────────────────────────────────
def resolve_runtime_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS", Path(sys.executable).resolve().parent))
    return Path(__file__).resolve().parent


ROOT = resolve_runtime_root()
STATE_DIR = Path(tempfile.gettempdir()) / "streamglow"
STATE_DIR.mkdir(parents=True, exist_ok=True)
OVERLAY_DIR = ROOT / "overlays"
ARTWORK_EXPORT_PATH = STATE_DIR / ".artwork-export.bin"
ARTWORK_CACHE_PATH = STATE_DIR / ".current-artwork.bin"
FIELD_SEPARATOR = chr(30)
SYSTEM = platform.system()  # "Darwin", "Windows", "Linux"

# ─── Data ────────────────────────────────────────────────────────────

@dataclass
class TrackInfo:
    available: bool = False
    state: str = "stopped"
    source: str = ""
    title: str = ""
    artist: str = ""
    album: str = ""
    duration_ms: int = 0
    position_ms: int = 0
    artwork_url: str = ""
    updated_at: float = field(default_factory=time.time)


@dataclass
class ThemeSettings:
    accent_hex: str = "#8b5cf6"
    glow_opacity: float = 0.35
    card_opacity: float = 0.55
    blur_radius: int = 18
    corner_radius: int = 16

# ─── Shared State ────────────────────────────────────────────────────

class SharedState:
    """Thread-safe container shared between poller and HTTP handler."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._track = TrackInfo()
        self._theme = ThemeSettings()
        self._active_template = "glassmorphic"

    @property
    def track(self) -> TrackInfo:
        with self._lock:
            return copy.deepcopy(self._track)

    @track.setter
    def track(self, value: TrackInfo) -> None:
        with self._lock:
            self._track = value

    @property
    def theme(self) -> ThemeSettings:
        with self._lock:
            return copy.deepcopy(self._theme)

    @theme.setter
    def theme(self, value: ThemeSettings) -> None:
        with self._lock:
            self._theme = value

    @property
    def active_template(self) -> str:
        with self._lock:
            return self._active_template

    @active_template.setter
    def active_template(self, value: str) -> None:
        with self._lock:
            self._active_template = value


# ─── Helpers ─────────────────────────────────────────────────────────

def is_process_running(name: str) -> bool:
    """Check whether a process with *name* is running (cross-platform)."""
    if SYSTEM == "Darwin":
        result = run(["pgrep", "-x", name], stdout=DEVNULL, stderr=DEVNULL, check=False)
        return result.returncode == 0
    elif SYSTEM == "Windows":
        result = run(
            ["tasklist", "/FI", f"IMAGENAME eq {name}.exe", "/NH"],
            capture_output=True, text=True, check=False,
        )
        return name.lower() in result.stdout.lower()
    else:
        result = run(["pgrep", "-x", name], stdout=DEVNULL, stderr=DEVNULL, check=False)
        return result.returncode == 0


def run_osascript(script: str) -> str:
    """Execute an AppleScript snippet and return stdout (macOS only)."""
    completed = run(
        ["osascript", "-e", script],
        capture_output=True, text=True, check=False,
    )
    if completed.returncode != 0:
        raise CalledProcessError(
            completed.returncode, completed.args,
            output=completed.stdout, stderr=completed.stderr,
        )
    return completed.stdout.strip()


def parse_fields(payload: str) -> list[str]:
    if not payload:
        return []
    return payload.split(FIELD_SEPARATOR)


def clamp_int(value: float, minimum: int = 0) -> int:
    return max(minimum, int(round(value)))


def track_key(track: TrackInfo) -> str:
    return "::".join([
        track.source.strip(), track.title.strip(),
        track.artist.strip(), track.album.strip(),
    ])


def normalize_match_text(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def detect_image_content_type(payload: bytes) -> str:
    if payload.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if payload.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if payload.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if payload[:4] == b"RIFF" and payload[8:12] == b"WEBP":
        return "image/webp"
    return "application/octet-stream"


def normalize_duration_ms(source: str, raw_value: str) -> int:
    if not raw_value:
        return 0
    try:
        number = float(raw_value)
    except ValueError:
        return 0
    if source == "Spotify" and number > 1000:
        return clamp_int(number)
    return clamp_int(number * 1000)


def normalize_position_ms(raw_value: str, duration_ms: int) -> int:
    if not raw_value:
        return 0
    try:
        number = float(raw_value)
    except ValueError:
        return 0
    if duration_ms and number > duration_ms + 1000:
        return clamp_int(number)
    if duration_ms and number > 1000 and number <= duration_ms:
        return clamp_int(number)
    return clamp_int(number * 1000)


# ─── macOS: AppleScript Queries ──────────────────────────────────────

def query_spotify_macos() -> TrackInfo | None:
    if not is_process_running("Spotify"):
        return None

    script = f"""
set fieldSeparator to character id 30
tell application "Spotify"
    if player state is stopped then
        return ""
    end if
    set trackState to player state as text
    set trackTitle to ""
    set trackArtist to ""
    set trackAlbum to ""
    set trackDuration to ""
    set trackPosition to ""
    set trackArtwork to ""
    try
        set trackTitle to name of current track as text
    end try
    try
        set trackArtist to artist of current track as text
    end try
    try
        set trackAlbum to album of current track as text
    end try
    try
        set trackDuration to duration of current track as text
    end try
    try
        set trackPosition to player position as text
    end try
    try
        set trackArtwork to artwork url of current track as text
    end try
    set AppleScript's text item delimiters to fieldSeparator
    return {{trackState, trackTitle, trackArtist, trackAlbum, trackDuration, trackPosition, trackArtwork}} as text
end tell
"""
    try:
        fields = parse_fields(run_osascript(script))
    except CalledProcessError:
        return None
    if len(fields) < 7:
        return None

    state, title, artist, album, raw_dur, raw_pos, artwork_url = fields[:7]
    dur = normalize_duration_ms("Spotify", raw_dur)
    pos = normalize_position_ms(raw_pos, dur)

    return TrackInfo(
        available=bool(title or artist), state=state or "stopped",
        source="Spotify", title=title, artist=artist, album=album,
        duration_ms=dur, position_ms=min(pos, dur) if dur else pos,
        artwork_url=artwork_url, updated_at=time.time(),
    )


def query_music_macos() -> TrackInfo | None:
    if not is_process_running("Music"):
        return None

    script = f"""
set fieldSeparator to character id 30
tell application "Music"
    if player state is stopped then
        return ""
    end if
    set trackState to player state as text
    set trackTitle to ""
    set trackArtist to ""
    set trackAlbum to ""
    set trackDuration to ""
    set trackPosition to ""
    try
        if exists current track then
            set trackTitle to name of current track as text
        end if
    end try
    try
        if exists current track then
            set trackArtist to artist of current track as text
        end if
    end try
    try
        if exists current track then
            set trackAlbum to album of current track as text
        end if
    end try
    try
        if exists current track then
            set trackDuration to duration of current track as text
        end if
    end try
    try
        set trackPosition to player position as text
    end try
    set AppleScript's text item delimiters to fieldSeparator
    return {{trackState, trackTitle, trackArtist, trackAlbum, trackDuration, trackPosition}} as text
end tell
"""
    try:
        fields = parse_fields(run_osascript(script))
    except CalledProcessError:
        return None
    if len(fields) < 6:
        return None

    state, title, artist, album, raw_dur, raw_pos = fields[:6]
    dur = normalize_duration_ms("Music", raw_dur)
    pos = normalize_position_ms(raw_pos, dur)

    return TrackInfo(
        available=bool(title or artist), state=state or "stopped",
        source="Music", title=title, artist=artist, album=album,
        duration_ms=dur, position_ms=min(pos, dur) if dur else pos,
        updated_at=time.time(),
    )


# ─── Windows: Window-Title & PowerShell Queries ─────────────────────

def _powershell(script: str) -> str:
    """Run a PowerShell snippet and return stdout."""
    completed = run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
        capture_output=True, text=True, check=False,
    )
    return completed.stdout.strip()


def query_spotify_windows() -> TrackInfo | None:
    """Detect Spotify playback on Windows via the main window title.

    Spotify's window title is "Spotify Premium" or "Spotify Free" when idle,
    and "Artist - Song Title" when playing.
    """
    if not is_process_running("Spotify"):
        return None

    ps_script = r"""
$proc = Get-Process Spotify -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne '' } | Select-Object -First 1
if ($proc) { $proc.MainWindowTitle } else { '' }
"""
    title = _powershell(ps_script)

    if not title or title.lower() in ("spotify", "spotify premium", "spotify free", ""):
        # Spotify is open but not playing anything identifiable
        return TrackInfo(
            available=False, state="stopped", source="Spotify",
            updated_at=time.time(),
        )

    # Title format: "Artist - Song Title"
    parts = title.split(" - ", 1)
    if len(parts) == 2:
        artist, song_title = parts[0].strip(), parts[1].strip()
    else:
        artist, song_title = "", title.strip()

    return TrackInfo(
        available=True, state="playing", source="Spotify",
        title=song_title, artist=artist,
        updated_at=time.time(),
    )


def query_itunes_windows() -> TrackInfo | None:
    """Detect iTunes / Apple Music playback on Windows via COM."""
    if not is_process_running("iTunes"):
        return None

    ps_script = r"""
try {
    $itunes = New-Object -ComObject iTunes.Application
    if ($itunes.PlayerState -eq 1) {
        $track = $itunes.CurrentTrack
        $sep = [char]30
        $pos = [math]::Round($itunes.PlayerPosition * 1000)
        $dur = [math]::Round($track.Duration * 1000)
        "$($track.Name)$sep$($track.Artist)$sep$($track.Album)$sep$dur$sep$pos"
    } else {
        "stopped"
    }
} catch {
    ""
}
"""
    result = _powershell(ps_script)

    if not result or result == "stopped":
        return TrackInfo(
            available=False, state="stopped", source="iTunes",
            updated_at=time.time(),
        )

    fields = result.split(FIELD_SEPARATOR)
    if len(fields) < 5:
        return None

    title, artist, album, raw_dur, raw_pos = fields[:5]
    dur = clamp_int(float(raw_dur)) if raw_dur else 0
    pos = clamp_int(float(raw_pos)) if raw_pos else 0

    return TrackInfo(
        available=bool(title or artist), state="playing",
        source="iTunes", title=title, artist=artist, album=album,
        duration_ms=dur, position_ms=min(pos, dur) if dur else pos,
        updated_at=time.time(),
    )


# ─── Windows: Media Session fallback (Win 10 1809+) ─────────────────

def query_media_session_windows() -> TrackInfo | None:
    """Attempt to read the Global System Media Transport Controls.

    This is a best-effort fallback that reads the now-playing info from
    any media app (YouTube in browser, VLC, etc.) via PowerShell + WinRT.
    """
    ps_script = r"""
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

    Function Await($WinRtTask, $ResultType) {
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(-1) | Out-Null
        $netTask.Result
    }

    [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime] | Out-Null
    $sessManager = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
    $sess = $sessManager.GetCurrentSession()
    if ($sess) {
        $info = Await ($sess.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
        $pb = $sess.GetPlaybackInfo()
        $state = if ($pb.PlaybackStatus -eq 4) { "playing" } elseif ($pb.PlaybackStatus -eq 5) { "paused" } else { "stopped" }
        $tl = $sess.GetTimelineProperties()
        $sep = [char]30
        "$($info.Title)$sep$($info.Artist)$sep$($info.AlbumTitle)$sep$([math]::Round($tl.EndTime.TotalMilliseconds))$sep$([math]::Round($tl.Position.TotalMilliseconds))$sep$state$sep$($sess.SourceAppUserModelId)"
    } else { "" }
} catch { "" }
"""
    result = _powershell(ps_script)
    if not result:
        return None

    fields = result.split(FIELD_SEPARATOR)
    if len(fields) < 7:
        return None

    title, artist, album, raw_dur, raw_pos, state, source_app = fields[:7]
    dur = clamp_int(float(raw_dur)) if raw_dur else 0
    pos = clamp_int(float(raw_pos)) if raw_pos else 0

    # Try to determine a friendly source name
    source_lower = source_app.lower()
    if "spotify" in source_lower:
        source = "Spotify"
    elif "itunes" in source_lower or "music" in source_lower or "apple" in source_lower:
        source = "Music"
    elif "chrome" in source_lower or "firefox" in source_lower or "edge" in source_lower:
        source = "Browser"
    else:
        source = source_app.split(".")[-1].split("!")[-1] if source_app else "Unknown"

    return TrackInfo(
        available=bool(title or artist), state=state or "stopped",
        source=source, title=title, artist=artist, album=album,
        duration_ms=dur, position_ms=min(pos, dur) if dur else pos,
        updated_at=time.time(),
    )


# ─── Platform Dispatcher ────────────────────────────────────────────

def query_all_sources() -> list[TrackInfo]:
    """Query all available music sources for the current platform."""
    candidates: list[TrackInfo] = []

    if SYSTEM == "Darwin":
        for fn in (query_spotify_macos, query_music_macos):
            try:
                result = fn()
                if result is not None:
                    candidates.append(result)
            except Exception:
                pass

    elif SYSTEM == "Windows":
        # Try specific apps first
        for fn in (query_spotify_windows, query_itunes_windows):
            try:
                result = fn()
                if result is not None:
                    candidates.append(result)
            except Exception:
                pass

        # If nothing found, try the global media session (catches browser, VLC, etc.)
        if not any(c.available and c.state == "playing" for c in candidates):
            try:
                result = query_media_session_windows()
                if result is not None:
                    candidates.append(result)
            except Exception:
                pass

    return candidates


# ─── Artwork Resolver ────────────────────────────────────────────────

class ArtworkResolver:
    def __init__(self) -> None:
        self._lookup_cache: dict[tuple[str, str, str], str] = {}
        self._lock = threading.Lock()
        self._track_key = ""
        self._content_type = ""
        self._updated_at = 0.0

    def resolve(self, track: TrackInfo) -> str:
        if not track.available:
            self.clear()
            return ""

        key = track_key(track)
        with self._lock:
            if self._track_key == key and ARTWORK_CACHE_PATH.exists():
                return self._endpoint()

        artwork = None

        # macOS: try extracting artwork directly from Music.app
        if SYSTEM == "Darwin" and track.source == "Music":
            artwork = self._load_track_artwork_macos(track)

        # Try the artwork URL from the player
        if artwork is None and track.artwork_url:
            artwork = self._download_artwork(track.artwork_url)

        # Fallback: iTunes Search API
        if artwork is None:
            fallback_url = self._lookup_catalog_artwork(track)
            if fallback_url:
                artwork = self._download_artwork(fallback_url)

        if artwork is None:
            self.clear(key)
            return ""

        content_type, payload = artwork
        self._store_artwork(key, content_type, payload)
        return self._endpoint()

    def snapshot(self) -> tuple[bytes, str] | None:
        with self._lock:
            if not ARTWORK_CACHE_PATH.exists() or not self._content_type:
                return None
            try:
                return ARTWORK_CACHE_PATH.read_bytes(), self._content_type
            except FileNotFoundError:
                return None

    def clear(self, key: str = "") -> None:
        with self._lock:
            self._track_key = key
            self._content_type = ""
            self._updated_at = time.time()
        if ARTWORK_CACHE_PATH.exists():
            ARTWORK_CACHE_PATH.unlink(missing_ok=True)

    def _store_artwork(self, key: str, content_type: str, payload: bytes) -> None:
        temp_path = ARTWORK_CACHE_PATH.with_suffix(".tmp")
        temp_path.write_bytes(payload)
        temp_path.replace(ARTWORK_CACHE_PATH)
        with self._lock:
            self._track_key = key
            self._content_type = content_type
            self._updated_at = time.time()

    def _endpoint(self) -> str:
        return f"/artwork?t={int(self._updated_at * 1000)}"

    def _load_track_artwork_macos(self, track: TrackInfo) -> tuple[str, bytes] | None:
        quoted_path = str(ARTWORK_EXPORT_PATH).replace("\\", "\\\\").replace('"', '\\"')
        script = f"""
set artworkFile to "{quoted_path}"
tell application "Music"
    if player state is stopped then return ""
    try
        set currentTrack to current track
        set myArtwork to artwork 1 of currentTrack
        set myPicture to data of myArtwork
        set myFile to (open for access (POSIX file artworkFile) with write permission)
        set eof of myFile to 0
        write myPicture to myFile
        try
            close access (POSIX file artworkFile)
        end try
        return "ok"
    on error
        try
            close access (POSIX file artworkFile)
        end try
        return ""
    end try
end tell
"""
        try:
            result = run_osascript(script)
        except CalledProcessError:
            return None
        if not result or not ARTWORK_EXPORT_PATH.exists():
            return None
        payload = ARTWORK_EXPORT_PATH.read_bytes()
        if not payload:
            return None
        content_type = detect_image_content_type(payload)
        if not content_type.startswith("image/"):
            return None
        return content_type, payload

    def _download_artwork(self, url: str) -> tuple[str, bytes] | None:
        """Download artwork using curl (macOS/Linux) or PowerShell (Windows)."""
        try:
            if SYSTEM == "Windows":
                ps = f'(New-Object System.Net.WebClient).DownloadData("{url}")'
                # Use a temp file approach for binary data on Windows
                import tempfile
                tmp = Path(tempfile.mktemp(suffix=".img"))
                ps_dl = f"""
try {{
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("{url}", "{tmp}")
    "ok"
}} catch {{ "" }}
"""
                result_text = _powershell(ps_dl)
                if result_text != "ok" or not tmp.exists():
                    return None
                payload = tmp.read_bytes()
                tmp.unlink(missing_ok=True)
            else:
                result = run(
                    ["curl", "-L", "-s", "--max-time", "5", url],
                    capture_output=True, check=False,
                )
                if result.returncode != 0:
                    return None
                payload = result.stdout

            if not payload:
                return None
            content_type = detect_image_content_type(payload)
            if not content_type.startswith("image/"):
                return None
            return content_type, payload
        except Exception:
            return None

    def _lookup_catalog_artwork(self, track: TrackInfo) -> str:
        key = (track.title.strip().lower(), track.artist.strip().lower(), track.album.strip().lower())
        if key in self._lookup_cache:
            return self._lookup_cache[key]

        query = " ".join(part for part in (track.title, track.artist, track.album) if part).strip()
        if not query:
            self._lookup_cache[key] = ""
            return ""

        params = urllib.parse.urlencode({"term": query, "media": "music", "entity": "song", "limit": 5})
        url = f"https://itunes.apple.com/search?{params}"

        try:
            if SYSTEM == "Windows":
                result = run(
                    ["powershell", "-NoProfile", "-Command",
                     f'(New-Object System.Net.WebClient).DownloadString("{url}")'],
                    capture_output=True, text=True, check=False,
                )
            else:
                result = run(
                    ["curl", "-L", "-s", "--max-time", "5", url],
                    capture_output=True, text=True, check=False,
                )
        except Exception:
            self._lookup_cache[key] = ""
            return ""

        if result.returncode != 0 or not result.stdout.strip():
            self._lookup_cache[key] = ""
            return ""

        try:
            payload_json = json.loads(result.stdout)
        except json.JSONDecodeError:
            self._lookup_cache[key] = ""
            return ""

        best_url = ""
        best_score = -1
        title_norm = normalize_match_text(track.title)
        artist_norm = normalize_match_text(track.artist)
        album_norm = normalize_match_text(track.album)

        for item in payload_json.get("results", []):
            item_artist = normalize_match_text(str(item.get("artistName", "")))
            item_track = normalize_match_text(str(item.get("trackName", "")))
            item_album = normalize_match_text(str(item.get("collectionName", "")))

            score = 0
            if title_norm and (title_norm in item_track or item_track in title_norm):
                score += 3
            if artist_norm and (artist_norm in item_artist or item_artist in artist_norm):
                score += 2
            if album_norm and (album_norm in item_album or item_album in album_norm):
                score += 1

            art_candidate = str(item.get("artworkUrl100", ""))
            if score > best_score and art_candidate:
                best_url = art_candidate
                best_score = score

        if not best_url and payload_json.get("results"):
            best_url = str(payload_json["results"][0].get("artworkUrl100", ""))

        if best_url:
            best_url = best_url.replace("100x100bb", "600x600bb")

        self._lookup_cache[key] = best_url
        return best_url


# ─── Poller ──────────────────────────────────────────────────────────

class Poller:
    def __init__(self, interval_seconds: float = 1.5) -> None:
        self.interval_seconds = interval_seconds
        self._artwork = ArtworkResolver()
        self._lock = threading.Lock()
        self._state = TrackInfo()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, name="now-playing-poller", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._thread.join(timeout=2)

    def snapshot(self) -> TrackInfo:
        with self._lock:
            return copy.deepcopy(self._state)

    def _loop(self) -> None:
        while not self._stop.is_set():
            self._refresh()
            self._stop.wait(self.interval_seconds)

    def _refresh(self) -> None:
        state = self._detect_track()
        state.artwork_url = self._artwork.resolve(state)
        with self._lock:
            self._state = state

    def _detect_track(self) -> TrackInfo:
        candidates = query_all_sources()
        if not candidates:
            return TrackInfo(updated_at=time.time())

        # Prefer actively playing tracks
        for c in candidates:
            if c.state == "playing":
                return c
        for c in candidates:
            if c.available:
                return c
        return candidates[0]


# ─── HTTP Server ─────────────────────────────────────────────────────

class OverlayHandler(SimpleHTTPRequestHandler):
    shared_state: SharedState
    poller: Poller

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        # Serve from the overlays directory for static files
        template = self.shared_state.active_template
        serve_dir = OVERLAY_DIR / template
        if not serve_dir.is_dir():
            serve_dir = OVERLAY_DIR / "glassmorphic"
        super().__init__(*args, directory=str(serve_dir), **kwargs)

    def do_GET(self) -> None:
        if self.path.startswith("/api/now-playing"):
            self._serve_api()
            return
        if self.path.startswith("/api/settings"):
            self._serve_settings()
            return
        if self.path.startswith("/api/templates"):
            self._serve_template_list()
            return
        if self.path.startswith("/artwork"):
            self._serve_artwork()
            return
        if self.path == "/":
            self.path = "/index.html"
        super().do_GET()

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def log_message(self, fmt: str, *args: Any) -> None:
        return  # Silence request logs

    def _serve_api(self) -> None:
        snapshot = self.poller.snapshot()
        payload = json.dumps(asdict(snapshot)).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _serve_settings(self) -> None:
        theme = self.shared_state.theme
        data = {
            "accent_hex": theme.accent_hex,
            "glow_opacity": theme.glow_opacity,
            "card_opacity": theme.card_opacity,
            "blur_radius": theme.blur_radius,
            "corner_radius": theme.corner_radius,
        }
        payload = json.dumps(data).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _serve_template_list(self) -> None:
        templates = []
        if OVERLAY_DIR.is_dir():
            for d in sorted(OVERLAY_DIR.iterdir()):
                if d.is_dir() and (d / "index.html").exists():
                    templates.append(d.name)
        payload = json.dumps({"templates": templates, "active": self.shared_state.active_template}).encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _serve_artwork(self) -> None:
        snapshot = self.poller._artwork.snapshot()
        if snapshot is None:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        payload, content_type = snapshot
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


# ─── Entry Point ─────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="StreamGlow – Now Playing overlay server for OBS (Mac + Windows)",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Host interface to bind (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8974, help="Port to serve on (default: 8974)")
    parser.add_argument("--interval", type=float, default=1.5, help="Polling interval in seconds (default: 1.5)")
    parser.add_argument("--template", default="glassmorphic", help="Default overlay template (default: glassmorphic)")
    parser.add_argument("--headless", action="store_true", help="Run without the Windows control window")
    return parser.parse_args()


def print_startup_banner(url: str, template: str) -> None:
    print()
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║         StreamGlow is running! 🎵            ║")
    print("  ╠══════════════════════════════════════════════╣")
    print(f"  ║  Overlay URL: {url:<31}║")
    print(f"  ║  Platform:    {SYSTEM:<31}║")
    print(f"  ║  Template:    {template:<31}║")
    print("  ╠══════════════════════════════════════════════╣")
    print("  ║  Add this URL as an OBS Browser Source       ║")
    print("  ║  Recommended size: 720 x 220                 ║")
    print("  ║  Press Ctrl+C to stop                        ║")
    print("  ╚══════════════════════════════════════════════╝")
    print()


def should_show_windows_control_window(args: argparse.Namespace) -> bool:
    return SYSTEM == "Windows" and getattr(sys, "frozen", False) and not args.headless


def run_windows_control_window(server: ThreadingHTTPServer, poller: Poller, url: str) -> int:
    try:
        import tkinter as tk
        from tkinter import messagebox
    except Exception as exc:  # pragma: no cover - only used in packaged Windows builds
        print(f"[WARN] Could not start Windows control window: {exc}", file=sys.stderr)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()
            poller.stop()
        return 0

    server_thread = threading.Thread(target=server.serve_forever, name="StreamGlowHTTPServer", daemon=True)
    server_thread.start()

    root = tk.Tk()
    root.title("StreamGlow")
    root.geometry("460x260")
    root.resizable(False, False)
    root.configure(bg="#10141f")

    url_var = tk.StringVar(value=url)
    status_var = tk.StringVar(value="StreamGlow is running. Paste this URL into an OBS Browser Source.")

    def copy_url() -> None:
        root.clipboard_clear()
        root.clipboard_append(url)
        status_var.set("Copied OBS URL.")

    def open_overlay() -> None:
        webbrowser.open(url)
        status_var.set("Opened overlay in your browser.")

    def quit_app() -> None:
        root.destroy()

    def on_close() -> None:
        if messagebox.askokcancel("Quit StreamGlow?", "Stop the overlay server and close StreamGlow?"):
            quit_app()

    container = tk.Frame(root, bg="#10141f", padx=24, pady=22)
    container.pack(fill="both", expand=True)

    title = tk.Label(
        container,
        text="StreamGlow",
        bg="#10141f",
        fg="#ffffff",
        font=("Segoe UI", 20, "bold"),
        anchor="w",
    )
    title.pack(fill="x")

    subtitle = tk.Label(
        container,
        text="Native OBS now-playing overlay server for Windows",
        bg="#10141f",
        fg="#c8ceda",
        font=("Segoe UI", 10),
        anchor="w",
    )
    subtitle.pack(fill="x", pady=(2, 18))

    url_entry = tk.Entry(
        container,
        textvariable=url_var,
        readonlybackground="#0a0d14",
        fg="#ffffff",
        bg="#0a0d14",
        insertbackground="#ffffff",
        relief="flat",
        font=("Consolas", 13, "bold"),
    )
    url_entry.configure(state="readonly")
    url_entry.pack(fill="x", ipady=9)

    button_row = tk.Frame(container, bg="#10141f")
    button_row.pack(fill="x", pady=(16, 14))

    button_style = {
        "font": ("Segoe UI", 10, "bold"),
        "relief": "flat",
        "borderwidth": 0,
        "padx": 16,
        "pady": 9,
        "cursor": "hand2",
    }

    tk.Button(button_row, text="Copy OBS URL", command=copy_url, bg="#ff9f3c", fg="#111111", **button_style).pack(side="left")
    tk.Button(button_row, text="Open Preview", command=open_overlay, bg="#263044", fg="#ffffff", **button_style).pack(side="left", padx=(10, 0))
    tk.Button(button_row, text="Quit", command=quit_app, bg="#3a1d28", fg="#ffffff", **button_style).pack(side="right")

    status = tk.Label(
        container,
        textvariable=status_var,
        bg="#10141f",
        fg="#aeb7c8",
        font=("Segoe UI", 9),
        anchor="w",
        justify="left",
        wraplength=400,
    )
    status.pack(fill="x")

    root.protocol("WM_DELETE_WINDOW", on_close)

    try:
        root.mainloop()
    finally:
        server.shutdown()
        server.server_close()
        poller.stop()
        server_thread.join(timeout=2)

    return 0


def main() -> int:
    args = parse_args()

    # Ensure overlays directory exists
    if not OVERLAY_DIR.is_dir():
        print(f"[ERROR] Overlays directory not found: {OVERLAY_DIR}", file=sys.stderr)
        print("Make sure the 'overlays' folder is in the same directory as server.py", file=sys.stderr)
        return 1

    shared = SharedState()
    shared.active_template = args.template

    poller = Poller(interval_seconds=max(0.5, args.interval))

    handler = OverlayHandler
    handler.poller = poller
    handler.shared_state = shared

    url = f"http://{args.host}:{args.port}"
    show_windows_control = should_show_windows_control_window(args)

    try:
        server = ThreadingHTTPServer((args.host, args.port), handler)
    except OSError as exc:
        message = f"Could not start StreamGlow on {url}.\n\n{exc}"
        if show_windows_control:
            try:
                import tkinter as tk
                from tkinter import messagebox

                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("StreamGlow could not start", message)
                root.destroy()
            except Exception:
                pass
        print(f"[ERROR] {message}", file=sys.stderr)
        return 1

    poller.start()

    if show_windows_control:
        return run_windows_control_window(server, poller, url)

    print_startup_banner(url, args.template)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down StreamGlow...")
    finally:
        server.server_close()
        poller.stop()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
