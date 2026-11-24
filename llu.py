#!/usr/bin/env python3
"""LibreLinkUp fetcher for the Omarchy bar widget.

Reads credentials from ~/.config/librelinkup/config.json, caches the session
token in ~/.cache/librelinkup/session.json, and prints one JSON object to
stdout. Uses the unofficial LibreView follower API (can change without notice).
"""
import calendar, hashlib, json, os, sys, time, urllib.request, urllib.error

CONFIG = os.path.expanduser("~/.config/librelinkup/config.json")
CACHE = os.path.expanduser("~/.cache/librelinkup/session.json")
HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "product": "llu.android",
    "version": "4.16.0",
    "User-Agent": "Mozilla/5.0",
    "cache-control": "no-cache",
}


class Err(Exception):
    pass


def out(obj):
    print(json.dumps(obj))
    sys.exit(0)


def request(host, path, body=None, token=None, account=None):
    h = dict(HEADERS)
    if token:
        h["Authorization"] = "Bearer " + token
    if account:
        h["account-id"] = account
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("https://%s%s" % (host, path), data=data, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise Err("auth")
        if e.code == 430 or e.code == 429:
            raise Err("rate limited by LibreView, try again later")
        raise Err("HTTP %d" % e.code)
    except (urllib.error.URLError, TimeoutError, OSError):
        raise Err("network")


def load_cache():
    try:
        with open(CACHE) as f:
            c = json.load(f)
        if c.get("expires", 0) > time.time() + 300:
            return c
    except Exception:
        pass
    return None


def save_cache(c):
    os.makedirs(os.path.dirname(CACHE), mode=0o700, exist_ok=True)
    fd = os.open(CACHE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(c, f)


def login(cfg):
    host = cfg.get("host") or "api.libreview.io"
    body = {"email": cfg["email"], "password": cfg["password"]}
    for _ in range(3):
        r = request(host, "/llu/auth/login", body)
        data = r.get("data") or {}
        if data.get("redirect") and data.get("region"):
            host = "api-%s.libreview.io" % data["region"]
            continue
        if r.get("status") == 2 or "authTicket" not in data:
            if (data.get("step") or {}).get("type"):
                raise Err("accept the new terms in the LibreLinkUp phone app")
            raise Err("login failed: check email/password in config.json")
        tok = data["authTicket"]["token"]
        uid = data["user"]["id"]
        c = {
            "host": host,
            "token": tok,
            "account": hashlib.sha256(uid.encode()).hexdigest(),
            "expires": data["authTicket"].get("expires", time.time() + 3600),
        }
        save_cache(c)
        return c
    raise Err("too many region redirects")


def parse_ts(s):
    # LibreView timestamps are "M/D/YYYY h:mm:ss AM" in UTC (FactoryTimestamp).
    try:
        return calendar.timegm(time.strptime(s, "%m/%d/%Y %I:%M:%S %p"))
    except Exception:
        return 0


def fetch(sess, cfg):
    unit = cfg.get("unit", "")
    h, t, a = sess["host"], sess["token"], sess["account"]
    conns = request(h, "/llu/connections", token=t, account=a).get("data") or []
    if not conns:
        raise Err("no LibreLinkUp connections: share from the Libre app first")
    want = cfg.get("patient")
    conn = next((c for c in conns if c["patientId"] == want), conns[0]) if want else conns[0]
    graph = request(h, "/llu/connections/%s/graph" % conn["patientId"], token=t, account=a)
    gd = (graph.get("data") or {})
    cur = gd.get("connection", conn).get("glucoseMeasurement") or conn.get("glucoseMeasurement")
    if not cur:
        raise Err("no reading yet")
    pts = []
    for p in gd.get("graphData") or []:
        pts.append({"t": parse_ts(p.get("FactoryTimestamp", "")), "mgdl": p.get("ValueInMgPerDl")})
    pts.append({"t": parse_ts(cur.get("FactoryTimestamp", "")), "mgdl": cur.get("ValueInMgPerDl")})
    pts = [p for p in pts if p["mgdl"]]
    tgt = gd.get("connection", conn)
    return {
        "ok": True,
        "unit": unit,
        "mgdl": cur.get("ValueInMgPerDl"),
        "trend": cur.get("TrendArrow", 3),
        "t": parse_ts(cur.get("FactoryTimestamp", "")),
        "isHigh": bool(cur.get("isHigh")),
        "isLow": bool(cur.get("isLow")),
        "targetLow": tgt.get("targetLow", 70),
        "targetHigh": tgt.get("targetHigh", 180),
        "history": pts,
        "fetched": int(time.time()),
    }


def save_config():
    email = os.environ.get("LLU_EMAIL", "").strip()
    password = os.environ.get("LLU_PASSWORD", "")
    if not email or not password:
        out({"ok": False, "setup": True, "error": "enter both email and password"})
    os.makedirs(os.path.dirname(CONFIG), mode=0o700, exist_ok=True)
    cfg = {}
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
    except Exception:
        pass
    cfg["email"], cfg["password"] = email, password
    fd = os.open(CONFIG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2)
    try:
        os.remove(CACHE)
    except FileNotFoundError:
        pass


def set_unit():
    unit = sys.argv[sys.argv.index("--unit") + 1] if len(sys.argv) > sys.argv.index("--unit") + 1 else ""
    if unit not in ("mgdl", "mmol"):
        out({"ok": False, "error": "unit must be mgdl or mmol"})
    cfg = {}
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
    except Exception:
        pass
    cfg["unit"] = unit
    os.makedirs(os.path.dirname(CONFIG), mode=0o700, exist_ok=True)
    fd = os.open(CONFIG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2)
    out({"ok": True, "saved": True})


def main():
    if "--unit" in sys.argv:
        set_unit()
    if "--save" in sys.argv:
        save_config()
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
        if not cfg.get("email") or not cfg.get("password"):
            raise KeyError
    except FileNotFoundError:
        out({"ok": False, "setup": True, "error": "Sign in with your LibreLinkUp follower account"})
    except Exception:
        out({"ok": False, "setup": True, "error": "Sign in with your LibreLinkUp follower account"})
    try:
        sess = load_cache() or login(cfg)
        try:
            out(fetch(sess, cfg))
        except Err as e:
            if str(e) != "auth":
                raise
            out(fetch(login(cfg), cfg))
    except Err as e:
        out({"ok": False, "setup": str(e).startswith("login failed"), "error": str(e)})
    except Exception as e:
        out({"ok": False, "error": "unexpected: %s" % type(e).__name__})


main()
