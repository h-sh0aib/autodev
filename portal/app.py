"""Public status/tickets and authenticated team controls; run behind HTTPS."""

from contextlib import asynccontextmanager
import hmac
import os
from pathlib import Path
import secrets
import threading
import time
from urllib.parse import urlsplit

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from starlette.middleware.trustedhost import TrustedHostMiddleware

from .bridge import Hermes, worker
from .store import Store, digest, password_hash, ROLES

STATIC = Path(__file__).parent / "static"
COOKIE = "autodev_session"


class Login(BaseModel):
    username: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=1, max_length=256)


class TicketInput(BaseModel):
    project: str = Field(min_length=1, max_length=80)
    title: str = Field(min_length=3, max_length=160)
    description: str = Field(min_length=10, max_length=12000)
    contact: str = Field(default="", max_length=254)
    website: str = Field(default="", max_length=200)  # honeypot


class Message(BaseModel):
    body: str = Field(min_length=1, max_length=12000)
    public: bool = False


class Brief(BaseModel):
    title: str = Field(min_length=3, max_length=160)
    body: str = Field(min_length=10, max_length=12000)
    request_id: str = Field(pattern=r"^[a-zA-Z0-9-]{16,80}$")


class Publication(BaseModel):
    public: bool
    summary: str = Field(max_length=2000)


def create_app(store=None, hermes=None, start_worker=True, origin=None):
    store = store or Store()
    hermes = hermes or Hermes()
    origin = (
        origin or os.environ.get("AUTODEV_PORTAL_ORIGIN", "http://127.0.0.1:8787")
    ).rstrip("/")
    parsed = urlsplit(origin)
    if (
        parsed.scheme not in ("http", "https")
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.path
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError(
            "AUTODEV_PORTAL_ORIGIN must be an origin such as https://team.example.com"
        )
    if parsed.scheme != "https" and parsed.hostname not in (
        "127.0.0.1",
        "localhost",
        "::1",
        "testserver",
    ):
        raise ValueError("Public portals require an HTTPS origin.")
    secure = parsed.scheme == "https"
    stop = threading.Event()
    control_lock = threading.Lock()

    @asynccontextmanager
    async def lifespan(_app):
        thread = None
        if start_worker:
            thread = threading.Thread(
                target=worker, args=(store, hermes, stop), daemon=True
            )
            thread.start()
        yield
        stop.set()

    app = FastAPI(
        title="AutoDev workspace",
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )
    app.add_middleware(
        TrustedHostMiddleware, allowed_hosts=[parsed.hostname, "127.0.0.1", "localhost"]
    )

    @app.middleware("http")
    async def boundary(request, call_next):
        if request.method in ("POST", "PUT", "PATCH", "DELETE"):
            # All browser mutations require an exact origin, including unauthenticated submissions and login.
            if request.headers.get("origin") != origin:
                return JSONResponse(
                    {"detail": "Reload this page from the configured portal address."},
                    status_code=403,
                )
            if (
                request.headers.get("content-type", "").split(";")[0]
                != "application/json"
            ):
                return JSONResponse({"detail": "JSON required."}, status_code=415)
            # Count streamed bytes as well as Content-Length (chunked bodies must not bypass the limit).
            chunks, size = [], 0
            async for chunk in request.stream():
                size += len(chunk)
                if size > 32768:
                    return JSONResponse(
                        {"detail": "Request is too large."}, status_code=413
                    )
                chunks.append(chunk)
            request._body = b"".join(chunks)
        response = await call_next(request)
        response.headers.update(
            {
                "X-Content-Type-Options": "nosniff",
                "Referrer-Policy": "no-referrer",
                "Cache-Control": "no-store",
                "X-Frame-Options": "DENY",
                "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
                "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
            }
        )
        if secure:
            response.headers["Strict-Transport-Security"] = "max-age=31536000"
        return response

    @app.exception_handler(ValueError)
    async def invalid(_request, exc):
        return JSONResponse({"detail": str(exc)}, status_code=400)

    def rate(request, name, count, seconds):
        # Uvicorn trusts proxy headers only from the local Caddy proxy. Never parse arbitrary X-Forwarded-For here.
        ip = request.client.host if request.client else "unknown"
        if not store.limit(name + ":" + digest(ip), count, seconds):
            raise HTTPException(
                429,
                "Too many attempts. Please try again later.",
                headers={"Retry-After": str(seconds)},
            )

    def identity(request, allowed=("owner", "support", "viewer"), mutation=False):
        token = request.cookies.get(COOKIE, "")
        with store.db() as db:
            row = db.execute(
                "SELECT s.*,u.role FROM sessions s JOIN users u ON u.username=s.username WHERE s.token=? AND s.expires>?",
                (digest(token), time.time()),
            ).fetchone()
        if not row:
            raise HTTPException(401, "Sign in to use the team workspace.")
        if row["role"] not in allowed:
            raise HTTPException(
                403, "Your account does not have access to this control."
            )
        if mutation and not hmac.compare_digest(
            row["csrf"].encode(), request.headers.get("x-csrf-token", "").encode()
        ):
            raise HTTPException(403, "Session verification failed. Reload the page.")
        return dict(row)

    def customer(request, ticket):
        rate(request, "ticket-access", 60, 60)
        token = request.headers.get("authorization", "").removeprefix("Bearer ")
        with store.db() as db:
            row = db.execute(
                "SELECT token FROM tickets WHERE id=?", (ticket,)
            ).fetchone()
        if not row or not hmac.compare_digest(row["token"], digest(token)):
            raise HTTPException(
                404, "Ticket not found. Use your private tracking link."
            )

    @app.get("/healthz")
    def health():
        with store.db() as db:
            db.execute("SELECT 1").fetchone()
        return {"status": "ok"}

    @app.get("/api/public/projects")
    def public_projects():
        return store.projects(public=True)

    @app.post("/api/public/tickets", status_code=201)
    def submit(request: Request, data: TicketInput):
        rate(request, "intake", 5, 3600)
        if not store.limit("intake-global", 100, 3600):
            raise HTTPException(
                429, "The support desk is busy. Please try again later."
            )
        if data.website or not data.title.strip() or not data.description.strip():
            raise HTTPException(400, "Please check your ticket details.")
        return store.create_ticket(
            data.project,
            data.title.strip(),
            data.description.strip(),
            data.contact.strip(),
        )

    @app.get("/api/public/tickets/{ticket}")
    def track(request: Request, ticket: str):
        customer(request, ticket)
        return store.ticket(ticket, public=True)

    @app.post("/api/public/tickets/{ticket}/reply")
    def customer_reply(request: Request, ticket: str, data: Message):
        customer(request, ticket)
        rate(request, "customer-reply", 10, 3600)
        store.ticket_action(ticket, "reply", data.body, "customer", public=True)
        return {"ok": True}

    @app.post("/api/public/tickets/{ticket}/reopen")
    def customer_reopen(request: Request, ticket: str, data: Message):
        customer(request, ticket)
        rate(request, "customer-reply", 10, 3600)
        store.ticket_action(ticket, "reopen", data.body, "customer", public=True)
        return {"ok": True}

    @app.post("/api/login")
    def login(request: Request, data: Login):
        rate(request, "login", 10, 900)
        if not store.limit("login-global", 100, 60):
            raise HTTPException(
                429, "Too many sign-in attempts. Please try again later."
            )
        with store.db() as db:
            row = db.execute(
                "SELECT * FROM users WHERE username=?", (data.username,)
            ).fetchone()
        hashed = row["password"] if row else "0" * 32 + ":" + "0" * 128
        try:
            matches = hmac.compare_digest(
                password_hash(data.password, hashed.split(":")[0]), hashed
            )
        except ValueError:
            matches = False
        if not row or not matches:
            raise HTTPException(401, "Username or password is incorrect.")
        token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        with store.db() as db:
            db.execute(
                "DELETE FROM sessions WHERE token=? OR expires<?",
                (digest(request.cookies.get(COOKIE, "")), time.time()),
            )
            db.execute(
                "INSERT INTO sessions VALUES(?,?,?,?)",
                (digest(token), row["username"], csrf, time.time() + 8 * 3600),
            )
            store.audit(db, row["username"], "signed in", "workspace")
        response = JSONResponse(
            {"username": row["username"], "role": row["role"], "csrf": csrf}
        )
        response.set_cookie(
            COOKIE,
            token,
            httponly=True,
            secure=secure,
            samesite="strict",
            max_age=8 * 3600,
            path="/",
        )
        return response

    @app.get("/api/me")
    def me(request: Request):
        user = identity(request)
        return {k: user[k] for k in ("username", "role", "csrf")}

    @app.post("/api/logout")
    def logout(request: Request):
        user = identity(request, mutation=True)
        with store.db() as db:
            db.execute("DELETE FROM sessions WHERE token=?", (user["token"],))
        response = JSONResponse({"ok": True})
        response.delete_cookie(
            COOKIE, path="/", secure=secure, httponly=True, samesite="strict"
        )
        return response

    @app.get("/api/workspace")
    def workspace(request: Request):
        user = identity(request)
        with store.db() as db:
            tickets = [
                dict(t)
                for t in db.execute(
                    "SELECT id,project,title,status,priority,created,updated FROM tickets ORDER BY updated DESC LIMIT 200"
                )
            ]
            queue = [
                dict(o)
                for o in db.execute(
                    "SELECT id,project,title,task_id,attempts,error FROM outbox WHERE task_id IS NULL ORDER BY created LIMIT 100"
                )
            ]
            audit = [
                dict(a)
                for a in db.execute(
                    "SELECT actor,action,target,created FROM audit ORDER BY id DESC LIMIT 30"
                )
            ]
            runtime = dict(db.execute("SELECT key,value FROM runtime").fetchall())
        return {
            "projects": store.projects(),
            "tickets": tickets,
            "queue": queue,
            "audit": audit,
            "gateway": runtime.get("gateway", "unknown")
            if time.time() - float(runtime.get("synced", "0")) < 180
            else "unknown",
            "synced": runtime.get("synced"),
            "roles": ROLES,
            "user": {k: user[k] for k in ("username", "role")},
        }

    @app.post("/api/projects/{project}/publish")
    def publish(request: Request, project: str, data: Publication):
        user = identity(request, ("owner",), mutation=True)
        with store.db() as db:
            if not db.execute(
                "SELECT 1 FROM projects WHERE slug=?", (project,)
            ).fetchone():
                raise HTTPException(404, "Project not found.")
            db.execute(
                "UPDATE projects SET public=?,summary=? WHERE slug=?",
                (int(data.public), data.summary.strip(), project),
            )
            store.audit(db, user["username"], "public visibility updated", project)
        return {"ok": True}

    @app.post("/api/projects/{project}/brief", status_code=202)
    def brief(request: Request, project: str, data: Brief):
        user = identity(request, ("owner",), mutation=True)
        rate(request, "brief", 20, 3600)
        with store.db() as db:
            if not db.execute(
                "SELECT 1 FROM projects WHERE slug=?", (project,)
            ).fetchone():
                raise HTTPException(404, "Project not found.")
            key = store.enqueue(
                db,
                project,
                "brief",
                data.title,
                "Owner request:\n"
                + data.body
                + "\n\nPlan and deliver this outcome through the department workflow. "
                "Define acceptance criteria, assign specialists, verify release gates, and report human blockers. Keep working until the outcome is verified.",
                "project-manager",
                key=f"brief:{project}:{data.request_id}",
            )
            store.audit(db, user["username"], "work requested", project)
        return {"id": key, "status": "queued"}

    @app.get("/api/tickets/{ticket}")
    def private_ticket(request: Request, ticket: str):
        identity(request)
        return store.ticket(ticket)

    @app.post("/api/tickets/{ticket}/{action}")
    def ticket_action(request: Request, ticket: str, action: str, data: Message):
        user = identity(request, ("owner", "support"), mutation=True)
        if action not in (
            "reply",
            "review",
            "escalate",
            "resolve",
            "reopen",
            "waiting",
        ):
            raise HTTPException(404, "Unknown action.")
        store.ticket_action(ticket, action, data.body, user["username"], data.public)
        return {"ok": True}

    @app.post("/api/team/{action}")
    def control(request: Request, action: str):
        user = identity(request, ("owner",), mutation=True)
        if action not in ("start", "stop"):
            raise HTTPException(404, "Unknown control.")
        if not control_lock.acquire(blocking=False):
            raise HTTPException(409, "Another team control is still running.")
        try:
            with store.db() as db:
                store.audit(
                    db,
                    user["username"],
                    "team " + action + " requested",
                    "all projects",
                )
            try:
                state = hermes.gateway(action)
            except Exception:
                with store.db() as db:
                    store.audit(
                        db,
                        user["username"],
                        "team " + action + " failed",
                        "all projects",
                    )
                raise HTTPException(
                    503, "The team control failed. Check server services, then retry."
                ) from None
            with store.db() as db:
                db.execute(
                    "INSERT OR REPLACE INTO runtime VALUES('gateway',?)", (state,)
                )
                store.audit(db, user["username"], "team " + state, "all projects")
            return {"state": state}
        finally:
            control_lock.release()

    app.mount("/static", StaticFiles(directory=STATIC), name="static")

    @app.get("/")
    @app.get("/team")
    @app.get("/ticket/{ticket}")
    def index(ticket: str = ""):
        return FileResponse(STATIC / "index.html")

    return app
