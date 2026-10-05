#!/usr/bin/env python3
"""Keep unused iOS 26 simulator background services from starving hosted UI tests.

Inspired by the documented simulator workaround in biscuitehh/yeetd.
Only processes whose executable lives inside a simulator runtime are eligible.
Push-delivery tests must run without this watcher. This app's UI suite exercises
public browsing, saved preferences and layout. Every paused process is resumed
on cleanup, after checking that its PID still refers to the same executable.
"""
import ctypes
import os
import signal
import sys
import time

if sys.platform != "darwin":
    raise SystemExit(0)

libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
libproc.proc_listallpids.argtypes = [ctypes.c_void_p, ctypes.c_int]
libproc.proc_listallpids.restype = ctypes.c_int
libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
libproc.proc_pidpath.restype = ctypes.c_int

runtime_marker = "simruntime/Contents/Resources/RuntimeRoot"
background_names = {
    "AegirPoster", "InfographPoster", "CollectionsPoster",
    "ExtragalacticPoster", "KaleidoscopePoster", "EmojiPosterExtension",
    "AmbientPhotoFramePosterProvider", "PhotosPosterProvider",
    "AvatarPosterExtension", "GradientPosterExtension",
    "MonogramPosterExtension", "apsd",
}
paused = {}
stopping = False


def process_path(pid):
    buffer = ctypes.create_string_buffer(4096)
    if libproc.proc_pidpath(pid, buffer, len(buffer)) <= 0:
        return ""
    return os.fsdecode(buffer.value)


def stop_watching(*_):
    global stopping
    stopping = True


signal.signal(signal.SIGTERM, stop_watching)
signal.signal(signal.SIGINT, stop_watching)
deadline = time.monotonic() + 30 * 60

try:
    while not stopping and time.monotonic() < deadline:
        count = libproc.proc_listallpids(None, 0)
        if count > 0:
            pids = (ctypes.c_int * (count + 128))()
            actual = libproc.proc_listallpids(pids, ctypes.sizeof(pids))
            for pid in pids[:max(0, min(actual, len(pids)))]:
                if pid <= 0 or pid in paused:
                    continue
                path = process_path(pid)
                if runtime_marker not in path or os.path.basename(path) not in background_names:
                    continue
                try:
                    os.kill(pid, signal.SIGSTOP)
                    paused[pid] = path
                    print("Paused simulator background service: " + os.path.basename(path), flush=True)
                except ProcessLookupError:
                    pass
                except PermissionError:
                    pass
        time.sleep(3)
finally:
    for pid, path in paused.items():
        if process_path(pid) == path:
            try:
                os.kill(pid, signal.SIGCONT)
            except (ProcessLookupError, PermissionError):
                pass
