locals {
  labels = {
    managed-by  = "opentofu"
    project     = "platform"
    environment = var.environment
  }

  # R2 accepts only the region "auto".
  object_storage_host     = "${var.r2_account_id}.r2.cloudflarestorage.com"
  object_storage_endpoint = "https://${local.object_storage_host}"
  object_storage_region   = "auto"
  state_key               = "platform-infra/${var.environment}/terraform.tfstate"

  ports = {
    http     = 80
    https    = 443
    ssh      = 22
    kube_api = 6443
  }
  internet_cidrs = ["0.0.0.0/0", "::/0"]

  bootstrap_dir      = "${path.module}/../bootstrap"
  k3s_manifests_dir  = "/var/lib/rancher/k3s/server/manifests"
  k3s_config_path    = "/etc/rancher/k3s/config.yaml"
  k3s_install_script = "https://raw.githubusercontent.com/k3s-io/k3s/${urlencode(var.k3s_version)}/install.sh"

  k3s_config = {
    "cluster-init"                = true
    "token"                       = var.k3s_token
    "tls-san"                     = [hcloud_primary_ip.control_plane.ip_address]
    "etcd-snapshot-schedule-cron" = var.etcd_snapshot_schedule_cron
    "etcd-snapshot-retention"     = var.etcd_snapshot_retention
    "etcd-s3"                     = true
    "etcd-s3-endpoint"            = local.object_storage_host
    "etcd-s3-region"              = local.object_storage_region
    "etcd-s3-bucket"              = var.etcd_snapshot_bucket
    "etcd-s3-bucket-lookup-type"  = "path"
    "etcd-s3-folder"              = var.server_name
    "etcd-s3-access-key"          = var.etcd_s3_access_key
    "etcd-s3-secret-key"          = var.etcd_s3_secret_key
  }

  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    k3s_config_path    = local.k3s_config_path
    k3s_config         = base64encode(yamlencode(local.k3s_config))
    k3s_manifests_dir  = local.k3s_manifests_dir
    k3s_version        = var.k3s_version
    k3s_install_script = local.k3s_install_script
    argocd_manifest    = base64encode(file("${local.bootstrap_dir}/argocd.yaml"))
    root_app_manifest = base64encode(templatefile("${local.bootstrap_dir}/root-app.yaml", {
      gitops_repo_url = var.gitops_repo_url
      gitops_revision = var.gitops_revision
    }))
  })
}
