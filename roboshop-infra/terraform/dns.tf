locals {
  app_fqdn = "${var.app_subdomain}.${var.domain_name}"
}

# =====================================================================
# PUBLIC DNS  (zone must already exist in Route53)
#   roboshop.example.com  -> public ALB   (HTTPS via ACM)
#   bastion.example.com   -> bastion EIP  (SSH, admin IP only)
# =====================================================================
data "aws_route53_zone" "public" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "app" {
  domain_name       = local.app_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.public.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

resource "aws_route53_record" "app_public" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = local.app_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.public.dns_name
    zone_id                = aws_lb.public.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "bastion_public" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "bastion.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.bastion.public_ip]
}

# =====================================================================
# PRIVATE DNS  (only resolvable inside the VPC)
#   app.roboshop.internal    -> internal ALB   (nginx proxies here)
#   mysql.roboshop.internal  -> RDS endpoint   (app connects here)
#   web-N / app-N            -> instance IPs   (ops / troubleshooting)
# =====================================================================
resource "aws_route53_zone" "private" {
  name = var.private_zone_name

  vpc {
    vpc_id = module.vpc.vpc_id
  }
}

resource "aws_route53_record" "app_internal" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "app.${var.private_zone_name}"
  type    = "A"

  alias {
    name                   = aws_lb.internal.dns_name
    zone_id                = aws_lb.internal.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "mysql_internal" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "mysql.${var.private_zone_name}"
  type    = "CNAME"
  ttl     = 60
  records = [aws_db_instance.mysql.address] # CNAME follows RDS Multi-AZ failover
}

resource "aws_route53_record" "web_hosts" {
  count   = var.web_count
  zone_id = aws_route53_zone.private.zone_id
  name    = "web-${count.index + 1}.${var.private_zone_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.web[count.index].private_ip]
}

resource "aws_route53_record" "app_hosts" {
  count   = var.app_count
  zone_id = aws_route53_zone.private.zone_id
  name    = "app-${count.index + 1}.${var.private_zone_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.app[count.index].private_ip]
}
