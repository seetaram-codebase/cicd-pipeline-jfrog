# Persistent JENKINS_HOME — a Fargate task's local disk doesn't survive a
# restart, which would otherwise wipe Jenkins config/credentials/job history.

resource "aws_efs_file_system" "jenkins_home" {
  creation_token = "${var.app_name}-home"
  encrypted      = true

  tags = { Name = "${var.app_name}-home" }
}

resource "aws_efs_mount_target" "jenkins_home" {
  for_each        = toset(data.aws_subnets.default.ids)
  file_system_id  = aws_efs_file_system.jenkins_home.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "jenkins_home" {
  file_system_id = aws_efs_file_system.jenkins_home.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/jenkins_home"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = { Name = "${var.app_name}-ap" }
}
