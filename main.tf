provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

locals {
  azs               = ["us-east-2a"]
  cidr              = var.vpc_cidr
}

resource "random_id" "id" {
  byte_length = 2
}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

data "aws_secretsmanager_secret" "tlskey" {
  name = var.tlskey
}

data "aws_secretsmanager_secret" "tlscert" {
  name = var.tlscert
}

data "aws_secretsmanager_secret_version" "tlskey" {
  secret_id = data.aws_secretsmanager_secret.tlskey.id
}

data "aws_secretsmanager_secret_version" "tlscert" {
  secret_id = data.aws_secretsmanager_secret.tlscert.id
}

resource "aws_key_pair" "sshkey" {
  key_name   = format("%s-key-%s", var.prefix, random_id.id.hex)
  public_key = file(var.public_key_path)
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                 = format("%s-vpc-%s", var.prefix, random_id.id.hex)
  cidr                 = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  azs = local.azs

  public_subnets = [
    for num in range(length(local.azs)) :
    cidrsubnet(var.vpc_cidr, 2, num)
  ]

  tags = {
    Name        = format("%s-vpc-%s", var.prefix, random_id.id.hex)
  }
}

resource "aws_security_group" "sg" {
  name        = format("%s-sg-%s", var.prefix, random_id.id.hex)
  vpc_id            = module.vpc.vpc_id

  ingress {
    description = "Full Access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self = true
    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  ingress {
    description = "All for 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self = true
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All for 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    self = true
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = format("%s-sg-%s", var.prefix, random_id.id.hex)
  }
}

####

data "template_file" "web_userdata" {
  template = file("${path.module}/templates/web_userdata.yaml")
  vars = {
    beacon_token = var.beacon_token
    cur_hostname = var.ub_hostname
    tlskey = data.aws_secretsmanager_secret_version.tlskey.secret_string
    tlscert = data.aws_secretsmanager_secret_version.tlscert.secret_string
  }
}

data "aws_ami" "ubuntu" {
    most_recent = true

    filter {
        name   = "name"
        values = ["ubuntu/*20.04-amd64*"]
    }
    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }
    filter {
        name   = "root-device-type"
        values = ["ebs"]
    }

    owners = ["099720109477"] # Canonical
}

resource "aws_instance" "web" {
  subnet_id = module.vpc.public_subnets[0]
  ami = data.aws_ami.ubuntu.id
  user_data = data.template_file.web_userdata.rendered
  vpc_security_group_ids = [aws_security_group.sg.id]
  instance_type = "t2.small"
  key_name = aws_key_pair.sshkey.id

  tags = {
    Name = format("%s-tg-%s", var.prefix, random_id.id.hex)
  }
}

data "aws_route53_zone" "rdomain" {
  name         = var.rdomain
  private_zone = false
}

resource "aws_route53_record" "arecord" {
  zone_id = data.aws_route53_zone.rdomain.zone_id
  name    = format("%s.r.4st.io", var.prefix)
  type    = "A"
  ttl     = "10"
  records = [aws_instance.web.public_ip]
}

output "webip" {
  value = aws_instance.web.public_ip
}

output "tlskey" {
  value = data.aws_secretsmanager_secret_version.tlskey.secret_string
  sensitive = true
}




