resource "hcloud_firewall" "cluster" {
  name   = "${var.server_name}-firewall"
  labels = local.labels

  dynamic "rule" {
    for_each = { http = local.ports.http, https = local.ports.https }
    content {
      description = "${rule.key} from anywhere"
      direction   = "in"
      protocol    = "tcp"
      port        = tostring(rule.value)
      source_ips  = local.internet_cidrs
    }
  }

  dynamic "rule" {
    for_each = { ssh = local.ports.ssh, kube-api = local.ports.kube_api }
    content {
      description = "${rule.key} from admin IPs"
      direction   = "in"
      protocol    = "tcp"
      port        = tostring(rule.value)
      source_ips  = var.admin_ips
    }
  }
}
