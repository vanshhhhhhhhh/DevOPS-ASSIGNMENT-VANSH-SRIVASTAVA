# ---------------------------------------------------------------------------
# Security groups, one per tier. Only the web tier is reachable from the
# internet; the app tier only from the web tier; the database only from the app.
# ---------------------------------------------------------------------------
resource "aws_security_group" "web" {
  name        = "${var.project}-web-sg"
  description = "Ingress controller / load balancer: HTTP and HTTPS from the internet"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-web-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "web_http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "web_https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "TicketDesk backend and frontend pods / nodes"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_web" {
  security_group_id            = aws_security_group.app.id
  description                  = "App ports from the web tier only"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8080
}

resource "aws_security_group" "db" {
  name        = "${var.project}-db-sg"
  description = "PostgreSQL, reachable from the app tier only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from the app tier"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# Egress: allow outbound traffic inside the VPC and HTTPS out (image pulls, APIs).
resource "aws_vpc_security_group_egress_rule" "all_tiers_https_out" {
  for_each          = { web = aws_security_group.web.id, app = aws_security_group.app.id }
  security_group_id = each.value
  description       = "HTTPS out"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "all_tiers_vpc_out" {
  for_each          = { web = aws_security_group.web.id, app = aws_security_group.app.id, db = aws_security_group.db.id }
  security_group_id = each.value
  description       = "Any traffic inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}
