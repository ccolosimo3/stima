# Demo Deployment Runbook

This runbook defines the cheap demo deployment contract for moving Stima off the
current GCP-backed runtime and onto Vercel Hobby, Render Free, and Neon Free.
It is a demo-only contract: no data migration, no Redis, no ARQ worker, no GCS,
no production guarantees.

Last platform limit review: 2026-05-23.

## Target Topology

| Surface | Target | Contract |
| --- | --- | --- |
| Frontend | Vercel Hobby | Static Vite app from `frontend/`, configured with `VITE_API_URL` pointing at the Render API. |
| Backend | Render Free web service | One public web service only. Do not create a Render worker, cron, Redis/Key Value, persistent disk, or one-off job path for the demo. |
| Database | Fresh Neon Free Postgres | New empty database. No GCP data import, no Render Postgres. |
| Background jobs | Inline mode | `JOB_EXECUTION_MODE=inline`; PDF and email initiation still return durable job records, but web requests run the handlers inline. |
| Cache/rate limits/idempotency | In-memory degraded mode | Leave `REDIS_URL` unset. State is process-local and resets on restart/spin-down. |
| Object storage | Render local filesystem | `STORAGE_BACKEND=local` with `LOCAL_STORAGE_ROOT` on Render's ephemeral filesystem. Logos and generated PDFs can disappear. |
| Providers | Optional | Extraction and email provider keys are intentionally optional. Setting them can create external API usage. |

Prefer a shared custom domain pair for auth, for example:

- Frontend: `https://demo.stima.example`
- Backend API: `https://demo-api.stima.example`

The default `*.vercel.app` + `*.onrender.com` pairing is useful for a very quick
smoke test, but it is not the preferred auth configuration because the CSRF
cookie cannot be shared across unrelated host families.

## Platform Limits And Hard Caps

Use the provider dashboards as the final source of truth before cutover. These
limits were checked against official docs on 2026-05-23.

| Provider | Current free/Hobby limits to watch | Demo risk |
| --- | --- | --- |
| Render Free web service | Free web services spin down after 15 minutes without inbound traffic and take about a minute to spin up again. Local filesystem changes are lost on redeploy, restart, or spin-down. Render grants 750 Free instance hours per workspace per month and suspends free web services if those hours run out. Free web services also lack persistent disks, scaling beyond one instance, one-off jobs, shell access, and some networking features. Source: [Render Free instances](https://render.com/docs/free). | Cold starts are expected. Uploaded logos and generated PDFs are disposable. Usage bursts or external API traffic can suspend the service. |
| Render Free Postgres | Free Render Postgres is limited to one active free database per workspace, 1 GB storage, 30-day expiry plus grace period, and no backups. Source: [Render Free Postgres](https://render.com/docs/free#free-postgres). | Do not use it. A demo database that expires or has no backups is worse than starting with Neon Free. |
| Render port binding | Render expects web services to bind `0.0.0.0` and recommends the `PORT` env var; the default expected port is `10000`, and the service fails deploy if Render cannot detect the bound port. Source: [Render web service port binding](https://render.com/docs/web-services#port-binding). | The current backend Dockerfile binds port `8000`. For this demo, set Render `PORT=8000`, or make a separate code change to honor `$PORT`. |
| Vercel Hobby | Included usage currently includes 4 Active CPU-hours, 360 GB-hours provisioned memory, 1 million invocations, 100 GB Fast Data Transfer, up to 10 GB Fast Origin Transfer, 6,000 build minutes, 1,000 image optimization source images, and 100 MB static file uploads. Source: [Vercel limits](https://vercel.com/docs/limits). Hobby deployments are paused when they exceed included free tier usage. Source: [Vercel plans](https://vercel.com/docs/plans#what-happens-when-i-reach-100-usage). | A static Vite app should mostly spend transfer/build budget, but unexpected functions, image optimization, or high traffic can pause the project. |
| Neon Free | Free currently includes 100 projects, 10 branches/project, 100 CU-hours/project/month, autoscaling up to 2 CU, scale-to-zero after 5 minutes, 0.5 GB storage/project, 5 GB public network transfer/month, 1 day monitoring retention, and a 6-hour restore window. Source: [Neon plans](https://neon.com/docs/introduction/plans). | Compute cold starts and small storage/egress are accepted. Treat restore as very short safety net, not a backup plan. |

Region choice:

- Prefer Render `Virginia, USA` and Neon `AWS US East (N. Virginia) - aws-us-east-1`.
- If a different Render region is chosen, choose the closest Neon region. Neon recommends placing the database close to the application server, and Render regions cannot be changed in place after service creation. Sources: [Neon regions](https://neon.com/docs/introduction/regions), [Render regions](https://render.com/docs/regions).

## Render Backend Setup

Create exactly one Render Free web service.

Recommended Docker setup:

- Repository: `odysian/stima`
- Root directory: `backend`
- Dockerfile path: `Dockerfile`
- Instance type: Free
- Health check path: `/health`
- Start command: use the Dockerfile `CMD`
- Environment variable `PORT=8000`

Do not start the worker command in demo mode:

```bash
.venv/bin/python -m arq app.worker.arq_worker.WorkerSettings
```

That command is for the queue worker runbook only. In demo mode the backend must
start only the web process and must not import/run the ARQ worker as a second
process.

### Backend Environment

Use this as the demo env contract. Values marked `replace` and the
`*.stima.example` domains are placeholders that must be generated for the actual
deployment.

```bash
# Core runtime
ENVIRONMENT=demo
DATABASE_URL=postgresql+asyncpg://replace-user:replace-password@replace-neon-host/replace-db?ssl=require
SECRET_KEY=replace-with-at-least-32-random-characters
APP_VERSION=demo

# Render port contract for the current backend/Dockerfile.
PORT=8000

# Frontend/API origin, host, and cookie contract for shared custom domains.
FRONTEND_URL=https://demo.stima.example
ALLOWED_ORIGINS=https://demo.stima.example
ALLOWED_HOSTS=demo-api.stima.example,replace-render-service.onrender.com
COOKIE_SECURE=true
COOKIE_HTTPONLY=true
COOKIE_SAMESITE=lax
COOKIE_DOMAIN=.stima.example

# Proxy and HTTPS redirect. Leave redirect off unless proxy headers are aligned.
ENABLE_HTTPS_REDIRECT=false
TRUSTED_PROXY_IPS=

# No Redis and no worker for the demo.
REDIS_URL=
JOB_EXECUTION_MODE=inline

# Local ephemeral storage for demo logos and PDF artifacts.
STORAGE_BACKEND=local
LOCAL_STORAGE_ROOT=/tmp/stima-storage
GCS_BUCKET_NAME=

# Optional provider usage. Leave blank to avoid external API calls.
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
RESEND_API_KEY=
EMAIL_FROM_ADDRESS=
EMAIL_FROM_NAME=
SUPPORT_CONTACT_RECIPIENT_EMAIL=

# Optional observability/admin.
SENTRY_DSN=
ADMIN_API_KEY=
```

Cookie fallback for default provider domains:

- If the frontend stays on `*.vercel.app` and the backend stays on `*.onrender.com`,
  use `COOKIE_DOMAIN=` and `COOKIE_SAMESITE=none`.
- That shape can pass a short login/manual-flow smoke test, but prefer shared
  custom domains before depending on refresh after page reloads.

Database URL note:

- Neon displays standard Postgres URLs with `sslmode=require`. The backend uses
  SQLAlchemy asyncpg URLs, so keep the app env in `postgresql+asyncpg://...`
  shape and keep SSL required for Neon. Neon connection string docs: [Connect to
  Neon](https://neon.com/docs/get-started-with-neon/connect-neon).

## Neon Database Setup

Create a fresh Neon project. Do not import GCP data.

1. Choose the region closest to Render, preferably `AWS US East (N. Virginia) - aws-us-east-1`.
2. Create the database and role for the demo.
3. Build the backend `DATABASE_URL` in the same format used by Render.
4. Run migrations against that fresh database from a trusted local shell:

```bash
cd backend
DATABASE_URL='postgresql+asyncpg://replace-user:replace-password@replace-neon-host/replace-db?ssl=require' \
  .venv/bin/alembic upgrade head
```

Do not run `make db-verify` from an agent session. This one-off migration command
is an operator cutover step against the fresh Neon database.

## Vercel Frontend Setup

Create one Vercel Hobby project for the frontend.

- Root directory: `frontend`
- Install command: `npm install`
- Build command: `npm run build`
- Output directory: `dist`
- Required env var:

```bash
VITE_API_URL=https://demo-api.stima.example
```

Use the Render API origin with no trailing slash. If a custom frontend domain is
used, update `FRONTEND_URL`, `ALLOWED_ORIGINS`, and cookie config on Render to
match it before running auth smoke tests.

## Accepted Demo Tradeoffs

- Cold starts are expected from Render Free web service spin-down and Neon
  scale-to-zero.
- Local logo and PDF files are ephemeral. They can be lost on Render restart,
  redeploy, or spin-down. Database rows remain, but file-backed public logo/PDF
  reads may fail until the logo is uploaded again or the PDF is regenerated.
- Rate limits, idempotency, and extraction quota state are in memory. They reset
  on restart and are not distributed. This is acceptable only because the demo
  uses one Render web process.
- Inline jobs run inside the web process. They preserve the job record contract,
  but long PDF/email work can make the initiating request slower than queue mode.
- Provider keys are optional. When set, extraction/transcription/email flows can
  spend Anthropic, OpenAI, or Resend usage.
- There are no production SLOs, backups, persistent object storage, Redis-backed
  controls, or worker isolation in this deployment.

## Manual Smoke Checklist

Run this after Render, Neon, and Vercel are configured.

- [ ] Health: `GET https://demo-api.stima.example/health` returns `200` with
  `status: "ok"`, `runtime_mode: "degraded_memory"`, and
  `queue_available: false`.
- [ ] Auth: register or log in from the Vercel frontend, reload the page, and
  confirm the app still loads the authenticated user. If mutating requests fail
  with CSRF errors after reload, fix `COOKIE_DOMAIN`, `COOKIE_SAMESITE`,
  `FRONTEND_URL`, and `ALLOWED_ORIGINS` before continuing.
- [ ] Manual quote creation: create or select a customer, create a manual quote,
  add at least one line item, save, and reload the quote detail/edit screen.
- [ ] PDF generation: generate a quote PDF and confirm the returned job reaches
  a terminal success state and the PDF can be downloaded.
- [ ] Public share: share the quote, open the copied frontend `/doc/{token}` URL
  in a private browser session, confirm public JSON renders, and confirm the raw
  backend `/share/{token}` PDF path works.
- [ ] Logo upload: upload a profile logo, confirm authenticated logo preview
  loads, then confirm the public shared document logo endpoint loads.
- [ ] Optional email: only if `RESEND_API_KEY` and sender env vars are set, send
  a quote email and confirm the inline email job succeeds. Expect external API
  usage.

## Cutover Decisions

- Wake-up/demo banner: do not add a banner before the initial cutover. The demo
  is founder/operator-led, and the accepted cold-start/file-loss behavior is
  documented here. Add a follow-up banner only if testers are invited without
  operator context or if cold starts create repeated confusion.
- GCP deploy workflow disposition: target manual-only for the demo cutover and
  do not add a Render deploy workflow in this runbook task. Before the cutover
  branch becomes the source of truth, remove the `push` trigger from
  `.github/workflows/backend-deploy.yml` or disable that workflow in GitHub so
  merges no longer auto-deploy to GCP. Keep
  `.github/workflows/backend-deploy-emergency.yml` manual-only unless production
  GCP rollback is explicitly retired.
- Render deployment flow: use Render's dashboard/Git integration for the demo
  web service. A repository-managed Render deploy workflow is a separate follow-up
  only if demo operations need repeatable CI-controlled deploys.
