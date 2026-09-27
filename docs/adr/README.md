# Architecture Decision Records

ADRs halten langlebige Entscheidungen samt Alternativen und Folgen fest. Die Nummern sind stabil; eine Änderung der Grundentscheidung bekommt eine neue ADR und verlinkt die abgelöste. Details, die vor der Implementierung noch geprüft werden müssen, stehen im Abschnitt „Offene Prüfungen“ und sind keine stillschweigend freigegebenen Features.

| Nr. | Entscheidung |
| --- | --- |
| [0001](0001-modularer-monolith.md) | Modularer Monolith |
| [0002](0002-flutter-client.md) | Flutter als gemeinsamer Client |
| [0003](0003-dart-backend.md) | Dart als Backend |
| [0004](0004-postgresql.md) | PostgreSQL |
| [0005](0005-local-first-self-hosted.md) | Local-first und Self-hosted |
| [0006](0006-standort-und-unternehmensserver.md) | Standortserver und optionaler Unternehmensserver |
| [0007](0007-plugin-architektur.md) | Plugin-Architektur |
| [0008](0008-event-system.md) | Event-System |
| [0009](0009-audit-trail.md) | Audit Trail |
| [0010](0010-offline-und-sync-strategie.md) | Offline- und Synchronisationsstrategie |
| [0011](0011-atomare-schichtveroeffentlichung.md) | Atomare Schichtveröffentlichung im ersten Slice |
| [0012](0012-phase-1-plattform-und-plugin-api.md) | Vorgezogene Plattformverwaltung und minimale Plugin-API |

Neue ADRs verwenden „Kontext“, „Entscheidung“, „Alternativen“, „Konsequenzen“ und „Offene Prüfungen“ sowie einen Status wie „Vorgeschlagen“, „Beschlossen“ oder „Abgelöst durch ADR …“.
