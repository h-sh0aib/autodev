import json
import os
import sqlite3
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from portal.app import create_app
from portal.bridge import Hermes, sync_once
from portal.store import GATES, Store


class FakeHermes:
    def __init__(self):
        self.items = {}
        self.fail = False
        self.lose_ack = False
        self.rev = "a" * 40
        self.state = "running"
        self.dirty = False

    def create(self, project, item):
        if self.fail:
            raise RuntimeError("offline")
        self.items.setdefault(
            item["id"],
            {
                "id": "t_" + str(len(self.items) + 1),
                "title": item["title"],
                "status": "ready",
                "assignee": item["assignee"],
                "project": project["slug"],
            },
        )
        if self.lose_ack:
            raise RuntimeError("remote committed but caller lost the response")
        return self.items[item["id"]]["id"]

    def tasks(self, project):
        if self.fail:
            raise RuntimeError("offline")
        return [t for t in self.items.values() if t["project"] == project["slug"]]

    def revision(self, project):
        return self.rev

    def clean(self, project):
        return not self.dirty

    def gateway(self, action):
        if self.fail:
            raise RuntimeError("offline")
        if action != "status":
            self.state = "running" if action == "start" else "stopped"
        return self.state


@pytest.fixture
def env(tmp_path):
    store = Store(tmp_path / "state")
    store.register("sample", "Sample product", "/private/repo")
    store.register("secret", "Secret project", "/private/secret")
    store.add_user("owner", "correct-password-test", "owner")
    store.add_user("helper", "support-password-test", "support")
    store.add_user("reader", "viewer-password-test", "viewer")
    with store.db() as db:
        db.execute(
            "UPDATE projects SET public=1,summary='Customer update' WHERE slug='sample'"
        )
    hermes = FakeHermes()
    app = create_app(
        store, hermes, start_worker=False, origin="https://team.example.com"
    )
    with TestClient(
        app,
        base_url="https://team.example.com",
        headers={"origin": "https://team.example.com"},
    ) as client:
        yield store, hermes, client


def login(client, username="owner", password="correct-password-test"):
    response = client.post(
        "/api/login", json={"username": username, "password": password}
    )
    assert response.status_code == 200, response.text
    client.headers["x-csrf-token"] = response.json()["csrf"]
    return response


def new_ticket(client, **changes):
    data = {
        "project": "sample",
        "title": "Cannot finish checkout",
        "description": "The checkout page stops after I enter my address.",
        "contact": "private@example.com",
    }
    data.update(changes)
    return client.post("/api/public/tickets", json=data)


def retry_now(store):
    with store.db() as db:
        db.execute("UPDATE outbox SET retry_at=0")


def test_public_projection_never_exposes_private_state(env):
    store, hermes, client = env
    store.evidence(
        "sample", "tests", hermes.rev, "passed", "private QA report", "tester"
    )
    with store.db() as db:
        db.execute(
            "UPDATE projects SET tasks=? WHERE slug='sample'",
            (
                json.dumps(
                    [{"id": "t_1", "title": "Secret customer bug", "status": "blocked"}]
                ),
            ),
        )
    result = client.get("/api/public/projects")
    assert result.status_code == 200
    assert len(result.json()) == 1
    assert set(result.json()[0]) == {
        "slug",
        "name",
        "summary",
        "ready",
        "fresh",
        "synced",
    }
    assert "private" not in result.text and "Secret" not in result.text
    assert client.get("/api/workspace").status_code == 401
    assert new_ticket(client, project="secret").status_code == 400


def test_cookie_csrf_logout_and_password_reset(env):
    store, _, client = env
    response = login(client)
    cookie = response.headers["set-cookie"]
    assert all(flag in cookie for flag in ("HttpOnly", "Secure", "SameSite=strict"))
    client.headers.pop("x-csrf-token")
    assert client.post("/api/team/stop", json={}).status_code == 403
    client.headers["x-csrf-token"] = response.json()["csrf"]
    assert client.post("/api/team/stop", json={}).status_code == 200
    store.add_user("owner", "new-password-is-long", "owner")
    assert client.get("/api/me").status_code == 401
    login(client, password="new-password-is-long")
    assert client.post("/api/logout", json={}).status_code == 200
    assert client.get("/api/me").status_code == 401


def test_rejects_cross_origin_dns_rebinding_and_oversize(env):
    _, _, client = env
    assert (
        client.post(
            "/api/login",
            headers={"origin": "https://attacker.example"},
            json={"username": "owner", "password": "correct-password-test"},
        ).status_code
        == 403
    )
    assert (
        client.get(
            "/api/public/projects", headers={"host": "attacker.example"}
        ).status_code
        == 400
    )
    assert (
        client.post(
            "/api/public/tickets",
            content=b"x" * 33000,
            headers={"content-type": "application/json"},
        ).status_code
        == 413
    )
    assert (
        client.post(
            "/api/public/tickets", content="x", headers={"content-type": "text/plain"}
        ).status_code
        == 415
    )
    with pytest.raises(ValueError, match="HTTPS"):
        create_app(env[0], origin="http://public.example.com", start_worker=False)


@pytest.mark.parametrize(
    "username,password",
    [("helper", "support-password-test"), ("reader", "viewer-password-test")],
)
def test_roles_cannot_control_agents_or_publish(env, username, password):
    _, _, client = env
    login(client, username, password)
    assert client.get("/api/workspace").status_code == 200
    assert client.post("/api/team/stop", json={}).status_code == 403
    assert (
        client.post(
            "/api/projects/sample/publish", json={"public": True, "summary": "unsafe"}
        ).status_code
        == 403
    )
    assert (
        client.post(
            "/api/projects/sample/brief",
            json={
                "title": "Do work",
                "body": "Some new work please",
                "request_id": "1234567890123456",
            },
        ).status_code
        == 403
    )
    ticket = new_ticket(client).json()
    response = client.post(
        f"/api/tickets/{ticket['id']}/reply",
        json={"body": "We are investigating", "public": True},
    )
    assert response.status_code == (200 if username == "helper" else 403)


def test_ticket_capability_private_notes_and_durable_storage(env):
    store, _, client = env
    ticket = new_ticket(client).json()
    url = "/api/public/tickets/" + ticket["id"]
    assert client.get(url).status_code == 404
    assert client.get(url, headers={"authorization": "Bearer wrong"}).status_code == 404
    store.ticket_action(
        ticket["id"], "reply", "private internal finding", "support-manager"
    )
    store.ticket_action(
        ticket["id"],
        "reply",
        "We are investigating your report.",
        "support-agent",
        True,
    )
    response = client.get(url, headers={"authorization": "Bearer " + ticket["token"]})
    assert response.status_code == 200
    assert (
        "private internal" not in response.text
        and "private@example" not in response.text
    )
    assert "Support team" in response.text
    assert "token" not in response.json()
    restored = Store(store.root)
    assert restored.ticket(ticket["id"])["contact"] == "private@example.com"
    assert ticket["token"] not in store.path.read_bytes().decode(errors="ignore")
    assert store.path.stat().st_mode & 0o777 == 0o600


def test_full_support_to_development_to_resolution_journey(env):
    store, hermes, client = env
    ticket = new_ticket(client).json()
    key = ticket["id"]
    sync_once(store, hermes)
    assert store.ticket(key)["triage_task"]
    assert list(hermes.items.values())[0]["assignee"] == "support-agent"
    store.ticket_action(
        key, "review", "Reproduction and impact documented.", "support-agent"
    )
    sync_once(store, hermes)
    assert any(t["assignee"] == "support-manager" for t in hermes.items.values())
    store.ticket_action(
        key,
        "escalate",
        "Verified bug; expected checkout to complete.",
        "support-manager",
    )
    store.ticket_action(key, "escalate", "Retry the same handoff.", "support-manager")
    sync_once(store, hermes)
    with store.db() as db:
        assert (
            db.execute(
                "SELECT count(*) FROM outbox WHERE kind='development'"
            ).fetchone()[0]
            == 1
        )
    dev_id = store.ticket(key)["development_task"]
    assert dev_id
    with pytest.raises(ValueError, match="Development must finish"):
        store.ticket_action(key, "resolve", "It seems fixed", "support-manager")
    for t in hermes.items.values():
        if t["id"] == dev_id:
            t["status"] = "done"
    sync_once(store, hermes)
    sync_once(store, hermes)
    assert store.ticket(key)["status"] == "verifying"
    with store.db() as db:
        assert (
            db.execute(
                "SELECT count(*) FROM outbox WHERE kind='verification'"
            ).fetchone()[0]
            == 1
        )
    store.ticket_action(
        key,
        "resolve",
        "Verified checkout on the delivered release and QA report.",
        "support-manager",
    )
    assert store.ticket(key)["status"] == "resolved"
    assert store.ticket(key, public=True)["messages"][-1]["public"] == 1
    response = client.post(
        f"/api/public/tickets/{key}/reopen",
        headers={"authorization": "Bearer " + ticket["token"]},
        json={"body": "This is happening again."},
    )
    assert response.status_code == 200
    store.ticket_action(key, "escalate", "Regression confirmed", "support-manager")
    sync_once(store, hermes)
    assert store.ticket(key)["development_task"] != dev_id


def test_failed_verification_creates_new_development_work(env):
    store, hermes, client = env
    key = new_ticket(client).json()["id"]
    store.ticket_action(key, "escalate", "Bug confirmed", "support-manager")
    sync_once(store, hermes)
    original = store.ticket(key)["development_task"]
    for item in hermes.items.values():
        if item["id"] == original:
            item["status"] = "done"
    sync_once(store, hermes)
    store.ticket_action(
        key, "escalate", "Retest failed. Reproduction attached.", "support-manager"
    )
    sync_once(store, hermes)
    assert store.ticket(key)["development_task"] != original
    assert store.ticket(key)["status"] == "in_development"


def test_outage_and_lost_ack_retry_without_duplicates(env):
    store, hermes, client = env
    key = new_ticket(client).json()["id"]
    hermes.fail = True
    sync_once(store, hermes)
    assert store.ticket(key)["triage_task"] is None
    with store.db() as db:
        assert db.execute("SELECT attempts FROM outbox").fetchone()[0] == 1
    hermes.fail = False
    hermes.lose_ack = True
    retry_now(store)
    sync_once(store, hermes)
    assert len(hermes.items) == 1
    hermes.lose_ack = False
    retry_now(store)
    sync_once(Store(store.root), hermes)
    assert store.ticket(key)["triage_task"]
    assert len(hermes.items) == 1


def test_concurrent_ticket_escalation_is_idempotent(env):
    store, hermes, client = env
    key = new_ticket(client).json()["id"]
    with ThreadPoolExecutor(max_workers=6) as pool:
        list(
            pool.map(
                lambda _: store.ticket_action(
                    key, "escalate", "Bug evidence", "support-manager"
                ),
                range(6),
            )
        )
    sync_once(store, hermes)
    assert (
        len([t for t in hermes.items.values() if t["assignee"] == "project-manager"])
        == 1
    )


def test_readiness_requires_all_current_commit_gates_and_fresh_sync(env):
    store, hermes, _ = env
    sync_once(store, hermes)
    for gate in GATES[:-1]:
        store.evidence(
            "sample", gate, hermes.rev, "passed", "Report evidence", "tester"
        )
    assert not next(p for p in store.projects() if p["slug"] == "sample")["ready"]
    store.evidence(
        "sample",
        GATES[-1],
        hermes.rev,
        "passed",
        "Verified staging deployment, rollback, monitoring and recovery",
        "project-manager",
    )
    assert next(p for p in store.projects() if p["slug"] == "sample")["ready"]
    hermes.dirty = True
    sync_once(store, hermes)
    assert not next(p for p in store.projects() if p["slug"] == "sample")["ready"]
    hermes.dirty = False
    hermes.rev = "b" * 40
    sync_once(store, hermes)
    project = next(p for p in store.projects() if p["slug"] == "sample")
    assert not project["ready"] and all(
        g["status"] == "stale" for g in project["gates"]
    )
    for gate in GATES:
        store.evidence(
            "sample", gate, hermes.rev, "passed", "New report evidence", "tester"
        )
    with store.db() as db:
        db.execute("UPDATE projects SET synced=?", (time.time() - 181,))
    assert not next(p for p in store.projects() if p["slug"] == "sample")["ready"]
    sync_once(store, hermes)
    store.evidence(
        "sample",
        "security",
        hermes.rev,
        "failed",
        "Unresolved finding",
        "security-tester",
    )
    assert not next(p for p in store.projects() if p["slug"] == "sample")["ready"]


def test_customer_reply_wakes_support_but_keeps_development_state(env):
    store, _, client = env
    ticket = new_ticket(client).json()
    store.ticket_action(
        ticket["id"], "waiting", "Which browser did you use?", "support-agent"
    )
    headers = {"authorization": "Bearer " + ticket["token"]}
    assert (
        client.post(
            f"/api/public/tickets/{ticket['id']}/reply",
            headers=headers,
            json={"body": "Safari"},
        ).status_code
        == 200
    )
    assert store.ticket(ticket["id"])["status"] == "triaged"
    store.ticket_action(ticket["id"], "escalate", "Repro confirmed", "support-manager")
    client.post(
        f"/api/public/tickets/{ticket['id']}/reply",
        headers=headers,
        json={"body": "Also Chrome"},
    )
    assert store.ticket(ticket["id"])["status"] == "in_development"


def test_login_and_intake_rate_limits_are_durable(env):
    _, _, client = env
    for _ in range(10):
        assert (
            client.post(
                "/api/login",
                json={"username": "owner", "password": "incorrect-pass-test"},
            ).status_code
            == 401
        )
    assert (
        client.post(
            "/api/login",
            json={"username": "owner", "password": "correct-password-test"},
        ).status_code
        == 429
    )
    for _ in range(5):
        assert new_ticket(client).status_code == 201
    assert new_ticket(client).status_code == 429


def test_brief_idempotency_publication_and_gateway_audit(env):
    store, hermes, client = env
    login(client)
    payload = {
        "title": "Improve signup",
        "body": "Make signup work on a small screen.",
        "request_id": "a-stable-request-12345",
    }
    first = client.post("/api/projects/sample/brief", json=payload)
    assert first.status_code == 202
    assert (
        client.post("/api/projects/sample/brief", json=payload).json()["id"]
        == first.json()["id"]
    )
    sync_once(store, hermes)
    assert len(hermes.items) == 1
    assert (
        client.post(
            "/api/projects/secret/publish",
            json={"public": True, "summary": "Now shared"},
        ).status_code
        == 200
    )
    assert len(client.get("/api/public/projects").json()) == 2
    assert client.post("/api/team/arbitrary-command", json={}).status_code == 404
    hermes.fail = True
    assert client.post("/api/team/stop", json={}).status_code == 503
    assert any(
        a["action"] == "team stop failed"
        for a in client.get("/api/workspace").json()["audit"]
    )


def test_hermes_adapter_real_subprocess_argv(tmp_path, monkeypatch):
    log = tmp_path / "argv.json"
    script = tmp_path / "hermes"
    script.write_text(
        f"#!{sys.executable}\nimport json,sys\nfrom pathlib import Path\nPath({str(log)!r}).write_text(json.dumps(sys.argv[1:]))\nprint(json.dumps({{'id':'t_abc123'}}))\n"
    )
    script.chmod(0o755)
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    payload = {
        "id": "stable-1",
        "title": "--evil-title $(touch /tmp/no)",
        "body": "literal `whoami` text",
        "assignee": "support-agent",
    }
    assert (
        Hermes().create({"slug": "sample", "repo": "/repo with spaces"}, payload)
        == "t_abc123"
    )
    args = json.loads(log.read_text())
    assert args[-2:] == ["--", payload["title"]]
    assert args[args.index("--body") + 1] == payload["body"]
    assert args[args.index("--workspace") + 1] == "scratch"


def test_cli_account_backup_and_restore(env, tmp_path):
    store, _, client = env
    ticket = new_ticket(client).json()
    destination = tmp_path / "snapshot.sqlite"
    environment = dict(os.environ, HERMES_AUTODEV_STATE_DIR=str(store.root))
    result = subprocess.run(
        [sys.executable, "-m", "portal.cli", "backup", str(destination)],
        env=environment,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    with sqlite3.connect(destination) as db:
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert db.execute("SELECT id FROM tickets").fetchone()[0] == ticket["id"]
    assert destination.stat().st_mode & 0o777 == 0o600
    result = subprocess.run(
        [sys.executable, "-m", "portal.cli", "user", "new-owner", "--password-stdin"],
        input="long-account-password\n",
        env=environment,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "long-account-password" not in result.stdout + result.stderr
    login(client, "new-owner", "long-account-password")


def test_security_headers_and_static_frontend(env):
    _, _, client = env
    response = client.get("/")
    assert response.status_code == 200
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
    assert response.headers["referrer-policy"] == "no-referrer"
    assert response.headers["strict-transport-security"] == "max-age=31536000"
    assert client.get("/static/app.js").status_code == 200
    assert client.get("/docs").status_code == 404
