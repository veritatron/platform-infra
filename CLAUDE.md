# platform-infra

`platform-infra` baut die Grundlage für alle meine Webseiten und Anwendungen: einen gemieteten Server in der Hetzner Cloud mit k3s und Argo CD. Danach übergibt es an `platform-gitops`. Dieses Repo wird selten angefasst, typischerweise beim ersten Aufbau, bei einem neuen Node oder wenn sich die Firewall ändert.

```
platform-infra  ──OpenTofu──►  Hetzner-Server + Primary IP + Firewall + SSH-Key
                                  │ cloud-init installiert k3s und legt Argo CD + Root-Application ab
                                  ▼
platform-gitops ◄──Argo CD liest──  ab hier kommt alles im Cluster aus Git
```

Was im Cluster läuft, also Plattform-Komponenten und Projekte, steht ausschließlich in `platform-gitops`, nie hier.

## Aufbau

```
platform-infra/
├── tofu/
│   ├── versions.tf                OpenTofu- und Provider-Versionen, Backend, State-Verschlüsselung
│   ├── providers.tf
│   ├── server.tf                  hcloud_server, hcloud_primary_ip, hcloud_ssh_key
│   ├── firewall.tf                80/443 offen, 22 und 6443 nur von den Admin-IPs
│   ├── variables.tf / outputs.tf
│   ├── templates/
│   │   └── cloud-init.yaml.tftpl  k3s-Installation, k3s-Konfiguration, Bootstrap-Manifeste
│   └── environments/
│       └── prod.tfvars            Werte je Umgebung, keine Secrets
├── bootstrap/
│   ├── argocd.yaml                Argo CD als k3s-HelmChart-Ressource
│   └── root-app.yaml              Root-Application, zeigt auf platform-gitops/appsets
├── docs/
│   ├── runbooks/                  Anleitungen, z. B. Restore aus etcd-Snapshot, Node hinzufügen
│   └── adr/                       Architekturentscheidungen
├── scripts/                       Hilfsskripte, z. B. Prüfung der k3s-Pins
├── .github/workflows/             checks (fmt, validate, kubeconform), tofu (Plan im PR, Apply nach Freigabe)
├── Makefile                       make plan, make apply, make kubeconfig
└── README.md
```

## Entscheidungen

- **Argo CD ohne kubeconfig in OpenTofu.** k3s installiert automatisch alles, was in `/var/lib/rancher/k3s/server/manifests/` liegt. cloud-init legt dort `bootstrap/argocd.yaml` und `bootstrap/root-app.yaml` ab. OpenTofu braucht damit keinen Zugriff auf die Kubernetes-API, und es gibt kein Henne-Ei-Problem. Nach dem Start verwaltet Argo CD sich selbst aus `platform-gitops`.
- **k3s-Version gepinnt** über `INSTALL_K3S_VERSION` in cloud-init. Spätere Upgrades laufen über den System Upgrade Controller aus `platform-gitops`, nicht über einen neuen Server.
- **Embedded etcd** (`cluster-init: true`) statt SQLite. k3s schreibt damit regelmäßig etcd-Snapshots in einen R2-Bucket, und später lassen sich weitere Nodes hinzufügen.
- **Traefik und ServiceLB von k3s bleiben aktiv.** Für einen Node braucht es weder MetalLB noch einen Hetzner Load Balancer. Traefik dient als Implementierung der Gateway API; die Konfiguration dafür liegt in `platform-gitops`.
- **Löschschutz** auf zwei Ebenen: `delete_protection` und `rebuild_protection` bei Hetzner für Server und Primary IP, dazu `lifecycle { prevent_destroy = true }` in OpenTofu. Ein versehentliches `tofu destroy` entfernt so weder den Server noch die IP-Adresse.
- **Primary IP** als eigene Ressource, damit die öffentliche IP und damit die DNS-Einträge einen neuen Server überleben.
- **State und etcd-Snapshots** liegen in Cloudflare R2 (S3-kompatibel, Region `auto`), in zwei getrennten Buckets. R2 statt Hetzner Object Storage wegen des kostenlosen Kontingents; beides ist winzig. Der State ist mit der State-Verschlüsselung von OpenTofu verschlüsselt, auch Daten im State liegen so nie im Klartext. Gesperrt wird über `use_lockfile`, das bedingte Schreibvorgänge nutzt; R2 unterstützt sie. Die Buckets werden einmalig von Hand angelegt, weil OpenTofu den Bucket seines eigenen States nicht selbst anlegen kann.
- **Nur was vor dem Cluster da sein muss, gehört hierher.** Das sind Server, Primary IP, Firewall, SSH-Key, State und Bootstrap. Alles, was sich auch nach dem ersten Aufbau erledigen lässt, gehört nach `platform-gitops`. Begründung und Abgrenzung im Einzelnen: `docs/adr/0003-abgrenzung-platform-infra-und-platform-gitops.md`.
- **DNS und Domains** gehören deshalb nach `platform-gitops`. Die Domains liegen bei IONOS; A-Records (etwa mit external-dns) und Zertifikate (cert-manager per DNS-01 über den IONOS-Webhook) werden dort verwaltet. Dieses Repo liefert nur die feste Primary IP als Output `server_ipv4`.
- **Server:** ein Hetzner **CX23** (2 vCPU, 4 GB RAM). Das reicht für k3s, Argo CD, cert-manager, Sealed Secrets und einige kleine Apps. Ein voller Prometheus-Stack passt nicht dazu; Monitoring muss schlank bleiben. Der Servertyp steht als `server_type = "cx23"` in `environments/prod.tfvars`. Der Server wird ausschließlich von OpenTofu angelegt, nie in der Hetzner Console; nur so läuft cloud-init beim ersten Start und der Server bleibt reproduzierbar. Dasselbe gilt für Primary IP, Firewall und SSH-Key.

## Secrets

Secrets gehören nie ins Repo. Das Repository ist öffentlich; auch private, aber nicht geheime Werte (Admin-IPs, Cloudflare-Account-ID) stehen deshalb nicht im Repo, sondern kommen wie Secrets aus Umgebungsvariablen bzw. GitHub-Environment-Secrets.

- Das Hetzner-API-Token kommt als `HCLOUD_TOKEN`, die Zugangsdaten für State- und Snapshot-Bucket sowie die Passphrase der State-Verschlüsselung kommen als Umgebungsvariablen (`TF_VAR_...`, `AWS_...`).
- Werte, die in cloud-init landen, etwa die Zugangsdaten für die etcd-Snapshots, sind `sensitive` und kommen ebenfalls nur über Umgebungsvariablen.
- `*.tfstate`, kubeconfig-Dateien, private Schlüssel und unverschlüsselte Secret-Dateien (`*.secret.*`, `secrets.auto.tfvars`) werden nie gelesen oder ausgegeben, auch nicht über die Shell.

## Arbeitsweise

- **Nichts von Hand auf dem Server.** Keine Änderungen per SSH, kein `kubectl apply`, kein `helm install`. Was im Cluster läuft, kommt aus `platform-gitops`.
- **`tofu apply` und `tofu destroy` führt nur der Nutzer aus**, nach einem gezeigten `tofu plan`. Claude erstellt und erklärt Pläne, wendet sie aber nie an. Der übliche Weg ist der Workflow `tofu` in GitHub: Plan im PR, nach dem Merge wendet der Job `apply` den gespeicherten Plan erst an, wenn der Nutzer das Environment `prod` freigibt. Ein `destroy` gibt es im Workflow nicht.
- **Änderungen an `user_data` ersetzen den Server.** Jeder Plan, der das tut, wird vorher ausdrücklich genannt, mit den Folgen für die laufenden Projekte.
- **Versionen nicht raten.** Provider auf search.opentofu.org bzw. im Registry nachsehen, k3s auf den GitHub-Releases, das Argo-CD-Chart auf ArtifactHub. Alles wird gepinnt: Provider in `versions.tf` mit `.terraform.lock.hcl` im Repo, k3s mit fester Version, das Argo-CD-Chart mit fester Version.
- **Jede Änderung endet geprüft:** `tofu fmt -check -recursive` und `tofu validate`, für die Bootstrap-Manifeste `kubeconform`. Was sich nicht lokal prüfen lässt, wird im Bericht genannt.

Bezeichner, Ressourcennamen, Code-Kommentare und Commit-Messages sind englisch, Dokumentation ist deutsch. Commits folgen Conventional Commits, etwa `feat(tofu): ...`, `fix(cloud-init): ...` oder `docs(runbooks): ...`.

```
make plan        # tofu plan mit environments/prod.tfvars
make apply       # nur durch den Nutzer
make kubeconfig  # holt die kubeconfig vom Server und ersetzt die Adresse
tofu -chdir=tofu fmt -check -recursive
tofu -chdir=tofu validate
```

Die Regeln für OpenTofu und cloud-init stehen in `.claude/rules/opentofu.md`. Für Reviews, Erklärungen und Pläne gibt es Agents in `.claude/agents/`.
