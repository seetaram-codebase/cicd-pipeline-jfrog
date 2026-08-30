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

# JFrog CLI — the installer drops a binary literally named `jfrog` (not
# `jf`) into the current directory.
mkdir -p /tmp/jfrog-install && cd /tmp/jfrog-install
curl -fL https://getcli.jfrog.io | sh
install -m 0755 jfrog /usr/local/bin/jf
cd /

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
