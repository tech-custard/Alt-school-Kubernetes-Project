#Install Grafana to EKS using Helm Chart
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = "monitoring"
  create_namespace = true

  values = [
    "${file("./files/grafana.yaml")}"
  ]
 
  set {
    name  = "persistence.storageClassName"
    value = "gp2"
  }

  set {
    name  = "persistence.enabled"
    value = true
  }
  set {
    name  = "adminPassword"
    value = "admin"
  }
}