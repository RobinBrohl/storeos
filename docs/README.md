# Dokumentationsindex

Diese Dokumente verdichten die vom Projektgründer bereitgestellte StoreOS-Produktvision. Die Architektur beschreibt überwiegend das Zielbild; der tatsächliche Implementierungsumfang steht in der [Phase-0-Grundlage](development/phase-0.md), [Phase-1-Plattform](development/phase-1.md) und der [Startanleitung](../README.md). Bei Konflikten gilt: konkrete ADR für eine Architekturentscheidung, [Produktprinzipien](product-principles.md) für Wertkonflikte, [Fahrplan](roadmap/phases.md) für die Reihenfolge.

- [Vision](vision.md) – Problem, Nutzen, Zielbild und bewusste Grenzen
- [Produktprinzipien](product-principles.md) – dauerhafte Prioritäten
- [Kritische Prüfung und offene Fragen](risks-and-open-questions.md) – Spannungen und Entscheidungsbedarf
- [Architekturüberblick](architecture/overview.md) – Systemkontext und Bausteine
- [Domainmodell](architecture/domain-model.md), [Modulgrenzen](architecture/module-boundaries.md), [Workforce Orchestration](architecture/workforce-orchestration.md), [Guided Work](architecture/guided-work.md)
- [Event-System](architecture/event-system.md), [Plugin-System](architecture/plugin-system.md), [Sicherheit](architecture/security.md), [Offline-Strategie](architecture/offline-strategy.md), [Deployment](architecture/deployment.md), [Datenhoheit](architecture/data-ownership.md)
- [Entwicklungsphasen](roadmap/phases.md), [Compliance](compliance/overview.md), [Architekturentscheidungen](adr/)
- [Phase-1-Prüfnachweis](development/phase-1-verification.md) – Tests, Migration, Browser-Smoke und Restore
- [Implementierungsreview nach P1](development/implementation-review-2026-09-27.md) – Befunde, Korrekturen und zusätzliche Sicherheitsprüfungen
- [P1b.1 – Mitarbeiteridentität und Eigenansicht](development/phase-1b-employee.md) – Umfang, Eigentümer, Rechte, API und Abnahme
- [P1b.1-Prüfnachweis](development/phase-1b-verification.md) – Tests, Upgrade, Browser-Smoke, Restore und geänderte Dateien
- [Review des P1b.1-Entwicklungszyklus](development/phase-1b-review-2026-09-27.md) – konkrete Befunde, Korrekturen, Regressionstests und verbleibende Grenzen

Änderungen an Verhalten, Eigentümerschaft von Daten oder Modulgrenzen aktualisieren die betroffenen Dokumente im selben Arbeitsschritt. Eine verworfene ADR wird durch eine neue ersetzt und im alten Dokument als überholt markiert.
