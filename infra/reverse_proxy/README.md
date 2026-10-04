# Lokaler TLS-Proxy

Das optionale Compose-Profil `tls` startet Caddy mit [Caddyfile](Caddyfile). Caddy bedient den gebauten Flutter-Webclient aus `apps/client_flutter/build/web` und leitet `/api/*` an den internen Dart-Server weiter. Standardbindung ist `127.0.0.1:8443`; Caddy stellt ein Zertifikat aus seiner lokalen CA aus. Für Handhelds und andere Rechner müssen DNS-Name, LAN-Bindung, Firewall und Vertrauensstellung der CA eingerichtet werden. Die Caddy-CA im Volume `caddy_data` gehört zum Wiederherstellungsplan.

Die direkte Serverfreigabe auf Port `8080` und PostgreSQL auf `5432` bleiben auf Loopback beschränkt. Die Konfiguration ist ein lokaler Ausgangspunkt; bevor echte Geräte zugreifen, muss das Zertifikat geprüft und die passende Client-Origin in `.env` gesetzt werden. Für öffentlich erreichbare Dienste ist eine eigene Sicherheits- und Netzarchitektur nötig.

## Current real-user pilot gate — M1

The current login limiter derives its remote key from the socket peer. Behind
this proxy, users share the proxy's failure bucket (30 failures per 15 minutes),
which can lock out unrelated site logins. Per-username limits still apply.
Do not infer working per-client throttling from TLS or the reference proxy setup.

Before proxied real users, decide and test a trusted-proxy attribution design or
an explicit operator exposure mitigation. Arbitrary forwarded headers must not
be trusted. The proxy configuration and limiter are unchanged by this documentation
pass. See [technical debt](../../docs/development/technical-debt.md) and
[security](../../docs/architecture/security.md). Public publishing and remote
self-service require separate future access contracts.
