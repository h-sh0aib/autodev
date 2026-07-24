---
name: security-testing
description: Perform authorized, report-only application security assessments and remediation retests using a risk-based OWASP verification baseline, safe static and dynamic techniques, and evidence-backed release recommendations.
version: 1.0.0
author: Hermes autonomous development team
license: Private
metadata:
  hermes:
    tags: [security, appsec, owasp, asvs, wstg, sast, dast, sca, threat-modeling]
---

# Security Testing

Use this skill for every task assigned to the `security-tester` profile.

## Reproducible Standards Snapshot

This package pins stable documents so assessments remain comparable:

| Product surface | Primary baseline | How to use it |
|---|---|---|
| Web application | OWASP ASVS 5.0.0 | Select verifiable controls and record versioned requirement IDs. |
| Web test procedure | OWASP WSTG 4.2 | Select test scenarios and record versioned scenario IDs. |
| Web risk review | OWASP Top 10:2025 | Use for risk awareness and gap review, never as the only checklist. |
| HTTP/API | OWASP API Security Top 10:2023 | Cover API authorization, resource, inventory, and trust-boundary risks. |
| Secure delivery | NIST SP 800-218 SSDF 1.1 | Review available build, provenance, dependency, protection, and response evidence. |
| Mobile | OWASP MASVS and MASTG | Use the current stable release and record its version at assessment time. |
| LLM/agent feature | Current OWASP GenAI/LLM guidance | Apply only when relevant and record the exact document/version used. |

Reference sources:

- https://owasp.org/www-project-application-security-verification-standard/
- https://owasp.org/www-project-web-security-testing-guide/
- https://owasp.org/www-project-top-ten/
- https://owasp.org/API-Security/
- https://mas.owasp.org/
- https://csrc.nist.gov/pubs/sp/800/218/final

If network access is available, check whether a newer stable release exists. Do not silently switch to an unreleased or draft document. Record any deliberate version change in the report.

## Select The Assurance Level

- ASVS Level 1 is the minimum for any web-facing application.
- Use ASVS Level 2 for authenticated business software or software handling personal, tenant, financial, health, operational, or otherwise sensitive data. This is the default for normal company products.
- Use ASVS Level 3 only when the owner explicitly requests high assurance and provides the time, architecture, access, and specialist tooling needed.

An incremental PR review selects requirements affected by the change and adjacent trust boundaries. A full release review requires a documented control matrix. Never call selected-control testing "ASVS compliant."

## Phase 1: Orient And Authorize

Read the Kanban task and linked context first. Capture:

- Repository and exact commit or PR.
- Authorized target URL or host, if any.
- Whether the target is local, isolated test, staging, or production.
- In-scope paths, APIs, roles, tenants, accounts, and data.
- Explicit exclusions and forbidden techniques.
- Available synthetic test identities and credentials.
- Time window, rate limit, and stop/contact conditions.
- Prior findings and expected remediation.

Source review needs a repository assignment. Dynamic testing additionally needs an exact target. If dynamic scope is absent, perform source-only work and mark dynamic coverage not tested.

## Phase 2: Model The Attack Surface

Create a compact model before choosing tests:

1. Identify security-sensitive assets and business actions.
2. Identify entry points, protocols, uploaded content, webhooks, jobs, admin paths, and internal services.
3. Map unauthenticated, user, privileged, support, service, and tenant roles.
4. Mark trust boundaries, external providers, data stores, queues, caches, and secret stores.
5. Trace personal, credential, payment, tenant, and regulated data.
6. List realistic attacker goals, misuse cases, and failure impacts.
7. Rank test areas by reachability, privilege gained, affected records/tenants, and business consequence.

Do not spend equal effort on every checklist item. Explain why the selected controls cover the highest-risk paths.

## Phase 3: Establish Clean Evidence

Before tools:

- Record `git status --short`, the commit SHA, branch, and relevant diff.
- Select a private artifact directory outside the application repository.
- Set restrictive permissions when the platform supports them.
- Record tool versions before recording results.
- Remove credentials from command transcripts and process arguments where possible.

After tools, run `git status --short` again. If the worktree changed, identify the tool and paths, stop using it, and report the protocol violation.

## Phase 4: Layered Verification

### Code And Configuration Review

Trace untrusted input to sensitive operations and verify controls at the actual enforcement point. Review:

- Authentication, recovery, MFA, session rotation/revocation, and token validation.
- Server-side authorization for objects, properties, functions, tenants, and administrative operations.
- Query construction, shell/process use, templates, serializers, parsers, file paths, archives, uploads, and redirects.
- Outbound requests, URL validation, DNS/IP handling, webhooks, and metadata/internal network reachability.
- Cryptographic choices, randomness, key lifecycle, secret access, and failure modes.
- Debug settings, error details, logs, metrics, caches, and sensitive-data retention.
- Cross-origin, CSRF, content security, cookies, browser storage, and cache directives.
- Transaction boundaries, idempotency, ordering, races, replay, state machines, and approval workflows.

Do not report a pattern match as a vulnerability without following data flow and reachable behavior.

### Secrets

Review tracked files, relevant history, examples, CI definitions, deployment files, and generated artifacts using a secret detector when available.

For any candidate:

- Determine whether it is a real secret or a documented placeholder.
- Determine whether it is active only through owner-approved channels; never validate a secret against a provider on your own.
- Record only a redacted fingerprint and precise repository location.
- Treat rotation and history removal as separate remediation outcomes where applicable.

### Dependencies And Supply Chain

Use lockfile-aware ecosystem checks or an available SCA tool. Record the database timestamp and tool version. For each result:

- Confirm the affected package and resolved version are actually present.
- Determine runtime, development, build-only, optional, or unreachable use.
- Check known fixed versions and compatibility constraints.
- Assess exploit prerequisites in this product.
- Review install/build scripts, unpinned actions/images, artifact provenance, CI permissions, and release secret exposure.

A CVE feed match is a candidate until product relevance is evaluated.

### Infrastructure, Containers, And CI/CD

Review:

- Publicly exposed services and management interfaces.
- Default credentials and example secrets.
- Container user, capabilities, mounts, host access, base-image pinning, and build context.
- IaC identity permissions, network rules, storage access, encryption, logging, and secret sources.
- CI token permissions, pull-request trust, untrusted script execution, action pinning, artifact handling, and environment protections.
- Production debug flags, verbose errors, source maps, admin tooling, backup access, and environment separation.

Do not scan cloud accounts or networks unless their exact scope and read-only authorization are attached.

### Safe Dynamic Testing

Start with passive observation and ordinary requests. Then apply narrowly selected, low-impact tests:

- Authentication and session state transitions.
- Cross-account and cross-tenant authorization using controlled identities.
- Input handling with harmless markers.
- CSRF, CORS, cookies, headers, caching, redirects, and browser security policy.
- API object/property/function authorization and documented bounded rate behavior.
- File type, size, name, path, metadata, and safe processing boundaries.
- Business workflow replay, duplicate submission, ordering, and state transition checks.
- Error and audit behavior without forcing resource exhaustion.

Use the minimum requests and data needed. Do not brute force, exhaust resources, enumerate real users, dump data, or run destructive payloads. Automated DAST active scanning requires explicit authorization; passive/baseline modes are preferred.

### Conditional Surfaces

When present, add focused coverage:

- Mobile: storage, platform interaction, network validation, deep links, IPC, privacy, and release build controls using MASVS/MASTG.
- Payments/financial actions: amount and currency integrity, replay, idempotency, authorization, webhook authenticity, and race conditions with provider-approved test mode.
- Webhooks/integrations: signature validation, replay windows, destination allowlists, event ordering, and unsafe upstream data.
- Multi-tenancy: every object and search/list/export path, background jobs, caches, files, logs, and administrative support access.
- LLM/agents: prompt and tool trust boundaries, instruction/data separation, excessive agency, output handling, retrieval poisoning, secrets, tenant isolation, approval gates, and cost/resource limits.

Never attack a real third-party provider while testing the integration.

## Tool Selection

Prefer existing, reputable, read-only tools and project-native checks. Examples by purpose include:

- Secret discovery: Gitleaks or equivalent.
- SCA: OSV-Scanner, ecosystem audit commands, or equivalent.
- SAST: Semgrep or language-native analyzers.
- Containers/IaC: Trivy, Checkov, or equivalent.
- DAST: OWASP ZAP passive or baseline mode by default.

These are examples, not mandatory dependencies. Record the exact tool/version actually used. Do not install globally, alter the repo, or claim missing tools ran. Never upload proprietary source to a third-party scanner without explicit owner approval.

## Phase 5: Verify And Triage

For every candidate:

1. Establish reachability.
2. Establish attacker-controlled input or precondition.
3. Identify the missing or bypassed control.
4. Reproduce with a harmless minimum proof when authorized.
5. Determine affected roles, tenants, records, systems, and environments.
6. Reject or downgrade false positives and defense-in-depth gaps with rationale.
7. Assign severity from demonstrated business impact and realistic likelihood.
8. Map CWE and versioned OWASP controls only after checking that the mapping is accurate.

Use CVSS 4.0 only with a complete vector. Scanner severities are never authoritative.

## Phase 6: Report Without Creating A New Risk

Each finding needs:

- ID, title, severity, and confidence.
- Commit, target, component, endpoint, role, and tenant.
- Preconditions and attacker capability.
- Safe reproduction.
- Expected versus actual control.
- Redacted evidence.
- Demonstrated impact and scope.
- CWE and verified versioned standard references.
- Remediation outcome and testable acceptance criteria.
- Retest status.

Separate:

- Confirmed vulnerabilities.
- Suspected findings needing access or environment evidence.
- Defense-in-depth recommendations.
- Rejected false positives.
- Not-tested coverage.

Use restricted records for sensitive proof. A public or broad PR comment should state impact and link to the restricted record, not expose a weaponized proof.

## Phase 7: Retest

Retest the exact original behavior against the Developer's fixed commit and environment. Then check:

- Equivalent endpoints or code paths.
- Cross-role and cross-tenant variants.
- Encoding or workflow bypasses relevant to the original cause.
- Regression of legitimate behavior.
- Whether logs, alerts, revocation, rotation, or cleanup promised by remediation occurred.

Record fixed, partially fixed, not fixed, or not retested. Tool output and Developer assertions alone do not close a finding.

## Release Gate

- `pass`: the defined scope completed with no unresolved confirmed critical/high findings.
- `pass-with-risk-notes`: no unresolved critical/high findings; residual risk and gaps are explicit.
- `fail`: confirmed critical/high findings remain, or an essential security control failed.
- `incomplete`: material scope, access, target, tool, or environment gaps prevent a responsible decision.

Only the human owner may accept security risk. A pass is scoped to the assessed commit, target, techniques, identities, and date; it is never a guarantee of no vulnerabilities.
