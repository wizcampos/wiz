from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pymongo import MongoClient
from urllib.parse import urlparse
import datetime
import socket
import requests
import os

app = FastAPI()
templates = Jinja2Templates(directory="app/templates")

MONGO_URI = os.environ.get("MONGO_URI", "").strip()
mongo_client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=3000) if MONGO_URI else None
db = mongo_client["exposure_scanner"] if mongo_client is not None else None
scans = db["scans"] if db is not None else None

UA = {"User-Agent": "Mozilla/5.0 (compatible; PublicCloudExposureScanner/1.0)"}


def normalize_target(target: str) -> str:
    target = (target or "").strip()
    if not target:
        return ""
    if "://" not in target:
        target = "https://" + target
    return target


def get_host(target_url: str) -> str:
    p = urlparse(target_url)
    return p.hostname or ""


def tcp_check(host: str, port: int, timeout: float = 1.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except Exception:
        return False


def fetch_headers(url: str, timeout_head: float = 4.0, timeout_get: float = 7.0):
    """
    Attempt HEAD (fast) then fallback to GET (some servers block HEAD).
    Returns (ok: bool, info: dict)
    info: url, status_code, final_url, headers (subset), error (optional)
    """
    info = {"url": url}

    try:
        r = requests.head(url, allow_redirects=True, timeout=timeout_head, headers=UA)
        info["method"] = "HEAD"
    except Exception as e_head:

        try:
            r = requests.get(url, allow_redirects=True, timeout=timeout_get, headers=UA, stream=True)
            r.close()
            info["method"] = "GET"
        except Exception as e_get:
            info["error"] = f"HEAD failed: {e_head}; GET failed: {e_get}"
            return False, info

    info["status_code"] = r.status_code
    info["final_url"] = str(r.url)

    h = r.headers
    info["headers"] = {
        "strict-transport-security": h.get("Strict-Transport-Security", ""),
        "content-security-policy": h.get("Content-Security-Policy", ""),
        "x-content-type-options": h.get("X-Content-Type-Options", ""),
        "referrer-policy": h.get("Referrer-Policy", ""),
        "permissions-policy": h.get("Permissions-Policy", ""),
        "x-frame-options": h.get("X-Frame-Options", ""),
        "x-xss-protection": h.get("X-XSS-Protection", ""),
        "server": h.get("Server", ""),
        "x-powered-by": h.get("X-Powered-By", ""),
        "location": h.get("Location", ""),
    }

    return True, info


@app.get("/", response_class=HTMLResponse)
def home(request: Request):
    return templates.TemplateResponse("index.html", {"request": request, "result": None})


@app.get("/favicon.ico")
def favicon():
    return HTMLResponse(status_code=204)


@app.post("/scan", response_class=HTMLResponse)
def scan(request: Request, target: str = Form(...)):
    target_url = normalize_target(target)
    host = get_host(target_url)

    result = {
        "target": target,
        "normalized": target_url,
        "host": host,
        "timestamp_utc": datetime.datetime.utcnow().isoformat() + "Z",
        "checks": {},
        "raw_headers": {},
        "checklist": [],
        "summary": {"met": 0, "total": 0},
    }

    if not host:
        result["checks"]["error"] = "Invalid or empty target"
        result["checklist"] = [{
            "title": "Valid target provided",
            "met": False,
            "detail": "Enter a hostname like example.com or a full URL like https://example.com."
        }]
        result["summary"] = {"met": 0, "total": 1}
        return templates.TemplateResponse("index.html", {"request": request, "result": result})


    http_ok, http_info = fetch_headers(f"http://{host}", timeout_head=3.0, timeout_get=5.0)
    result["checks"]["http_reachable"] = http_ok
    result["checks"]["http_status"] = http_info.get("status_code")
    result["checks"]["http_final_url"] = http_info.get("final_url")
    if not http_ok:
        result["checks"]["http_error"] = http_info.get("error", "")
        result["checks"]["http_redirects_to_https"] = False
    else:
        final = (http_info.get("final_url") or "")
        result["checks"]["http_redirects_to_https"] = final.lower().startswith("https://")

    https_ok, https_info = fetch_headers(f"https://{host}", timeout_head=4.0, timeout_get=8.0)
    result["checks"]["https_reachable"] = https_ok
    result["checks"]["https_status"] = https_info.get("status_code")
    result["checks"]["https_final_url"] = https_info.get("final_url")
    if not https_ok:
        result["checks"]["https_error"] = https_info.get("error", "")
    else:
        result["raw_headers"] = https_info.get("headers", {}) or {}

    ssh_open = tcp_check(host, 22)
    result["checks"]["ssh_22_open"] = ssh_open

    checklist = []

    def add_item(title: str, met: bool, detail: str):
        checklist.append({"title": title, "met": bool(met), "detail": detail})

    add_item(
        "HTTPS reachable",
        https_ok,
        "The site responded over HTTPS (encrypted transport)."
        if https_ok else
        f"HTTPS request did not complete ({result['checks'].get('https_error', 'unknown error')})."
    )

    if http_ok:
        redirects = result["checks"].get("http_redirects_to_https") is True
        add_item(
            "HTTP is not usable without HTTPS",
            redirects,
            "HTTP redirects to HTTPS (prevents plaintext access)."
            if redirects else
            "HTTP is reachable but a redirect to HTTPS was not observed."
        )
    else:
        add_item(
            "HTTP is not usable without HTTPS",
            https_ok,
            "HTTP endpoint is not reachable (often intentionally disabled) and HTTPS is reachable."
            if https_ok else
            "HTTP endpoint is not reachable, and HTTPS could not be confirmed."
        )

    hdrs = result.get("raw_headers") or {}

    if not https_ok:
        add_item("HSTS enabled", False, "Unknown (HTTPS not reachable from scanner).")
        add_item("Content Security Policy present", False, "Unknown (HTTPS not reachable from scanner).")
        add_item("X-Content-Type-Options set to nosniff", False, "Unknown (HTTPS not reachable from scanner).")
        add_item("Referrer-Policy present", False, "Unknown (HTTPS not reachable from scanner).")
    else:
        hsts_val = (hdrs.get("strict-transport-security") or "").strip()
        add_item(
            "HSTS enabled",
            bool(hsts_val),
            f"Strict-Transport-Security present ({hsts_val})."
            if hsts_val else
            "Strict-Transport-Security not observed."
        )

        csp_val = (hdrs.get("content-security-policy") or "").strip()
        add_item(
            "Content Security Policy present",
            bool(csp_val),
            "Content-Security-Policy present (helps mitigate XSS/injection)."
            if csp_val else
            "Content-Security-Policy not observed."
        )

        xcto_val = (hdrs.get("x-content-type-options") or "").strip()
        xcto_ok = ("nosniff" in xcto_val.lower())
        add_item(
            "X-Content-Type-Options set to nosniff",
            xcto_ok,
            f"X-Content-Type-Options: {xcto_val}"
            if xcto_val else
            "X-Content-Type-Options not observed."
        )

        rp_val = (hdrs.get("referrer-policy") or "").strip()
        add_item(
            "Referrer-Policy present",
            bool(rp_val),
            f"Referrer-Policy: {rp_val}"
            if rp_val else
            "Referrer-Policy not observed."
        )

    add_item(
        "SSH (port 22) not publicly exposed",
        not ssh_open,
        "Port 22 did not respond (good)."
        if not ssh_open else
        "Port 22 responded (consider restricting SSH to internal/VPN/bastion)."
    )

    result["checklist"] = checklist
    result["summary"] = {
        "met": sum(1 for c in checklist if c["met"]),
        "total": len(checklist),
    }

    if scans is not None:
        try:
            scans.insert_one(dict(result))
        except Exception:
            pass

    result.pop("_id", None)
    return templates.TemplateResponse("index.html", {"request": request, "result": result})


@app.get("/history", response_class=HTMLResponse)
def history(request: Request):
    items = []
    if scans is not None:
        try:
            items = list(scans.find({}, {"_id": 0}).sort("timestamp_utc", -1).limit(25))
        except Exception:
            items = []
    return templates.TemplateResponse("history.html", {"request": request, "items": items})