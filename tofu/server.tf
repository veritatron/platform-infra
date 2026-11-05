resource "hcloud_ssh_key" "admin" {
  name       = "${var.server_name}-admin"
  public_key = var.ssh_public_key
  labels     = local.labels
}

resource "hcloud_primary_ip" "control_plane" {
  name              = "${var.server_name}-ipv4"
  type              = "ipv4"
  location          = var.location
  auto_delete       = false
  delete_protection = true
  labels            = local.labels

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_server" "control_plane" {
  name               = var.server_name
  server_type        = var.server_type
  image              = var.image
  location           = var.location
  ssh_keys           = [hcloud_ssh_key.admin.id]
  firewall_ids       = [hcloud_firewall.cluster.id]
  user_data          = local.cloud_init
  delete_protection  = true
  rebuild_protection = true
  labels             = local.labels

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.control_plane.id
    ipv6_enabled = false
  }

  lifecycle {
    prevent_destroy = true
  }
}
