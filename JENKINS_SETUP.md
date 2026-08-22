# Jenkins CI/CD setup

This repo's `Jenkinsfile` assumes a Jenkins instance already running on your VPS, configured as follows.

## 1. Jenkins agent prerequisites

The machine running the Jenkins agent (built-in node is fine for a single VPS) needs:

- **Node.js** matching `package.json`'s `engines.node` (`>=22.12.0`) on `PATH`
- **Docker CLI + buildx**, with the Jenkins user able to reach the Docker daemon (either Jenkins runs directly on the VPS with its user in the `docker` group, or Jenkins itself runs in a container with the host's Docker socket mounted in)

## 2. Jenkins plugins

- **Pipeline** (ships by default with most Jenkins installs)
- **Git** / **GitHub Branch Source** — needed for the Multibranch Pipeline job type below
- **Credentials Binding** — for `withCredentials`, used in the push stage

## 3. Docker Hub credential

Create a Jenkins credential yourself (never share the raw value with me):

1. Jenkins → **Manage Jenkins** → **Credentials** → (a suitable store/domain) → **Add Credentials**
2. Kind: **Username with password**
3. Username: your Docker Hub username (`asiqurrahman`)
4. Password: a **Docker Hub Personal Access Token** (Docker Hub → Account Settings → Security → New Access Token) — not your account password
5. ID: `dockerhub-credentials` (the `Jenkinsfile` references this exact ID)

## 4. Job: Multibranch Pipeline

The `Jenkinsfile`'s `when { branch 'production' }` conditions require a **Multibranch Pipeline** job (not a plain Pipeline job):

1. Jenkins → **New Item** → **Multibranch Pipeline**
2. Branch source: Git (or GitHub), pointed at `https://github.com/asiqur-rahman/OpenHands-contrib.git`
3. Build configuration: **by Jenkinsfile**, path `Jenkinsfile` (default)
4. Save — Jenkins scans branches and creates a sub-job per branch it finds (e.g. `production`)

## 5. Trigger on push

Either:

- **Webhook (recommended, near-instant):** GitHub repo → Settings → Webhooks → Add webhook → Payload URL `http://<your-vps>:<jenkins-port>/github-webhook/`, content type `application/json`, event: **Just the push event**. Requires your VPS's Jenkins port reachable from GitHub (a public IP/domain, or a tunnel).
- **Polling (no inbound access needed):** on the Multibranch Pipeline job, enable **Scan Multibranch Pipeline Triggers** → periodically (e.g. every 5 minutes) instead of a webhook, if your VPS isn't publicly reachable.

## What the pipeline actually does

Every push to any branch: install, lint, build — fully automatic, no approval needed. `npm test` is expected to be run locally before pushing to `production`, not in CI.

Push to `production` specifically, additionally:
1. Suggests the next version (reads Docker Hub's existing tags, bumps the patch — same logic as `make push`)
2. **Pauses and waits for a human to click "Push" in the Jenkins UI**, showing the suggested version (editable) before anything happens
3. If nobody clicks "Push" (or clicks "Abort") within **15 minutes**, the push is skipped and the build ends as `ABORTED` — it does not fail, and it does not push
4. Only after approval within that window: builds fresh and pushes `asiqurrahman/openhands-canvas:production` + `:VERSION` to Docker Hub

## Honesty check

I wrote and carefully reviewed this `Jenkinsfile` for correctness (agent placement, credential binding, the `input()` step's return-value quirk with a single parameter, why the executor-blocking pitfall needed fixing), but **I have not run it against a real Jenkins instance** — I don't have one available to test against from here. First real run should be watched, not assumed to work.
