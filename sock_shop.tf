data "kubectl_path_documents" "sock-shop-file" {
  pattern = "./deploy/kubernetes/manifests/*.yaml"
}

resource "kubectl_manifest" "sock_shop" {
  for_each  = toset(data.kubectl_path_documents.sock-shop-file.documents)
  yaml_body = each.value
}