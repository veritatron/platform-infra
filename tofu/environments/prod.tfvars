environment = "prod"

server_name = "platform-cp-1"
server_type = "cx23"
location    = "nbg1"
image       = "ubuntu-24.04"

k3s_version               = "v1.37.2+k3s1"
k3s_install_script_commit = "f6973cb850e9b245585363d15bde80904ac862fd"
k3s_install_script_sha256 = "ed01f89fd977bf20ac1516bbebf8370bf3ddbaa55dac8aba610956a4c78cc00b"

ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC05rqL7cetmUsLDbnSRHrcsxw9Ga3tnpkayPX4zDxun veritatron@hetzner-k3s"

gitops_repo_url = "https://github.com/veritatron/platform-gitops.git"
gitops_revision = "main"

r2_jurisdiction      = "eu"
state_bucket         = "veritatron-state"
etcd_snapshot_bucket = "veritatron-etcd-snapshot"

etcd_snapshot_schedule_cron = "0 */6 * * *"
etcd_snapshot_retention     = 20
