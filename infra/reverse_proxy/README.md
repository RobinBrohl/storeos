# Lokaler TLS-Proxy

Das optionale Compose-Profil `tls` startet Caddy mit [Caddyfile](Caddyfile). Caddy bedient den gebauten Flutter-Webclient aus `apps/client_flutter/build/web` und leitet `/api/*` an den internen Dart-Server weiter. Standardbindung ist `127.0.0.1:8443`; Caddy stellt ein Zertifikat aus seiner lokalen CA aus. Für Handhelds und andere Rechner müssen DNS-Name, LAN-Bindung, Firewall und Vertrauensstellung der CA eingerichtet werden. Die Caddy-CA im Volume `caddy_data` gehört zum Wiederherstellungsplan.

Die direkte Serverfreigabe auf Port `8080` und PostgreSQL auf `5432` bleiben auf Loopback beschränkt. Die Konfiguration ist ein lokaler Ausgangspunkt; bevor echte Geräte zugreifen, muss das Zertifikat geprüft und die passende Client-Origin in `.env` gesetzt werden. Für öffentlich erreichbare Dienste ist eine eigene Sicherheits- und Netzarchitektur nötig.
