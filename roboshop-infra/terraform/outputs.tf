output "app_url" {
  value = "https://${local.app_fqdn}"
}

output "bastion_public_ip" {
  value = aws_eip.bastion.public_ip
}

output "web_private_ips" {
  value = aws_instance.web[*].private_ip
}

output "app_private_ips" {
  value = aws_instance.app[*].private_ip
}

output "internal_app_endpoint" {
  value = aws_route53_record.app_internal.fqdn
}

output "db_endpoint" {
  value = aws_route53_record.mysql_internal.fqdn
}
