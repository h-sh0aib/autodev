# Codex Auth Troubleshooting

## Quick Verification (run before unblocking)

```bash
# 1. Check login status
codex login status
# Expected: "Logged in (ChatGPT)" or "Logged in (API key)"

# 2. Test execution from the project directory
cd /absolute/path/to/project && codex exec "echo CODEX_OK" 2>&1 | tail -5
# Expected: output includes "CODEX_OK" with no 401 errors

# 3. Check auth.json freshness
stat -c "%y" ~/.codex/auth.json
# If > 7 days old, tokens are likely expired
python3 -c "import json, pathlib; p=pathlib.Path.home()/'.codex/auth.json'; d=json.load(open(p)); print('mode:', d.get('auth_mode'), '| last_refresh:', d.get('last_refresh'))"
```

**Do NOT unblock until ALL THREE checks pass.** The user saying "it's fixed" is not enough — verify.

## Auth Modes

| Mode | Source | Reliability on headless |
|---|---|---|
| `auth_mode: "chatgpt"` | OAuth tokens in `~/.codex/auth.json` | Tokens expire ~7 days; `codex login` needs a browser |
| `OPENAI_API_KEY` env var | API key in environment | Permanent until key rotates; best for headless |

## Common Failure: Developer reports 401, user says "fixed"

The user might have run `codex login` on their local machine (with a browser) but NOT copied `auth.json` to the server. Or they set `OPENAI_API_KEY` in their local shell but not on the server.

**Always check the server yourself before unblocking.** Run the verification sequence above from the project repository directory.

## Common Failure: Developer process can't find auth

The Developer profile might have its own `$HOME/.codex` that isn't populated. Check:
```bash
# What .codex does the Developer profile see?
ls -la ~/.hermes/profiles/developer/.codex 2>/dev/null
grep CODEX ~/.hermes/profiles/developer/.env
```

If the Developer profile's `.codex` is empty or missing, either:
- Symlink: `ln -s ~/.codex ~/.hermes/profiles/developer/.codex`
- Or set `CODEX_HOME` in the profile's `.env` to the server account's Codex auth directory.

## Common Failure: 401 "Missing bearer or basic authentication"

This means no auth method is configured at all:
```
ERROR: unexpected status 401 Unauthorized: Missing bearer or basic authentication in header
```

Fix: Either set `OPENAI_API_KEY` or ensure `auth.json` has valid tokens.
