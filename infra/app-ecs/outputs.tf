output "app_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "ecs_instance_id" {
  value = aws_instance.ecs.id
}

output "jfrog_pull_creds_secret_arn" {
  value = aws_secretsmanager_secret.jfrog_pull_creds.arn
}

output "next_steps" {
  value = <<-EOT
    1. Populate the JFrog pull-credentials secret (task execution role
       reads this to pull from artifact-release):
         aws secretsmanager put-secret-value \
           --secret-id ${aws_secretsmanager_secret.jfrog_pull_creds.name} \
           --secret-string '{"username":"<jfrog-user>","password":"<jfrog-access-token>"}'

    2. Until step 1 is done AND a real image has been pushed to
       artifact-release, the service's task will fail to start (the
       placeholder image ":bootstrap" doesn't exist) — expected at this
       point, not a bug.

    3. First successful `master` branch Jenkins run registers a real task
       definition revision with a real image tag and updates the service
       — that's when the task actually comes up.

    4. Once a task is running, hit the app: http://${aws_lb.app.dns_name}/health
  EOT
}
