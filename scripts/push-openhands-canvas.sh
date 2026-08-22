#!/usr/bin/env bash
# Push asiqurrahman/openhands-canvas :latest + :VERSION to Docker Hub.
# Invoked by: make push   (or make push-check for a dry-run preflight)
#
# Version is never hardcoded. In a console, make push always prompts,
# suggesting the next patch after the newest semver tag already on Docker
# Hub. Override without prompting: make push VERSION=x.y.z
#
# Adapted from the same pattern used in the nirman repo's push-nirman.sh,
# simplified for this project's single production image
# (docker/Dockerfile) instead of multiple api/web/agent images.
#
# WSL/Ubuntu: make's default shell is dash — this script always runs under bash.
# Prompt reads from /dev/tty so it still works when make redirects stdin.

set -euo pipefail

IMAGE="${IMAGE:-asiqurrahman/openhands-canvas}"
# Set only when user passes: make push VERSION=x.y.z
CLI_VERSION="${CLI_VERSION:-}"
# amd64-only by default (fast, routine iteration, matches how the upstream
# ghcr.io/openhands/agent-canvas image itself is built in CI). Override for a
# QEMU-emulated multi-arch build in one go: make push PLATFORMS=linux/amd64,linux/arm64
PLATFORMS="${PLATFORMS:-linux/amd64}"
BUILDER_NAME="openhands-canvas-multiarch"

cd "$(dirname "$0")/.."

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "$*" >&2; }

preflight() {
  command -v docker >/dev/null 2>&1 || die "docker not found in PATH"
  docker info >/dev/null 2>&1 || die "Docker daemon not reachable. Start Docker Desktop / dockerd."
  command -v node >/dev/null 2>&1 || die "node not found in PATH (needed to read config/defaults.json)"
  if [ ! -f "${HOME}/.docker/config.json" ]; then
    die "Not logged in to Docker Hub. Run: docker login"
  fi
  if ! grep -Eq '"auths"|"credsStore"|"credHelpers"' "${HOME}/.docker/config.json" 2>/dev/null; then
    die "Docker config has no credentials. Run: docker login"
  fi
}

# Best-effort only — network/rate-limit must never abort push.
list_hub_semver() {
  local raw=""
  raw="$(curl -fsS -m 10 \
    "https://hub.docker.com/v2/repositories/${IMAGE}/tags/?page_size=100" 2>/dev/null || true)"
  [ -n "$raw" ] || return 0
  printf '%s' "$raw" \
    | grep -oE '"name":"[^"]*"' \
    | sed -E 's/"name":"([^"]*)"/\1/' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || true
}

is_semver() {
  printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# Suggest next patch after Hub's newest tag (1.14.0 → 1.14.1). Fallback to
# this checkout's own package.json version (config/defaults.json versions.agentCanvas).
suggest_next() {
  local last="$1" major minor patch
  if [ -z "$last" ]; then
    node -e "console.log(require('./config/defaults.json').versions.agentCanvas)"
    return 0
  fi
  IFS=. read -r major minor patch <<<"$last"
  printf '%s.%s.%s' "$major" "$minor" "$((patch + 1))"
}

# Logs → stderr; chosen version alone on stdout.
pick_version() {
  local pushed last suggest version input=""
  local -a tags=()

  mapfile -t tags < <(list_hub_semver | sort -V)
  if [ "${#tags[@]}" -gt 0 ]; then
    pushed="$(printf '%s ' "${tags[@]}" | sed 's/[[:space:]]*$//')"
    last="${tags[-1]}"
  else
    pushed=""
    last=""
  fi
  suggest="$(suggest_next "$last")"

  if [ -n "$pushed" ]; then
    info "Semver tags on Docker Hub (${IMAGE}): ${pushed}"
    info "Most recent: ${last}"
  else
    info "No semver tags found on Docker Hub yet (or offline/rate-limited)."
  fi

  # Explicit override skips the prompt.
  if [ -n "$CLI_VERSION" ]; then
    version="$CLI_VERSION"
    info "Using VERSION from command line: ${version}"
    is_semver "$version" || die "VERSION must look like x.y.z (got: ${version})"
    printf '%s' "$version"
    return 0
  fi

  # Always ask in a real console (read the controlling TTY — works under make).
  if [ -e /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    info "Enter the version to tag & push (immutable snapshot alongside :latest)."
    printf "Version to tag & push [%s]: " "$suggest" >/dev/tty
    input=""
    # Do not let a failed read abort the script (set -e).
    IFS= read -r input </dev/tty || true
    version="${input:-$suggest}"
  else
    die "No console TTY to ask for VERSION. Re-run in a terminal, or: make push VERSION=x.y.z"
  fi

  is_semver "$version" || die "VERSION must look like x.y.z (got: ${version})"
  printf '%s' "$version"
}

is_multi_platform() {
  case "$PLATFORMS" in
    *,*) return 0 ;;
    *) return 1 ;;
  esac
}

# Idempotent: creates the builder only if it doesn't already exist.
ensure_buildx_builder() {
  docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1 \
    || docker buildx create --name "$BUILDER_NAME" --driver docker-container >/dev/null \
    || die "Failed to create buildx builder '${BUILDER_NAME}'"
  docker buildx use "$BUILDER_NAME"
  docker buildx inspect --bootstrap >/dev/null \
    || die "Failed to bootstrap buildx builder '${BUILDER_NAME}'"
}

# Confirms the pushed manifest actually contains every requested platform —
# catches a silent single-arch fallback from a slipped flag.
verify_platforms() {
  local tag="$1" out p
  out="$(docker buildx imagetools inspect "${IMAGE}:${tag}" 2>&1)" \
    || die "imagetools inspect failed for ${IMAGE}:${tag}"
  IFS=',' read -ra want <<<"$PLATFORMS"
  for p in "${want[@]}"; do
    printf '%s' "$out" | grep -qF "$p" \
      || die "${IMAGE}:${tag} is missing platform ${p} (manifest list incomplete)"
  done
}

# Same build args scripts/docker-build.mjs derives from config/defaults.json,
# so the pushed image stays pinned to the same agent-server/automation
# versions as a local `make up` — never hand-duplicated here.
read_build_args() {
  node -e "
    const c = require('./config/defaults.json');
    console.log(\`\${c.images.agentServer}:\${c.versions.agentServer}-python\`);
    console.log(c.versions.automation);
    console.log(c.paths.canvasBasePath);
  "
}

build_and_push() {
  local version="$1"
  local -a build_info
  local agent_server_image automation_version base_path git_sha git_ref
  mapfile -t build_info < <(read_build_args)
  agent_server_image="${build_info[0]}"
  automation_version="${build_info[1]}"
  base_path="${build_info[2]}"

  git_sha="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  git_ref="$(git branch --show-current 2>/dev/null || echo unknown)"

  info "Agent Server image : ${agent_server_image}"
  info "Automation version : ${automation_version}"
  info "Canvas base path   : ${base_path}"
  info "Build git ref/sha  : ${git_ref}@${git_sha}"

  docker buildx build \
    --platform "$PLATFORMS" \
    --no-cache \
    --build-arg "AGENT_SERVER_IMAGE=${agent_server_image}" \
    --build-arg "AUTOMATION_VERSION=${automation_version}" \
    --build-arg "VITE_BASE_PATH=${base_path}" \
    --build-arg "AGENT_CANVAS_VERSION=${version}" \
    --build-arg "OPENHANDS_BUILD_GIT_SHA=${git_sha}" \
    --build-arg "OPENHANDS_BUILD_GIT_REF=${git_ref}" \
    -t "${IMAGE}:latest" -t "${IMAGE}:${version}" \
    -f docker/Dockerfile \
    --push \
    . \
    || die "buildx build failed for ${IMAGE}"
}

push_image() {
  local version="$1"

  info "Using version: ${version}"
  case "$(pwd -P)" in
    /mnt/*)
      info "WARNING: build path is under /mnt (WSL 9p). If context transfer hangs, copy to \$HOME and rebuild."
      ;;
  esac

  if is_multi_platform; then
    info "Multi-platform build requested (${PLATFORMS})."
    ensure_buildx_builder
  fi

  info "Building + pushing (--no-cache, platforms: ${PLATFORMS})..."
  build_and_push "$version"

  info "Verifying pushed manifest lists every requested platform..."
  verify_platforms latest
  verify_platforms "$version"

  info "Pushed ${IMAGE}:latest and ${IMAGE}:${version} (${PLATFORMS})."
  info "On the target host: docker run -p 8000:8000 -v ~/.openhands:/home/openhands/.openhands -v ~/projects:/projects ${IMAGE}:${version}"
}

self_test() {
  local fails=0 v=""

  command -v docker >/dev/null || { echo "FAIL: docker missing"; fails=$((fails + 1)); }
  docker info >/dev/null 2>&1 || { echo "FAIL: docker daemon"; fails=$((fails + 1)); }
  command -v node >/dev/null || { echo "FAIL: node missing"; fails=$((fails + 1)); }
  [ -f "${HOME}/.docker/config.json" ] || { echo "FAIL: no docker login config"; fails=$((fails + 1)); }
  grep -Eq '"auths"|"credsStore"|"credHelpers"' "${HOME}/.docker/config.json" 2>/dev/null \
    || { echo "FAIL: docker config has no credentials"; fails=$((fails + 1)); }

  list_hub_semver >/dev/null || { echo "FAIL: list_hub_semver exited non-zero"; fails=$((fails + 1)); }
  echo "hub_lookup_ok"

  v="$(suggest_next "1.14.0")"
  [ "$v" = "1.14.1" ] || { echo "FAIL: suggest_next 1.14.0 → expected 1.14.1 got '$v'"; fails=$((fails + 1)); }
  echo "suggest_next_ok"

  v="$(CLI_VERSION=9.9.9 pick_version </dev/null)"
  [ "$v" = "9.9.9" ] || { echo "FAIL: CLI_VERSION expected 9.9.9 got '$v'"; fails=$((fails + 1)); }
  echo "cli_version_ok"

  if ( CLI_VERSION='9.9.9-test' pick_version </dev/null >/dev/null 2>&1 ); then
    echo "FAIL: accepted junk CLI version"
    fails=$((fails + 1))
  else
    echo "reject_junk_version_ok"
  fi

  [ -f docker/Dockerfile ] || { echo "FAIL: missing docker/Dockerfile"; fails=$((fails + 1)); }
  [ -f config/defaults.json ] || { echo "FAIL: missing config/defaults.json"; fails=$((fails + 1)); }
  echo "files_ok"

  docker buildx version >/dev/null 2>&1 || { echo "FAIL: docker buildx not available"; fails=$((fails + 1)); }
  echo "buildx_available_ok"

  if [ "$fails" -eq 0 ]; then
    echo "SELF_TEST_PASS"
    exit 0
  fi
  echo "SELF_TEST_FAIL count=$fails"
  exit 1
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  *)
    preflight
    push_image "$(pick_version)"
    ;;
esac
