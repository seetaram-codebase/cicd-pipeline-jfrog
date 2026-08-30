# JFrog × Jenkins container pipeline demo

Scaffold for the container CI/CD showcase (see `jfrog-agenda.txt`). A sample
FastAPI app, a Jenkinsfile that builds it, scans it with Xray, and promotes
it through `docker-dev-local` → `docker-staging-local` → `docker-release-local`,
and the Terraform to host Jenkins.

## Architecture note: one EC2 instance

Jenkins runs on a single EC2 instance (`infra/jenkins-ecs/agent-ec2.tf`) —
controller and build execution together. A real (non-Fargate) Docker
daemon lives on the same box, so pipeline stages just run on Jenkins'
**built-in node** — the Jenkinsfile's `agent { label 'build' }` is
satisfied by labeling that built-in node `build` (one-time UI step, see
below), no separate agent to attach. An Elastic IP keeps the address
stable across stops/restarts, so the GitHub webhook config doesn't break.

Tradeoff: `JENKINS_HOME` lives on the instance's local EBS volume, not a
separate durable store — if the instance is terminated, Jenkins config
(admin user, plugins, credentials) goes with it. Fine for this demo;
worth remembering if you start relying on it longer-term.

## Not yet built

- The app's own ECS services (`shipit-staging` / `shipit-production`) that
  the Jenkinsfile's deploy stages target — infra for those isn't scaffolded
  yet, so those two stages will fail until they exist.
- Artifactory repos and Xray watches/policies — created in the JFrog UI,
  not Terraform (see steps below).

## Setup order

1. **JFrog Cloud** — confirm your trial/tier includes Xray, then create
   three Docker repos: `docker-dev-local`, `docker-staging-local`,
   `docker-release-local`. Attach an Xray watch + policy per the gate table
   in the session runbook (Critical/High always blocks; Medium blocks only
   at the staging→release gate).

2. **Jenkins infrastructure — applied via GitHub Actions, not locally.**
   `infra/jenkins-ecs/providers.tf` uses a Terraform Cloud backend
   (org `agentic-ai-org`, workspace `jfrog-demo-jenkins` — change if that's
   not your org). `.github/workflows/infrastructure.yml` runs Terraform on
   a hosted GitHub runner. Before triggering it, add these repo secrets
   (Settings → Secrets and variables → Actions) — never commit these
   values anywhere:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `TF_API_TOKEN` (Terraform Cloud user API token)

   Then run the workflow: Actions tab → "Infrastructure - Terraform" →
   Run workflow → action = `plan` first to sanity-check, then again with
   `apply`. Check the run's Job Summary and the Terraform Cloud workspace
   for outputs — the Jenkins URL (Elastic IP).

3. **Jenkins UI** — unlock (initial admin password via SSM:
   `cat /var/lib/jenkins/secrets/initialAdminPassword`), install suggested
   plugins + the JFrog plugin, create an admin user, then Manage Jenkins >
   Nodes > built-in node > Configure > add label `build` so pipeline
   stages run on this same instance. Add a `jfrog-access-token`
   (Secret text) credential.

4. **Edit `Jenkinsfile`** — replace `JF_URL`, `DOCKER_REGISTRY`, and
   `ECS_CLUSTER` placeholders with real values.

5. **Push this repo to GitHub**, create a Jenkins pipeline job pointing at
   it, wire the GitHub webhook to `http://<jenkins-ip>:8080/github-webhook/`.

6. **Dry run.** Push a commit, watch the pipeline build `docker-dev-local`
   with the deliberately outdated base image (`app/base-image.env` starts
   on `3.9-slim-buster`) and get blocked at the Xray gate.

7. **Run `scripts/break-the-build.sh`**, commit, push — switches to a
   patched base image, re-run clears both gates. This is the live-demo
   beat: broken → fixed, same pipeline, no code changes besides the base
   image.

## Local dry run (no Jenkins)

```
cd app
docker build --build-arg PYTHON_VERSION=3.11-slim-bookworm -t shipit:local .
docker run -p 8000:8000 shipit:local
curl localhost:8000/version
```
