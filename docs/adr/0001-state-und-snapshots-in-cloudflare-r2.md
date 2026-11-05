# 0001: State und etcd-Snapshots in Cloudflare R2

- **Status:** angenommen
- **Datum:** 2026-11-05

## Kontext

Zwei Dinge brauchen einen Speicherort außerhalb des Servers:

1. **OpenTofu-State.** Er muss remote liegen, damit GitHub Actions planen und anwenden können und der State einen Defekt des lokalen Rechners übersteht.
2. **etcd-Snapshots.** k3s legt sie sonst nur auf der Festplatte des Servers ab, wo sie mit dem Server verloren gehen.

Beides ist klein: Der State umfasst wenige Kilobyte, ein Snapshot bei einem kleinen Cluster einige Megabyte. Ursprünglich war Hetzner Object Storage vorgesehen. Das kostet eine monatliche Grundgebühr, die bei dieser Datenmenge in keinem Verhältnis zum Nutzen steht.

## Entscheidung

State und Snapshots liegen in **Cloudflare R2**, in zwei getrennten Buckets:

| Bucket | Inhalt | Zugriff |
|---|---|---|
| State | OpenTofu-State, verschlüsselt mit State Encryption | R2-Token nur für diesen Bucket, in GitHub und lokal |
| Snapshots | etcd-Snapshots von k3s | R2-Token nur für diesen Bucket, auf dem Server |

Technische Eckpunkte:

- Endpoint `https://<account-id>.r2.cloudflarestorage.com`, Region `auto`, Path-Style-Adressierung.
- Locking über `use_lockfile`. R2 unterstützt die dafür nötigen bedingten Schreibvorgänge (`If-None-Match`) laut Cloudflare-Doku.
- Die Buckets werden einmalig von Hand angelegt, weil OpenTofu den Bucket für seinen eigenen State nicht selbst anlegen kann.

## Konsequenzen

**Positiv**

- Im kostenlosen Kontingent von R2 entstehen für diese Datenmenge keine Kosten.
- S3-kompatibel: OpenTofu-Backend und k3s brauchen nur Endpoint und Region.
- Getrennte Tokens: Das Token auf dem Server reicht nicht an den State.

**Negativ**

- Ein weiterer Anbieter und ein weiteres Konto neben Hetzner.
- Die Daten liegen außerhalb von Hetzner. Der State ist verschlüsselt. Die Snapshots enthalten Kubernetes-Secrets, und die Bootstrap-Daten darin sind mit dem k3s-Token verschlüsselt.
- Die Verbindung lässt sich nur mit einem echten Account prüfen. R2 lehnt unbekannte Account-IDs bereits beim TLS-Handshake ab.

## Betrachtete Alternativen

| Alternative | Warum nicht |
|---|---|
| Hetzner Object Storage | monatliche Grundgebühr für wenige Megabyte |
| State lokal | kein CI möglich, Sicherung liegt beim Nutzer |
| State verschlüsselt im Git-Repo | kein Locking, Risiko von State-Verlust bei fehlgeschlagenem Push |
| Backblaze B2 | ebenfalls möglich; R2 gewählt |
| keine Snapshots außerhalb des Servers | kein Backup, das einen Serververlust übersteht |
