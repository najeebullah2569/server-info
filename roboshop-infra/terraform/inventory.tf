# Generates the Ansible inventory from real instance IPs, so Terraform -> Ansible
# needs no copy/paste.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    bastion_ip       = aws_eip.bastion.public_ip
    web_ips          = aws_instance.web[*].private_ip
    app_ips          = aws_instance.app[*].private_ip
    ssh_key          = var.ssh_private_key_path
    aws_region       = var.aws_region
    vpc_cidr         = var.vpc_cidr
    app_backend_host = aws_route53_record.app_internal.fqdn
    db_host          = aws_route53_record.mysql_internal.fqdn
    db_password_ssm  = aws_ssm_parameter.db_password.name
  })
}
