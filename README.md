# platform-infra

Infrastruktur-Grundlage für alle Webseiten und Anwendungen: ein k3s-Single-Node-Cluster in der Hetzner Cloud, provisioniert mit OpenTofu und per cloud-init an Argo CD übergeben. Ab dem ersten Start verwaltet [`platform-gitops`](#abgrenzung-zu-platform-gitops) alles, was im Cluster läuft.

```
platform-infra  ──OpenTofu──►  Hetzner: Server, Primary IP, Firewall, SSH-Key
                                  │ cloud-init: k3s (embedded etcd) + Argo CD + Root-Application
                                  ▼
platform-gitops ◄──Argo CD──   alles im Cluster kommt aus Git
```

Das Repo enthält nur, was vor dem Cluster da sein muss. Alles, was sich auch später erledigen lässt, gehört nach `platform-gitops`. Geändert wird es entsprechend selten: beim ersten Aufbau, für einen weiteren Node oder bei Änderungen an der Firewall.

## Inhalt

- [Komponenten](#komponenten)
- [Repository-Struktur](#repository-struktur)
- [Voraussetzungen](#voraussetzungen)
- [Ersteinrichtung](#ersteinrichtung)
- [Konfiguration](#konfiguration)
- [Änderungen ausrollen](#änderungen-ausrollen)
- [Make-Targets](#make-targets)
- [Schutzmechanismen](#schutzmechanismen)
- [Versionen und Upgrades](#versionen-und-upgrades)
- [Bekannte Einschränkungen](#bekannte-einschränkungen)
- [Abgrenzung zu platform-gitops](#abgrenzung-zu-platform-gitops)

## Komponenten

| Komponente | Umsetzung |
|---|---|
| Server | Hetzner CX23 (2 vCPU, 4 GB RAM), Ubuntu 24.04, Standort `nbg1` |
| Öffentliche IP | eigene Primary IP (IPv4), überlebt einen Serverwechsel |
| Firewall | 80/443 öffentlich; 22 und 6443 nur von `admin_ips` |
| Kubernetes | k3s, gepinnte Version, embedded etcd (`cluster-init`), Traefik und ServiceLB aktiv |
| Backup | etcd-Snapshots alle 6 Stunden nach Cloudflare R2 |
| GitOps | Argo CD als k3s-`HelmChart`, Root-Application auf `platform-gitops/appsets` |
| State | Cloudflare R2, verschlüsselt mit OpenTofu State Encryption, Locking über `use_lockfile` |

Die Hintergründe zu diesen Entscheidungen stehen in [`CLAUDE.md`](CLAUDE.md#entscheidungen) und unter [`docs/adr/`](docs/adr/).

## Repository-Struktur

```
.
├── tofu/
│   ├── versions.tf                 OpenTofu/Provider-Versionen, Backend, State Encryption
│   ├── providers.tf
│   ├── variables.tf / locals.tf / outputs.tf
│   ├── server.tf                   Server, Primary IP, SSH-Key
│   ├── firewall.tf
│   ├── templates/cloud-init.yaml.tftpl
│   ├── environments/prod.tfvars    Umgebungswerte, keine Secrets
│   └── .terraform.lock.hcl         Provider-Prüfsummen, wird committet
├── bootstrap/
│   ├── argocd.yaml                 k3s-HelmChart für Argo CD
│   └── root-app.yaml               Root-Application (Template, gerendert von OpenTofu)
├── .github/workflows/
│   ├── checks.yml                  fmt, validate, kubeconform
│   └── tofu.yml                    Plan im PR, Apply nach Freigabe
├── docs/{adr,runbooks}/
└── Makefile
```

## Voraussetzungen

| Werkzeug | Version | Wofür |
|---|---|---|
| [OpenTofu](https://opentofu.org/docs/intro/install/) | 1.12.x (CI: 1.12.12) | lokal planen, Notfall-Apply, `make kubeconfig` |
| GNU `make` | beliebig | Makefile-Targets |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | passend zu k3s | Zugriff auf den Cluster |
| [kubeconform](https://github.com/yannh/kubeconform) | 0.8.0 | lokal `make lint`; alternativ per Docker, siehe [Make-Targets](#make-targets) |
| SSH-Client | | `make kubeconfig` |

Für den regulären Betrieb über GitHub Actions ist lokal nur `make kubeconfig` nötig.

## Ersteinrichtung

Einmalig, in dieser Reihenfolge.

### 1. Hetzner Cloud

Im Projekt **Veritatron** unter *Sicherheit → API-Tokens* zwei Tokens erzeugen:

- **Read** für Pläne in Pull Requests
- **Read & Write** für das Apply

Server, Primary IP, Firewall und SSH-Key werden ausschließlich von OpenTofu angelegt, nie in der Console. Nur so läuft cloud-init beim ersten Start und der Aufbau bleibt reproduzierbar.

### 2. Cloudflare R2

1. Zwei Buckets anlegen, etwa `platform-tofu-state` und `platform-etcd-snapshots`.
2. Je ein R2-API-Token mit **Object Read & Write** anlegen, beschränkt auf genau einen Bucket. Das Snapshot-Token liegt über cloud-init auf dem Server und darf deshalb keinen Zugriff auf den State haben.
3. Die Account-ID aus dem Cloudflare-Dashboard notieren.

Die Buckets entstehen von Hand, weil OpenTofu den Bucket für seinen eigenen State nicht selbst anlegen kann.

### 3. Umgebungswerte

In [`tofu/environments/prod.tfvars`](tofu/environments/prod.tfvars) alle Werte mit `CHANGE_ME` ersetzen:

| Variable | Beispiel |
|---|---|
| `ssh_public_key` | `"ssh-ed25519 AAAA… user@host"` |
| `gitops_repo_url` | `"https://github.com/<user>/platform-gitops.git"` |
| `state_bucket`, `etcd_snapshot_bucket` | Namen aus Schritt 2 |

Das Repository ist öffentlich. Private Werte stehen deshalb nicht in `prod.tfvars`, sondern kommen wie die Secrets aus Umgebungsvariablen: die Admin-IPs (`admin_ips`) und die Cloudflare-Account-ID (`r2_account_id`). Beim SSH-Key darauf achten, dass der Kommentar am Ende nichts Privates verrät.

Fehlende oder ungültige Werte lässt die Validierung der Variablen beim Plan scheitern, mit einer eindeutigen Meldung.

### 4. GitHub Environments

Unter *Settings → Environments*:

| Environment | Schutzregeln | `HCLOUD_TOKEN` |
|---|---|---|
| `prod-plan` | keine | Hetzner-Token **Read** |
| `prod` | *Required reviewers*: Repo-Owner; *Deployment branches*: nur `main` | Hetzner-Token **Read & Write** |

In beiden Environments zusätzlich:

| Secret | Inhalt |
|---|---|
| `STATE_ACCESS_KEY_ID`, `STATE_SECRET_ACCESS_KEY` | R2-Token für den State-Bucket |
| `STATE_PASSPHRASE` | Passphrase der State Encryption, mindestens 16 Zeichen |
| `ADMIN_IPS` | Admin-IPs als HCL-Liste, z. B. `["198.51.100.7/32"]` |
| `R2_ACCOUNT_ID` | Cloudflare-Account-ID |
| `K3S_TOKEN` | k3s-Server-Token, mindestens 32 Zeichen, z. B. `openssl rand -hex 32` |
| `ETCD_S3_ACCESS_KEY`, `ETCD_S3_SECRET_KEY` | R2-Token für den Snapshot-Bucket |

Alle Werte außer `HCLOUD_TOKEN` müssen in beiden Environments identisch sein. Sonst zeigt der Plan Änderungen, die es nicht gibt, bei `K3S_TOKEN` und den Snapshot-Zugangsdaten sogar einen Serverwechsel.

### 5. Repository-Einstellungen

Weil das Repository öffentlich ist, zusätzlich:

| Einstellung | Wert | Zweck |
|---|---|---|
| *Settings → Actions → General → Fork pull request workflows* | „Require approval for all external contributors“ | fremde PRs starten keine Workflows ohne Zustimmung |
| *Settings → Rules → Rulesets* für `main` | PR erforderlich; Status-Check `fmt, validate, kubeconform` erforderlich; Force-Push und Löschen verboten | `main` ändert sich nur geprüft über PRs |
| *Settings → Environments → `prod`* | Required reviewers: Repo-Owner; „Prevent self-review“ **aus**; Deployment branches: nur `main` | `apply` nur nach Freigabe |

„Prevent self-review“ muss aus bleiben: Der eigene Merge löst den Lauf aus, und mit der Option ließe er sich nicht selbst freigeben. Eine Genehmigungspflicht für PRs (Required approvals) ist aus demselben Grund nicht sinnvoll, solange nur eine Person am Repository arbeitet.

Fremde PRs bekommen grundsätzlich keine Secrets. Der Workflow nutzt `pull_request`, nicht `pull_request_target`, und das muss so bleiben.

Passphrase und `K3S_TOKEN` zusätzlich sicher aufbewahren, z. B. im Passwortmanager. Ohne die Passphrase ist der State nicht mehr lesbar, ohne den Token lassen sich die etcd-Snapshots nicht wiederherstellen.

### 6. Erster Rollout

1. Pull Request mit den Werten aus Schritt 3 öffnen und den Plan im PR-Kommentar prüfen. Erwartet werden vier neue Ressourcen: SSH-Key, Primary IP, Firewall, Server.
2. Mergen und im Lauf von `tofu` auf `main` das Environment `prod` freigeben.
3. cloud-init braucht danach einige Minuten für Updates, k3s und Argo CD.

### 7. Prüfen

```sh
make kubeconfig
export KUBECONFIG=~/.kube/platform-prod.yaml

kubectl get nodes
kubectl -n argocd get pods
kubectl -n argocd get applications
```

## Konfiguration

### Variablen

Alle Werte, die sich je Umgebung unterscheiden, stehen ohne Default in `tofu/environments/<env>.tfvars`. Die vollständige Liste mit Beschreibungen und Validierungen steht in [`tofu/variables.tf`](tofu/variables.tf).

### Secrets

Secrets und private Werte gehören nie ins Repo, auch nicht in `.tfvars`. Lokal kommen sie aus Umgebungsvariablen:

| Variable | Inhalt |
|---|---|
| `HCLOUD_TOKEN` | Hetzner-API-Token |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | R2-Token für den State-Bucket |
| `TF_VAR_state_passphrase` | Passphrase der State Encryption |
| `TF_VAR_admin_ips` | Admin-IPs, z. B. `'["198.51.100.7/32"]'` |
| `TF_VAR_r2_account_id` | Cloudflare-Account-ID, nötig schon für `make init` |
| `TF_VAR_k3s_token` | k3s-Server-Token, nötig für jede Wiederherstellung |
| `TF_VAR_etcd_s3_access_key`, `TF_VAR_etcd_s3_secret_key` | R2-Token für den Snapshot-Bucket |

State und gespeicherte Pläne sind verschlüsselt (`enforced = true`). Ein unverschlüsselter State wird weder geschrieben noch gelesen.

## Änderungen ausrollen

**Regulär über GitHub:**

1. Branch, Änderung, Pull Request.
2. `checks` prüft fmt, validate und kubeconform. `tofu` schreibt den Plan als Kommentar in den PR.
3. Nach dem Merge speichert `tofu` den Plan von `main`. Der Job `apply` wartet auf die Freigabe von `prod` und wendet genau diesen Plan an.

Ein freigegebener Plan, der inzwischen veraltet ist, wird von OpenTofu abgelehnt. Das Plan-Artefakt wird nach sieben Tagen gelöscht. Danach den Workflow neu starten.

**Lokal**, etwa im Notfall oder ohne GitHub:

```sh
make init     # einmalig je Arbeitskopie, braucht die Umgebungsvariablen
make plan
make apply    # wendet den zuvor gespeicherten Plan an
```

Commits folgen [Conventional Commits](https://www.conventionalcommits.org/): `feat(tofu): …`, `fix(cloud-init): …`, `docs(runbooks): …`.

## Make-Targets

| Target | Beschreibung |
|---|---|
| `make init` | `tofu init` mit Backend; nutzt `ENV`, Standard `prod` |
| `make fmt` | formatiert alle `.tf`- und `.tfvars`-Dateien |
| `make validate` | `tofu init -backend=false` und `tofu validate`; ohne Secrets |
| `make lint` | kubeconform für `bootstrap/` |
| `make check` | `validate`, `lint` und `fmt -check`; entspricht dem CI-Check |
| `make plan` | Plan nach `tofu/<env>.tfplan` |
| `make apply` | wendet den gespeicherten Plan an |
| `make kubeconfig` | holt die kubeconfig per SSH nach `~/.kube/platform-<env>.yaml` |

kubeconform ohne lokale Installation:

```sh
make lint KUBECONFORM="docker run --rm -v $PWD:/work -w /work ghcr.io/yannh/kubeconform:v0.8.0"
```

## Schutzmechanismen

| Risiko | Schutz |
|---|---|
| versehentliches `destroy` | `delete_protection`/`rebuild_protection` bei Hetzner und `prevent_destroy` in OpenTofu für Server und Primary IP |
| ungewollter Serverwechsel | Änderungen an `user_data`, `ssh_keys` oder `image` würden den Server ersetzen; `prevent_destroy` lässt solche Pläne scheitern |
| Verlust der IP | Primary IP mit `auto_delete = false`, unabhängig vom Server |
| offener Admin-Zugang | 22 und 6443 nur für `admin_ips`; die Validierung lehnt `/0`-Netze ab |
| Klartext-Secrets im State | State Encryption mit erzwungener Verschlüsselung |
| ungeprüftes Apply | Apply nur aus gespeichertem Plan, nach Freigabe von `prod`; kein `destroy` im Workflow |
| zu weit reichende Tokens | Read-only-Hetzner-Token für PR-Pläne; R2-Tokens je Bucket |

Ein gewollter Serverwechsel ist ein bewusster Eingriff: Schutz vorübergehend aufheben, Plan prüfen, anwenden, Schutz wiederherstellen. Laufende Projekte sind dabei bis zum Abschluss der neuen Installation nicht erreichbar.

## Versionen und Upgrades

Alle Versionen sind gepinnt und werden vor einer Änderung in der jeweiligen Quelle nachgeschlagen.

| Komponente | Ort | Quelle |
|---|---|---|
| OpenTofu | `tofu/versions.tf`, `.github/workflows/*.yml` | [GitHub-Releases](https://github.com/opentofu/opentofu/releases) |
| hcloud-Provider | `tofu/versions.tf`, `.terraform.lock.hcl` | [search.opentofu.org](https://search.opentofu.org/provider/hetznercloud/hcloud) |
| k3s | `k3s_version` in `prod.tfvars` | [GitHub-Releases](https://github.com/k3s-io/k3s/releases) |
| Argo-CD-Chart | `bootstrap/argocd.yaml` | [ArtifactHub](https://artifacthub.io/packages/helm/argo/argo-cd) |
| GitHub Actions | `.github/workflows/*.yml`, auf Commit-SHA | jeweiliges Repository |

`k3s_version` und die Chart-Version wirken nur beim ersten Start eines Servers. Ein Upgrade im laufenden Betrieb erfolgt für k3s über den System Upgrade Controller und für Argo CD über dessen Selbstverwaltung, beides in `platform-gitops`.

## Bekannte Einschränkungen

- **Single Node.** Fällt der Server aus, sind alle Projekte nicht erreichbar. Die Wiederherstellung erfolgt aus einem etcd-Snapshot, siehe [Runbook](docs/runbooks/restore-etcd-snapshot.md). Embedded etcd erlaubt später weitere Nodes.
- **Snapshot-Zugangsdaten auf dem Server.** Sie liegen in `/etc/rancher/k3s/config.yaml` (0600) und sind über den Hetzner-Metadatendienst abrufbar. Deshalb ist das Token auf den Snapshot-Bucket beschränkt.
- **Doppelte Verwaltung von Argo CD.** Der k3s-`HelmChart` und die Selbstverwaltung in `platform-gitops` müssen dasselbe Release (`argocd` im Namespace `argocd`) verwenden, bis der `HelmChart` stillgelegt ist.

## Abgrenzung zu platform-gitops

Dieses Repo endet mit der Root-Application. Alles Weitere gehört nach `platform-gitops`: Plattform-Komponenten (cert-manager, Sealed Secrets, Gateway-API-Konfiguration, System Upgrade Controller), DNS-Einträge und Domains, Backups der Daten in Volumes sowie alle Projekte. Als Ziel für DNS-Einträge liefert dieses Repo die feste Primary IP (`tofu -chdir=tofu output -raw server_ipv4`). Am Server wird nichts von Hand geändert: kein SSH-Eingriff, kein `kubectl apply`, kein `helm install`.
