# StoreOS-Standortserver (P0)

Dieser Dart-Prozess stellt nur die Plattformbasis bereit: Betriebspunkte,
lokale Anmeldung, standortgebundene Sitzung und einen authentifizierten
Systemstatus. Fachmodule und der spätere Vertical Slice sind hier noch nicht
implementiert.

## Start und Datenbankrollen

Die drei Befehle werden aus `apps/server` ausgeführt:

```text
dart run bin/migrate.dart
dart run bin/bootstrap.dart
dart run bin/server.dart
```

`migrate.dart` wendet versionierte SQL-Migrationen unter einer transaktionalen
Datenbanksperre an. Bereits angewandte Versionen und deren Prüfsummen werden
geprüft; unbekannte oder nachträglich geänderte Migrationen stoppen den Lauf.
`bootstrap.dart` legt genau einen ersten lokalen Account an und lehnt jeden
erneuten Bootstrap ab. Das Passwort wird ausschließlich aus einer Datei gelesen
und nie ausgegeben. Beide CLI-Befehle benötigen die Migrationsrolle.

Der HTTP-Prozess verwendet dagegen die eingeschränkte Runtime-Rolle. Die
Migration vergibt ihr nur Schema-Nutzung, Lesezugriff auf Migrationen und
Accounts sowie die für Sitzungen benötigten Rechte. Tabellenanlage und
Bootstrap-State bleiben der Migrationsrolle vorbehalten. Migration und
Bootstrap laufen nicht automatisch beim Serverstart.

Erforderliche Umgebungsvariablen:

| Variable | Zweck |
| --- | --- |
| `STOREOS_DB_HOST`, `STOREOS_DB_PORT`, `STOREOS_DB_NAME` | PostgreSQL-Ziel; Host und Port standardmäßig `127.0.0.1:5432` |
| `STOREOS_DB_USER`, `STOREOS_DB_PASSWORD_FILE` | Runtime-Rolle und Passwortdatei; alternativ `STOREOS_DB_PASSWORD` für lokale Entwicklung |
| `STOREOS_DB_MIGRATION_USER`, `STOREOS_DB_MIGRATION_PASSWORD_FILE` | Owner-Rolle für Migration und Bootstrap; alternativ direktes Passwort für lokale Entwicklung |
| `STOREOS_COMPANY_ID`, `STOREOS_LOCATION_ID` | Feste UUIDs des lokalen P0-Geltungsbereichs, für Bootstrap und HTTP benötigt |
| `STOREOS_BOOTSTRAP_USERNAME`, `STOREOS_BOOTSTRAP_PASSWORD_FILE` | Erst-Account; Passwort mindestens 24 und höchstens 1024 UTF-8-Bytes |

Optional sind `STOREOS_HOST` (Standard `127.0.0.1`), `STOREOS_PORT`
(Standard `8080`), `STOREOS_ALLOWED_ORIGINS` (kommagetrennte exakte
HTTP(S)-Origins), `STOREOS_SESSION_TTL_SECONDS` (60 bis 86400, Standard 3600)
und `STOREOS_DB_SSL_MODE` (`disable` oder `verify-full`). Bei `_FILE`-Variablen
ist die direkte Variante desselben Secrets unzulässig. Der Server liest keine
`.env`-Datei selbst; Docker Compose oder die lokale Shell stellen die Umgebung.

## HTTP-API v1

| Route | Verhalten |
| --- | --- |
| `GET /health` | Prozess lebt: `200 {"status":"ok"}` |
| `GET /ready` | Datenbank und erforderliche Migration erreichbar: `200 {"status":"ok"}`, sonst `503 {"status":"unavailable"}` |
| `POST /api/v1/auth/login` | JSON mit `username`, `password`; gibt ein zeitlich begrenztes Bearer-Token und User-Scope zurück |
| `POST /api/v1/auth/logout` | Widerruft die aktuelle Sitzung; `204` |
| `GET /api/v1/locations/{locationId}/system/status` | Erfordert gültige Sitzung im konfigurierten Company-/Location-Scope |

Passwörter werden mit Argon2id und individuellem Salt gespeichert. Die
Datenbank enthält nur SHA-256-Digests der zufälligen Session-Token. Abläufe,
Widerruf und inaktive Accounts werden serverseitig geprüft. Das Login hat ein
prozesslokales Versuchslimit und begrenzt gleichzeitige Passwortprüfungen;
bei mehreren Serverprozessen muss ein vorgeschaltetes globales Limit ergänzt
werden. JSON-Logs enthalten keine Passwörter oder Token. Bei externer
Erreichbarkeit muss ein TLS-terminierender Reverse Proxy davorstehen.

## Tests

`dart analyze` und `dart test` prüfen Konfiguration, Hashes, HTTP-Verhalten
und Authentifizierung. Datenbanktests laufen nur, wenn
`STOREOS_TEST_DATABASE` eine PostgreSQL-URL mit Zugang zu einer eigens
bereitgestellten Testdatenbank enthält. Jeder Lauf erzeugt ein zufälliges
Schema und entfernt ausschließlich dieses Schema wieder. Er prüft
Migrationen einschließlich Rollback und Prüfsumme, Rechte, konkurrierenden
Bootstrap und Session-Lebenszyklus. Eine bestehende Produktivdatenbank darf
nicht als Testdatenbank angegeben werden.
