#!/bin/bash
# EC2 user-data for the combined Jenkins controller + build box. Docker
# builds need a real Docker daemon (Fargate disallows privileged
# containers), and since Jenkins itself now lives on this same instance,
# pipeline stages run on Jenkins' built-in node directly — no separate
# agent to install or attach.
#
# Lives inside infra/jenkins-ecs/ (not scripts/) so Terraform's file()
# reference stays within this module's own directory — Terraform Cloud's
# remote runner only ever sees infra/jenkins-ecs/ as "the configuration",
# not the rest of the repo.
set -euo pipefail

apt-get update -y
apt-get install -y docker.io curl unzip openjdk-21-jre-headless awscli git gnupg

systemctl enable --now docker
usermod -aG docker ubuntu

# BuildKit (docker.io's apt package doesn't ship the buildx CLI plugin,
# but Dockerfiles using RUN --mount=... need it). Installed system-wide
# so it works for the jenkins user too, not just ubuntu.
BUILDX_VER=$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest | grep tag_name | cut -d'"' -f4)
mkdir -p /usr/libexec/docker/cli-plugins
curl -fL "https://github.com/docker/buildx/releases/download/${BUILDX_VER}/buildx-${BUILDX_VER}.linux-amd64" -o /usr/libexec/docker/cli-plugins/docker-buildx
chmod +x /usr/libexec/docker/cli-plugins/docker-buildx

# JFrog CLI v2 — getcli.jfrog.io defaults to the legacy v1 CLI, whose
# command set (no unified `jf docker push`, etc.) doesn't match what the
# Jenkinsfile uses. install-cli.jfrog.io is the v2 installer; it places
# the binary directly at /usr/local/bin/jf itself.
curl -fL https://install-cli.jfrog.io | sh

# Jenkins, from the official apt repo. The signing key is year-suffixed
# and rotates periodically (current one expires 2028-12-21) — if apt
# start reporting NO_PUBKEY, check https://pkg.jenkins.io/debian-stable/
# for the current filename. The key file is already ASCII-armored, so it
# goes to apt's signed-by as-is — no `gpg --dearmor` needed.
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key -o /usr/share/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt-get update -y
apt-get install -y jenkins

# Jenkins runs `docker build` directly on this box, as itself.
usermod -aG docker jenkins
systemctl enable --now jenkins

echo "Jenkins + build tooling ready. Label the built-in node 'build' from Manage Jenkins > Nodes so the Jenkinsfile's agent { label 'build' } runs here."
