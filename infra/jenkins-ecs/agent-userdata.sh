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
apt-get install -y docker.io curl unzip openjdk-17-jre-headless awscli git gnupg

systemctl enable --now docker
usermod -aG docker ubuntu

# JFrog CLI
curl -fL https://getcli.jfrog.io | sh
install -m 0755 jf /usr/local/bin/jf

# Jenkins, from the official apt repo
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt-get update -y
apt-get install -y jenkins

# Jenkins runs `docker build` directly on this box, as itself.
usermod -aG docker jenkins
systemctl enable --now jenkins

echo "Jenkins + build tooling ready. Label the built-in node 'build' from Manage Jenkins > Nodes so the Jenkinsfile's agent { label 'build' } runs here."
