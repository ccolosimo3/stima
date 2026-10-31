# Workflow: Verify

Verification tiers, canonical commands, and runtime constraints.

## Verification

Run the relevant checks before claiming completion.

### Verification Tiers

- Tier 1 (implementation loop): run the smallest checks that prove changed behavior. For backend code changes, run the targeted backend behavior check plus `make backend-static-verify` before push/PR update.
- Tier 2 (post-review patch): rerun only checks needed for patched findings unless scope expands. For backend code patches, keep the targeted rerun and also run `make backend-static-verify` before pushing follow-up commits.
- Tier 3 (PR/final gate): run canonical broad verify targets for affected surfaces (`make backend-verify`, `make frontend-verify`, `make verify` as applicable).
- Tier 4 (operator-only heavy): live/provider/manual or unusually expensive checks only when explicitly required.
- Docs-only or non-backend-only changes do not require backend static verification.

### Agent execution: backend tests vs sandboxes

Backend integration tests are **not** in-process unit stubs: `backend/conftest.py` builds an async engine to `**TEST_DATABASE_URL`** (defaults to **PostgreSQL on `localhost:5432`**). Session fixtures create a test schema and tables. **Any** shell that cannot reach that database will error during **setup** → pytest shows `**E` (error)** for most tests, often for **every** test, with **no** failed assertions yet.

This applies to **network-isolated agent runs** (Cursor sandbox, VS Code / Copilot / Codex agent terminals with sandboxing, some CI agents without a service container, etc.). **Outside sandbox** (or on the developer’s host terminal with Postgres up), the same command usually **passes**.

**Do:**

- Use `cd backend && .venv/bin/pytest ...` for targeted backend behavior runs, pair backend code changes with `make backend-static-verify` before push, and reserve `make backend-verify` for Tier 3 broad gates — never bare `pytest` (wrong interpreter / deps).
- When running from an **agent**, assume sandbox **until proven otherwise**. If you see all-`E` or hang at startup/collection, **stop** and either escalate to a **non-sandboxed** run with **localhost network**, or ask the **human** to run the exact command and paste the traceback.
- Confirm failures with `-x --tb=short` once before declaring product bugs.

**Do not:**

- Do not run live/provider-backed verification targets from agent sessions (for example `make extraction-live`); ask the human operator to run them manually and share output.
- Do not loop many pytest retries inside a sandbox that cannot reach Postgres.

Other notes:

- Do not run bare `pytest` from agent sessions. Use `make backend-verify` for broad backend verification, or `cd backend && .venv/bin/pytest ...` for targeted backend tests so the repo venv is used consistently.
- Backend pytest depends on host-local services in this repo's test harness (see `backend/conftest.py`). When backend tests are needed from an agent session, prefer an escalated run outside the sandbox over repeated retries inside the network-isolated sandbox.
- If sandboxed backend pytest hangs during startup, collection, or before first assertion, treat sandbox/service access as the default suspect and verify that path before debugging application code.

### Makefile Verification Contract (Recommended)

If the repo uses `make` for verification, standardize on these targets:

- `make verify` (full verification aggregator)
- `make backend-verify` (backend lint/type-check/tests/security checks as applicable)
- `make frontend-verify` (frontend type-check/tests/lint/build as applicable)
- `make db-verify` (migrations/schema checks when applicable)
- `make template-verify` (template-level checks such as unresolved-token guard)

Contract rules:

- Targets must be deterministic, non-interactive, and fail-fast (non-zero exit on failure).
- CI should run the same `make` targets used locally.
- Keep target names and scope stable; if changed, update README + workflow docs in the same Task.

### Full Verification

```bash
make verify
```

### Frontend Verification

```bash
make frontend-verify
```

The frontend gate checks application code with `tsconfig.json`, then the actual Vite build and Vitest test options with `tsconfig.node.json`. The shared config uses each tool's own API types; ESLint checks `src/` and `vite.config.ts` with their browser and Node environments respectively.

Both TypeScript projects use `skipLibCheck` for dependency declarations, including unused optional PWA tooling types. Application and configuration expressions still receive strict checking; this setting does not exclude invalid Vite, PWA or Vitest options.

When running the constituent commands directly, preserve the gate's order and fail-fast behavior:

```bash
bash scripts/check_file_sizes.sh --scope frontend && \
cd frontend && npx tsc --noEmit && npx tsc --project tsconfig.node.json --noEmit && npx eslint src/ vite.config.ts && npx vitest run && npm run build
```

### Mobile Verification

The sibling Flutter client uses Flutter 3.47.9 / Dart 3.13.7. From the repository
root on Windows, run `powershell -NoProfile -File scripts/mobile-verify.ps1` with
the pinned SDK on PATH. The script rejects an SDK mismatch before checks, then
runs enforced-lockfile dependency resolution, format, analyze, widget tests, and
an Android debug APK build, stopping on the first failure.

See [mobile setup and direct commands](../../mobile/README.md) for other hosts,
Android launch, and the required macOS/Xcode and iPhone development-signing proof.
Generated iOS source has no compile or runtime verification from Windows. Existing
web/backend gates remain separate; this entrypoint does not establish mobile CI.

### Backend Verification

```bash
cd backend && ruff check . && mypy . && bandit -r app/ && pytest
```

### Database Verification

```bash
cd backend && alembic upgrade head
```

### Verification Baseline Expectations

- Backend: boundary guardrail check + lint + type-check + tests + security scan.
- Frontend: type-check + tests + lint + production build.
- No-contract refactors: include parity lock results in final verification summary.
- Template maintenance: unresolved-token guard passes (`./scripts/check-unresolved-template-tokens.sh`).
