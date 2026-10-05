"""Real browser coverage. Run with AUTODEV_BROWSER_TESTS=1 after installing Chromium."""

import os
from pathlib import Path
import socket
import threading
import time

import pytest

from portal.app import create_app
from portal.bridge import sync_once
from portal.store import Store
from test_portal import FakeHermes


@pytest.mark.skipif(
    os.environ.get("AUTODEV_BROWSER_TESTS") != "1", reason="opt-in browser suite"
)
def test_public_customer_and_owner_workflows(tmp_path):
    import uvicorn
    from playwright.sync_api import sync_playwright, expect

    store = Store(tmp_path / "state")
    store.register("sample", "Atlas customer portal", str(tmp_path / "repo"))
    store.add_user("owner", "browser-test-password", "owner")
    with store.db() as db:
        db.execute(
            "UPDATE projects SET public=1, summary='We are improving checkout and account access.'"
        )
    hermes = FakeHermes()
    sync_once(store, hermes)
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    origin = f"http://127.0.0.1:{port}"
    server = uvicorn.Server(
        uvicorn.Config(
            create_app(store, hermes, start_worker=False, origin=origin),
            log_level="warning",
        )
    )
    thread = threading.Thread(
        target=server.run, kwargs={"sockets": [sock]}, daemon=True
    )
    thread.start()
    try:
        deadline = time.time() + 10
        while not server.started and time.time() < deadline:
            time.sleep(0.05)
        assert server.started
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": 1440, "height": 1000})
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.goto(origin)
            expect(
                page.get_by_role("heading", name="Good work. Visible progress.")
            ).to_be_visible()
            page.get_by_label("What do you need help with?").fill(
                '<img src=x onerror="alert(1)"> Checkout issue'
            )
            page.get_by_label("A little more detail").fill(
                "I cannot finish checkout on a small screen after entering my address."
            )
            page.get_by_label("Email (optional)").fill("customer@example.com")
            page.get_by_role("button", name="Send to support").click()
            expect(
                page.get_by_role("heading", name="Keep this private link")
            ).to_be_visible()
            ticket = page.url.split("/ticket/")[1].split("#")[0]
            store.ticket_action(
                ticket, "reply", "Confidential investigation note", "support-agent"
            )
            store.ticket_action(
                ticket,
                "reply",
                "We have received your report and are checking it.",
                "support-agent",
                True,
            )
            page.get_by_role("button", name="Check for updates").click()
            expect(
                page.get_by_text("We have received your report and are checking it.")
            ).to_be_visible()
            expect(page.get_by_text("Confidential investigation note")).to_have_count(0)
            page.get_by_label("Your message").fill("It also happens on my laptop.")
            page.get_by_role("button", name="Send reply").click()
            expect(
                page.get_by_text("It also happens on my laptop.", exact=True)
            ).to_be_visible()

            owner = browser.new_page(viewport={"width": 1440, "height": 1050})
            owner.on("pageerror", lambda error: errors.append(str(error)))
            owner.goto(origin + "/team")
            owner.get_by_label("Username", exact=True).fill("owner")
            owner.get_by_label("Password", exact=True).fill("browser-test-password")
            owner.get_by_role("button", name="Open workspace").click()
            expect(owner.get_by_role("heading", name="Your department")).to_be_visible()
            owner.get_by_role("button", name="Give the team a brief").click()
            owner.get_by_label("A short title").fill("Improve checkout on mobile")
            owner.get_by_label("What does a good result look like?").fill(
                "A customer can complete checkout on a phone and receive a confirmation."
            )
            owner.get_by_role("button", name="Send to project manager").click()
            expect(owner.get_by_role("dialog")).not_to_be_visible()
            sync_once(store, hermes)
            owner.get_by_role("button", name="Refresh workspace").click()
            owner.get_by_role("button", name="View project").click()
            expect(owner.get_by_text("Awaiting evidence", exact=True)).to_have_count(6)
            owner.get_by_label("Public update", exact=True).fill(
                "Checkout improvements are now in development."
            )
            owner.get_by_role("button", name="Save public update").click()
            expect(owner.get_by_role("dialog")).not_to_be_visible()
            owner.get_by_role("button", name="Support desk", exact=True).click()
            owner.get_by_role("button", name="Checkout issue", exact=False).click()
            expect(owner.get_by_text("Confidential investigation note")).to_be_visible()
            owner.get_by_label("Next step").select_option("escalate")
            owner.get_by_label("Message or handoff evidence").fill(
                "Confirmed on phone and laptop. Fix checkout with independent QA before release."
            )
            owner.get_by_role("button", name="Save next step").click()
            expect(owner.get_by_role("dialog")).not_to_be_visible()
            assert store.ticket(ticket)["status"] == "in_development"
            owner.get_by_role("button", name="Overview", exact=True).click()
            owner.on("dialog", lambda d: d.accept())
            owner.get_by_role("button", name="Pause scheduling").click()
            expect(
                owner.get_by_role("heading", name="The team is paused.")
            ).to_be_visible()
            owner.get_by_role("button", name="Start the team").click()
            expect(
                owner.get_by_role("heading", name="The team is moving.")
            ).to_be_visible()
            screenshot = Path(os.environ.get("AUTODEV_SCREENSHOT_DIR", str(tmp_path)))
            screenshot.mkdir(parents=True, exist_ok=True)
            owner.screenshot(
                path=str(screenshot / "workspace-desktop.png"), full_page=True
            )
            owner.set_viewport_size({"width": 390, "height": 844})
            assert owner.evaluate("document.documentElement.scrollWidth <= innerWidth")
            owner.screenshot(
                path=str(screenshot / "workspace-mobile.png"), full_page=True
            )
            page.goto(origin)
            expect(
                page.get_by_text("Checkout improvements are now in development.")
            ).to_be_visible()
            page.set_viewport_size({"width": 390, "height": 844})
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
            assert not errors, errors
            with store.db() as db:
                db.execute("DELETE FROM sessions")
            owner.get_by_role("button", name="Refresh workspace").click()
            expect(owner.get_by_role("heading", name="Welcome back.")).to_be_visible()
            browser.close()
    finally:
        server.should_exit = True
        thread.join(timeout=10)
        sock.close()
