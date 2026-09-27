# ADR 0004: PostgreSQL als persistente Serverdatenbank

## Status

Beschlossen für die Startarchitektur.

## Kontext

Schichten, Aufgaben, Abschlüsse und Auditdaten brauchen transaktionale Persistenz. Später folgen Bestand, Geld und Nachweise mit höheren Anforderungen an Integrität und Abfragen. Der Standortbetrieb muss ohne externen Datenbankdienst möglich sein.

## Entscheidung

Jeder Standortserver verwendet eine lokal betreibbare PostgreSQL-Instanz als primäre Serverdatenbank. Ein optionaler Unternehmensserver besitzt eine eigene Instanz und synchronisiert über definierte Verträge, nicht über gemeinsame Tabellen oder direkten Fernzugriff. Schemaänderungen erfolgen versioniert mit getesteten Migrationen. Transaktionen sichern zusammengehörige Fachänderungen, Event-Outbox und Auditeinträge. Dateien und große Nachweise werden mit referenzierten Metadaten und abgestimmtem Backup gespeichert.

## Alternativen

- Eingebettete Datenbank als alleinige Serverdatenbank: einfacher Start, aber Eignung für parallele Nutzer und komplexe Integrität müsste separat nachgewiesen werden.
- Eine gemeinsame zentrale Datenbank aller Standorte: verworfen, weil der Standort dann bei WAN-Ausfall abhängig wäre.

## Konsequenzen

- Betrieb benötigt Datenbankpflege, Backups, Restoretests und Migrationsdisziplin.
- PostgreSQL löst weder Konflikte zwischen Standorten noch Ausfälle einzelner Geräte automatisch.
- Client-Offlinecache ist eine eigene technische Entscheidung und keine zweite gleichberechtigte Fachquelle.

## Offene Prüfungen

- Hardwareprofil, Speicherbedarf, Verschlüsselung der Datenträger und Restoreziel je Standort bestimmen.
- Backupkonsistenz für Datenbank und Dateiablage nachweisen.
