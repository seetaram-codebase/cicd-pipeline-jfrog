# Talking points — building a secure, traceable container pipeline with JFrog

End-to-end narrative and speaker notes for this demo: a Jenkins + JFrog
Artifactory + JFrog Xray pipeline that builds, scans, gates, and deploys
a small FastAPI app to AWS ECS. Written as a walkthrough of what was
actually built and debugged, in order — useful both as a slide script
and as a record of the real journey (including the dead ends), not a
cleaned-up marketing version.

Companion repos:
- **cicd-pipeline-jfrog** (this repo) — Jenkins + AWS infra (Terraform)
- **[fastapi-jfrog-demo](https://github.com/seetaram-codebase/fastapi-jfrog-demo)** — the app, `Jenkinsfile`, `Dockerfile`

---

## 1. Where this started

A half-provisioned Jenkins setup: a two-host architecture (ECS Fargate
controller + a separate EC2 build agent) that was more complex than the
demo needed, with the build agent offline and no JFrog integration wired
up at all.

**Talking point:** "We started by asking one question — is Jenkins even
ready to talk to JFrog? The answer was no, on multiple levels."

## 2. Simplifying the infra: one box, not two

Docker builds need a real Docker daemon — Fargate disallows privileged
containers, so a Fargate-hosted Jenkins controller can't run `docker
build` itself, only dispatch to something else that can. Rather than
keep the controller/agent split, Jenkins now runs on a **single EC2
instance** (`infra/jenkins-ecs/agent-ec2.tf`) — controller and build
execution together, pipeline stages running on Jenkins' own built-in
node.

Fixed along the way:
- An expired apt signing key for the Jenkins package repo (keys are
  year-suffixed and rotate; the fix was finding the current one)
- A Java version mismatch (Jenkins now requires Java 21 minimum)
- JFrog CLI v1 vs v2 — `getcli.jfrog.io` installs the legacy v1 CLI,
  whose command set doesn't match what the Jenkinsfile needs
  (`jf docker push`, `jf c add`, etc. are v2-only)

**Talking point:** "Simpler infra isn't a compromise here — it's
correct. One EC2 instance with a real Docker daemon, an Elastic IP for
a stable address, SSM Session Manager for shell access instead of SSH
keys."

## 3. Splitting the repo

The FastAPI app, its `Dockerfile`, and its `Jenkinsfile` moved into
their own repo (`fastapi-jfrog-demo`), separate from this infra repo.
This repo stays pure Terraform; the app repo owns everything about what
gets built and how.

## 4. Branch-based promotion

```
feature/*          -> artifact-sandbox   (no deploy, zero-exception gate)
develop / master    -> artifact-release   (auto-deploy on a passing gate)
```

Two demo branches make the story concrete: `feature/vulnerable-demo`
pins a deliberately EOL base image (`python:3.9-slim-buster`) that
trips the sandbox gate on purpose; `master` stays on a patched,
Alpine-based image and is meant to pass.

**Talking point:** "No manual approval step between a passing gate and
production. The gate *is* the approval."

## 5. The real work: making the Xray gate mean something

This was most of the session, and it's the part worth walking through
slide by slide because every step was a real, reproducible finding —
not something documented anywhere obvious going in.

### 5a. Xray's "build" resource type silently doesn't work

`jf build-scan <name> <number>` targets Xray's **build** resource type.
On this account, it never actually computes violations — stuck at "Not
Scanned" no matter how many times it's re-triggered. Switched the gate
to `jf docker scan <image> --watches=<name> --fail=true`, which targets
the **repository/artifact** resource type — confirmed working by
comparing the two resource types' violation counts side by side in the
JFrog UI.

**Talking point:** "If your gate always says 'no violations,' don't
assume your image is clean — check whether the gate is actually
running."

### 5b. A watch with no policy silently disables itself

Xray watches auto-disable if no policy is attached, with no obvious
warning in the main UI. Easy to build a watch, forget the policy step,
and get a permanently-green gate that was never doing anything.

### 5c. Policy exceptions can hide almost everything — or block
everything

Two exception toggles on a CVE rule (`Except if a Fix Version is not
available`, `Skip not applicable CVEs`) determine what actually counts
as a violation. Too loose on a genuinely vulnerable image (sandbox) and
the gate never fires. Too strict on a *patched* image (release) and the
gate can never pass — no image is ever CVE-zero.

### 5d. No image is CVE-zero — base image choice is a security decision

Even a current, patched `python:3.11-slim-bookworm` carried 129
violations at a Medium threshold, 86% of them Debian OS packages with
no fix version available at all (continuous CVE disclosure vs. patch
cadence — normal, not a sign of a badly maintained image). Switching to
`python:3.11-alpine` dropped that to single digits: Alpine's musl/busybox
base has a dramatically smaller CVE surface than Debian's.

**Talking point, with the numbers:** "129 violations on Debian slim.
Single digits on Alpine, same app. That's not us finding vulnerabilities
in our code — that's the base image."

### 5e. Contextual analysis separates real risk from noise

Xray's contextual/reachability analysis marks each CVE `Applicable`,
`Not Applicable`, `Undetermined`, or `Not Covered` — is the vulnerable
code path actually reachable in how the image is built and run, not
just "does a vulnerable library exist somewhere in this image." Most of
the residual findings on the patched Alpine image were `Not Applicable`.

### 5f. The last few findings were genuinely unfixable — and why

After patching everything patchable (looser `fastapi` pin to pick up a
non-vulnerable `starlette` range; upgrading the base image's own bundled
pip/setuptools), 2–9 findings remained depending on the exact scan, all
structurally unfixable from application code:

| Finding | Why it can't be "fixed" |
|---|---|
| `CVE-2018-20225` (pip) | Disputed by pip's own maintainers as not a real vulnerability — a design-behavior report, not a bug. No pip version resolves it. |
| Old `setuptools`/`jaraco.context` versions | Not the active, upgraded packages — these are frozen wheel files Python's stdlib `ensurepip` bundles for future venv bootstrapping. `pip install --upgrade` never touches them. |
| `msgpack` finding | pip's own internal vendored copy (`pip._vendor`), not anything in `requirements.txt`. |
| Alpine `krb5-libs` CVEs | Real OS package CVEs with no upstream fix published yet. |

**Talking point — the core thesis of the whole demo:** "A security gate
that always shows green is a broken gate. Getting this one to *fail
correctly*, and then *pass for the right reasons*, took more work than
getting it to fail at all."

### 5g. Sandbox vs. release: two philosophies, same scanner

- **Sandbox** (`Security_policy_1`): zero accumulated exceptions. Every
  feature branch is scanned against the raw policy — nothing gets to
  hide behind an exception someone else granted.
- **Release** (`Release_policy_1`): a curated, documented exception
  list. The same CVEs get detected; the unfixable ones are triaged with
  named Ignore Rules and CVE-ID-scoped policy rules, each carrying a
  written justification.

**Talking point:** "Sandbox has no memory — any new risk shows up red.
Release has a memory — it remembers what's already been reviewed and
decided isn't worth blocking on, and shows that decision explicitly
instead of hiding it."

### 5h. A real platform quirk: Ignore Rules vs. policy rules

Correctly-scoped Ignore Rules (matched CVE, watch, artifact) were
verified in the JFrog UI but were **not** honored by `jf docker scan
--fail=true` on this account — a gap between how the CLI gate evaluates
policy and how the repository-violations UI does. The fix that actually
worked: a CVE-ID-specific **policy rule**, ordered *before* the general
severity rule (`generate violation` but not `fail build`), since policy
rule edits were already proven to reach the CLI gate.

**Talking point:** "Don't assume a feature that clearly works in the UI
also reaches every code path that enforces policy. Verify against the
actual gate, not just the dashboard."

## 6. Deploying to AWS — same "one box" philosophy

Rather than a Fargate-based ECS service, the app runs on **ECS with EC2
launch type** — one small EC2 instance registered as a container
instance, one task, an ALB in front (`infra/app-ecs/`). This keeps the
Jenkinsfile's `aws ecs update-service` command unchanged and mirrors the
same "single box, not a fleet" choice already made for Jenkins.

Bugs found and fixed on the way to a real deploy:
- **Missing AWS region** — `aws ecs update-service` had no region
  configured, only surfaced once the Xray gate actually started passing
  and the pipeline reached the deploy stage for the first time.
- **`--force-new-deployment` alone never rolls a new image** — it
  restarts tasks on whatever task definition revision the service is
  already running. Fixed by registering a fresh revision (via `jq`)
  pointing at the just-built image, then updating the service to that
  revision.
- **AWS security group description restrictions** — em-dashes and
  apostrophes aren't in AWS's allowed character set for SG
  descriptions; failed `terraform validate` twice before catching both.
- **`.gitignore` blocking `*.tfvars`** — a blanket `*.tfvars` ignore
  rule (to avoid ever committing secrets) had one repo-specific
  exception carved out for `infra/jenkins-ecs/`; the new `infra/app-ecs/`
  module needed the same exception added, or its (non-secret) env
  config would silently never reach GitHub.
- **Terraform Cloud remote execution needs its own credentials** — the
  `cloud` block means `plan`/`apply` run on Terraform Cloud's own
  runners, not the GitHub Actions runner. AWS credentials set as
  GitHub Actions secrets never reach that remote execution environment;
  they have to be configured as environment variables on the specific
  Terraform Cloud *workspace* itself.

**Talking point:** "Every one of these was a real error message, not a
hypothetical. Each one printed a fix in the log."

## 7. The finish line: verified, not assumed

The last step of the demo isn't "the pipeline says success" — it's
independently confirming the *right* thing is actually running:

```
curl http://<alb-dns-name>/health
curl http://<alb-dns-name>/version
```

`/version` returns the git commit and Jenkins build number baked into
the image at build time — matching it against the actual Jenkins build
that ran proves the traffic hitting the ALB really is the artifact that
build produced, not a stale or cached image.

**Talking point, closing line:** "Build, scan, gate, ship — and then
prove it, from the outside, every time."

## 8. What this demo is actually about

Not "JFrog has a lot of features." Specifically:

1. **A gate that always passes is worse than no gate** — it took real
   work to make this one fail correctly on bad input and pass correctly
   on good input, and that work (not the tool) is the point.
2. **Full traceability, end to end** — Build Info ties every pushed
   image back to its git commit, branch, and Jenkins build number; the
   deployed app's `/version` endpoint proves it independently.
3. **Two gate philosophies, one scanner** — sandbox (no exceptions) and
   release (curated, documented exceptions) aren't a compromise on
   security, they're a deliberate design choice about *where* zero
   tolerance belongs.
4. **The base image is a security decision**, not an implementation
   detail — Debian vs. Alpine changed the violation count by two orders
   of magnitude for the identical application.
