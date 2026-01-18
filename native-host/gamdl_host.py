#!/usr/bin/env python3
"""
Native messaging host for gamdl Chrome extension.
Receives URLs from the extension and launches gamdl to download.
"""

import asyncio
import glob
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import time

# Progress log directory
PROGRESS_DIR = os.path.join(tempfile.gettempdir(), "gamdl_progress")

# Apple Music URL pattern (same as gamdl)
VALID_URL_PATTERN = re.compile(
    r"https://music\.apple\.com"
    r"(?:"
    r"/(?P<storefront>[a-z]{2})"
    r"/(?P<type>artist|album|playlist|song|music-video|post)"
    r"(?:/(?P<slug>[^\s/]+))?"
    r"/(?P<id>[0-9]+|pl\.[0-9a-z]{32}|pl\.u-[a-zA-Z0-9]+)"
    r"(?:\?i=(?P<sub_id>[0-9]+))?"
    r"|"
    r"(?:/(?P<library_storefront>[a-z]{2}))?"
    r"/library/(?P<library_type>playlist|albums)"
    r"/(?P<library_id>p\.[a-zA-Z0-9]+|l\.[a-zA-Z0-9]+)"
    r")"
)


def read_message():
    """Read a message from stdin (Chrome native messaging protocol)."""
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length:
        return None
    message_length = struct.unpack("I", raw_length)[0]
    message = sys.stdin.buffer.read(message_length).decode("utf-8")
    return json.loads(message)


def send_message(message):
    """Send a message to stdout (Chrome native messaging protocol)."""
    encoded = json.dumps(message).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def get_project_root():
    """Get the project root directory."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


def find_gamdl():
    """Find the gamdl executable."""
    # Check common installed locations directly (don't rely on PATH/which)
    paths_to_check = [
        os.path.expanduser("~/.local/bin/gamdl"),  # pipx location
        "/usr/local/bin/gamdl",
        "/opt/homebrew/bin/gamdl",
    ]

    for path in paths_to_check:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return (path, [])

    return None


def get_gamdl_python():
    """Get a Python interpreter that can import gamdl."""
    # Check common locations for pipx-installed gamdl
    pipx_python = os.path.expanduser("~/.local/pipx/venvs/gamdl/bin/python")
    if os.path.isfile(pipx_python):
        return pipx_python

    # Check if system python3 can import gamdl
    result = subprocess.run(
        ["python3", "-c", "import gamdl"], capture_output=True
    )
    if result.returncode == 0:
        return "python3"
    return None


def get_output_path():
    """Get the configured output path from config file."""
    import configparser
    config_path = os.path.join(os.path.expanduser("~"), ".gamdl", "config.ini")
    if os.path.exists(config_path):
        config = configparser.ConfigParser()
        config.read(config_path)
        if "gamdl" in config and "output_path" in config["gamdl"]:
            return config["gamdl"]["output_path"]
    return os.path.join(get_project_root(), "Apple Music")


def check_album_downloaded(artist_name, album_name):
    """Check if an album folder exists in the output directory."""
    try:
        output_path = get_output_path()
        # Check for artist/album folder structure
        album_path = os.path.join(output_path, artist_name, album_name)
        if os.path.isdir(album_path):
            # Check if there are any audio files
            for f in os.listdir(album_path):
                if f.endswith(('.m4a', '.mp3', '.flac', '.aac')):
                    return True
        return False
    except (OSError, PermissionError):
        # Can't access the directory (e.g., SMB share permission issues)
        return False


def fetch_items(url):
    """Fetch available items for an artist or album URL."""
    match = VALID_URL_PATTERN.match(url)
    if not match:
        return {"success": False, "error": "Invalid Apple Music URL"}

    groups = match.groupdict()
    url_type = groups.get("type") or groups.get("library_type")
    url_id = groups.get("id") or groups.get("library_id")

    # Only fetch items for artists (albums are fetched as tracks)
    if url_type not in ("artist", "album"):
        return {
            "success": True,
            "type": url_type,
            "items": [],
            "message": "Direct download available",
        }

    gamdl_python = get_gamdl_python()
    if not gamdl_python:
        return {"success": False, "error": "gamdl not found. Install with: pipx install gamdl"}

    # Run a Python script to fetch items using gamdl's API
    fetch_script = f'''
import asyncio
import configparser
import json
from pathlib import Path

from gamdl.api.apple_music_api import AppleMusicApi

def get_cookies_path():
    config_path = Path.home() / ".gamdl" / "config.ini"
    if config_path.exists():
        config = configparser.ConfigParser()
        config.read(config_path)
        if "gamdl" in config and "cookies_path" in config["gamdl"]:
            return config["gamdl"]["cookies_path"]
    return "./cookies.txt"

async def fetch():
    try:
        cookies_path = get_cookies_path()
        api = await AppleMusicApi.create_from_netscape_cookies(cookies_path=cookies_path)

        url_type = "{url_type}"
        url_id = "{url_id}"

        if url_type == "artist":
            response = await api.get_artist(url_id)
            if not response:
                print(json.dumps({{"success": False, "error": "Artist not found"}}))
                return

            artist = response["data"][0]
            artist_name = artist["attributes"]["name"]

            # Get albums
            albums_data = artist.get("relationships", {{}}).get("albums", {{}}).get("data", [])

            # Extend to get all albums
            albums_rel = artist.get("relationships", {{}}).get("albums", {{}})
            if albums_rel:
                async for extended in api.extend_api_data(albums_rel):
                    albums_data.append(extended)

            items = []
            for album in albums_data:
                if album.get("attributes"):
                    attrs = album["attributes"]
                    # Get album artist (may differ from page artist for compilations)
                    album_artist = attrs.get("artistName", artist_name)
                    items.append({{
                        "id": album["id"],
                        "name": attrs.get("name", "Unknown"),
                        "artistName": album_artist,
                        "trackCount": attrs.get("trackCount", 0),
                        "releaseDate": attrs.get("releaseDate", ""),
                        "contentRating": attrs.get("contentRating", ""),
                        "type": "album"
                    }})

            # Sort by release date descending
            items.sort(key=lambda x: x.get("releaseDate", ""), reverse=True)

            print(json.dumps({{
                "success": True,
                "type": "artist",
                "artistName": artist_name,
                "items": items
            }}))

        elif url_type == "album":
            response = await api.get_album(url_id)
            if not response:
                print(json.dumps({{"success": False, "error": "Album not found"}}))
                return

            album = response["data"][0]
            album_name = album["attributes"]["name"]
            tracks_data = album.get("relationships", {{}}).get("tracks", {{}}).get("data", [])

            items = []
            for track in tracks_data:
                if track.get("attributes"):
                    attrs = track["attributes"]
                    items.append({{
                        "id": track["id"],
                        "name": attrs.get("name", "Unknown"),
                        "trackNumber": attrs.get("trackNumber", 0),
                        "discNumber": attrs.get("discNumber", 1),
                        "durationInMillis": attrs.get("durationInMillis", 0),
                        "type": "song"
                    }})

            # Sort by disc and track number
            items.sort(key=lambda x: (x.get("discNumber", 1), x.get("trackNumber", 0)))

            print(json.dumps({{
                "success": True,
                "type": "album",
                "albumName": album_name,
                "items": items
            }}))

    except Exception as e:
        print(json.dumps({{"success": False, "error": str(e)}}))

asyncio.run(fetch())
'''

    try:
        result = subprocess.run(
            [gamdl_python, "-c", fetch_script],
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode != 0:
            error = result.stderr.strip() if result.stderr else "Unknown error"
            return {"success": False, "error": error}

        response = json.loads(result.stdout.strip())

        # Check which items are already downloaded
        if response.get("success") and response.get("items"):
            for item in response["items"]:
                if item.get("type") == "album":
                    artist_name = item.get("artistName", response.get("artistName", ""))
                    album_name = item.get("name", "")
                    item["downloaded"] = check_album_downloaded(artist_name, album_name)
                else:
                    item["downloaded"] = False

        return response

    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Request timed out"}
    except json.JSONDecodeError:
        return {"success": False, "error": "Invalid response from gamdl"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def get_full_env():
    """Get environment with full PATH for finding ffmpeg, amdecrypt, etc."""
    env = os.environ.copy()
    # Add common paths where tools like ffmpeg, amdecrypt might be installed
    extra_paths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        os.path.expanduser("~/.local/bin"),
        os.path.expanduser("~/wrapper"),  # amdecrypt location
    ]
    current_path = env.get("PATH", "")
    env["PATH"] = ":".join(extra_paths) + ":" + current_path
    return env


def start_download_process(cmd, env):
    """Start a gamdl download process with progress logging."""
    # Create progress directory if it doesn't exist
    os.makedirs(PROGRESS_DIR, exist_ok=True)

    # Clean up old log files (older than 1 hour)
    cleanup_old_logs()

    # Create a unique log file for this download
    log_file = os.path.join(PROGRESS_DIR, f"download_{int(time.time() * 1000)}.log")

    # Start the process with output redirected to log file
    with open(log_file, "w") as f:
        subprocess.Popen(
            cmd,
            stdout=f,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
            cwd=get_project_root(),
            env=env,
        )


def cleanup_old_logs():
    """Remove log files older than 1 hour."""
    try:
        cutoff = time.time() - 3600  # 1 hour ago
        for log_file in glob.glob(os.path.join(PROGRESS_DIR, "download_*.log")):
            if os.path.getmtime(log_file) < cutoff:
                os.remove(log_file)
    except Exception:
        pass


def download(url, selected_ids=None, codec="aac-legacy"):
    """Launch gamdl to download the given URL or specific items."""
    if not VALID_URL_PATTERN.match(url):
        return {"success": False, "error": "Invalid Apple Music URL"}

    gamdl_info = find_gamdl()

    if not gamdl_info:
        return {
            "success": False,
            "error": "gamdl not found. Install with: pip install gamdl",
        }

    try:
        executable, extra_args = gamdl_info

        # Build codec args
        codec_args = ["--song-codec", codec] if codec else []

        # ALAC requires wrapper mode
        if codec == "alac":
            codec_args.append("--use-wrapper")

        env = get_full_env()

        # If specific IDs are selected, download each one
        if selected_ids:
            # Parse the original URL to get storefront
            match = VALID_URL_PATTERN.match(url)
            groups = match.groupdict()
            storefront = groups.get("storefront", "us")
            url_type = groups.get("type")

            # Build URLs for selected items
            urls_to_download = []
            for item_id in selected_ids:
                if url_type == "artist":
                    # Selected albums from artist page
                    item_url = f"https://music.apple.com/{storefront}/album/{item_id}"
                elif url_type == "album":
                    # Selected songs from album page - use ?i= parameter
                    item_url = f"{url.split('?')[0]}?i={item_id}"
                else:
                    item_url = url
                urls_to_download.append(item_url)

            # Download each selected item
            for item_url in urls_to_download:
                cmd = [executable] + extra_args + codec_args + [item_url]
                start_download_process(cmd, env)

            format_label = "ALAC" if codec == "alac" else "AAC"
            return {
                "success": True,
                "message": f"Started downloading {len(urls_to_download)} item(s) in {format_label}",
            }
        else:
            # Download the whole URL
            cmd = [executable] + extra_args + codec_args + [url]
            start_download_process(cmd, env)

            format_label = "ALAC" if codec == "alac" else "AAC"
            return {"success": True, "message": f"Download started in {format_label}"}

    except FileNotFoundError:
        return {
            "success": False,
            "error": "gamdl not found. Install with: pip install gamdl",
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


def strip_ansi(text):
    """Remove ANSI escape codes from text."""
    return re.sub(r'\x1b\[[0-9;]*m', '', text)


def parse_progress_from_logs():
    """Parse all active log files to extract download progress."""
    tracks = []
    errors = []

    try:
        log_files = glob.glob(os.path.join(PROGRESS_DIR, "download_*.log"))

        for log_file in log_files:
            # Skip old files (older than 10 minutes - likely finished)
            if time.time() - os.path.getmtime(log_file) > 600:
                continue

            try:
                with open(log_file, "r") as f:
                    content = strip_ansi(f.read())

                # Parse track progress from log content
                # Look for patterns like: [Track 1/10] Downloading "Song Name"
                track_matches = re.findall(
                    r'\[Track (\d+)/(\d+)\] Downloading "([^"]+)"',
                    content
                )

                # Look for download progress: [download] XX.X% of
                download_progress = re.findall(
                    r'\[download\]\s+(\d+(?:\.\d+)?%)',
                    content
                )

                # Look for completed tracks
                completed_matches = re.findall(
                    r'\[Track \d+/\d+\] Downloaded "[^"]+"',
                    content
                )

                # Look for errors
                error_matches = re.findall(
                    r'ERROR.*?downloading "([^"]+)"',
                    content,
                    re.IGNORECASE
                )

                # Check if finished
                finished = "Finished with" in content

                if track_matches:
                    current_track, total_tracks, track_name = track_matches[-1]
                    progress = download_progress[-1] if download_progress else "0%"

                    tracks.append({
                        "name": track_name,
                        "current": int(current_track),
                        "total": int(total_tracks),
                        "progress": progress,
                        "completed": len(completed_matches),
                        "finished": finished,
                    })

                errors.extend(error_matches)

            except Exception:
                continue

    except Exception:
        pass

    return tracks, errors


def check_download_status():
    """Check if any gamdl downloads are currently running."""
    try:
        # Check for running gamdl processes (matches both pipx and module invocations)
        result = subprocess.run(
            ["pgrep", "-f", "gamdl.*music.apple.com"],
            capture_output=True,
            text=True,
        )
        is_downloading = result.returncode == 0
        process_count = len(result.stdout.strip().split('\n')) if is_downloading else 0

        # Parse progress from log files
        tracks, errors = parse_progress_from_logs()

        return {
            "success": True,
            "isDownloading": is_downloading,
            "processCount": process_count,
            "tracks": tracks,
            "errors": errors,
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


def main():
    """Main entry point."""
    message = read_message()

    if not message:
        send_message({"success": False, "error": "No message received"})
        return

    action = message.get("action")

    if action == "download":
        url = message.get("url")
        selected_ids = message.get("selectedIds")
        codec = message.get("codec", "aac-legacy")
        if not url:
            send_message({"success": False, "error": "No URL provided"})
        else:
            result = download(url, selected_ids, codec)
            send_message(result)
    elif action == "fetch_items":
        url = message.get("url")
        if not url:
            send_message({"success": False, "error": "No URL provided"})
        else:
            result = fetch_items(url)
            send_message(result)
    elif action == "check_status":
        result = check_download_status()
        send_message(result)
    else:
        send_message({"success": False, "error": f"Unknown action: {action}"})


if __name__ == "__main__":
    main()
