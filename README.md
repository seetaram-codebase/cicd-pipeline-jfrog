# JFrog × Jenkins container pipeline demo — infra

Scaffold for the container CI/CD showcase (see `jfrog-agenda.txt`). This
repo is the **infra half**: Terraform to host Jenkins on a single EC2
instance. The application half — a sample FastAPI app, its `Jenkinsfile`,
and `scripts/break-the-build.sh` — lives in a separate repo:
[fastapi-jfrog-demo](https://github.com/seetaram-codebase/fastapi-jfrog-demo).
That's what the Jenkins job actually builds; this repo just stands up
Jenkins itself.

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

## The app's own infra: `infra/app-ecs/`

A second, independent Terraform module — own Terraform Cloud workspace
(`jfrog-demo-app`), own GitHub Actions workflow
(`.github/workflows/app-infrastructure.yml`), applied the same way as
Jenkins' infra (Actions tab → plan, then apply). It stands up what the
Jenkinsfile's `Deploy to ECS production` stage targets:

- ECS cluster `jfrog-demo-app` with a single EC2 container instance
  (same "one box" choice as Jenkins, not Fargate) running the `shipit`
  task, `desired_count = 1`.
- An ALB in front for a stable public URL — `terraform output app_url`.
- A Secrets Manager entry for the ECS task execution role's
  `repositoryCredentials`, so it can pull from `artifact-release` — the
  value isn't set by Terraform, see `infra/app-ecs/outputs.tf`'s
  `next_steps` output after apply.

The task definition starts pointed at a placeholder image
(`shipit:bootstrap`, which doesn't exist) — expected. The first
successful `master`-branch Jenkins run registers a real revision with a
real image tag and updates the service; that's when a task actually
starts.

## Not yet built

- Artifactory repos and Xray watches/policies — created in the JFrog UI,
  not Terraform (see steps below).

## Setup order

1. **JFrog Cloud** — confirm your trial/tier includes Xray, then create
   two Docker repos: `artifact-sandbox`, `artifact-release`.
   Attach an Xray watch + policy to each per the gate table in `SPEC.md`
   (both block Critical/High — passing the release-repo gate is what
   lets a build reach production).

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

4. **Edit `fastapi-jfrog-demo`'s `Jenkinsfile`** — replace `JF_URL`,
   `DOCKER_REGISTRY`, and `ECS_CLUSTER` placeholders with real values.

5. **Create a Jenkins Multibranch Pipeline** job pointing at
   `fastapi-jfrog-demo` (not this repo — a plain Pipeline job won't
   populate `env.BRANCH_NAME`, which the branch-routing logic needs), wire
   the GitHub webhook to `http://<jenkins-ip>:8080/github-webhook/`.

6. **Dry run.** Push to `fastapi-jfrog-demo`'s `feature/vulnerable-demo`
   branch, watch the pipeline build into `artifact-sandbox` with the
   deliberately outdated base image (`base-image.env` pinned to
   `3.9-slim-buster`) and get blocked at the Xray gate. `master` is
   pinned to a patched base image, so pushing there demonstrates the
   clean, auto-deployed path instead.

7. **Run `fastapi-jfrog-demo`'s `scripts/break-the-build.sh`**, commit,
   push — switches to a patched base image, re-run clears the gate. Then
   push the same fix to `master` to see it build straight into
   `artifact-release` and auto-deploy. This is the live-demo beat:
   broken → fixed, same pipeline, no code changes besides the base image.
