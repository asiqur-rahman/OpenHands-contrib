COMPOSE := docker compose -p openhands-canvas -f docker-compose.yml -f docker-compose.prod.yml

.PHONY: up down clean dev logs push push-check

# Build the production image (docker/Dockerfile, via the project's own build
# helper so version pins stay in sync with config/defaults.json) and run it.
up:
	mkdir -p data/openhands data/projects
	node scripts/docker-build.mjs --tag openhands-canvas:local
	$(COMPOSE) --profile prod up -d
	@echo "✓ Started. Access: http://localhost:8000/canvas"

# Development stack: builds the local dev Dockerfile (npm run dev, hot
# reload, source bind-mounted in) and runs it.
dev:
	$(COMPOSE) --profile dev up -d --build
	@echo "✓ Started. Access: http://localhost:8000"

# Stop containers (whichever stack is running).
down:
	$(COMPOSE) down
	@echo "✓ Stopped"

# Stop containers and remove volumes.
clean:
	$(COMPOSE) down -v
	@echo "✓ Cleaned"

# Watch logs (whichever stack is running).
logs:
	$(COMPOSE) logs -f

# Build the production image fresh (--no-cache) from this checkout and push
# it to Docker Hub as :latest + :VERSION. Prompts for VERSION on the console
# (suggests the next patch after Docker Hub's newest tag); skip the prompt
# with: make push VERSION=x.y.z
# Requires `docker login` to have been run already — never enters credentials.
push:
	@CLI_VERSION="$(if $(filter command line,$(origin VERSION)),$(VERSION),)" \
		PLATFORMS="$(PLATFORMS)" \
		bash scripts/push-openhands-canvas.sh

# Verify push preflight (docker, buildx, login, config files) without
# building or pushing anything.
push-check:
	@bash scripts/push-openhands-canvas.sh --self-test
