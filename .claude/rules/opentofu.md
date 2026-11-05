---
paths:
  - "tofu/**"
  - "bootstrap/**"
---

# OpenTofu und cloud-init

- Dateien nach Zweck: `versions.tf` (OpenTofu- und Provider-Versionen, Backend, State-Verschlüsselung), `providers.tf`, `server.tf`, `firewall.tf`, `variables.tf`, `locals.tf`, `outputs.tf`. Templates liegen unter `templates/` mit der Endung `.tftpl`.
- Der Hetzner-Provider ist `hetznercloud/hcloud`. Versionen werden mit `~>` auf die Minor-Version gepinnt, `.terraform.lock.hcl` wird committet. Eine neue Version wird vorher im Registry nachgesehen, nie geraten. Ein neuer Provider kommt nur nach Rückfrage dazu. DNS gehört nicht hierher, sondern nach `platform-gitops`.
- Jede Variable hat `type` und `description`. Werte, die sich je Umgebung unterscheiden, wie Standort, Servertyp, Image, k3s-Version, haben keinen Default und stehen in `environments/<umgebung>.tfvars`. Das Repository ist öffentlich: Private Werte wie Admin-IPs und die Cloudflare-Account-ID stehen deshalb nicht dort, sondern kommen wie Secrets über `TF_VAR_...`. Wo möglich sind sie `sensitive`; im Backend geht das nicht.
- Secrets sind Variablen mit `sensitive = true` und ohne Default. Sie kommen nur über Umgebungsvariablen (`TF_VAR_...`) und stehen nie in einer `.tfvars`-Datei im Repo.
- Keine Magic Strings und keine Magic Numbers: Ports, Namen und wiederkehrende Werte stehen in `locals` oder als Variable an genau einer Stelle.
- Ressourcennamen sind englisch und `snake_case`, etwa `hcloud_server.control_plane`, `hcloud_primary_ip.control_plane` oder `hcloud_firewall.cluster`. Jede Ressource, die es unterstützt, bekommt `labels` mit mindestens `managed-by = "opentofu"` und `project = "platform"`.
- Server und Primary IP bekommen `delete_protection = true` (beim Server auch `rebuild_protection = true`) und `lifecycle { prevent_destroy = true }`.
- Die Firewall öffnet nur 80 und 443 für alle. SSH (22) und die Kubernetes-API (6443) sind auf `var.admin_ips` beschränkt. Eine Regel, die diese Ports für `0.0.0.0/0` oder `::/0` öffnet, wird nie geschrieben.
- cloud-init macht nur das Nötigste: Systemupdates, k3s in gepinnter Version mit `cluster-init: true` und konfigurierten etcd-Snapshots nach S3, und das Ablegen der Bootstrap-Manifeste in `/var/lib/rancher/k3s/server/manifests/`. Alles Weitere kommt über Argo CD aus `platform-gitops`.
- `bootstrap/argocd.yaml` ist eine k3s-`HelmChart`-Ressource mit fester Chart-Version. `bootstrap/root-app.yaml` zeigt auf `platform-gitops` mit Pfad `appsets/`. Beide werden per `templatefile` bzw. `file` in cloud-init eingebettet, nicht dupliziert.
- Änderungen an `user_data` ersetzen den Server. Das wird im Plan ausdrücklich genannt, bevor der Nutzer anwendet.
- Kommentare nur, wo etwas nicht offensichtlich ist. Keine einzeiligen Block-Kommentare der Form `/* ... */`.
- Vor jedem Bericht: `tofu fmt -check -recursive` und `tofu validate` grün, `kubeconform` für `bootstrap/`. `tofu plan` wird gezeigt und erklärt, `tofu apply` führt nur der Nutzer aus.
