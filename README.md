# JFrog × Jenkins container pipeline demo

Scaffold for the container CI/CD showcase (see `jfrog-agenda.txt`). A sample
FastAPI app, a Jenkinsfile that builds it, scans it with Xray, and promotes
it through `docker-dev-local` → `docker-staging-local` → `docker-release-local`,
and the Terraform to host Jenkins.

## Architecture note: two hosts, not one

The Jenkins **controller** runs on ECS Fargate (`infra/jenkins-ecs/`) —
public, reachable by GitHub's webhook, no tunnel needed. But **Fargate
disallows privileged containers**, so it cannot run `docker build` itself.
A small EC2 instance (`infra/jenkins-ecs/agent-ec2.tf`) is the actual build
agent — real Docker daemon, `jf` CLI, `aws` CLI. The Jenkinsfile pins its
stages to `agent { label 'build' }`, which runs there.

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

2. **Jenkins infrastructure**
   ```
   cd infra/jenkins-ecs
   cp terraform.tfvars.example terraform.tfvars   # edit as needed
   terraform init
   terraform apply
   ```
   Read the `next_steps` output when it finishes — it has the controller
   URL, the build agent's IP, and the manual node-attach step.

3. **Jenkins UI** — unlock, install suggested plugins + the JFrog plugin,
   create an admin user, attach the EC2 build agent as a node labeled
   `build`, add a `jfrog-access-token` (Secret text) credential.

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
