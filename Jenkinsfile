// CI/CD for the OpenHands Agent Canvas fork, hosted on a self-managed Jenkins
// (VPS). Requires a Multibranch Pipeline job pointed at this repo so
// `branch 'production'`-gated stages only run for that branch.
//
// Every push: checkout, install, lint, test, build (fully automatic).
// production branch only: an approval gate pauses the pipeline in the
// Jenkins UI before anything is pushed to Docker Hub -- nothing publishes
// without a human clicking Proceed.
//
// Requires on the Jenkins agent:
//   - Node.js (matching package.json's engines.node, >=22.12.0) on PATH
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
      steps {
        sh 'npm ci'
      }
    }

    stage('Lint') {
      agent any
      steps {
        sh 'npm run lint'
      }
    }

    stage('Test') {
      agent any
      steps {
        sh 'npm test'
      }
    }

    stage('Build') {
      agent any
      steps {
        sh 'npm run build'
      }
    }

    stage('Suggest version') {
      agent any
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
        // Pauses here until a human approves in the Jenkins UI -- lint,
        // test, and build above already ran unattended; only the publish
        // step waits on a person. A single input() parameter returns its
        // raw value directly (not a map) -- must capture it explicitly or
        // RELEASE_VERSION would be empty in the next stage.
        script {
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
      }
    }

    stage('Push to Docker Hub') {
      agent any
      when {
        branch 'production'
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
