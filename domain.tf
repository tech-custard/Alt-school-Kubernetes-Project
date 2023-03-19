resource "aws_route53_zone" "hosted_zone" {
  name = var.domain_name
}

# create a record set in route 53
resource "aws_route53_record" "site_domain" {
  zone_id = aws_route53_zone.hosted_zone.zone_id
  name    = "microservice.${var.domain_name}"
  type    = "A"
  alias {
    name                   = data.kubernetes_service.ingress_nginx.status.0.load_balancer.0.ingress.0.hostname
    zone_id                = data.aws_elb.nlb.zone_id
    evaluate_target_health = true
  }
}