# Install Prometheus to EKS using Helm Chart
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = "monitoring"
  create_namespace = true
 
  set {
    name  = "alertmanager.persistentVolume.storageClass"
    value = "gp3"
  }

  set {
    name  = "server.persistentVolume.storageClass"
    value = "gp3"
  }

  depends_on = [
    kubectl_manifest.gp3-sc
  ]

}