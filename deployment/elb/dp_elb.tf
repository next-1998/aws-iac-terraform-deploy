locals {
  was_alb = var.was_alb
  web_ide_alb = var.web_ide_alb
  root_domain = var.root_domain
  cluster_name = var.cluster_name
  was_name = var.was_name
  web_ide_name = var.web_ide_name
}


############################################################
#was alb
############################################################


module "was_alb" {
  source = "${var.module_repo_url}//module/network/aws-elb-workload/lb"

  name = local.was_alb
  # name_prefix = var.load_balancer_name_prefix
  load_balancer_type = "application"
  enable_cross_zone_load_balancing = true
  enable_deletion_protection = true

  subnets = var.pub_subnet_ids[*] //고민필요 
  security_groups = module.was_alb_securitygroup.id[*] 
  internal = true
}

module "was_alb_securitygroup" {
  source = "${var.module_repo_url}//module/network/aws-elb-workload/securitygroup"

  name = "${local.was_alb}-alb-sg"
  vpc_id = var.vpc_id
  common_tags = var.common_tags
  resource_tags = var.resource_tags
  default_security_group_rules = {
    ingress = [
      {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
        description = "Security Group managed by Terraform"
      },
      {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
        description = "Security Group managed by Terraform"
      }
    ]

    egress = [
      {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Security Group managed by Terraform"
      }
    ]
  }
}

module "was_alb_target_group" {
  source = "${var.module_repo_url}//module/network/aws-elb-workload/lb-target"
  target_groups = {
    "8080" = {
      name = "${local.was_name}-WAS-TG"
      port = 8080
      protocol = "HTTP"
      vpc_id = var.vpc_id
      health_check = {
        path = "/ping"
      }
    }
  }
  vpc_id = var.vpc_id  
  target_id = var.ec2_was_id
  target_port = 8080  
}

module "was_alb_listener" {
  source = "${var.module_repo_url}//module/network/aws-elb-workload/lb-listeners"

  listeners = {
    "80" = {
      protocol = "HTTP"
      port = 80
      certificate_arn = null
      additional_certificate_arns = []
      default_action = {
        type = "redirect"
        redirect = {
          port        = "443"
          protocol    = "HTTPS"
          status_code = "HTTP_301"
        }
      }
    }
    "443" = {
      protocol = "HTTPS"
      port = 443
      certificate_arn = var.certificate_arn
      ssl_policy = "ELBSecurityPolicy-2016-08"
      additional_certificate_arns = []
      default_action = {
        type = "forward"
        target_group_arn = module.was_alb_target_group.target_group_arn #확인필요
      }
    }
  }
  listener_rules = {}
}

############################################################
#web ide alb
############################################################

module "web_ide_alb" {
  source = "${var.module_repo_url}//module/network/aws-elb-workload/lb"

  name = local.web_ide_alb
  # name_prefix = var.load_balancer_name_prefix
  load_balancer_type = "application"
  enable_cross_zone_load_balancing = true
  enable_deletion_protection = false

  subnets = var.pri_subnet_ids[*]
  security_groups = module.web_ide_alb_securitygroup.id[*]
  internal = true
}

module "web_ide_alb_securitygroup" {
  source = "./module/network/aws-elb-workload/securitygroup"

  name = "${local.web_ide_alb}-alb-sg"
  vpc_id = var.vpc_id
  common_tags = var.common_tags
  resource_tags = var.resource_tags
  default_security_group_rules = {
    ingress = [
      {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = var.pub_subnet_ids[*]
        description = "Security Group managed by Terraform"
      },
      {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = var.pub_subnet_ids[*]
        description = "Security Group managed by Terraform"
      }
    ]

    egress = [
      {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Security Group managed by Terraform"
      }
    ]
  }
}

module "web_ide_alb_target_group_1" {
  source = "${var.module_repo_url}//module/network/aws-elb-workload/lb-target"
  target_groups = {
    "80" = {
      name = "${local.web_ide_name}-WEB-IDE-TG"
      port = 80
      protocol = "HTTP"
      health_check = {
        path = "/ping"
      }
    }
  }
  vpc_id = var.vpc_id
  target_id = var.ec2_web_ide_id
  target_port = 80
}


module "web_ide_alb_target_group_2" {
  source = "${var.module_repo_url}//module/network/aws-elb-workload/lb-target"
  target_groups = {
    "8080" = {
      name = "${local.web_ide_name}-PREVIEW-TG"
      port = 8080
      protocol = "HTTP"
      health_check = {
        path = "/"
      }
    }
  }
  vpc_id = var.vpc_id
  target_id = var.ec2_web_ide_id
  target_port = 8080
}

module "web_ide_alb_listener" {
  source = "${var.module_repo_url}//module/network/aws-elb-workload/lb-listeners"

  listeners = {
    "80" = {
      protocol = "HTTP"
      port = 80
      certificate_arn = null
      additional_certificate_arns = []
      default_action = {
        type = "redirect"
        redirect = {
          port        = "443"
          protocol    = "HTTPS"
          status_code = "HTTP_301"
        }
      }
    }
    "443" = {
      protocol = "HTTPS"
      port = 443
      certificate_arn = var.certificate_arn
      additional_certificate_arns = []
      default_action = {
        type = "forward"
        target_group_arn = module.web_ide_alb_target_group_1.target_group_arn
      }
    }
  }
  listener_rules = {
    "web_ide" = {
      listener_arn = aws_lb_listener.this["443"].arn
      listener_key = "443"
      priority = 1
      actions = {
        type = "forward"
        target_group_arn = module.web_ide_alb_target_group_1.target_group_arn
      }
      conditions = {
        host_header = {
          values = ["ide.${var.cluster_name}.${local.root_domain}"] //도메인 조정 필요
        }
      } 
    }
    "web_ide_preview" = {
      listener_arn = aws_lb_listener.this["443"].arn
      listener_key = "443"
      priority = 2
      actions = {
        type = "forward"
        target_group_arn = module.web_ide_alb_target_group_2.target_group_arn
      }
      conditions = {
        host_header = {
          values = ["ide-preview.${var.cluster_name}.${local.root_domain}"] //도메인 조정필요
        }
      }
    }
  }
}

