---
name: kanban-worker
description: Follow the Hermes Kanban worker lifecycle for scoped security assessment, useful heartbeats, blocked decisions, structured handoffs, and safe cross-agent remediation routing.
version: 1.0.0
author: Hermes autonomous development team
license: Private
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [kanban, collaboration, security, workflow]
    related_skills: [security-testing]
---

# Kanban Worker

Use this skill whenever the Hermes Kanban dispatcher starts the Security Tester.

## Orient

1. Read the injected task id, board, workspace, branch, and tenant context.
2. Call `kanban_show` before doing work.
3. Stop if the task is already blocked or archived.
4. Read the full comment thread, linked issue and pull/merge request, prior runs, and dependency handoffs.
5. Confirm the repository/commit and, for dynamic testing, the exact authorized target and scope.

Do not repeat a failed prior run without addressing its recorded failure.

## Workspace Safety

The workspace may be:

- `scratch`: a private temporary workspace.
- `dir:<path>`: a shared persistent directory, often the application repo.
- `worktree`: a Git worktree.

Security Tester is report-only in all workspace types. A writable application worktree is not permission to alter it.

Keep scanner configuration, caches, vulnerability databases, browser/proxy state, payload files, and evidence outside the application repository. Use a private scratch/artifact directory and record its location. Check `git status --short` before and after tools.

If `$HERMES_TENANT` is set, prefix persistent memory with the tenant identifier and never leak one tenant's application details or findings to another.

## Start And Heartbeat

At start, leave a Kanban comment containing:

- Commit or pull/merge request and authorized target.
- Environment and synthetic identities.
- Standards, versions, ASVS level, and selected test layers.
- Explicit exclusions and safety/rate limits.
- Planned private artifact location.

For work lasting more than a few minutes, send useful heartbeats. Name completed layers, candidates being verified, evidence produced, and remaining coverage. Do not send vague messages such as "still testing."

Escalate a confirmed critical issue immediately with redacted impact. Do not wait for the final report and do not place weaponized proof or secrets in a broad comment.

## Block Correctly

Use `kanban_comment` for detailed context and `kanban_block` for the concise decision or access needed.

Good blockers identify a specific missing item, for example:

- Exact staging URL and authorization scope required for dynamic testing.
- Second synthetic tenant identity required to verify isolation.
- Owner decision required before any production observation.
- Restricted channel required for sensitive reproduction evidence.

Do not use interactive clarification tools in a headless worker. Do not remain silently running while waiting for access.

If source-only assessment can still provide material value, complete that portion and mark dynamic coverage not tested instead of blocking the whole task.

## Route Findings

Security Tester never fixes findings.

- Record confirmed findings in the narrowest approved durable record.
- Keep Kanban and broad pull/merge request comments redacted.
- Ask Project Manager to create or assign remediation to `developer`.
- Do not create remediation cards assigned to yourself.
- Capture every successful `kanban_create` task id if the task explicitly authorizes you to create follow-ups; never invent ids.
- Retest only after Developer supplies an exact fixed commit and target.

## Complete With Structured Evidence

Use `kanban_complete` only when the requested assessment or retest is genuinely finished. The summary must include scope and recommendation; metadata should remain machine-readable:

```python
kanban_complete(
    summary="Security assessment completed for <commit>/<target>; restricted findings linked; recommendation: <result>.",
    metadata={
        "commit": "<sha>",
        "target": "<authorized target or source-only>",
        "standards": ["OWASP ASVS 5.0.0", "OWASP WSTG 4.2"],
        "findings": {
            "critical": 0,
            "high": 0,
            "medium": 0,
            "low": 0,
            "informational": 0,
        },
        "coverage": {
            "passed": 0,
            "failed": 0,
            "not_tested": 0,
            "not_applicable": 0,
        },
        "release_recommendation": "pass|pass-with-risk-notes|fail|incomplete",
    },
)
```

The prose handoff must also state tools/versions, false positives rejected, limitations, residual risk, and retest status. Never claim universal security or compliance from partial coverage.

## Do Not

- Modify the application repository or apply a fix.
- Test outside the exact authorized scope.
- Use production, third-party, destructive, brute-force, denial-of-service, persistence, bulk-data, or real-customer techniques by default.
- Treat scanner output as confirmed without verification.
- Expose secrets or unnecessary exploit detail in Kanban, pull/merge requests, or logs.
- Complete a task whose material requested scope was not performed; use `incomplete` or block with the exact missing requirement.
