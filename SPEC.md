# Shipit Pipeline — End-to-End Spec

What happens, exactly, from `git push` to a running container in
production. Companion to `README.md` (setup steps) and `jfrog-agenda.txt`
(the session this demo supports).

## Components

| Component | Role | Defined in | Status |
|---|---|---|---|
| GitHub repo | source + webhook trigger | `github.com/seetaram-codebase/cicd-pipeline-jfrog` | **Live** |
| Jenkins controller | schedules pipeline, serves UI, webhook endpoint | `infra/jenkins-ecs/ecs.tf` (ECS Fargate) | Scaffolded, not applied |
| Jenkins build agent | runs `docker build` / `jf` / `aws` CLI | `infra/jenkins-ecs/agent-ec2.tf` (EC2) | Scaffolded, not applied |
| Terraform apply path | provisions the two above | `.github/workflows/infrastructure.yml`, state in Terraform Cloud (`agentic-ai-org` / `jfrog-demo-jenkins`) | Scaffolded — needs `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `TF_API_TOKEN` added as repo secrets, then run manually from the Actions tab |
| JFrog Artifactory | stores the image, 3 Docker repos | JFrog Cloud console | Not started |
| JFrog Xray | scans + gate policies | JFrog Cloud console | Not started |
| ECS staging service | runs `shipit` pre-prod | not yet scaffolded | Not started |
| ECS production service | runs `shipit` in prod | not yet scaffolded | Not started |
| GitHub webhook | fires Jenkins on push | GitHub repo settings | Not started (needs Jenkins IP first) |

Fargate can't run privileged containers, so the controller (Fargate) and
the agent (EC2, real Docker daemon) are deliberately two different hosts —
see `README.md` for why.

## End-to-end sequence

1. Developer commits and pushes to `master` on GitHub.
2. GitHub webhook `POST`s to `http://<jenkins-ip>:8080/github-webhook/`.
3. Jenkins controller (Fargate) picks it up, starts a `shipit` pipeline run,
   and dispatches every stage to the agent node labeled `build`.
4. Agent: `checkout scm` — pulls the commit.
5. Agent: `jf c add` / `jf c use` — authenticates to Artifactory using the
   `jfrog-access-token` Jenkins credential.
6. Agent: reads `app/base-image.env` for the current base image tag, runs
   `docker build` with that plus git-sha/build-number build-args, tags the
   result `<registry>/docker-dev-local/shipit:<sha>-<build>`.
7. Agent: `jf docker push` to `docker-dev-local`, then
   `jf rt build-publish` — build-info (git commit, dependencies, timestamps)
   is recorded in Artifactory against this build name/number.
8. **Gate 1.** Xray auto-scans the pushed image via the watch on
   `docker-dev-local`; Jenkins also runs `jf build-scan --fail=true` inline.
   Critical or High severity CVEs fail the pipeline right here — nothing
   downstream happens.
9. Passed: `jf rt build-promote` copies (does **not** rebuild) the same
   image digest into `docker-staging-local`.
10. Agent: `aws ecs update-service --cluster ... --service shipit-staging
    --force-new-deployment` — the ECS task pulls the new tag directly from
    Artifactory (registry credentials via Secrets Manager) and rolls.
11. Smoke test: `curl $STAGING_URL/health`.
12. Manual gate: Jenkins `input` step — "Promote this build to production?"
    A human clicks **Promote**.
13. **Gate 2.** `jf rt build-promote` copies staging → `docker-release-local`.
    This watch also blocks Medium-severity CVEs, not just Critical/High.
14. Agent: `aws ecs update-service ... shipit-production ...` — the
    production task rolls to the new image.
15. Same image, three repos, two automated scan gates, one human approval
    before prod. Nothing was ever rebuilt after step 6.

## Credentials — what lives where

| Secret | Stored in | Used by |
|---|---|---|
| JFrog access token | Jenkins credential store, id `jfrog-access-token` | `Jenkinsfile` → `withCredentials` |
| AWS permissions | EC2 agent's instance profile (`build_agent` IAM role) — no static keys | `aws ecs update-service` calls |
| ECS → Artifactory image pull | Secrets Manager entry, referenced by ECS task def's `repositoryCredentials` | not yet created — part of the missing ECS-services piece |
| GitHub webhook secret | not configured in this scaffold | optional hardening; add via Jenkins GitHub plugin if used beyond a demo |

## Registry structure and gates

| Repository | Populated by | Gate to get in |
|---|---|---|
| `docker-dev-local` | every pipeline run | none — Xray scans it, informational at this point |
| `docker-staging-local` | promotion from `docker-dev-local` | Gate 1: block on Critical/High CVE |
| `docker-release-local` | promotion from `docker-staging-local` | Gate 2: block on Critical/High/**Medium** CVE, plus manual approval |

## What's built vs. what's next

1. Add `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `TF_API_TOKEN` as
   GitHub repo secrets (Settings → Secrets and variables → Actions).
2. Run the "Infrastructure - Terraform" workflow from the Actions tab —
   `plan` first, then `apply` — to get the controller + agent public IPs.
3. SSH into the agent, attach it as a Jenkins node labeled `build`.
4. Sign up for JFrog Cloud; confirm Xray is included in the tier.
5. Create the 3 Docker repos, 2 Xray watches, and the blocking policy.
6. Generate a JFrog access token; add it as the `jfrog-access-token` Jenkins credential.
7. Edit `Jenkinsfile` placeholders: `JF_URL`, `DOCKER_REGISTRY`, `ECS_CLUSTER`.
8. Build the missing piece: ECS services for `shipit` (staging + prod) and
   the Secrets Manager entry for Artifactory pull credentials.
9. Wire the GitHub webhook to the Jenkins controller's public IP.
10. First end-to-end dry run.
11. Run `scripts/break-the-build.sh` to rehearse the Gate 1 failure/recovery beat.
