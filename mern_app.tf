data "kubectl_path_documents" "mern_app" {
  pattern = "./deploy/kubernetes/app_manifest/*.yaml"
}

resource "kubectl_manifest" "mern" {
  for_each  = toset(data.kubectl_path_documents.mern_app.documents)
  yaml_body = each.value
}