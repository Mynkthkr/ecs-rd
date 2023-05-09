data "aws_availability_zones" "available" {}

locals {
  region = "us-east-1"
  name   = "demotest"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  container_name = "ecs-sample"
  container_port = 80

  # tags = {
  #   Name       = "teswt"
  #   Example    = "demowa"
  #   Repository = "https://github.com/terraform-aws-modules/terraform-aws-ecs"
  # }
}

################################################################################
# Cluster   
################################################################################

module "ecs_cluster" {
  source = "terraform-aws-modules/ecs/aws//modules/cluster"

  cluster_name = local.workspace.ecs_cluster.cluster_name

  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = "/aws/ecs/aws-ec2"
      }
    }
  }

  autoscaling_capacity_providers = {
    one = {
      name = local.workspace.autoscaling_capacity_providers.name
      auto_scaling_group_arn         = "arn:aws:autoscaling:us-east-1:476498784073:autoScalingGroup:a3340e16-23b4-47e7-98cf-7caae7820477:autoScalingGroupName/test"
      #managed_termination_protection = "ENABLED"

      managed_scaling = {
        maximum_scaling_step_size = 2
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
        target_capacity           = 60
      }

      default_capacity_provider_strategy = {
        weight = 60
        base   = 20
      }
    }
    # two = {
    #   auto_scaling_group_arn         = "arn:aws:autoscaling:us-east-1:476498784073:autoScalingGroup:a3340e16-23b4-47e7-98cf-7caae7820477:autoScalingGroupName/test"
    #   managed_termination_protection = "ENABLED"

    #   managed_scaling = {
    #     maximum_scaling_step_size = 15
    #     minimum_scaling_step_size = 5
    #     status                    = "ENABLED"
    #     target_capacity           = 90
    #   }

    #   default_capacity_provider_strategy = {
    #     weight = 40
    #   }
    # }
  }

  tags = {
    Environment = "Development"
    Project     = "EcsEc2"
  }
}
# module "ecs_cluster" {
#   source = "terraform-aws-modules/ecs/aws"

#   #cluster_name = local.name

#   # Capacity provider - autoscaling groups
#   default_capacity_provider_use_fargate = false
#   autoscaling_capacity_providers = {
#     # On-demand instances
#     ex-1 = {
#       auto_scaling_group_arn         = module.autoscaling["ex-1"].autoscaling_group_arn
#       managed_termination_protection = "ENABLED"

#       managed_scaling = {
#         maximum_scaling_step_size = 5
#         minimum_scaling_step_size = 1
#         status                    = "ENABLED"
#         target_capacity           = 60
#       }

#       default_capacity_provider_strategy = {
#         weight = 60
#         base   = 20
#       }
#     }
#     # Spot instances
#     ex-2 = {
#       auto_scaling_group_arn         = module.autoscaling["ex-2"].autoscaling_group_arn
#       managed_termination_protection = "ENABLED"

#       managed_scaling = {
#         maximum_scaling_step_size = 15
#         minimum_scaling_step_size = 5
#         status                    = "ENABLED"
#         target_capacity           = 90
#       }

#       default_capacity_provider_strategy = {
#         weight = 40
#       }
#     }
#   }

  
# }

################################################################################
# Service
################################################################################

module "ecs_service" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  # Service
  name        =  local.workspace.ecs_service.name
  cluster_arn = module.ecs_cluster.arn

  # Task Definition
  requires_compatibilities = ["EC2"]
  capacity_provider_strategy = {
    # On-demand instances
    ex-1 = {
      capacity_provider = module.ecs_cluster.autoscaling_capacity_providers["one"].name
      weight            = 1
      base              = 1
    }
  }

  volume = {
    my-vol = {}
  }

  # Container definition(s)
  container_definitions = {
    (local.container_name) = {
      image = local.workspace.container_definitions.image 
      port_mappings = [
        {
          name          = local.workspace.container_definitions.name
          containerPort = local.workspace.container_definitions.containerPort
          protocol      = local.workspace.container_definitions.protocol
        }
      ]

      # mount_points = [
      #   {
      #     sourceVolume  = "my-vol",
      #     containerPath = "/var/www/my-vol"
      #   }
      # ]

      entry_point = ["/usr/sbin/apache2", "-D", "FOREGROUND"]

      # Example image used requires access to write to root filesystem
      readonly_root_filesystem = false
    }
  }

  load_balancer = {
    service = {
      target_group_arn = element(module.alb.target_group_arns, 0)
      container_name   = local.workspace.load_balancer.container_name
      container_port   = local.workspace.load_balancer.container_port
    }
  }

  subnet_ids = local.workspace.load_balancer.subnet_ids
  security_group_rules = {
    alb_http_ingress = {
      type                     = "ingress"
      from_port                = 80
      to_port                  = 80
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = "sg-0065ec72bb70f24bf"
    }
  }

#   tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html#ecs-optimized-ami-linux
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-service"
  description = "Service security group"
  vpc_id      = module.vpc.vpc_id

  ingress_rules       = ["http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = module.vpc.private_subnets_cidr_blocks

  tags = local.tags
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = local.name

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [module.alb_sg.security_group_id]

  http_tcp_listeners = [
    {
      port               = local.container_port
      protocol           = "HTTP"
      target_group_index = 0
    },
  ]

  target_groups = [
    {
      name             = "${local.name}-${local.container_name}"
      backend_protocol = "HTTP"
      backend_port     = local.container_port
      target_type      = "ip"
    },
  ]

  tags = local.tags
}

# module "autoscaling" {
#   source  = "terraform-aws-modules/autoscaling/aws"
#   version = "~> 6.5"

#   for_each = {
#     # On-demand instances
#     ex-1 = {
#       name= "myasg"
#       instance_type              = "t3.large"
#       use_mixed_instances_policy = false
#       mixed_instances_policy     = {}
#       user_data                  = <<-EOT
#         #!/bin/bash
#         cat <<'EOF' >> /etc/ecs/ecs.config
#         ECS_CLUSTER=${local.name}
#         ECS_LOGLEVEL=debug
#         ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
#         ECS_ENABLE_TASK_IAM_ROLE=true
#         EOF
#       EOT
#     }
#     # Spot instances
#     ex-2 = {
#       instance_type              = "t3.medium"
#       use_mixed_instances_policy = true
#       mixed_instances_policy = {
#         instances_distribution = {
#           on_demand_base_capacity                  = 0
#           on_demand_percentage_above_base_capacity = 0
#           spot_allocation_strategy                 = "price-capacity-optimized"
#         }

#         override = [
#           {
#             instance_type     = "m4.large"
#             weighted_capacity = "2"
#           },
#           {
#             instance_type     = "t3.large"
#             weighted_capacity = "1"
#           },
#         ]
#       }
#       user_data = <<-EOT
#         #!/bin/bash
#         cat <<'EOF' >> /etc/ecs/ecs.config
#         ECS_CLUSTER=${local.name}
#         ECS_LOGLEVEL=debug
#         ECS_CONTAINER_INSTANCE_TAGS=${jsonencode(local.tags)}
#         ECS_ENABLE_TASK_IAM_ROLE=true
#         ECS_ENABLE_SPOT_INSTANCE_DRAINING=true
#         EOF
#       EOT
#     }
#   }

#   name = "${local.name}-${each.key}"

#   image_id      = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
#   instance_type = each.value.instance_type

#   security_groups                 = [module.autoscaling_sg.security_group_id]
#   user_data                       = base64encode(each.value.user_data)
#   ignore_desired_capacity_changes = true

#   create_iam_instance_profile = true
#   iam_role_name               = local.name
#   iam_role_description        = "ECS role for ${local.name}"
#   iam_role_policies = {
#     AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
#     AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
#   }

#   vpc_zone_identifier = module.vpc.private_subnets
#   health_check_type   = "EC2"
#   min_size            = 1
#   max_size            = 5
#   desired_capacity    = 2

#   # https://github.com/hashicorp/terraform-provider-aws/issues/12582
#   autoscaling_group_tags = {
#     AmazonECSManaged = true
#   }

#   # Required for  managed_termination_protection = "ENABLED"
#   protect_from_scale_in = true

#   # Spot instances
#   use_mixed_instances_policy = each.value.use_mixed_instances_policy
#   mixed_instances_policy     = each.value.mixed_instances_policy

#   tags = local.tags
# }

# module "autoscaling_sg" {
#   source  = "terraform-aws-modules/security-group/aws"
#   version = "~> 4.0"

#   name        = local.name
#   description = "Autoscaling group security group"
#   vpc_id      = module.vpc.vpc_id

#   computed_ingress_with_source_security_group_id = [
#     {
#       rule                     = "http-80-tcp"
#       source_security_group_id = module.alb_sg.security_group_id
#     }
#   ]
#   number_of_computed_ingress_with_source_security_group_id = 1

#   egress_rules = ["all-all"]

#   tags = local.tags
# }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.tags
}