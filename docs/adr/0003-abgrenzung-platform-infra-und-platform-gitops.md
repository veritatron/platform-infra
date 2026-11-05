# 0003: Abgrenzung zwischen platform-infra und platform-gitops

- **Status:** angenommen
- **Datum:** 2026-11-05

## Kontext

Die Plattform besteht aus zwei Repositories:

- `platform-infra` stellt den Server bereit, mit OpenTofu und cloud-init.
- `platform-gitops` beschreibt alles, was im Cluster läuft, und wird von Argo CD angewendet.

Viele Aufgaben ließen sich in beiden Repos lösen, etwa DNS-Einträge, Zertifikate oder Upgrades von k3s und Argo CD. Ohne klare Regel wandert so etwas nach Bequemlichkeit in eines der beiden, und mit der Zeit ist unklar, wo was steht.

Die beiden Repos unterscheiden sich grundlegend:

| | platform-infra | platform-gitops |
|---|---|---|
| Anwendung | Plan und Apply mit Freigabe | Argo CD gleicht laufend ab |
| Fehler | können den Server ersetzen | betreffen einzelne Komponenten |
| Änderungshäufigkeit | selten | regelmäßig |

## Entscheidung

**In `platform-infra` gehört nur, was da sein muss, bevor der Cluster läuft. Alles, was sich auch danach erledigen lässt, gehört nach `platform-gitops`.**

| platform-infra | platform-gitops |
|---|---|
| Server, Primary IP, Firewall, SSH-Key | Plattform-Komponenten: cert-manager, Sealed Secrets, Gateway-API-Konfiguration |
| State-Backend und State Encryption | DNS-Einträge und Domains |
| k3s-Installation mit Einstellungen, die nur bei der Installation gehen: Version, `cluster-init`, Token, etcd-Snapshots, `tls-san` | k3s-Upgrades über den System Upgrade Controller |
| Bootstrap: Argo CD als k3s-`HelmChart` und die Root-Application | Argo CD in jeder späteren Version, als Selbstverwaltung |
| | Backups der Daten in Volumes |
| | alle Projekte |

Prüffrage bei jeder neuen Aufgabe: *Kann Argo CD das erledigen, sobald der Cluster läuft?* Wenn ja, gehört es nach `platform-gitops`.

### Warum k3s trotzdem hier installiert wird

k3s ist der Cluster selbst. Argo CD läuft auf k3s und kann es deshalb nicht installieren. Die Installation muss vorher passieren, also beim ersten Start über cloud-init. Hier liegt nur die Erstinstallation. Danach verwaltet `platform-gitops` k3s über den System Upgrade Controller. Die k3s-Version in `prod.tfvars` gilt damit nur für neu angelegte Server.

Dasselbe gilt für Argo CD: Es muss einmal installiert werden, damit es überhaupt etwas aus Git lesen kann. Danach übernimmt es seine eigene Verwaltung.

### Warum DNS nicht hier liegt

DNS-Einträge werden erst gebraucht, wenn eine Anwendung unter einem Namen erreichbar sein soll, also nach dem Aufbau. Im Cluster lassen sie sich zusammen mit der Anwendung verwalten, etwa mit external-dns. Dieses Repo liefert nur die feste Primary IP als Ziel (`server_ipv4`).

## Konsequenzen

**Positiv**

- Dieses Repo bleibt klein und wird selten geändert. Das passt zu seinem Risiko: Ein Fehler kann hier den Server betreffen.
- Änderungen an Plattform-Komponenten und Projekten laufen über Argo CD, ohne Plan und Freigabe in diesem Repo.
- Die Zuständigkeit ist mit einer einzigen Prüffrage entscheidbar.

**Negativ**

- Für eine kurze Zeit verwalten zwei Mechanismen Argo CD: der k3s-`HelmChart` und die Selbstverwaltung. Beide müssen dasselbe Release (`argocd` im Namespace `argocd`) verwenden, bis der `HelmChart` stillgelegt ist.
- Die k3s-Version in `prod.tfvars` und die tatsächlich laufende Version können auseinanderlaufen, sobald der System Upgrade Controller ein Upgrade gemacht hat. Bei laufendem Server bleiben die Werte bewusst stehen, weil jede Änderung an `user_data` den Server ersetzen würde. Erst unmittelbar vor dem Anlegen eines neuen Servers werden `k3s_version`, `k3s_install_script_commit` und `k3s_install_script_sha256` gemeinsam auf den aktuellen Stand gebracht. Sonst startet der neue Server mit einer älteren Version als der Snapshot, der darauf wiederhergestellt wird.
- Der Zugriff auf den DNS-Anbieter liegt im Cluster, als Secret für external-dns und cert-manager.

## Betrachtete Alternativen

| Alternative | Warum nicht |
|---|---|
| DNS-Einträge in OpenTofu (`dns.tf`) | wird erst nach dem Aufbau gebraucht und gehört zur jeweiligen Anwendung |
| k3s über ein fertiges Image (Packer) | zusätzliches Werkzeug und eigene Image-Pflege, für einen Node ohne Mehrwert |
| k3s über Ansible | zusätzliches Werkzeug, und Änderungen per SSH widersprechen „nichts von Hand auf dem Server“ |
| k3s-Upgrades durch einen neuen Server | ersetzt den Server bei jedem Upgrade, mit Ausfall aller Projekte |
