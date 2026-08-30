output "jenkins_public_ip" {
  value = aws_eip.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_eip.jenkins.public_ip}:8080"
}

output "next_steps" {
  value = <<-EOT
    1. Open http://${aws_eip.jenkins.public_ip}:8080 — stable address (Elastic
       IP), survives instance stop/start. Update Manage Jenkins > System >
       "Jenkins URL" to this same value so generated commands / webhook
       config stop pointing at old IPs.
    2. Initial admin password: SSM into the instance and run
       `cat /var/lib/jenkins/secrets/initialAdminPassword`
    3. Install suggested plugins + the "JFrog" plugin, create an admin user
    4. Manage Jenkins > Nodes > built-in node > Configure > add label
       "build" — the Jenkinsfile's `agent { label 'build' }` then runs
       right here, no separate agent to attach
    5. Add credentials: jfrog-access-token (Secret text)
    6. Create a pipeline job pointing at this repo's Jenkinsfile
  EOT
}
