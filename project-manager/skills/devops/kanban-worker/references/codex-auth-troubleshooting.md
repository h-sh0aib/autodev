# Codex CLI Auth Troubleshooting

## Quick diagnostic commands

```bash
codex login status          # Shows auth state
codex exec "echo hello"     # Quick smoke test — should return output without 401
env | grep OPENAI           # Check for OPENAI_API_KEY
hermes auth list            # Check hermes-managed credentials
cat ~/.codex/config.toml    # Project trust, model, provider
```

## Auth modes

Codex supports two authentication modes:

1. **API Key** — `OPENAI_API_KEY` environment variable. Simplest. Codex connects directly to api.openai.com.
2. **ChatGPT OAuth** — `codex login` flow. Stores tokens in `~/.codex/auth.json`. Tokens expire and must be refreshed.

## Common failure: stale OAuth tokens

**Symptoms:**
- `codex login status` → "Not logged in"
- `codex exec ...` → `401 Unauthorized: Missing bearer or basic authentication in header`
- `~/.codex/auth.json` exists with valid-looking tokens but `last_refresh` is days/weeks old

**Root cause:** ChatGPT OAuth tokens in `auth.json` have expired. The `auth_mode` field will be `"chatgpt"` and `OPENAI_API_KEY` will be `null`. The tokens look present but are stale.

**Fix:** Run `codex login` to refresh the OAuth session. This should reuse existing tokens if they're refreshable, or prompt for a new browser login.

## Common failure: missing API key

**Symptoms:**
- No `OPENAI_API_KEY` in environment
- `~/.codex/auth.json` absent or has `"OPENAI_API_KEY": null`
- `codex exec ...` → 401 with "Missing bearer or basic authentication"

**Fix A (API key):**
```bash
export OPENAI_API_KEY=***
```
Add to the relevant profile's `.env` file (for example, `~/.hermes/profiles/developer/.env`).

**Fix B (OAuth):**
```bash
hermes auth add openai-codex   # or: codex login
```

## Verifying the fix

After applying the fix, ALWAYS verify with:
```bash
codex exec "echo CODEX_OK"
```
Expected: output containing "CODEX_OK" with exit code 0. If you still get 401, the fix didn't take — do not unblock.

## Checking from the orchestrator's perspective

When the Developer blocks with a Codex auth error, the orchestrator MUST reproduce the failure before unblocking:
```bash
codex login status
codex exec "echo hello"
```
Only unblock when these pass. A human saying "it's fixed" is not verification — see kanban-orchestrator pitfall "Unblocking without verification."
