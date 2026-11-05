# 0002: Plan und Apply über GitHub Actions mit Freigabe

- **Status:** angenommen
- **Datum:** 2026-11-05

## Kontext

Laut Arbeitsweise in `CLAUDE.md` wendet nur der Nutzer einen Plan an, und das erst, nachdem er ihn gesehen hat. Ursprünglich sollte das lokal per `make apply` geschehen. Das hat Nachteile:

- Lokal sind passende Werkzeuge nötig: OpenTofu in der richtigen Version und `make`.
- Alle Secrets müssen auf dem lokalen Rechner liegen.
- Es gibt keine nachvollziehbare Historie, wer wann was angewendet hat.

## Entscheidung

OpenTofu läuft regulär in GitHub Actions:

1. **Pull Request:** `tofu plan`, das Ergebnis erscheint als Kommentar im PR.
2. **Push auf `main`:** Der Plan wird erneut erstellt und als Artefakt gespeichert. Das Artefakt ist mit der Plan-Verschlüsselung geschützt.
3. **Apply:** Der Job hängt am Environment `prod` mit Required Reviewers und läuft nur von `main`. Nach der Freigabe wendet er genau den gespeicherten Plan an.

Dazu gehören zwei Environments mit getrennten Rechten:

| Environment | Hetzner-Token | Schutz |
|---|---|---|
| `prod-plan` | Read | keiner |
| `prod` | Read & Write | Required Reviewers, nur `main` |

Ein `destroy` gibt es im Workflow nicht. Lokales Arbeiten mit `make plan`/`make apply` bleibt als Notfallweg erhalten.

## Konsequenzen

**Positiv**

- Lokal sind weder Werkzeuge noch Secrets nötig, außer für `make kubeconfig`.
- Jede Änderung hat einen PR, einen sichtbaren Plan und eine protokollierte Freigabe.
- Ein veralteter Plan wird von OpenTofu abgelehnt. Es wird nie etwas anderes angewendet als das, was freigegeben wurde.
- PR-Pläne können mit dem Read-Token nichts verändern.

**Negativ**

- Die Secrets liegen in GitHub. Das Hetzner-Token mit Schreibrecht hat Vollzugriff auf das Projekt. Hetzner bietet keine kurzlebigen Zugangsdaten über OIDC; das ist nach aktuellem Kenntnisstand angenommen, aber nicht nachgeprüft.
- Das Repository ist öffentlich, also sind auch Pläne, PR-Kommentare und Logs öffentlich. Private Werte wie Admin-IPs und die Cloudflare-Account-ID kommen deshalb als Secrets und erscheinen nicht im Klartext. Required Reviewers sind für öffentliche Repositories kostenlos.
- Fremde PRs dürfen nie an Secrets kommen. Der Workflow nutzt deshalb `pull_request`, nicht `pull_request_target`, und Workflows aus Forks brauchen eine Zustimmung.

## Betrachtete Alternativen

| Alternative | Warum nicht |
|---|---|
| nur lokal | siehe Kontext |
| Atlantis, Spacelift, HCP Terraform | eigene Plattform für ein einzelnes, selten geändertes Repo überdimensioniert |
| Apply vor dem Merge (Atlantis-Stil) | für eine Person ohne Mehrwert gegenüber Apply nach dem Merge |
| Apply automatisch ohne Freigabe | widerspricht der Regel, dass nur der Nutzer anwendet |
