# =====================================================================
# PUBLIC ALB  (internet-facing)  ->  web tier (nginx :80)
# =====================================================================
resource "aws_lb" "public" {
  name               = "${local.name}-public"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_alb.id]
  subnets            = module.vpc.public_subnets
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "web" {
  name     = "${local.name}-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  deregistration_delay = 30

  health_check {
    path                = "/nginx-health" # served by nginx itself, see nginx.conf.j2
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group_attachment" "web" {
  count            = var.web_count
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# HTTP -> HTTPS redirect
resource "aws_lb_listener" "public_http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "public_https" {
  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# =====================================================================
# INTERNAL ALB  (private only)  ->  app tier (spring boot :8080)
# =====================================================================
resource "aws_lb" "internal" {
  name               = "${local.name}-internal"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.internal_alb.id]
  subnets            = module.vpc.private_subnets
}

resource "aws_lb_target_group" "app" {
  name     = "${local.name}-app"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  deregistration_delay = 30

  health_check {
    path                = var.app_health_check_path
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # The monolith keeps login/cart in the server-side HTTP session, so a user must
  # keep hitting the same app instance. The cookie passes through nginx to the browser.
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }
}

resource "aws_lb_target_group_attachment" "app" {
  count            = var.app_count
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app[count.index].id
  port             = 8080
}

resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
