"use strict";
const app = document.querySelector("#app");
const dialog = document.querySelector("#dialog");
let me = null,
  workspace = null,
  currentView = "overview",
  noticeTimer;
const esc = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const labels = {
  new: "Received",
  triaged: "With support",
  waiting_for_customer: "Waiting for your reply",
  in_development: "With development",
  verifying: "Checking the fix",
  resolved: "Resolved",
  running: "Working",
  ready: "Queued",
  todo: "Planned",
  triage: "Being scoped",
  blocked: "Needs attention",
  review: "In review",
  done: "Complete",
  archived: "Archived",
  stopped: "Paused",
  unknown: "Checking",
  missing: "Awaiting evidence",
  stale: "Recheck needed",
  passed: "Passed",
  failed: "Needs work",
};
const names = {
  "project-manager": "Project manager",
  "frontend-designer": "Frontend designer",
  developer: "Developer",
  tester: "Quality assurance",
  "security-tester": "Security tester",
  "support-agent": "Support specialist",
  "support-manager": "Support manager",
};
const desc = {
  "project-manager": "Planning & delivery",
  "frontend-designer": "Design & experience",
  developer: "Implementation with Codex",
  tester: "Real customer workflows",
  "security-tester": "Security & release checks",
  "support-agent": "Customer questions & triage",
  "support-manager": "Escalations & resolution",
};
const date = (value) =>
  value
    ? new Date(Number(value) * 1000).toLocaleString([], {
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      })
    : "Not synced yet";
const pill = (value) =>
  `<span class="pill ${["done", "resolved", "passed"].includes(value) ? "good" : ["blocked", "failed"].includes(value) ? "bad" : ["waiting_for_customer", "review", "stale"].includes(value) ? "warn" : ""}"><span class="dot"></span>${esc(labels[value] || value)}</span>`;
const brand = `<a class="brand" href="/"><span class="brand-mark" aria-hidden="true">✳</span> autodev <span>WORKSPACE</span></a>`;
function notify(message) {
  const el = document.querySelector("#notice");
  el.textContent = message;
  el.classList.add("visible");
  clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => el.classList.remove("visible"), 6000);
}
async function api(path, body, opts = {}) {
  const headers = {
    ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
    ...(me ? { "X-CSRF-Token": me.csrf } : {}),
    ...opts.headers,
  };
  const response = await fetch(path, {
    method: body !== undefined ? "POST" : "GET",
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
    credentials: "same-origin",
  });
  const data = await response.json();
  if (!response.ok) {
    if (
      response.status === 401 &&
      path !== "/api/login" &&
      path !== "/api/me" &&
      location.pathname === "/team"
    ) {
      me = null;
      if (dialog.open) dialog.close();
      await loginPage();
    }
    throw new Error(
      typeof data.detail === "string"
        ? data.detail
        : "Please check the form and try again.",
    );
  }
  return data;
}
function bindForm(id, handler) {
  document.getElementById(id)?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.currentTarget,
      button = form.querySelector("button[type=submit]");
    const error = form.querySelector(".form-error");
    if (error) error.textContent = "";
    if (button) button.disabled = true;
    try {
      await handler(Object.fromEntries(new FormData(form)), form);
    } catch (err) {
      if (error) error.textContent = err.message;
      else notify(err.message);
    } finally {
      if (button) button.disabled = false;
    }
  });
}
function modal(title, content) {
  dialog.innerHTML = `<button class="close" aria-label="Close dialog">×</button><h2 id="dialog-title">${esc(title)}</h2>${content}`;
  dialog.querySelector(".close").onclick = () => dialog.close();
  dialog.showModal();
}
const errorBox = '<p class="form-error" role="alert"></p>';
function publicHeader() {
  return `<header class="public-header row between">${brand}<a class="btn quiet" href="/team">Team sign in ↗</a></header>`;
}
async function publicPage() {
  const projects = await api("/api/public/projects");
  app.innerHTML = `${publicHeader()}<main id="main" class="public-main"><div class="public-hero"><div class="eyebrow">Your project. A team behind it.</div><h1>Good work.<br>Visible progress.</h1><p>See what’s moving forward and reach the people working on it. From your first question to a verified fix, we keep the conversation connected.</p></div><div class="public-grid"><section><div class="section-heading"><h2>Project updates</h2><span class="small">${projects.length} shared ${projects.length === 1 ? "project" : "projects"}</span></div><div class="projects">${projects.map((p) => `<article class="card project"><div class="row between"><div class="row"><div class="project-icon">${esc(p.name[0].toUpperCase())}</div><h3>${esc(p.name)}</h3></div>${pill(!p.fresh ? "Awaiting update" : p.ready ? "Release checks passed" : "In progress")}</div><p>${esc(p.summary || "The team is working on this project. Check back for the next update.")}</p><span class="small">Updated ${esc(date(p.synced))}</span></article>`).join("") || '<div class="card empty"><strong>No public updates yet</strong>Projects will appear here when the team shares them.</div>'}</div></section><section class="card"><div class="eyebrow">Support desk</div><h2>How can we help?</h2><p class="small">Tell us what happened. Our support team will investigate and bring in development when a fix is needed.</p>${projects.length ? `<form id="ticket-form"><div class="field"><label for="project">Project</label><select id="project" name="project">${projects.map((p) => `<option value="${esc(p.slug)}">${esc(p.name)}</option>`).join("")}</select></div><div class="field"><label for="title">What do you need help with?</label><input id="title" name="title" required minlength="3" maxlength="160" placeholder="For example, I can’t finish checkout"></div><div class="field"><label for="description">A little more detail</label><textarea id="description" name="description" required minlength="10" maxlength="12000" placeholder="What were you trying to do? What happened instead?"></textarea><span class="small">Please leave out passwords, payment details and other sensitive information.</span></div><div class="field"><label for="contact">Email (optional)</label><input id="contact" name="contact" type="email" maxlength="254" autocomplete="email"><span class="small">Replies appear on your private tracking page. Email notifications are not enabled.</span></div><div class="hp" aria-hidden="true"><label for="website">Website</label><input id="website" name="website" tabindex="-1" autocomplete="off"></div>${errorBox}<button type="submit" class="btn primary full">Send to support ↗</button></form>` : '<p class="empty">Support opens when a project is shared.</p>'}</section></div><footer class="row between wrap"><span>AutoDev · Development & support, working together.</span><a href="/team">Team workspace</a></footer></main>`;
  bindForm("ticket-form", async (data) => {
    const ticket = await api("/api/public/tickets", data);
    location.assign(`/ticket/${encodeURIComponent(ticket.id)}#${ticket.token}`);
  });
}
async function loginPage() {
  app.innerHTML = `${publicHeader()}<main id="main"><section class="card login"><div class="eyebrow">For your team</div><h1>Welcome back.</h1><p>Sign in to see the full picture and keep work moving.</p><form id="login-form"><div class="field"><label for="username">Username</label><input id="username" name="username" required autocomplete="username"></div><div class="field"><label for="password">Password</label><input id="password" name="password" type="password" required autocomplete="current-password"></div>${errorBox}<button class="btn primary" type="submit">Open workspace →</button></form><p class="small recent">Need an account or a password reset? Ask the person who manages this server.</p></section></main>`;
  bindForm("login-form", async (data) => {
    me = await api("/api/login", data);
    await refreshWorkspace();
  });
}
function ticketRows(tickets) {
  return (
    tickets
      .map(
        (t) =>
          `<button class="ticket-row" data-ticket="${esc(t.id)}"><span><strong>${esc(t.title)}</strong><span class="small mono">${esc(t.id)}</span><span class="small"> · ${esc(t.project)} · ${esc(date(t.updated))}</span></span><span>${pill(t.status)}</span></button>`,
      )
      .join("") ||
    '<div class="empty"><strong>The inbox is clear</strong>Customer tickets will appear here, with their next step and owner.</div>'
  );
}
function projectCards() {
  return (
    workspace.projects
      .map(
        (p) =>
          `<article class="card project"><div class="row between"><div class="row"><div class="project-icon">${esc(p.name[0].toUpperCase())}</div><div><h3>${esc(p.name)}</h3><span class="small">${p.public ? "Public status enabled" : "Private project"}</span></div></div>${pill(!p.fresh ? "Awaiting update" : p.ready ? "Release checks passed" : "In progress")}</div><div class="progress" aria-label="${p.gates.filter((g) => g.status === "passed").length} of 6 release checks passed">${p.gates.map((g) => `<span class="${g.status === "passed" ? "passed" : ""}"></span>`).join("")}</div><div class="row between"><span class="small">${p.gates.filter((g) => g.status === "passed").length} of 6 release checks · ${p.tasks.filter((t) => t.status === "running").length} active tasks</span><button class="btn" data-project="${esc(p.slug)}">View project ↗</button></div></article>`,
      )
      .join("") ||
    '<div class="card empty"><strong>Your first project starts here</strong>Ask your server operator to connect a repository using the project setup wizard. Then send the team a brief from this workspace.</div>'
  );
}
function teamCard() {
  return `<section class="card"><div class="section-heading"><h2>Your department</h2><span class="small">7 specialists</span></div><div class="team-list">${workspace.roles.map((role, i) => `${i === 0 ? '<div class="team-label">DEVELOPMENT</div>' : i === 5 ? '<div class="team-label">CUSTOMER SUPPORT</div>' : ""}<div class="team-member row between"><div class="row"><span class="role-icon">${i + 1 < 10 ? "0" : ""}${i + 1}</span><div><strong>${esc(names[role])}</strong><div class="small">${esc(desc[role])}</div></div></div>${pill(workspace.projects.some((p) => p.fresh && p.tasks.some((t) => t.assignee === role && t.status === "running")) ? "running" : "No active task")}</div>`).join("")}</div><p class="small recent">Each specialist owns a part of the work. The project manager coordinates delivery; support follows through with the customer.</p></section>`;
}
function auditList() {
  return (
    workspace.audit
      .map(
        (a) =>
          `<div class="audit"><span class="dot"></span><div><strong>${esc(a.actor)}</strong> · ${esc(a.action)}<div class="small">${esc(a.target)} · ${esc(date(a.created))}</div></div></div>`,
      )
      .join("") ||
    '<div class="empty">Activity will appear as your team starts working.</div>'
  );
}
function taskTable() {
  const tasks = workspace.projects.flatMap((p) =>
    p.tasks.map((t) => ({ ...t, project: p.name })),
  );
  return `<div class="card table-wrap"><h2>Work across the department</h2>${tasks.length ? `<table class="task-table"><thead><tr><th>Task</th><th>Project</th><th>Owner</th><th>Status</th></tr></thead><tbody>${tasks.map((t) => `<tr><td>${esc(t.title)}</td><td>${esc(t.project)}</td><td>${esc(names[t.assignee] || t.assignee || "Unassigned")}</td><td>${pill(t.status)}</td></tr>`).join("")}</tbody></table>` : '<div class="empty">Send your first brief to create a work plan.</div>'}</div>`;
}
function renderWorkspace() {
  const owner = me.role === "owner",
    active = workspace.projects.reduce(
      (n, p) =>
        n +
        (p.fresh ? p.tasks.filter((t) => t.status === "running").length : 0),
      0,
    ),
    blocked = workspace.projects.reduce(
      (n, p) => n + p.tasks.filter((t) => t.status === "blocked").length,
      0,
    );
  const tickets = workspace.tickets.filter((t) => t.status !== "resolved");
  const headings = {
    overview: [
      "A little clarity. A lot of progress.",
      "Your development and support teams, in one place.",
    ],
    projects: [
      "From brief to release.",
      "Track the work, inspect the evidence, and give the team its next direction.",
    ],
    support: [
      "Every question has a next step.",
      "Follow customer conversations through triage, development and verification.",
    ],
    activity: [
      "The work behind the work.",
      "An accountable record of requests, handoffs and team controls.",
    ],
  };
  app.innerHTML = `<div class="shell"><aside class="sidebar">${brand}<div class="nav-label">Team workspace</div><nav class="nav" aria-label="Workspace">${[
    ["overview", "◫", "Overview"],
    ["projects", "▤", "Projects"],
    ["support", "◎", "Support desk"],
    ["activity", "↗", "Activity"],
  ]
    .map(
      ([id, icon, label]) =>
        `<button data-view="${id}" class="${currentView === id ? "selected" : ""}" ${currentView === id ? 'aria-current="page"' : ""}><span class="nav-icon" aria-hidden="true">${icon}</span>${label}</button>`,
    )
    .join(
      "",
    )}</nav><div class="sidebar-bottom"><a class="small" href="/">↗ Open public page</a><div class="account"><div class="avatar">${esc(me.username.slice(0, 2).toUpperCase())}</div><div><strong>${esc(me.username)}</strong><span class="small">${esc(me.role)} access</span></div></div><button class="btn quiet" id="logout">Sign out</button></div></aside><div class="content"><header class="topbar"><span>Workspace <span class="muted">/</span> <b>${esc({ overview: "Overview", projects: "Projects", support: "Support desk", activity: "Activity" }[currentView])}</b></span><div class="row"><span class="small">Updated ${esc(date(workspace.synced))}</span><button class="btn quiet" id="refresh" aria-label="Refresh workspace">↻</button><button class="btn quiet" id="mobile-logout">Sign out</button></div></header><main id="main" class="workspace"><div class="page-heading row between wrap"><div><div class="eyebrow">Made to move forward</div><h1>${headings[currentView][0]}</h1><p>${headings[currentView][1]}</p></div>${owner ? '<button class="btn primary" id="new-brief">＋ Give the team a brief</button>' : ""}</div>${workspace.projects.some((p) => !p.fresh) ? '<div class="error-banner">Some project updates are not current. The portal is retrying the connection; readiness stays unconfirmed until it refreshes.</div>' : ""}${workspace.queue.length ? `<div class="error-banner">${workspace.queue.length} handoff${workspace.queue.length === 1 ? " is" : "s are"} waiting to reach Hermes. Saved safely; delivery retries automatically.</div>` : ""}${
    currentView === "overview"
      ? `<section class="hero-band"><div><div class="eyebrow">Development + customer support</div><h2>${workspace.gateway === "running" ? "The team is moving." : workspace.gateway === "stopped" ? "The team is paused." : "Checking the team connection."}</h2><p>${workspace.gateway === "running" ? "The project manager coordinates delivery. Support brings customer feedback into the loop." : "Start the team to let the scheduler pick up new tasks and recurring project reviews."}</p></div>${owner ? `<button class="btn" id="team-control" data-action="${workspace.gateway === "running" ? "stop" : "start"}">${workspace.gateway === "running" ? "Pause scheduling" : "Start the team"} ${workspace.gateway === "running" ? "Ⅱ" : "→"}</button>` : pill(workspace.gateway)}</section><div class="metrics">${[
          [
            workspace.projects.length,
            "Projects",
            "Connected to your department",
          ],
          [active, "Working now", "Tasks picked up by specialists"],
          [
            tickets.length,
            "Open conversations",
            "Support is tracking the next step",
          ],
          [blocked, "Needs attention", "Blocked work to follow up"],
        ]
          .map(
            ([n, label, note]) =>
              `<div class="card metric"><span class="small">${label}</span><div class="number">${n}</div><div class="small">${note}</div></div>`,
          )
          .join(
            "",
          )}</div><div class="split"><div><div class="section-heading"><h2>Projects in motion</h2><button class="btn quiet" data-view="projects">All projects →</button></div><div class="projects">${projectCards()}</div><section class="card recent"><div class="section-heading"><h2>Support inbox</h2><button class="btn quiet" data-view="support">View all →</button></div>${ticketRows(workspace.tickets.slice(0, 5))}</section></div>${teamCard()}</div>`
      : currentView === "projects"
        ? `<div class="projects">${projectCards()}</div><section class="recent">${taskTable()}</section>`
        : currentView === "support"
          ? `<section class="card"><div class="section-heading"><h2>Customer conversations</h2><span class="small">Latest 200 tickets</span></div>${ticketRows(workspace.tickets)}</section>`
          : `<div class="split"><section class="card"><h2>Recent activity</h2>${auditList()}</section><section class="card"><h2>Pending handoffs</h2>${workspace.queue.map((o) => `<div class="audit"><div><strong>${esc(o.title)}</strong><div class="small">${esc(o.project)} · ${o.attempts} delivery attempts</div><p class="small">${esc(o.error || "Queued for delivery")}</p></div></div>`).join("") || '<div class="empty">All handoffs have reached the team.</div>'}</section></div>`
  }</main></div></div>`;
  document.querySelectorAll("[data-view]").forEach(
    (b) =>
      (b.onclick = () => {
        currentView = b.dataset.view;
        renderWorkspace();
      }),
  );
  document
    .querySelectorAll("[data-project]")
    .forEach((b) => (b.onclick = () => projectModal(b.dataset.project)));
  document
    .querySelectorAll("[data-ticket]")
    .forEach(
      (b) =>
        (b.onclick = () =>
          ticketModal(b.dataset.ticket).catch((e) => notify(e.message))),
    );
  for (const id of ["logout", "mobile-logout"])
    document.getElementById(id)?.addEventListener("click", async () => {
      try {
        await api("/api/logout", {});
      } catch (error) {
        notify(error.message);
      }
      me = null;
      await loginPage();
    });
  document.getElementById("refresh").onclick = () =>
    refreshWorkspace().catch((e) => notify(e.message));
  document
    .getElementById("new-brief")
    ?.addEventListener("click", () => briefModal());
  document
    .getElementById("team-control")
    ?.addEventListener("click", async (event) => {
      const button = event.currentTarget,
        action = button.dataset.action;
      if (
        action === "stop" &&
        !confirm(
          "Pause scheduling for all projects? New work stops being picked up. Tasks already running may continue until they finish.",
        )
      )
        return;
      button.disabled = true;
      try {
        await api(`/api/team/${action}`, {});
        notify(
          action === "start"
            ? "The team is running."
            : "Scheduling paused. Running tasks may still finish.",
        );
        await refreshWorkspace();
      } catch (e) {
        notify(e.message);
        button.disabled = false;
      }
    });
}
async function refreshWorkspace() {
  workspace = await api("/api/workspace");
  renderWorkspace();
}
function briefModal(slug) {
  if (!workspace.projects.length) {
    notify("Connect a project through the server setup wizard first.");
    return;
  }
  const requestId = crypto.randomUUID();
  modal(
    "What should the team work on?",
    `<p class="small">Describe the outcome in your own words. Your project manager will plan the work and coordinate the specialists.</p><form id="brief-form"><div class="field"><label for="brief-project">Project</label><select name="project" id="brief-project">${workspace.projects.map((p) => `<option ${p.slug === slug ? "selected" : ""} value="${esc(p.slug)}">${esc(p.name)}</option>`).join("")}</select></div><div class="field"><label for="brief-title">A short title</label><input id="brief-title" name="title" required minlength="3" maxlength="160"></div><div class="field"><label for="brief-body">What does a good result look like?</label><textarea id="brief-body" name="body" required minlength="10" maxlength="12000" placeholder="Who is this for? What should they be able to do? Include any limits, priorities or decisions."></textarea></div>${errorBox}<button type="submit" class="btn primary">Send to project manager →</button></form>`,
  );
  bindForm("brief-form", async (data) => {
    await api(`/api/projects/${encodeURIComponent(data.project)}/brief`, {
      title: data.title,
      body: data.body,
      request_id: requestId,
    });
    dialog.close();
    notify("Your brief is saved and queued for the project manager.");
    await refreshWorkspace();
  });
}
function projectModal(slug) {
  const p = workspace.projects.find((p) => p.slug === slug);
  modal(
    p.name,
    `<div class="eyebrow">Release readiness</div><p class="small">All six checks need evidence for the current commit. Passing checks is a readiness recommendation; deployment still needs its own verification.</p>${p.gates.map((g) => `<div class="gate"><div><span class="gate-name">${esc(g.gate)}</span>${g.reference ? `<small>${esc(g.reference)}</small>` : ""}</div>${pill(g.status)}</div>`).join("")}<p class="small">Last checked ${esc(date(p.synced))}. ${esc(p.error || (!p.clean ? "Uncommitted repository changes must be verified before release readiness." : ""))}</p>${me.role === "owner" ? `<button class="btn primary" id="project-brief">Give this project a brief</button><hr><h3>Public project page</h3><form id="publish-form"><div class="field"><label class="check"><input type="checkbox" name="public" ${p.public ? "checked" : ""}>Show this project publicly and accept support tickets</label></div><div class="field"><label for="summary">Public update</label><textarea id="summary" name="summary" maxlength="2000" placeholder="Share a short, customer-friendly progress update.">${esc(p.summary)}</textarea><span class="small">Only this update and readiness are public. Internal tasks and evidence stay in the workspace.</span></div>${errorBox}<button class="btn" type="submit">Save public update</button></form>` : ""}`,
  );
  document.getElementById("project-brief")?.addEventListener("click", () => {
    dialog.close();
    briefModal(slug);
  });
  bindForm("publish-form", async (data) => {
    await api(`/api/projects/${encodeURIComponent(slug)}/publish`, {
      public: data.public === "on",
      summary: data.summary,
    });
    dialog.close();
    notify("Public page updated.");
    await refreshWorkspace();
  });
}
function messages(ticket) {
  return ticket.messages
    .map(
      (m) =>
        `<article class="message ${m.public ? "" : "internal"}"><div class="row between"><strong class="small">${esc(m.author)}${m.public ? "" : " · Internal note"}</strong><span class="small">${esc(date(m.created))}</span></div><p>${esc(m.body)}</p></article>`,
    )
    .join("");
}
async function ticketModal(id) {
  const t = await api(`/api/tickets/${encodeURIComponent(id)}`);
  modal(
    t.title,
    `<div class="row between"><span class="small mono">${esc(t.id)} · ${esc(t.project)}</span>${pill(t.status)}</div><p class="ticket-description">${esc(t.description)}</p><p class="small">Contact: ${esc(t.contact || "Not provided")}<br>Development task: ${esc(t.development_task || "Not escalated")}</p>${messages(t)}${me.role !== "viewer" ? `<form id="reply-form"><div class="field"><label for="reply-action">Next step</label><select name="action" id="reply-action"><option value="reply">Add a reply or note</option><option value="waiting">Ask the customer for more information</option><option value="review">Ask support manager to review</option><option value="escalate">Hand off to development</option><option value="resolve">Resolve with verification evidence</option><option value="reopen">Reopen this conversation</option></select></div><div class="field"><label for="reply-body">Message or handoff evidence</label><textarea id="reply-body" name="body" required maxlength="12000" placeholder="For development: impact, steps to reproduce, expected result and acceptance criteria."></textarea></div><label class="check"><input type="checkbox" name="public">Make this message visible to the customer</label><p class="small">Requests for information and resolution messages are always customer-visible. Keep sensitive investigation details in internal notes.</p>${errorBox}<button class="btn primary" type="submit">Save next step</button></form>` : ""}`,
  );
  bindForm("reply-form", async (data) => {
    await api(`/api/tickets/${encodeURIComponent(id)}/${data.action}`, {
      body: data.body,
      public: data.public === "on",
    });
    dialog.close();
    notify("Ticket updated.");
    await refreshWorkspace();
  });
}
async function trackingPage() {
  const id = decodeURIComponent(location.pathname.split("/")[2]),
    key = "ticket:" + id;
  const token = location.hash.slice(1) || sessionStorage.getItem(key);
  if (!token)
    throw new Error(
      "Open the full private tracking link you received when you submitted this ticket.",
    );
  sessionStorage.setItem(key, token);
  const headers = { Authorization: "Bearer " + token },
    t = await api(`/api/public/tickets/${encodeURIComponent(id)}`, undefined, {
      headers,
    });
  const link =
    location.origin + "/ticket/" + encodeURIComponent(id) + "#" + token;
  app.innerHTML = `${publicHeader()}<main id="main" class="public-main tracking"><div class="eyebrow">Your support conversation</div><h1>${esc(t.title)}</h1><div class="row between"><span class="small mono">${esc(t.id)}</span>${pill(t.status)}</div><section class="card recent"><h2>Keep this private link</h2><p class="small">This link is your key to updates and replies. Save it somewhere safe; anyone with it can view this ticket.</p><div class="row"><input aria-label="Private tracking link" value="${esc(link)}" readonly><button class="btn" id="copy-link">Copy</button></div></section><p class="ticket-description recent">${esc(t.description)}</p>${messages(t)}<section class="card recent"><h2>${t.status === "resolved" ? "Need more help?" : "Add to the conversation"}</h2><form id="customer-reply"><div class="field"><label for="customer-message">Your message</label><textarea id="customer-message" name="body" required maxlength="12000"></textarea></div>${errorBox}<div class="btn-group"><button class="btn primary" type="submit">${t.status === "resolved" ? "Reopen ticket" : "Send reply"}</button><button class="btn" id="check-updates" type="button">Check for updates</button></div></form></section></main>`;
  document.getElementById("copy-link").onclick = () =>
    navigator.clipboard
      .writeText(link)
      .then(() => notify("Private link copied."))
      .catch(() => notify("Select and copy the private link above."));
  document.getElementById("check-updates").onclick = () =>
    trackingPage().catch((e) => notify(e.message));
  bindForm("customer-reply", async (data) => {
    await api(
      `/api/public/tickets/${encodeURIComponent(id)}/${t.status === "resolved" ? "reopen" : "reply"}`,
      { body: data.body },
      { headers },
    );
    notify("Your message has reached support.");
    await trackingPage();
  });
}
async function start() {
  try {
    if (location.pathname.startsWith("/ticket/")) {
      await trackingPage();
      return;
    }
    if (location.pathname === "/team") {
      try {
        me = await api("/api/me");
      } catch {
        await loginPage();
        return;
      }
      await refreshWorkspace();
    } else await publicPage();
  } catch (e) {
    app.innerHTML = `${publicHeader()}<main id="main" class="public-main"><section class="card"><h1>We couldn’t open this page.</h1><p>${esc(e.message)}</p><a class="btn" href="/">Return to the public page</a></section></main>`;
  }
}
setInterval(async () => {
  if (me && location.pathname === "/team" && !dialog.open) {
    try {
      await refreshWorkspace();
    } catch (e) {
      notify(e.message);
    }
  }
}, 30000);
start();
