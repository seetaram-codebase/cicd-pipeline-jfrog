#!/bin/bash
# EC2 user-data for the Jenkins build agent. Fargate can't run `docker build`
# (no privileged containers), so this instance carries the real Docker
# daemon plus the tools the Jenkinsfile shells out to.
set -euo pipefail

apt-get update -y
apt-get install -y docker.io curl unzip openjdk-17-jre-headless awscli git

systemctl enable --now docker
usermod -aG docker ubuntu

# JFrog CLI
curl -fL https://getcli.jfrog.io | sh
install -m 0755 jf /usr/local/bin/jf

echo "Build agent ready. Attach it as a Jenkins node (label: build) from the controller's UI."
