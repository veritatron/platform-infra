# Wiederherstellung aus einem etcd-Snapshot

Stellt den Cluster-Zustand aus einem etcd-Snapshot in Cloudflare R2 wieder her.

Dies ist die einzige dokumentierte Ausnahme von der Regel „nichts von Hand auf dem Server“. Die Wiederherstellung lässt sich nicht über Git erledigen, weil Argo CD selbst Teil des wiederhergestellten Zustands ist.

## Wann

| Lage | Vorgehen |
|---|---|
| Server läuft, Cluster-Zustand ist defekt (z. B. versehentlich gelöschte Ressourcen, kaputtes etcd) | [A: auf dem bestehenden Server](#a-auf-dem-bestehenden-server) |
| Server ist verloren oder muss neu aufgesetzt werden | [B: auf einem neuen Server](#b-auf-einem-neuen-server) |

Fehlen nur einzelne Anwendungen, ist meist keine Wiederherstellung nötig. Argo CD stellt aus `platform-gitops` alles wieder her, was in Git steht.

## Was ein Snapshot enthält

| Enthalten | Nicht enthalten |
|---|---|
| alle Kubernetes-Objekte, auch Secrets und den Schlüssel von Sealed Secrets | Daten in Volumes (Datenbanken, Uploads) |
| Zertifikate und CA des Clusters | alles, was nach dem Snapshot entstanden ist |
| Zustand von Argo CD | |

Daten in Volumes brauchen ein eigenes Backup aus `platform-gitops`.

## Voraussetzungen

- SSH-Zugang von einer Adresse aus `admin_ips`
- der **k3s-Token** (`K3S_TOKEN`), derselbe wie beim Anlegen des Snapshots. Er steht bereits in `/etc/rancher/k3s/config.yaml`, solange der Server aus demselben `user_data` gebaut wurde. Ohne ihn ist der Snapshot unbrauchbar.
- R2-Zugang über die k3s-Konfiguration auf dem Server; hier ist nichts zusätzlich nötig

## A: auf dem bestehenden Server

1. Anmelden:

   ```sh
   ssh root@"$(tofu -chdir=tofu output -raw server_ipv4)"
   ```

2. Verfügbare Snapshots anzeigen und den gewünschten Namen notieren:

   ```sh
   k3s etcd-snapshot list
   ```

3. k3s stoppen:

   ```sh
   systemctl stop k3s
   ```

4. Snapshot wiederherstellen. Da die S3-Einstellungen in `/etc/rancher/k3s/config.yaml` stehen, holt k3s den Snapshot selbst aus R2. Anzugeben ist nur der Name, kein Pfad:

   ```sh
   k3s server --cluster-reset --cluster-reset-restore-path=<snapshot-name>
   ```

   Erfolgreich ist der Schritt, wenn diese Meldung erscheint:

   ```
   Managed etcd cluster membership has been reset, restart without --cluster-reset flag now.
   ```

5. k3s normal starten:

   ```sh
   systemctl start k3s
   ```

6. [Prüfen](#prüfen).

k3s legt bei einem Reset `/var/lib/rancher/k3s/server/db/reset-flag` an. Die Datei verhindert einen zweiten Reset direkt hintereinander und verschwindet beim nächsten normalen Start.

## B: auf einem neuen Server

Die Primary IP bleibt erhalten (`auto_delete = false`). Der neue Server bekommt also dieselbe Adresse, und DNS-Einträge müssen nicht geändert werden.

1. **Neuen Server anlegen.**
   - *Server existiert nicht mehr:* PR öffnen oder den Workflow `tofu` auf `main` neu starten. Der Plan muss genau eine neue Ressource zeigen, `hcloud_server.control_plane`. Danach freigeben.
   - *Server existiert noch, soll aber ersetzt werden:* Das ist ein bewusster Eingriff. Siehe README, Abschnitt [Schutzmechanismen](../../README.md#schutzmechanismen). Schutz aufheben, Plan prüfen, anwenden, Schutz wiederherstellen.

2. **Warten, bis cloud-init fertig ist.** Der neue Server installiert k3s mit demselben Token und legt die Bootstrap-Manifeste ab. Den Fortschritt zeigt:

   ```sh
   ssh root@<ip> cloud-init status --wait
   ```

   Der alte SSH-Host-Key passt nicht mehr. Vorher entfernen:

   ```sh
   ssh-keygen -R <ip>
   ```

3. **Snapshot wiederherstellen** wie in [A](#a-auf-dem-bestehenden-server), Schritte 2 bis 5. Der frisch installierte Cluster wird dabei durch den Stand aus dem Snapshot ersetzt.

4. **kubeconfig neu holen:**

   ```sh
   make kubeconfig
   ```

5. [Prüfen](#prüfen).

## Prüfen

```sh
kubectl get nodes
kubectl get pods -A
kubectl -n argocd get applications
```

Erwartet:

- Der Node `platform-cp-1` ist `Ready`.
- Die Pods in `kube-system` und `argocd` laufen.
- Die Applications sind `Synced` und `Healthy`. Argo CD gleicht dabei alles an den aktuellen Stand von `platform-gitops` an, auch was sich seit dem Snapshot in Git geändert hat.

Danach prüfen, ob Daten in Volumes aus deren eigenem Backup wiederhergestellt werden müssen.

## Testen

Ein Runbook, das nie geübt wurde, funktioniert im Ernstfall selten. Empfohlen ist, die Wiederherstellung nach dem ersten Aufbau einmal durchzuspielen: Snapshot auswählen, Schritte A ausführen, prüfen. Variante B lässt sich nur mit einem zweiten Server oder einem Serverwechsel testen.
