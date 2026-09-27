# Dauerhafte Entwicklungsregeln

- Lies vor Architektur- oder Facharbeit die [Dokumentation](docs/README.md), insbesondere [Prinzipien](docs/product-principles.md), [Modulgrenzen](docs/architecture/module-boundaries.md) und [ADRs](docs/adr/).
- Baue einen modularen Monolithen. Fachlogik gehört in Domain und Application, nicht in Flutter-Widgets, HTTP-Routen oder Plugins. Module kommunizieren über dokumentierte Schnittstellen und Events; fremde Tabellen bleiben privat.
- Lege vor jedem größeren Modul Domainmodell, Use Cases, Berechtigungen, Events, Auditbedarf und aussagekräftige Tests fest. Halte weitreichende Architekturänderungen als ADR fest.
- Erzwinge Berechtigungen serverseitig. Schütze sensible Mitarbeiterdaten, zeichne relevante Änderungen nachvollziehbar auf und überschreibe Konflikte niemals still.
- Erhalte den eigenständigen Standortbetrieb ohne Internet und die Datenportabilität. Automatisierte Empfehlungen müssen erklärbar sein; personelle Entscheidungen bleiben bei Menschen.
- Liefere keine scheinbar fertigen Funktionen. Ein Feature braucht persistente Daten, Validierung, Rechteprüfung, Fehlerbehandlung, passende Tests und Dokumentation.
