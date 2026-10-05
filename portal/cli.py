"""Operator setup and a structured support interface for trusted local agents."""

import argparse
import getpass
import json
import os
from pathlib import Path
import re
import sqlite3
import sys

from .store import GATES, Store


def main():
    parser = argparse.ArgumentParser(
        description="AutoDev portal and support operations"
    )
    sub = parser.add_subparsers(dest="command", required=True)
    user = sub.add_parser(
        "user", help="Create/reset a team account; revokes existing sessions"
    )
    user.add_argument("username")
    user.add_argument("--role", choices=("owner", "support", "viewer"), default="owner")
    user.add_argument("--password-stdin", action="store_true")
    register = sub.add_parser("register")
    register.add_argument("--slug", required=True)
    register.add_argument("--name", required=True)
    register.add_argument("--repo", required=True)
    configure = sub.add_parser("configure")
    configure.add_argument("--domain", required=True)
    configure.add_argument("--port", type=int, default=8787)
    serve = sub.add_parser("serve")
    serve.add_argument("--port", type=int)
    serve.add_argument(
        "--local", action="store_true", help="Local HTTP preview on loopback"
    )
    sub.add_parser("sync")
    sub.add_parser("projects")
    backup = sub.add_parser("backup")
    backup.add_argument("destination")
    evidence = sub.add_parser("evidence")
    evidence.add_argument("--project", required=True)
    evidence.add_argument("--gate", choices=GATES, required=True)
    evidence.add_argument("--revision", required=True)
    evidence.add_argument("--status", choices=("passed", "failed"), required=True)
    evidence.add_argument("--reference", required=True)
    evidence.add_argument("--author", required=True)
    tickets = sub.add_parser("tickets")
    tickets.add_argument("--project")
    show = sub.add_parser("show")
    show.add_argument("ticket")
    for name in ("reply", "review", "escalate", "resolve", "waiting", "reopen"):
        action = sub.add_parser(name)
        action.add_argument("ticket")
        action.add_argument(
            "--body-file",
            required=True,
            help="UTF-8 message/evidence file; '-' reads stdin",
        )
        action.add_argument("--author", required=True)
        action.add_argument("--public", action="store_true")
    args = parser.parse_args()
    store = Store()
    if args.command == "user":
        password = (
            sys.stdin.readline().rstrip("\r\n")
            if args.password_stdin
            else getpass.getpass("Password (12+ characters): ")
        )
        if not args.password_stdin and password != getpass.getpass(
            "Confirm password: "
        ):
            raise ValueError("Passwords do not match.")
        store.add_user(args.username, password, args.role)
        print(f"Account {args.username} configured ({args.role}).")
    elif args.command == "register":
        store.register(args.slug, args.name, args.repo)
        print(
            f"Project {args.slug} registered privately. An owner can publish its status from the workspace."
        )
    elif args.command == "configure":
        domain = args.domain.lower()
        if len(domain) > 253 or not re.fullmatch(
            r"(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}",
            domain,
        ):
            raise ValueError(
                "Enter a DNS name such as team.example.com, without a URL path or scheme."
            )
        if not 1024 <= args.port <= 65535:
            raise ValueError("Choose an unprivileged port between 1024 and 65535.")
        config = store.root / "portal.json"
        temp = config.with_suffix(".tmp")
        temp.write_text(
            json.dumps({"origin": "https://" + domain, "port": args.port}) + "\n"
        )
        temp.chmod(0o600)
        temp.replace(config)
        caddy = store.root / "Caddyfile"
        caddy.write_text(
            f"{domain} {{\n    encode zstd gzip\n    request_body {{\n        max_size 32KB\n    }}\n    reverse_proxy 127.0.0.1:{args.port}\n}}\n"
        )
        caddy.chmod(0o600)
        print(f"Portal address: https://{domain}\nCaddy configuration: {caddy}")
    elif args.command == "serve":
        import uvicorn
        from .app import create_app

        config_path = store.root / "portal.json"
        config = json.loads(config_path.read_text()) if config_path.exists() else {}
        if not args.local and not config:
            raise ValueError(
                "Configure a domain first, or use serve --local for a local preview."
            )
        port = args.port or config.get("port", 8787)
        origin = f"http://127.0.0.1:{port}" if args.local else config["origin"]
        # Exactly one process owns the synchronization worker. Never expose this port on 0.0.0.0.
        uvicorn.run(
            create_app(store, origin=origin),
            host="127.0.0.1",
            port=port,
            proxy_headers=not args.local,
            forwarded_allow_ips="127.0.0.1",
            access_log=False,
            limit_concurrency=100,
            timeout_keep_alive=5,
        )
    elif args.command == "sync":
        from .bridge import Hermes, sync_once

        sync_once(store, Hermes())
        print(
            "Synchronization pass complete. See projects for freshness and delivery errors."
        )
    elif args.command == "projects":
        print(json.dumps(store.projects(), indent=2))
    elif args.command == "backup":
        target = Path(args.destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
        os.close(fd)
        with store.db() as source:
            destination = sqlite3.connect(target)
            try:
                source.backup(destination)
            finally:
                destination.close()
        print(f"Consistent portal snapshot saved: {target}")
    elif args.command == "evidence":
        store.evidence(
            args.project,
            args.gate,
            args.revision,
            args.status,
            args.reference,
            args.author,
        )
        print(
            "Evidence recorded. Readiness requires all six gates on the current commit."
        )
    elif args.command == "tickets":
        with store.db() as db:
            rows = db.execute(
                "SELECT id,project,title,status,priority,updated FROM tickets"
                + (" WHERE project=?" if args.project else "")
                + " ORDER BY updated DESC LIMIT 200",
                (args.project,) if args.project else (),
            ).fetchall()
            print(json.dumps([dict(r) for r in rows], indent=2))
    elif args.command == "show":
        print(json.dumps(store.ticket(args.ticket), indent=2))
    else:
        body = (
            sys.stdin.read(12001)
            if args.body_file == "-"
            else Path(args.body_file).read_text(encoding="utf-8")
        )
        store.ticket_action(args.ticket, args.command, body, args.author, args.public)
        print(f"Ticket {args.ticket}: {args.command} recorded.")


if __name__ == "__main__":
    os.umask(0o077)
    try:
        main()
    except (ValueError, OSError, sqlite3.Error) as exc:
        sys.exit(str(exc))
