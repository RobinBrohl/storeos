# StoreOS

StoreOS ist ein langfristig angelegtes, quelloffenes Betriebssystem für standortgebundene Unternehmen. Es soll tägliche Arbeit, Wissen und betriebliche Daten in einer selbst betriebenen Plattform verbinden. Der erste fachliche Schwerpunkt ist die geführte Arbeit von Mitarbeitenden.

**Projektstand:** Architektur und Repository-Struktur. Es gibt noch keinen ausführbaren Server, Client oder Fachmodule.

## Einstieg

- [Vision](docs/vision.md) und [Produktprinzipien](docs/product-principles.md)
- [Architektur](docs/architecture/overview.md), [kritische Prüfung](docs/risks-and-open-questions.md) und [ADRs](docs/adr/)
- [Entwicklungsphasen](docs/roadmap/phases.md) und [Compliance-Überblick](docs/compliance/overview.md)
- [Regeln für Mitwirkende und Agenten](AGENTS.md)

## Repository

```text
apps/       Auslieferbare Server- und Flutter-Anwendungen
packages/   Technische, fachlich neutrale Verträge und UI-Bausteine
modules/    Fachliche Module des modularen Monolithen (noch nicht angelegt)
plugins/    Spätere externe Erweiterungen und Beispiele
infra/      Spätere Betriebsartefakte für Installation und Backup
docs/       Verbindliche Produkt- und Architekturgrundlagen
```

Die angelegten Unterverzeichnisse enthalten derzeit nur Platzhalter. Ein Verzeichnis ist keine Zusage, dass die jeweilige Funktion schon existiert.

## Lizenz

Der Repository-Quelltext steht unter der [GNU AGPLv3](LICENSE). Vor dem Einbringen fremder Komponenten oder proprietärer Integrationen sind deren Lizenzbedingungen gesondert zu prüfen.
