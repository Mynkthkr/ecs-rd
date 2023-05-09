locals {
  #env       = yamldecode(file("${path.module}/config.yml"))
 # common    = local.env["common"]
  env_space = yamldecode(file("config-aws-infra-us-east-1-qa.yml"))
  workspace = local.env_space["workspace"][terraform.workspace]

  project_name_prefix = "${local.workspace.environment_name}"

  tags = {
    Project     = local.workspace.environment_name
    Environment = local.workspace.environment_name
  }
}


