# Security Testing Profile

The `security-tester` profile is the team's report-only application security specialist. It runs on OpenRouter with:

```yaml
model:
  provider: openrouter
  default: moonshotai/kimi-k3
```

It can read application source and configuration, run safe security tooling, and perform explicitly authorized dynamic tests. It cannot edit the application, apply fixes, test arbitrary targets, or treat raw scanner output as a confirmed vulnerability.

No model fallback is configured: repeated OpenRouter authentication, billing, rate, or provider-capacity errors should be recorded as an operations blocker rather than silently moving the assessment to a different model.

## Standards Baseline

The profile pins stable standards for reproducible assessments:

- [OWASP ASVS 5.0.0](https://owasp.org/www-project-application-security-verification-standard/) for verifiable application controls.
- [OWASP WSTG 4.2](https://owasp.org/www-project-web-security-testing-guide/) for web test procedures.
- [OWASP Top 10:2025](https://owasp.org/www-project-top-ten/) for risk awareness, not as the sole checklist.
- [OWASP API Security Top 10:2023](https://owasp.org/API-Security/) for API-specific risks.
- [NIST SP 800-218 SSDF 1.1](https://csrc.nist.gov/pubs/sp/800/218/final) for secure delivery and supply-chain evidence.
- OWASP MASVS/MASTG for mobile products and current OWASP GenAI/LLM guidance for products containing those surfaces. The report must record the exact stable version used.

ASVS Level 1 is the minimum web baseline. Level 2 is the default for authenticated company software and systems handling personal, tenant, financial, health, or other sensitive data. Level 3 requires an explicit high-assurance engagement.

A PR review normally assesses selected controls affected by the change. A claim of ASVS compliance requires every in-scope requirement at the stated level to be evaluated in a complete coverage matrix.

## Team Workflow

1. Project Manager creates a scoped task assigned to `security-tester`.
2. Security Tester records the commit, authorized target, identities, standards, exclusions, and planned techniques.
3. Security Tester models the attack surface, reviews source/configuration/dependencies/infrastructure, and performs safe dynamic checks when authorized.
4. Confirmed findings are recorded in a restricted durable record and linked from a redacted Kanban summary.
5. Project Manager assigns remediation to `developer`.
6. Developer sends every code change through Codex and returns the fixed commit and environment.
7. Security Tester independently retests the original proof and relevant bypass variants.
8. Project Manager gates release on the scoped security recommendation.

Functional QA remains separate: `tester` validates the real browser experience through Playwright, while `security-tester` validates security controls through source-aware and safe dynamic techniques.

## Required Dynamic-Test Scope

Every dynamic assessment task should state:

```text
Repository and commit:
Authorized target/base URL:
Environment: local | isolated test | staging | production
In-scope hosts, paths, APIs, roles, and tenants:
Out-of-scope systems and third parties:
Synthetic test accounts/data:
Allowed techniques:
Forbidden techniques:
Maximum request rate:
Test window and stop/contact conditions:
Artifact location and access restrictions:
```

If the target is omitted, the profile may still complete safe source and configuration review and must mark dynamic coverage as not tested.

Production is out of scope by default. Production testing requires explicit human-owner authorization naming the exact target, window, allowed techniques, rate, accounts/data, rollback/contact plan, and stop conditions. Denial-of-service, brute force, destructive payloads, persistence, bulk data access, real-customer data collection, and testing third-party providers are never default techniques.

## Optional Tooling

The base package does not install global security tools because supported projects and VPS operating systems vary. The profile uses tools already present, project-native read-only checks, or isolated temporary tooling explicitly authorized for the task.

Useful optional tools include:

- Gitleaks for secret detection.
- OSV-Scanner or ecosystem-native audit commands for dependency analysis.
- Semgrep or language-native analyzers for static analysis.
- Trivy or Checkov for containers and infrastructure-as-code.
- OWASP ZAP passive or baseline mode for safe initial dynamic analysis.

Tool absence is a coverage gap, not permission to modify the application or global server. Reports must name every tool/version actually used and distinguish verified findings from untriaged candidates.

## Evidence And Release Gate

Security evidence stays outside the application repository and must redact secrets, session material, personal records, and unnecessary exploit detail. Broad PR/Kanban comments should link to restricted evidence rather than reproduce it.

The final recommendation is one of:

- `pass`: defined scope completed with no unresolved confirmed critical/high findings.
- `pass-with-risk-notes`: no unresolved critical/high findings, with residual risks and gaps stated.
- `fail`: confirmed critical/high findings remain or an essential security control failed.
- `incomplete`: scope, access, target, tool, or environment gaps prevent a responsible decision.

Only the human owner may accept residual security risk. A pass applies only to the assessed commit, target, identities, techniques, and date; it is not a guarantee that no vulnerability exists.
