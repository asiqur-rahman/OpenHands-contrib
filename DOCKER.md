# Docker (personal use)

Two stacks, one `Makefile`, one Docker Compose project (`openhands-canvas`):

| Command | What it runs | Config |
|---|---|---|
| `make up` | Production-grade build: the real multi-service image (`docker/Dockerfile`) — agent-server + automation + prebuilt static frontend, unified behind one port. Built from this local checkout via the project's own `scripts/docker-build.mjs`. | `docker-compose.prod.yml` |
| `make dev` | Local dev stack: hot-reload frontend, live agent-server via `uvx`, source bind-mounted in. | `docker-compose.yml` |
| `make down` | Stop whichever stack is running. | both |
| `make clean` | Stop and remove volumes (settings, conversations, `/projects` data wiped). | both |
| `make logs` | Tail logs for whichever stack is running. | both |

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

## Notes

- Both stacks share one Compose project name (`openhands-canvas`), so `make down` / `make clean` stop whichever one you last started — no need to remember which.
- `make up` always rebuilds the image from current source before running, so it reflects your latest local changes, not a cached or published tag.
