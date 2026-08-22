# Docker (personal use)

Two stacks, one `Makefile`, one Docker Compose project (`openhands-canvas`):

| Command | What it runs | Config |
|---|---|---|
| `make up` | Production-grade build: the real multi-service image (`docker/Dockerfile`) — agent-server + automation + prebuilt static frontend, unified behind one port. Built from this local checkout via the project's own `scripts/docker-build.mjs`. | `docker-compose.prod.yml` |
| `make dev` | Local dev stack: hot-reload frontend, live agent-server via `uvx`, source bind-mounted in. | `docker-compose.yml` |
| `make down` | Stop whichever stack is running. | both |
| `make clean` | Stop and remove volumes (settings, conversations, `/projects` data wiped). | both |
| `make logs` | Tail logs for whichever stack is running. | both |
| `make push` | Build fresh (`--no-cache`) and push `asiqurrahman/openhands-canvas` to Docker Hub as `:production` + `:VERSION`. | `scripts/push-openhands-canvas.sh` |
| `make push-check` | Preflight only — docker/buildx/login/config checks, no build or push. | `scripts/push-openhands-canvas.sh --self-test` |

## `make up` — production

```bash
make up
```

Builds the image tagged `openhands-canvas:local` from this checkout (so any local code changes are baked in), then runs it. Access at **http://localhost:8000/canvas**.

Data persists across restarts in `./data/openhands` (settings, secrets, conversations) and `./data/projects` (the workspace the agent can read/edit) — both gitignored. `make clean` wipes them; plain `make down` / `make up` again does not.

## `make dev` — development

```bash
make dev
```

Runs the frontend dev server + agent-server + automation backend live, with this checkout bind-mounted for hot reload. Access at **http://localhost:8000**.

## `make push` — publish to Docker Hub

```bash
make push               # prompts for a version, suggesting the next patch
make push VERSION=1.2.3 # skip the prompt
make push-check         # verify docker/buildx/login without building anything
```

Requires `docker login` to already be done — the script checks for existing credentials and refuses to run without them; it never enters credentials itself.

Every push tags and overwrites `asiqurrahman/openhands-canvas:production` (the rolling tag — always this fork's current build; deliberately not `:latest`, since that name would imply "the latest official OpenHands release," which this isn't) alongside an immutable `:VERSION` snapshot for rollback. `casaos-openhands-canvas.yml` and any personal deployment should reference `:production` so updates need only a re-pull, never a manifest edit; pin `:X.Y.Z` instead if you want to freeze on a known-good build.

## CasaOS

`casaos-openhands-canvas.yml` is a ready-to-import CasaOS App Store manifest for the image `make push` publishes. Not yet verified against a real CasaOS instance — test an import before relying on it.

## Notes

- Both stacks share one Compose project name (`openhands-canvas`), so `make down` / `make clean` stop whichever one you last started — no need to remember which.
- `make up` always rebuilds the image from current source before running, so it reflects your latest local changes, not a cached or published tag.
- `make up`'s local image (`openhands-canvas:local`) and `make push`'s published image (`asiqurrahman/openhands-canvas:production`) are built the same way but are separate tags — pushing doesn't affect your local `make up`, and vice versa.
