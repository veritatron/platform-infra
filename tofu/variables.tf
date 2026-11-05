variable "environment" {
  type        = string
  description = "Name of the environment, used in labels and the state key."
}

variable "server_name" {
  type        = string
  description = "Hostname of the k3s control plane server."
}

variable "server_type" {
  type        = string
  description = "Hetzner Cloud server type."
}

variable "location" {
  type        = string
  description = "Hetzner Cloud location for the server and its Primary IP."
}

variable "image" {
  type        = string
  description = "Hetzner Cloud image the server is created from."
}

variable "k3s_version" {
  type        = string
  description = "Pinned k3s release, e.g. v1.37.2+k3s1. Only used when a server is created; changing it replaces the server, so update it together with k3s_install_script_commit and k3s_install_script_sha256 only before creating a new server."

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be a full k3s release tag such as v1.37.2+k3s1."
  }
}

variable "k3s_install_script_commit" {
  type        = string
  description = "Commit SHA of the k3s repository the install script is downloaded from; the commit of the k3s_version tag."

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.k3s_install_script_commit))
    error_message = "k3s_install_script_commit must be a full 40-character commit SHA."
  }
}

variable "k3s_install_script_sha256" {
  type        = string
  description = "SHA-256 checksum of install.sh at k3s_install_script_commit."

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.k3s_install_script_sha256))
    error_message = "k3s_install_script_sha256 must be a 64-character SHA-256 checksum."
  }
}

variable "admin_ips" {
  type        = list(string)
  sensitive   = true
  description = "CIDRs allowed to reach SSH and the Kubernetes API, e.g. [\"198.51.100.7/32\"]. Private in a public repository, so set via TF_VAR_admin_ips, never in a .tfvars file."

  validation {
    condition = length(var.admin_ips) > 0 && alltrue([
      for cidr in var.admin_ips :
      can(cidrhost(cidr, 0)) && try(tonumber(split("/", cidr)[1]) > 0, false)
    ])
    error_message = "admin_ips must contain at least one valid CIDR, and none of them may cover the whole internet."
  }
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for root access to the server."

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) ", var.ssh_public_key))
    error_message = "ssh_public_key must be an OpenSSH public key."
  }
}

variable "gitops_repo_url" {
  type        = string
  description = "HTTPS URL of the platform-gitops repository the root Application points to."

  validation {
    condition     = startswith(var.gitops_repo_url, "https://")
    error_message = "gitops_repo_url must be an HTTPS URL."
  }
}

variable "gitops_revision" {
  type        = string
  description = "Git revision (branch, tag or commit) of platform-gitops that Argo CD tracks."
}

variable "r2_account_id" {
  type        = string
  description = "Cloudflare account ID that owns the R2 buckets for state and etcd snapshots. Private in a public repository, so set via TF_VAR_r2_account_id. Not sensitive because the backend rejects sensitive values."

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.r2_account_id))
    error_message = "r2_account_id must be a 32-character Cloudflare account ID."
  }
}

variable "state_bucket" {
  type        = string
  description = "Bucket that holds the OpenTofu state."
}

variable "etcd_snapshot_bucket" {
  type        = string
  description = "Bucket that receives the k3s etcd snapshots."
}

variable "etcd_snapshot_schedule_cron" {
  type        = string
  description = "Cron schedule for k3s etcd snapshots."
}

variable "etcd_snapshot_retention" {
  type        = number
  description = "Number of etcd snapshots k3s keeps."
}

variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for OpenTofu state and plan encryption. Set via TF_VAR_state_passphrase."

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase must be at least 16 characters long."
  }
}

variable "k3s_token" {
  type        = string
  sensitive   = true
  description = "k3s server token. It encrypts bootstrap data in etcd and is required to restore a snapshot on a new server. Set via TF_VAR_k3s_token."

  validation {
    condition     = length(var.k3s_token) >= 32
    error_message = "k3s_token must be at least 32 characters long."
  }
}

variable "etcd_s3_access_key" {
  type        = string
  sensitive   = true
  description = "Access key for the etcd snapshot bucket. Set via TF_VAR_etcd_s3_access_key."
}

variable "etcd_s3_secret_key" {
  type        = string
  sensitive   = true
  description = "Secret key for the etcd snapshot bucket. Set via TF_VAR_etcd_s3_secret_key."
}
