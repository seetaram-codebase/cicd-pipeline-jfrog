# Shipit Pipeline — End-to-End Spec

What happens, exactly, from `git push` to a running container in
production. Companion to `README.md` (setup steps) and `jfrog-agenda.txt`
(the session this demo supports).

## Components

| Component | Role | Defined in | Status |
|---|---|---|---|
| GitHub repo | source + webhook trigger | `github.com/seetaram-codebase/cicd-pipeline-jfrog` | **Live** |
| Jenkins controller + build execution | schedules pipeline, serves UI/webhook endpoint, runs `docker build` / `jf` / `aws` CLI | `infra/jenkins-ecs/agent-ec2.tf` (single EC2 instance) | Scaffolded, not applied |
| Terraform apply path | provisions the instance above | `.github/workflows/infrastructure.yml`, state in Terraform Cloud (`agentic-ai-org` / `jfrog-demo-jenkins`) | Scaffolded — needs `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `TF_API_TOKEN` added as repo secrets, then run manually from the Actions tab |
| JFrog Artifactory | stores the image, 2 Docker repos (sandbox, release) | JFrog Cloud console | Not started |
| JFrog Xray | scans + gate policies | JFrog Cloud console | Not started |
| ECS production service | runs `shipit` in prod | not yet scaffolded | Not started |
| GitHub webhook | fires Jenkins on push | GitHub repo settings | Not started (needs Jenkins IP first) |

Jenkins controller and build execution run on the same EC2 instance —
a real Docker daemon (not Fargate, which disallows privileged
containers), with pipeline stages running on Jenkins' built-in node. See
`README.md` for the tradeoffs of this single-instance setup.

## End-to-end sequence

The destination repo — and whether the run can touch production — is
decided by **branch name**, not by a manual promotion step. This requires
the Jenkins job to be a **Multibranch Pipeline** so `env.BRANCH_NAME` is
populated.

| Branch | Pushes to | Deploys to prod? |
|---|---|---|
| `feature/*` (and anything else) | `docker-sandbox-local` | No — stops after the scan gate |
| `develop`, `master` | `docker-release-local` | Yes — automatically, if the scan passes |

1. Developer commits and pushes to a branch on GitHub.
2. GitHub webhook `POST`s to `http://<jenkins-ip>:8080/github-webhook/`.
3. Jenkins (single EC2 instance) picks it up and starts a `shipit`
   pipeline run on its built-in node, labeled `build`.
4. `checkout scm` — pulls the commit.
5. `jf c add` / `jf c use` — authenticates to Artifactory using the
   `jfrog-access-token` Jenkins credential.
6. **Route by branch.** `feature/*` (or anything not `develop`/`master`)
   targets `docker-sandbox-local`; `develop`/`master` target
   `docker-release-local` directly — there's no promotion step, the image
   is built straight into its final repo based on which branch triggered it.
7. Reads `app/base-image.env` for the current base image tag, runs
   `docker build` with that plus git-sha/build-number build-args, tags the
   result `<registry>/<target-repo>/shipit:<sha>-<build>`.
8. `jf docker push` to the target repo, then `jf rt build-publish` —
   build-info (git commit, dependencies, timestamps) is recorded in
   Artifactory against this build name/number.
9. **Xray gate.** Xray auto-scans the pushed image via the watch on
   whichever repo it landed in — `docker-sandbox-local`'s watch blocks
   Critical/High, `docker-release-local`'s watch also blocks Medium.
   Jenkins runs `jf build-scan --fail=true` inline; a violation fails the
   pipeline right here.
10. **If this was a `develop`/`master` build and the scan passed:**
    `aws ecs update-service ... shipit-production ...` runs automatically
    — no human click in between. The production task pulls the new tag
    directly from Artifactory (registry credentials via Secrets Manager)
    and rolls. Feature-branch builds stop at step 9 — there's nothing
    further for them to do.

## Credentials — what lives where

| Secret | Stored in | Used by |
|---|---|---|
| JFrog access token | Jenkins credential store, id `jfrog-access-token` | `Jenkinsfile` → `withCredentials` |
| AWS permissions | EC2 instance's instance profile (`jenkins` IAM role) — no static keys | `aws ecs update-service` calls |
| ECS → Artifactory image pull | Secrets Manager entry, referenced by ECS task def's `repositoryCredentials` | not yet created — part of the missing ECS-services piece |
| GitHub webhook secret | not configured in this scaffold | optional hardening; add via Jenkins GitHub plugin if used beyond a demo |

## Registry structure and gates

| Repository | Populated by | Gate to get in |
|---|---|---|
| `docker-sandbox-local` | `feature/*` (and any other non-release) branch builds | block on Critical/High CVE |
| `docker-release-local` | `develop`/`master` branch builds, pushed directly (no promotion) | block on Critical/High/**Medium** CVE — passing this gate auto-deploys to prod |

## What's built vs. what's next

1. Add `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `TF_API_TOKEN` as
   GitHub repo secrets (Settings → Secrets and variables → Actions).
2. Run the "Infrastructure - Terraform" workflow from the Actions tab —
   `plan` first, then `apply` — to get the Jenkins instance's Elastic IP.
3. In Jenkins, label the built-in node `build` (Manage Jenkins > Nodes >
   built-in node > Configure) — no separate agent to attach.
4. Sign up for JFrog Cloud; confirm Xray is included in the tier.
5. Create the 2 Docker repos (`docker-sandbox-local`, `docker-release-local`),
   2 Xray watches, and the blocking policy.
6. Generate a JFrog access token; add it as the `jfrog-access-token` Jenkins credential.
7. Edit `Jenkinsfile` placeholders: `JF_URL`, `DOCKER_REGISTRY`, `ECS_CLUSTER`.
8. Build the missing piece: an ECS service for `shipit-production` and
   the Secrets Manager entry for Artifactory pull credentials.
9. Wire the GitHub webhook to the Jenkins instance's public IP.
10. First end-to-end dry run.
11. Run `scripts/break-the-build.sh` to rehearse the Gate 1 failure/recovery beat.
