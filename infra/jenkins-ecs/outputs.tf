output "ecs_cluster_name" {
  value = aws_ecs_cluster.jenkins.name
}

output "build_agent_public_ip" {
  value = aws_instance.build_agent.public_ip
}

output "next_steps" {
  value = <<-EOT
    1. Find the Jenkins controller's public IP in the ECS console
       (cluster "${var.app_name}" > service "jenkins" > task > Networking)
       and open http://<public-ip>:8080
    2. Initial admin password is in CloudWatch: log group /ecs/${var.app_name}
    3. Install suggested plugins + the "JFrog" plugin, create an admin user
    4. Manage Jenkins > Nodes > New Node > name it, label "build",
       "Launch agent by connecting it to the controller" — use the agent at
       ${aws_instance.build_agent.public_ip} (SSH in, run the JNLP connect
       command Jenkins shows you)
    5. Add credentials: jfrog-access-token (Secret text)
    6. Create a pipeline job pointing at this repo's Jenkinsfile
  EOT
}
