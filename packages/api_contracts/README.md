# API-Verträge

Reines Dart-Package `storeos_api_contracts` für die HTTP-Verträge von P0, P1 und P1b.1. Keine Flutter-, Datenbank- oder Domain-Abhängigkeit. [Basis-OpenAPI](openapi.yaml) und [Plattform-OpenAPI](platform.openapi.json) beschreiben die API maschinenlesbar. Mitarbeiterprofile und Account-Verknüpfungen werden als öffentliche DTOs transportiert; interne Domainmodelle bleiben im jeweiligen Servermodul.

`/api/v1/` ist die erste Vertragsversion. Zusätzliche optionale Antwortfelder sind kompatibel; vorhandene Pflichtfelder, Typen und Semantik bleiben stabil. Breaking Changes erhalten eine neue API-Version. IDs sind opake Referenzen und verleihen keine Berechtigung. Login- und Session-Payloads dürfen nicht geloggt werden.

`dart pub get`, `dart analyze` und `dart test` in diesem Verzeichnis prüfen das Package unabhängig von Flutter. Die Anwendungen binden es lokal über eine Pfadabhängigkeit ein; Lockfiles werden eingecheckt.
