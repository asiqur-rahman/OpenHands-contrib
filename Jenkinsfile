// CI/CD for the OpenHands Agent Canvas fork, hosted on a self-managed Jenkins
// (VPS). Requires a Multibranch Pipeline job pointed at this repo so
// `branch 'production'`-gated stages only run for that branch.
//
// Every push: checkout, install, lint, build (fully automatic). Vitest is
// run locally before pushing, not in CI.
// production branch only: an approval gate pauses the pipeline in the
// Jenkins UI before anything is pushed to Docker Hub -- nothing publishes
// without a human clicking Push within 15 minutes. Letting that window
// pass (or clicking Abort) skips the push instead of failing the build.
//
// Requires on the Jenkins agent:
//   - A NodeJS tool installation named node-22.12.0 (Manage Jenkins > Tools
//     > NodeJS installations), matching package.json's engines.node. Every
//     stage below declares its own `tools { nodejs 'node-22.12.0' }` --
//     `agent any` per stage means PATH changes from `tools` don't persist
//     across stages even on a single-agent Jenkins, so it can't be declared
//     once at the pipeline level here.
//   - Docker CLI + buildx, with the Jenkins user able to reach the daemon
//   - A "Username with password" credential named dockerhub-credentials
//     (Docker Hub username + a Personal Access Token, not your account
//     password) -- create this in Jenkins yourself; the pipeline only
//     references it by ID, never touches the raw values in code.
// See JENKINS_SETUP.md for the one-time setup this Jenkinsfile assumes.

pipeline {
  // No default agent: the approval stage below deliberately runs with
  // `agent none` so a pending manual approval never holds a Jenkins
  // executor hostage (a well-known input-step pitfall). Every other stage
  // declares `agent any` itself instead. A single-VPS Jenkins has one
  // agent regardless, so the workspace is shared across stages without
  // needing stash/unstash.
  agent none

  options {
    disableConcurrentBuilds()
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
  }

  stages {
    stage('Install') {
      agent any
      tools { nodejs 'node-22.12.0' }
      // The Jenkins container itself is cgroup-limited to 2GB total
      // (confirmed via /sys/fs/cgroup/memory.max = 2147483648 through the
      // Script Console -- free -m / /proc/meminfo inside this container
      // misleadingly report the HOST's 11.9GB, not this cgroup cap).
      // npm ci's postinstall scripts spawn their own node subprocesses,
      // which by default size their heap off whatever memory Node
      // detects -- the host's 11.9GB, not the real 2GB ceiling -- so cap
      // it explicitly here too, not just in the stages below.
      environment { NODE_OPTIONS = '--max-old-space-size=1280' }
      steps {
        sh 'npm ci'
      }
    }

    stage('Lint') {
      agent any
      tools { nodejs 'node-22.12.0' }
      // Container raised to 4GB (was 2GB when Install's 1280 was chosen).
      // Confirmed on the previous run: tsc hit exactly the 1280MB ceiling
      // ("1268.9 -> 1311.3 MB") as a graceful V8 heap-limit error, not a
      // container-level SIGKILL -- it genuinely needs more than 1280MB,
      // just not 4096MB as the very first (pre-cgroup-check) attempt used.
      // 3072 leaves ~1GB of the container's 4GB for Jenkins' own JVM + OS.
      environment { NODE_OPTIONS = '--max-old-space-size=3072' }
      steps {
        sh 'npm run lint'
      }
    }

    stage('Build') {
      agent any
      tools { nodejs 'node-22.12.0' }
      environment { NODE_OPTIONS = '--max-old-space-size=3072' }
      steps {
        sh 'npm run build'
      }
    }

    stage('Suggest version') {
      agent any
      // scripts/push-openhands-canvas.sh --suggest-version falls back to
      // `node -e ...` against config/defaults.json when Docker Hub has no
      // semver tags yet, so this stage needs Node on PATH too.
      tools { nodejs 'node-22.12.0' }
      when {
        branch 'production'
      }
      steps {
        script {
          env.SUGGESTED_VERSION = sh(
            script: 'bash scripts/push-openhands-canvas.sh --suggest-version',
            returnStdout: true
          ).trim()
        }
      }
    }

    stage('Approve Docker Hub push') {
      // No agent: this stage only waits on a human via input() and holds
      // no executor while it does.
      agent none
      when {
        branch 'production'
      }
      steps {
        // Pauses here until a human approves in the Jenkins UI -- lint
        // and build above already ran unattended; only the publish step
        // waits on a person. A single input() parameter returns its raw
        // value directly (not a map) -- must capture it explicitly or
        // RELEASE_VERSION would be empty in the next stage.
        //
        // Wrapped in its own timeout so silence has a safe default: no
        // approval within 15 minutes means "don't push", not "wait
        // forever" (the input step has no deadline of its own) and not
        // "fail the build" (the pipeline's own 45-minute timeout would
        // otherwise eventually abort the whole run). Catching the
        // interruption here and leaving RELEASE_VERSION unset lets the
        // next stage's `when` skip the push cleanly instead.
        script {
          try {
            timeout(time: 15, unit: 'MINUTES') {
              env.RELEASE_VERSION = input(
                message: "Push asiqurrahman/openhands-canvas to Docker Hub as :production + :${env.SUGGESTED_VERSION}?",
                ok: 'Push',
                parameters: [
                  string(
                    name: 'RELEASE_VERSION',
                    defaultValue: env.SUGGESTED_VERSION,
                    description: 'Version tag to push (semver x.y.z). Leave as suggested unless you need a specific bump.'
                  )
                ]
              )
            }
          } catch (err) {
            env.RELEASE_VERSION = null
            currentBuild.result = 'ABORTED'
            echo 'No approval within 15 minutes (or approval was declined) -- skipping the Docker Hub push.'
          }
        }
      }
    }

    stage('Push to Docker Hub') {
      agent any
      // read_build_args() inside the push script calls `node -e` to read
      // config/defaults.json.
      tools { nodejs 'node-22.12.0' }
      when {
        allOf {
          branch 'production'
          expression { return env.RELEASE_VERSION != null }
        }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub-credentials',
          usernameVariable: 'DOCKERHUB_USERNAME',
          passwordVariable: 'DOCKERHUB_TOKEN'
        )]) {
          sh '''
            set -euo pipefail
            echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
            CLI_VERSION="${RELEASE_VERSION}" bash scripts/push-openhands-canvas.sh
          '''
        }
      }
      // Stage-level post, not pipeline-level: the pipeline's top-level
      // `agent none` means a top-level post has no agent to run `sh` on.
      // This stage's own `agent any` gives this post a valid context.
      post {
        always {
          sh 'docker logout || true'
        }
      }
    }
  }
}
