# Lokaler Standortbetrieb mit Compose

`compose.yaml` startet standardmäßig nur PostgreSQL 17. Der Datenport ist für die Entwicklung an `127.0.0.1:5432` gebunden. Der Server kann mit lokal installiertem Dart/Flutter laufen; die optionalen Profile `migrate`, `bootstrap`, `app` und `tls` bieten Container-Alternativen. Es wird kein Herstellerdienst benötigt.

Vor dem ersten Start erzeugt `scripts/dev.ps1 Setup` die ignorierte `.env` und vier zufällige Dateien in `.local/secrets/`:

| Datei | Zweck |
| --- | --- |
| `db_owner_password.txt` | PostgreSQL-Owner für Migration und Restore |
| `db_password.txt` | eingeschränkter Runtime-Account `storeos` |
| `bootstrap_password.txt` | einmalige lokale Erstanlage |
| `backup_key.bin` | 32-Byte-Schlüssel für verschlüsselte Datenbanksicherungen |

Die Dateien dürfen nicht eingecheckt werden. Der Backup-Schlüssel muss für eine echte Wiederherstellung unabhängig vom Standortserver geschützt verfügbar sein. Die beiden DB-Passwörter werden nach der Initialisierung eines Volumes nicht durch Änderung der Dateien automatisch in PostgreSQL geändert.

```powershell
docker compose up -d db
docker compose --profile migrate run --build --rm migrator
docker compose --profile bootstrap run --build --rm bootstrap
```

Danach kann `apps/server` mit dem Host-SDK über `scripts/dev.ps1 server` gestartet werden. Für die Container-Variante:

```powershell
docker compose --profile app up -d --build app
```

Der `app`-Container hat nur das Runtime-Passwort; Owner-Rechte sind ausschließlich in den einmaligen `migrator`- und `bootstrap`-Containern verfügbar. Der API-Port ist lokal an `127.0.0.1:8080` gebunden. Für den Zugriff anderer Geräte wird TLS über den Proxy benötigt. Eine bereits initialisierte Datenbank erhält bei einem Wechsel der Compose-Konfiguration keine erneuten Initdb-Skripte; Rechteänderungen benötigen eine gezielte Migration, keine Volume-Löschung.

## Optionaler Webclient mit lokalem TLS

Das Profil `tls` bedient einen zuvor in `apps/client_flutter` gebauten Webclient und leitet `/api/*` an `app` weiter. `--no-web-resources-cdn` hält Flutter-Web-Ressourcen im eigenen Webverzeichnis; `STOREOS_API_URL` muss auf die tatsächlich verwendete TLS-Origin zeigen, damit der Browser keine unsicheren HTTP-API-Aufrufe ausführt. Standardmäßig bindet es nur `127.0.0.1:8443` und nutzt Caddys lokale Zertifizierungsstelle. Deren Root-Zertifikat muss auf jedem Clientgerät bewusst vertraut werden; ein bloßes `https://` ohne Zertifikatsprüfung ist kein sicherer Betrieb.

```powershell
Push-Location apps/client_flutter
flutter build web --release --no-web-resources-cdn --dart-define=STOREOS_API_URL=https://localhost:8443
Pop-Location
docker compose --profile tls up -d --build app proxy
```

Für die Standardadresse muss `STOREOS_ALLOWED_ORIGINS` ausdrücklich `https://localhost:8443` enthalten, auch wenn Browser und API denselben Ursprung verwenden. Für Zugriff im Standort-LAN müssen `STOREOS_TLS_BIND` auf eine konkrete LAN-Adresse und `STOREOS_TLS_SITE` auf den passenden DNS-Namen gesetzt werden; die erlaubte Origin wird entsprechend angepasst. Diese Freigabe braucht Firewall-, DNS- und Zertifikatsprüfung. Der Entwicklungsport `8080` bleibt nur auf Loopback. Das Profil ist eine lokale Referenzkonfiguration; öffentliche Erreichbarkeit oder ein produktiver Zertifikatsbetrieb werden dadurch nicht eingerichtet.

Die Caddy-CA liegt im Volume `caddy_data`. Bei einem Restore für dieselben Clientgeräte sind CA und Schlüssel zusammen mit Konfiguration und Secrets gesondert zu sichern; das Datenbanksicherungsskript deckt diese Dateien nicht ab.
