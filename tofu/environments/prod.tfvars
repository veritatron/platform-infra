# Values for the prod environment. This repository is public: no secrets and no private values here.
# Secrets and private values (admin_ips, r2_account_id) come from TF_VAR_* environment variables.
# Every value marked CHANGE_ME is a placeholder and must be replaced before the first `make init`.

environment = "prod"

server_name = "platform-cp-1"
server_type = "cx23"
location    = "nbg1"
image       = "ubuntu-24.04"

k3s_version = "v1.37.2+k3s1"

ssh_public_key = "CHANGE_ME" # CHANGE_ME: content of your *.pub file; check that its trailing comment reveals nothing private

gitops_repo_url = "https://github.com/CHANGE_ME/platform-gitops.git" # CHANGE_ME: GitHub URL of platform-gitops
gitops_revision = "main"

state_bucket         = "CHANGE_ME" # CHANGE_ME: R2 bucket for the OpenTofu state
etcd_snapshot_bucket = "CHANGE_ME" # CHANGE_ME: R2 bucket for the etcd snapshots

etcd_snapshot_schedule_cron = "0 */6 * * *"
etcd_snapshot_retention     = 20
