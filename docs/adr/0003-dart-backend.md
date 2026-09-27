# ADR 0003: Dart für das Backend

## Status

Beschlossen für die Startarchitektur.

## Kontext

StoreOS nutzt Flutter im Client und benötigt einen lokalen Server für Fachlogik, Authentifizierung, Transaktionen und Schnittstellen. Ein gemeinsames Sprachökosystem kann die Pflege von Verträgen erleichtern; Flutter selbst ist kein Serverframework.

## Entscheidung

Das Backend wird in reinem Dart erstellt. HTTP-Transport, Persistenz, Jobs und Ereignisverarbeitung bleiben hinter austauschbaren Schnittstellen. API-Verträge werden versioniert und maschinenlesbar beschrieben; Client und Server teilen nur bewusst stabile Typen, keine Infrastrukturmodelle. Der Server muss ohne Flutter-Laufzeit startbar sein.

## Alternativen

- Backend in einer anderen etablierten Serversprache: größeres Ökosystem in manchen Bereichen, aber zusätzliche Sprach- und Vertragsgrenzen.
- Geschäftslogik in Flutter oder direkt in HTTP-Routen: verworfen, weil sie Berechtigungen und Tests über Oberflächen und Transport verteilt.

## Konsequenzen

- Das Team kann Sprache und Typmodell über Client und Server hinweg nutzen.
- Bibliotheken für PostgreSQL, Migrationen, Authentifizierung, Observability und Pluginprozesse müssen vor Festlegung der konkreten Frameworks auf Wartbarkeit geprüft werden.
- Gemeinsamer Code darf keine Kopplung erzeugen, die getrennte Releases verhindert.

## Offene Prüfungen

- Geeignete Dart-HTTP-, Datenbank- und Migrationsbibliotheken anhand eines kleinen technischen Spikes bewerten.
- Sicherheitsupdates, Runtime-Support und Deployment auf der vorgesehenen Standort-Hardware prüfen.
