#!/usr/bin/env python3
"""
AirPlay video receiver -> FPP matrix overlay bridge.

Pipeline:
1) UxPlay receives AirPlay mirror stream.
2) UxPlay sends decoded video frames to a GStreamer shared-memory sink.
3) gst-launch reads that sink, scales to matrix size, outputs RGB bytes on stdout.
4) This daemon writes RGB frames into FPP overlay mmap buffer and sets dirty bit.
"""

from __future__ import annotations

import argparse
import json
import mmap
import os
import select
import shlex
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from typing import Dict, Optional, Tuple

DEFAULT_CONFIG = {
    "enabled": True,
    "airplay_name": "FPP AirPlay Matrix",
    "model_name": "Matrix",
    "fps": 20,
    "flip_x": False,
    "flip_y": False,
    "uxplay_extra_args": "",
}

STOP = False


def log(msg: str) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def handle_signal(signum, _frame) -> None:
    global STOP
    STOP = True
    log(f"Received signal {signum}, shutting down")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--config", required=True)
    p.add_argument("--media-dir", required=True)
    p.add_argument("--plugin-dir", required=True)
    return p.parse_args()


def load_config(path: str) -> Dict:
    cfg = dict(DEFAULT_CONFIG)
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            cfg.update(data)
    except FileNotFoundError:
        log(f"Config not found at {path}, using defaults")
    except Exception as ex:
        log(f"Failed reading config {path}: {ex}; using defaults")

    cfg["enabled"] = bool(cfg.get("enabled", True))
    cfg["airplay_name"] = str(cfg.get("airplay_name", DEFAULT_CONFIG["airplay_name"]))
    cfg["model_name"] = str(cfg.get("model_name", DEFAULT_CONFIG["model_name"]))

    try:
        cfg["fps"] = int(cfg.get("fps", DEFAULT_CONFIG["fps"]))
    except Exception:
        cfg["fps"] = DEFAULT_CONFIG["fps"]
    cfg["fps"] = max(5, min(60, cfg["fps"]))

    cfg["flip_x"] = bool(cfg.get("flip_x", False))
    cfg["flip_y"] = bool(cfg.get("flip_y", False))
    cfg["uxplay_extra_args"] = str(cfg.get("uxplay_extra_args", ""))
    return cfg


def http_json(method: str, url: str, body: Optional[Dict] = None, timeout: float = 5.0) -> Dict:
    data = None
    headers = {"Content-Type": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")

    req = urllib.request.Request(url=url, method=method.upper(), data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        payload = resp.read()
        if not payload:
            return {}
        decoded = payload.decode("utf-8", errors="replace")
        try:
            return json.loads(decoded)
        except Exception:
            return {"raw": decoded}


def ensure_model_ready(model: str) -> Tuple[int, int]:
    encoded = urllib.parse.quote(model, safe="")
    base = f"http://127.0.0.1/api/overlays/model/{encoded}"

    last_error = ""
    for _ in range(30):
        if STOP:
            raise RuntimeError("Interrupted")
        try:
            info = http_json("GET", base)
            width = int(info.get("width", 0))
            height = int(info.get("height", 0))
            if width <= 0 or height <= 0:
                raise RuntimeError(f"Invalid matrix dimensions from FPP API: {width}x{height}")

            http_json("PUT", f"{base}/state", {"State": 1})
            http_json("PUT", f"{base}/mmap", {})
            return width, height
        except Exception as ex:
            last_error = str(ex)
            time.sleep(1)

    raise RuntimeError(f"Could not prepare model '{model}': {last_error}")


def overlay_shm_path(model: str) -> str:
    # FPP replaces '/' with '_' in model names for shm object names.
    safe_model = model.replace("/", "_")
    return f"/dev/shm/FPP-Model-Overlay-Buffer-{safe_model}"


def open_overlay_mmap(model: str, width: int, height: int) -> mmap.mmap:
    path = overlay_shm_path(model)
    size = 12 + (width * height * 3)

    last_error = ""
    for _ in range(40):
        if STOP:
            raise RuntimeError("Interrupted")
        try:
            fd = os.open(path, os.O_RDWR)
            try:
                mm = mmap.mmap(fd, size, access=mmap.ACCESS_WRITE)
            finally:
                os.close(fd)

            actual_w = int.from_bytes(mm[0:4], "little", signed=False)
            actual_h = int.from_bytes(mm[4:8], "little", signed=False)
            if actual_w != width or actual_h != height:
                mm.close()
                raise RuntimeError(
                    f"Overlay header mismatch. expected={width}x{height} actual={actual_w}x{actual_h}"
                )
            return mm
        except Exception as ex:
            last_error = str(ex)
            time.sleep(0.25)

    raise RuntimeError(f"Unable to open overlay mmap {path}: {last_error}")


def set_dirty(mm: mmap.mmap) -> None:
    flags = int.from_bytes(mm[8:12], "little", signed=False)
    flags |= 0x1
    mm[8:12] = flags.to_bytes(4, "little", signed=False)


def clear_frame(mm: mmap.mmap, frame_size: int) -> None:
    mm[12 : 12 + frame_size] = b"\x00" * frame_size
    set_dirty(mm)


def transform_frame(frame: bytes, width: int, height: int, flip_x: bool, flip_y: bool) -> bytes:
    if not flip_x and not flip_y:
        return frame

    out = bytearray(len(frame))
    row_bytes = width * 3

    for y in range(height):
        src_y = (height - 1 - y) if flip_y else y
        for x in range(width):
            src_x = (width - 1 - x) if flip_x else x
            src_idx = (src_y * row_bytes) + (src_x * 3)
            dst_idx = (y * row_bytes) + (x * 3)
            out[dst_idx : dst_idx + 3] = frame[src_idx : src_idx + 3]

    return bytes(out)


def start_uxplay(airplay_name: str, socket_path: str, extra_args: str) -> subprocess.Popen:
    sink = (
        f"shmsink socket-path={socket_path} "
        "shm-size=33554432 wait-for-connection=false sync=false"
    )

    # Some distro builds (including certain FPP images) do not support -vsync.
    cmd = ["uxplay", "-n", airplay_name, "-vs", sink]
    if extra_args.strip():
        cmd.extend(shlex.split(extra_args.strip()))

    log("Starting UxPlay: " + " ".join(shlex.quote(c) for c in cmd))
    # Inherit daemon stdout/stderr so UxPlay diagnostics land in plugin log.
    return subprocess.Popen(cmd)


def check_discovery_environment() -> None:
    try:
        proc = subprocess.run(
            ["systemctl", "is-active", "avahi-daemon"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        state = (proc.stdout or "").strip()
        if state != "active":
            log("WARNING: avahi-daemon is not active; AirPlay target may not be discoverable.")
    except Exception as ex:
        log(f"WARNING: Unable to check avahi-daemon state: {ex}")


def start_gst_reader(socket_path: str, width: int, height: int, fps: int) -> subprocess.Popen:
    caps = f"video/x-raw,format=RGB,width={width},height={height},framerate={fps}/1,pixel-aspect-ratio=1/1"

    cmd = [
        "gst-launch-1.0",
        "-q",
        "shmsrc",
        f"socket-path={socket_path}",
        "is-live=true",
        "do-timestamp=true",
        "!",
        "queue",
        "!",
        "videoconvert",
        "!",
        "videoscale",
        "!",
        "videorate",
        "!",
        caps,
        "!",
        "fdsink",
        "fd=1",
        "sync=false",
    ]

    log("Starting frame reader: " + " ".join(shlex.quote(c) for c in cmd))
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)


def terminate_process(proc: Optional[subprocess.Popen], name: str) -> None:
    if proc is None:
        return

    try:
        if proc.poll() is None:
            proc.terminate()
            for _ in range(20):
                if proc.poll() is not None:
                    break
                time.sleep(0.1)
            if proc.poll() is None:
                proc.kill()
    except Exception as ex:
        log(f"Error stopping {name}: {ex}")


def main() -> int:
    global STOP

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    args = parse_args()
    cfg = load_config(args.config)

    if not cfg["enabled"]:
        log("Plugin disabled in config; exiting")
        return 0

    if shutil.which("uxplay") is None:
        log("uxplay binary not found in PATH")
        return 1
    if shutil.which("gst-launch-1.0") is None:
        log("gst-launch-1.0 binary not found in PATH")
        return 1

    check_discovery_environment()

    model_name = cfg["model_name"]
    airplay_name = cfg["airplay_name"]
    fps = cfg["fps"]
    flip_x = cfg["flip_x"]
    flip_y = cfg["flip_y"]

    runtime_dir = os.path.join(args.media_dir, "tmp", "fpp-AirPlayMatrix")
    os.makedirs(runtime_dir, exist_ok=True)
    socket_path = os.path.join(runtime_dir, "uxplay-video.sock")

    if os.path.exists(socket_path):
        try:
            os.unlink(socket_path)
        except Exception:
            pass

    log(f"Preparing matrix model '{model_name}'")
    width, height = ensure_model_ready(model_name)
    log(f"Matrix size: {width}x{height}")

    mm = open_overlay_mmap(model_name, width, height)
    frame_size = width * height * 3
    clear_frame(mm, frame_size)

    ux_proc: Optional[subprocess.Popen] = None
    gst_proc: Optional[subprocess.Popen] = None
    frame_buffer = bytearray()

    try:
        ux_proc = start_uxplay(airplay_name, socket_path, cfg["uxplay_extra_args"])

        while not STOP:
            if ux_proc.poll() is not None:
                raise RuntimeError(f"UxPlay exited with code {ux_proc.returncode}")

            if gst_proc is None or gst_proc.poll() is not None:
                terminate_process(gst_proc, "gst-reader")
                gst_proc = start_gst_reader(socket_path, width, height, fps)
                frame_buffer = bytearray()
                time.sleep(0.2)

            if gst_proc.stdout is None:
                time.sleep(0.1)
                continue

            ready, _, _ = select.select([gst_proc.stdout], [], [], 0.5)
            if not ready:
                continue

            chunk = os.read(gst_proc.stdout.fileno(), 65536)
            if not chunk:
                terminate_process(gst_proc, "gst-reader")
                gst_proc = None
                frame_buffer = bytearray()
                time.sleep(0.3)
                continue

            frame_buffer.extend(chunk)
            while len(frame_buffer) >= frame_size:
                raw = bytes(frame_buffer[:frame_size])
                del frame_buffer[:frame_size]

                frame = transform_frame(raw, width, height, flip_x, flip_y)
                mm[12 : 12 + frame_size] = frame
                set_dirty(mm)

    except Exception as ex:
        log(f"Fatal error: {ex}")
        return_code = 1
    else:
        return_code = 0
    finally:
        clear_frame(mm, frame_size)
        mm.close()
        terminate_process(gst_proc, "gst-reader")
        terminate_process(ux_proc, "uxplay")

        if os.path.exists(socket_path):
            try:
                os.unlink(socket_path)
            except Exception:
                pass

    return return_code


if __name__ == "__main__":
    sys.exit(main())
