"""Small allowlisted Hermes CLI adapter and restart-safe delivery worker."""

import fcntl
import json
import logging
from pathlib import Path
import subprocess
import time

from .store import ROLES

log = logging.getLogger(__name__)
PACKAGE = Path(__file__).resolve().parent.parent


class Hermes:
    @staticmethod
    def run(args, timeout=45):
        # argv only: no shell and no customer-controlled executable/flags.
        result = subprocess.run(
            args, text=True, capture_output=True, timeout=timeout, check=False
        )
        if result.returncode:
            # Raw Hermes output can contain credentials or customer content; never send it to the browser.
            raise RuntimeError(
                "Hermes command failed. Check the gateway and profile configuration on the server."
            )
        return result.stdout

    def tasks(self, project):
        data = json.loads(
            self.run(
                [
                    "hermes",
                    "-p",
                    "project-manager",
                    "kanban",
                    "--board",
                    project["slug"],
                    "list",
                    "--json",
                ]
            )
        )
        if not isinstance(data, list) or any(
            not isinstance(t, dict) or "id" not in t or "status" not in t for t in data
        ):
            raise RuntimeError(
                "Unsupported Hermes task response. Update Hermes and check the board."
            )
        return [
            {key: t.get(key) for key in ("id", "title", "status", "assignee")}
            for t in data
        ]

    def create(self, project, item):
        if item["assignee"] not in ROLES:
            raise ValueError("Unknown team role.")
        data = json.loads(
            self.run(
                [
                    "hermes",
                    "-p",
                    "project-manager",
                    "kanban",
                    "--board",
                    project["slug"],
                    "create",
                    "--assignee",
                    item["assignee"],
                    "--workspace",
                    "scratch"
                    if item["assignee"].startswith("support-")
                    else "dir:" + project["repo"],
                    "--idempotency-key",
                    "portal:" + item["id"],
                    "--body",
                    item["body"],
                    "--json",
                    "--",
                    item["title"],
                ]
            )
        )
        if not isinstance(data, dict) or not isinstance(data.get("id"), str):
            raise RuntimeError(
                "Hermes did not return a task ID. Delivery will retry with the same idempotency key."
            )
        return data["id"]

    def gateway(self, action):
        if action not in ("start", "stop", "status"):
            raise ValueError("Unknown team control.")
        args = ["bash", str(PACKAGE / "scripts/gateway.sh"), action]
        if action == "status":
            result = subprocess.run(
                args, text=True, capture_output=True, timeout=15, check=False
            )
            return "running" if result.returncode == 0 else "stopped"
        self.run(args, timeout=90)
        return self.gateway("status")

    def revision(self, project):
        return self.run(
            ["git", "-C", project["repo"], "rev-parse", "HEAD"], timeout=10
        ).strip()

    def clean(self, project):
        return not self.run(
            ["git", "-C", project["repo"], "status", "--porcelain"], timeout=10
        ).strip()


def sync_once(store, hermes):
    # flock is released on process death. One worker can safely run even if a CLI sync overlaps it.
    with (store.root / "portal-sync.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        with store.db() as db:
            projects = [dict(p) for p in db.execute("SELECT * FROM projects")]
        for project in projects:
            with store.db() as db:
                pending = [
                    dict(o)
                    for o in db.execute(
                        "SELECT * FROM outbox WHERE project=? AND task_id IS NULL AND retry_at<=? ORDER BY created LIMIT 20",
                        (project["slug"], time.time()),
                    )
                ]
            for item in pending:
                try:
                    task_id = hermes.create(project, item)
                    with store.db() as db:
                        db.execute(
                            "UPDATE outbox SET task_id=?,error=NULL WHERE id=?",
                            (task_id, item["id"]),
                        )
                        if item["kind"] in ("triage", "development"):
                            column = (
                                "triage_task"
                                if item["kind"] == "triage"
                                else "development_task"
                            )
                            db.execute(
                                f"UPDATE tickets SET {column}=?,updated=? WHERE id=?",
                                (task_id, time.time(), item["ticket"]),
                            )
                except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired):
                    with store.db() as db:
                        db.execute(
                            "UPDATE outbox SET attempts=attempts+1,retry_at=?,error=? WHERE id=?",
                            (
                                time.time()
                                + min(900, 15 * 2 ** min(item["attempts"], 6)),
                                "Delivery is waiting for Hermes. Retrying automatically.",
                                item["id"],
                            ),
                        )
            try:
                tasks = hermes.tasks(project)
                revision = hermes.revision(project)
                clean = hermes.clean(project)
                by_id = {t["id"]: t for t in tasks}
                with store.db() as db:
                    db.execute(
                        "UPDATE projects SET tasks=?,revision=?,clean=?,synced=?,error=NULL WHERE slug=?",
                        (
                            json.dumps(tasks),
                            revision,
                            int(clean),
                            time.time(),
                            project["slug"],
                        ),
                    )
                    tickets = db.execute(
                        "SELECT * FROM tickets WHERE project=? AND status='in_development' AND development_task IS NOT NULL",
                        (project["slug"],),
                    ).fetchall()
                    for ticket in tickets:
                        if (
                            by_id.get(ticket["development_task"], {}).get("status")
                            == "done"
                        ):
                            store.enqueue(
                                db,
                                project["slug"],
                                "verification",
                                f"Verify resolution of {ticket['id']}",
                                f"Development reports {ticket['development_task']} complete. Read hermes-autodev support show {ticket['id']}. "
                                "Independently check the delivered fix against the customer's reproduction and QA evidence. "
                                "Resolve only with a customer-facing explanation and evidence; otherwise escalate the failed verification to PM.",
                                "support-manager",
                                ticket["id"],
                                f"ticket:{ticket['id']}:verify:{ticket['development_task']}",
                            )
                            db.execute(
                                "UPDATE tickets SET status='verifying',updated=? WHERE id=?",
                                (time.time(), ticket["id"]),
                            )
                            store.audit(
                                db,
                                "bridge",
                                "development complete; support verification queued",
                                ticket["id"],
                            )
            except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired):
                with store.db() as db:
                    db.execute(
                        "UPDATE projects SET error=? WHERE slug=?",
                        (
                            "Cannot refresh from Hermes. Check the installation and board.",
                            project["slug"],
                        ),
                    )
        try:
            gateway = hermes.gateway("status")
        except (OSError, RuntimeError, subprocess.TimeoutExpired):
            gateway = "unknown"
        with store.db() as db:
            db.execute("INSERT OR REPLACE INTO runtime VALUES('gateway',?)", (gateway,))
            db.execute(
                "INSERT OR REPLACE INTO runtime VALUES('synced',?)", (str(time.time()),)
            )
            db.execute("DELETE FROM sessions WHERE expires<?", (time.time(),))


def worker(store, hermes, stop):
    while not stop.is_set():
        try:
            sync_once(store, hermes)
        except Exception:
            log.exception("Portal synchronization failed; will retry")
        stop.wait(30)
