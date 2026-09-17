#!/usr/bin/env python3
"""Grok Build credentials for the board. Invoked as root via sudo from phpBB.

Subcommands: status | set-key | device-start | device-status | device-cancel | clear
set-key reads the key from stdin (one line). stdout is always JSON.
"""
from __future__ import annotations

import json
import os
import pwd
import re
import signal
import sys
import time
from datetime import datetime, timezone
from typing import Any

GROK_USER = os.environ.get("GROK_USER", "grokbuild")
GROK_HOME = f"/home/{GROK_USER}"
AUTH_JSON = f"{GROK_HOME}/.grok/auth.json"
XAI_ENV = "/etc/grokboard/xai.env"
STAMP = "/etc/grokboard/auth.status"
STATE_DIR = "/etc/grokboard/auth-state"
STATE_PID = f"{STATE_DIR}/pid"
STATE_OUT = f"{STATE_DIR}/out"
GROK_BIN = "/usr/local/bin/grok"


def out(payload: dict[str, Any], code: int = 0) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()
    raise SystemExit(code)


def fail(message: str, **extra: Any) -> None:
    payload = {"ok": False, "error": message, "authenticated": False}
    payload.update(extra)
    out(payload, 1)


def require_root() -> None:
    if os.geteuid() != 0:
        fail("root required")


def ensure_dirs() -> None:
    os.makedirs("/etc/grokboard", mode=0o750, exist_ok=True)
    os.makedirs(f"{GROK_HOME}/.grok", mode=0o700, exist_ok=True)
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    try:
        u = pwd.getpwnam(GROK_USER)
        os.chown(f"{GROK_HOME}/.grok", u.pw_uid, u.pw_gid)
        os.chmod(f"{GROK_HOME}/.grok", 0o700)
    except KeyError:
        pass


def parse_iso(ts: str) -> datetime | None:
    if not ts:
        return None
    try:
        if ts.endswith("Z"):
            ts = ts[:-1] + "+00:00"
        return datetime.fromisoformat(ts)
    except ValueError:
        return None


def auth_json_info() -> dict[str, Any]:
    info: dict[str, Any] = {
        "present": False,
        "email": "",
        "expired": False,
        "expires_at": "",
    }
    if not os.path.isfile(AUTH_JSON) or os.path.getsize(AUTH_JSON) == 0:
        return info
    try:
        with open(AUTH_JSON, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return info
    info["present"] = True

    def walk(obj: Any) -> None:
        if not isinstance(obj, dict):
            return
        if not info["email"] and isinstance(obj.get("email"), str):
            info["email"] = obj["email"]
        if not info["expires_at"] and isinstance(obj.get("expires_at"), str):
            info["expires_at"] = obj["expires_at"]
        for v in obj.values():
            if isinstance(v, dict):
                walk(v)

    walk(data)
    exp = parse_iso(info["expires_at"])
    if exp is not None:
        now = datetime.now(timezone.utc)
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        # Still "present" if expired — grok can refresh from the refresh_token.
        info["expired"] = exp <= now
    return info


def api_key_present() -> bool:
    if not os.path.isfile(XAI_ENV):
        return False
    try:
        with open(XAI_ENV, "r", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("XAI_API_KEY="):
                    return bool(line.split("=", 1)[1].strip().strip("\"'"))
    except OSError:
        return False
    return False


def snapshot() -> dict[str, Any]:
    info = auth_json_info()
    key = api_key_present()
    if info["present"]:
        method = "device"
        authed = True
    elif key:
        method = "api_key"
        authed = True
    else:
        method = "none"
        authed = False
    return {
        "ok": True,
        "authenticated": authed,
        "method": method,
        "email": info["email"] if authed and method == "device" else "",
        "expired": bool(info["expired"]) if info["present"] else False,
    }


def write_stamp(snap: dict[str, Any] | None = None) -> dict[str, Any]:
    snap = snap or snapshot()
    lines = ["ok" if snap.get("authenticated") else "missing"]
    lines.append(str(snap.get("method") or "none"))
    if snap.get("email"):
        lines.append(str(snap["email"]))
    tmp = STAMP + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, STAMP)
    return snap


def write_xai_env(key: str) -> None:
    ensure_dirs()
    tmp = XAI_ENV + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("XAI_API_KEY=" + key + "\n")
    os.chmod(tmp, 0o600)
    try:
        u = pwd.getpwnam(GROK_USER)
        os.chown(tmp, u.pw_uid, u.pw_gid)
    except KeyError:
        pass
    os.replace(tmp, XAI_ENV)


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def read_pid() -> int:
    try:
        with open(STATE_PID, "r", encoding="utf-8") as fh:
            return int(fh.read().strip() or "0")
    except (OSError, ValueError):
        return 0


def reap(pid: int) -> None:
    if pid <= 0:
        return
    try:
        os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        pass


def kill_device() -> None:
    pid = read_pid()
    if pid_alive(pid):
        try:
            os.killpg(pid, signal.SIGTERM)
        except OSError:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        for _ in range(20):
            if not pid_alive(pid):
                break
            time.sleep(0.1)
        if pid_alive(pid):
            try:
                os.killpg(pid, signal.SIGKILL)
            except OSError:
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
        reap(pid)
    for path in (STATE_PID, STATE_OUT):
        try:
            os.remove(path)
        except OSError:
            pass


def strip_ansi(text: str) -> str:
    text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
    text = re.sub(r"\r", "\n", text)
    return text


def parse_device_output(text: str) -> tuple[str, str]:
    text = strip_ansi(text)
    urls = re.findall(r"https://[^\s\"'<>]+", text)
    url = urls[0] if urls else ""
    code = ""
    m = re.search(
        r"(?:user[_ ]?code|enter(?: the)? code|code is|code:)\s*([A-Z0-9][A-Z0-9-]{3,})",
        text,
        re.I,
    )
    if m:
        code = m.group(1).rstrip(".,);")
    if not code:
        m = re.search(r"\b([A-Z0-9]{4}-[A-Z0-9]{4})\b", text)
        if m:
            code = m.group(1)
    if not code and url:
        m = re.search(r"user_code=([A-Z0-9-]+)", url, re.I)
        if m:
            code = m.group(1)
    return url, code


def read_out() -> str:
    try:
        with open(STATE_OUT, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def device_payload(status: str, **extra: Any) -> dict[str, Any]:
    raw = read_out()
    url, code = parse_device_output(raw)
    snap = snapshot()
    payload = {
        "ok": True,
        "status": status,
        "verification_url": url,
        "user_code": code,
        "authenticated": snap["authenticated"],
        "method": snap["method"],
        "email": snap["email"],
    }
    payload.update(extra)
    return payload


def cmd_status() -> None:
    out(write_stamp())


def cmd_set_key() -> None:
    key = sys.stdin.read()
    if "\n" in key:
        key = key.split("\n", 1)[0]
    key = key.strip().strip("\"'")
    if not key:
        fail("API key was empty")
    if len(key) > 8192 or any(ord(c) < 32 for c in key):
        fail("API key is not valid")
    write_xai_env(key)
    # Prefer the key over a stale device session.
    if os.path.isfile(AUTH_JSON):
        bak = AUTH_JSON + ".bak"
        try:
            os.replace(AUTH_JSON, bak)
        except OSError:
            try:
                os.remove(AUTH_JSON)
            except OSError:
                pass
    snap = write_stamp()
    snap["message"] = "API key stored on the data volume."
    out(snap)


def cmd_device_start() -> None:
    if not os.path.isfile(GROK_BIN) or not os.access(GROK_BIN, os.X_OK):
        fail("Grok Build CLI is missing from the container")
    ensure_dirs()
    pid = read_pid()
    if pid_alive(pid):
        out(device_payload("pending", message="Device login already in progress."))
        return
    kill_device()
    ensure_dirs()
    out_fh = os.open(STATE_OUT, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
    pid = os.fork()
    if pid == 0:
        try:
            os.setsid()
            os.dup2(out_fh, 1)
            os.dup2(out_fh, 2)
            import pty

            u = pwd.getpwnam(GROK_USER)
            os.chdir(GROK_HOME)
            os.setgid(u.pw_gid)
            try:
                os.initgroups(GROK_USER, u.pw_gid)
            except OSError:
                pass
            os.setuid(u.pw_uid)
            os.environ["HOME"] = GROK_HOME
            os.environ["USER"] = GROK_USER
            os.environ["LOGNAME"] = GROK_USER
            os.environ["TERM"] = "xterm-256color"
            os.environ.pop("XAI_API_KEY", None)
            pty.spawn([GROK_BIN, "login", "--device-auth"])
        except Exception as exc:
            try:
                os.write(2, ("device login failed: %s\n" % exc).encode())
            except OSError:
                pass
            os._exit(1)
        os._exit(0)
    os.close(out_fh)
    with open(STATE_PID, "w", encoding="utf-8") as fh:
        fh.write(str(pid) + "\n")
    url = code = ""
    for _ in range(25):
        time.sleep(0.4)
        url, code = parse_device_output(read_out())
        if url or code:
            break
        if not pid_alive(pid):
            break
    if not pid_alive(pid) and not os.path.isfile(AUTH_JSON):
        tail = strip_ansi(read_out()).strip().splitlines()
        fail(
            "Device login exited before a code appeared.",
            status="failed",
            log="\n".join(tail[-20:]),
        )
    out(device_payload("pending", message="Open the URL and enter the code."))


def cmd_device_status() -> None:
    snap = snapshot()
    if snap["authenticated"] and snap["method"] == "device":
        kill_device()
        write_stamp(snap)
        out(device_payload("complete", message="Signed in.", **snap))
        return
    pid = read_pid()
    if pid_alive(pid):
        out(device_payload("pending"))
        return
    if os.path.isfile(STATE_OUT) or os.path.isfile(STATE_PID):
        tail = strip_ansi(read_out()).strip().splitlines()
        # Login process ended. If auth.json still missing, it failed.
        if not snap["authenticated"]:
            payload = device_payload(
                "failed",
                ok=False,
                error="Device login did not finish. You can start it again.",
                log="\n".join(tail[-20:]),
            )
            out(payload, 1)
            return
        write_stamp(snap)
        out(device_payload("complete", **snap))
        return
    out(device_payload("idle"))


def cmd_device_cancel() -> None:
    kill_device()
    out({**write_stamp(), "status": "idle", "message": "Device login cancelled."})


def cmd_clear() -> None:
    kill_device()
    for path in (AUTH_JSON, AUTH_JSON + ".bak", XAI_ENV):
        try:
            os.remove(path)
        except OSError:
            pass
    snap = write_stamp()
    snap["message"] = "Grok Build credentials removed."
    out(snap)


def main() -> None:
    require_root()
    ensure_dirs()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    cmds = {
        "status": cmd_status,
        "set-key": cmd_set_key,
        "device-start": cmd_device_start,
        "device-status": cmd_device_status,
        "device-cancel": cmd_device_cancel,
        "clear": cmd_clear,
    }
    if cmd not in cmds:
        fail("unknown command: " + cmd)
    cmds[cmd]()


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        fail(str(exc))
