# Official Red Hat RHEL 10 AMI (the README targets RHEL 10). Default login user: ec2-user
data "aws_ami" "rhel" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat

  filter {
    name   = "name"
    values = ["RHEL-10.*_HVM-*-x86_64-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = local.name
  public_key = file(pathexpand(var.ssh_public_key_path))
}

locals {
  common_instance = {
    ami      = data.aws_ami.rhel.id
    key_name = aws_key_pair.this.key_name
  }
}

# ---------- Bastion (only host with a public IP) ----------
resource "aws_instance" "bastion" {
  ami                    = local.common_instance.ami
  instance_type          = var.bastion_instance_type
  key_name               = local.common_instance.key_name
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.bastion.id]

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = { Name = "${local.name}-bastion", Role = "bastion" }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
  tags     = { Name = "${local.name}-bastion" }
}

# ---------- Web tier (Nginx) - spread across AZs, private subnets ----------
resource "aws_instance" "web" {
  count                  = var.web_count
  ami                    = local.common_instance.ami
  instance_type          = var.web_instance_type
  key_name               = local.common_instance.key_name
  subnet_id              = element(module.vpc.private_subnets, count.index)
  vpc_security_group_ids = [aws_security_group.web.id]

  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = { Name = "${local.name}-web-${count.index + 1}", Role = "web" }
}

# ---------- App tier (Spring Boot) - spread across AZs, private subnets ----------
resource "aws_instance" "app" {
  count                  = var.app_count
  ami                    = local.common_instance.ami
  instance_type          = var.app_instance_type
  key_name               = local.common_instance.key_name
  subnet_id              = element(module.vpc.private_subnets, count.index)
  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 20
  }

  tags = { Name = "${local.name}-app-${count.index + 1}", Role = "app" }
}
