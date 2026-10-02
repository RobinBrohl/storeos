# Dokumentationsindex

**Current entry points:** [HANDOVER](HANDOVER.md) is the starting point for a new coding agent; [actual status](roadmap/status.md) records implemented scope, [workflow](development/workflow.md) defines the English technical-language policy, and [handover verification](development/handover-verification.md) records the latest checks. Older phase reports are historical evidence; architecture documents also describe planned capabilities.

These documents preserve the founder's StoreOS vision. Architecture describes the target and explicitly bounded implementations; [actual status](roadmap/status.md) records the current scope through P1b.8. For conflicts, use the relevant ADR for architecture decisions, [product principles](product-principles.md) for priorities and [roadmap](roadmap/phases.md) for sequencing.

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

- [P1b.2 – Arbeitsvorlagen](development/phase-1b-templates.md) – verbindlicher Scope, Modell, API, Rechte und Audit
- [P1b.2-Prüfnachweis](development/phase-1b-templates-verification.md) – Tests, Smoke, Wiederherstellung und geänderte Dateien

- [Review des P1b.2-Zyklus](development/phase-1b-templates-review-2026-09-27.md) – drei behobene Befunde, Regressionstests und finale Prüfung

Änderungen an Verhalten, Eigentümerschaft von Daten oder Modulgrenzen aktualisieren die betroffenen Dokumente im selben Arbeitsschritt. Eine verworfene ADR wird durch eine neue ersetzt und im alten Dokument als überholt markiert.

- [P1b.3 – Schichten und Employee Home](development/phase-1b-shifts.md) – Scope, Rechte, Transaktion und API
- [P1b.3-Prüfnachweis](development/phase-1b-shifts-verification.md) – Tests, Browser-Smoke und Restore
- [Review des P1b.3-Zyklus](development/phase-1b-shifts-review-2026-09-27.md) – drei behobene Befunde und finale Prüfung

- [P1b.4 – Guided Work und Completion](development/phase-1b-execution.md) – bestätigte Schritte, Rechte, Wiederholungen und Grenzen
- [P1b.4-Prüfnachweis](development/phase-1b-execution-verification.md) – Tests, Browser-Smoke und Restore
- [Review des P1b.4-Zyklus](development/phase-1b-execution-review-2026-09-27.md) – zwei behobene Fehler beim Fortschrittsabgleich und finale Prüfung

- [P1b.5 – Blockierung und Klärung](development/phase-1b-blocking.md) – Scope, Rechte, Historie und Migration

- [P1b.5-Prüfnachweis](development/phase-1b-blocking-verification.md) – Tests, Zwei-Benutzer-Smoke, Upgrade, Restore und geänderte Dateien
- [Review des P1b.5-Zyklus](development/phase-1b-blocking-review-2026-09-27.md) – zwei behobene UI-Zustandsfehler und finale Prüfung

- [P1b.6 – Stornierung blockierter Aufgaben](development/phase-1b-cancellation.md) – Scope, Rechte, terminaler Zustand und Migration
- [P1b.6-Prüfnachweis](development/phase-1b-cancellation-verification.md) – Tests, Browser-Smoke, Upgrade, Restore und geänderte Dateien
- [Review des P1b.6-Zyklus](development/phase-1b-cancellation-review-2026-09-27.md) – korrigierte Fehlerzustände, API-Vertrag und finale Prüfung

- [P1b.7 – Numerische Guided-Work-Schritte](development/phase-1b-7-numeric-steps.md) – verbindlicher Scope, Rechte, Audit und Abnahmekriterien
- [P1b.7-Prüfnachweis](development/phase-1b-7-numeric-verification.md) – Tests, API-Smoke, automatisierter Browserablauf, Upgrade und Restore

- [P2 – Aufgabenbezogene Backup-/Restore-Abnahme](development/phase-2-restore-acceptance.md) – lokaler Prüfnachweis, verschlüsselte Wiederherstellung der Aufgaben-Nachweise und verbleibende Grenzen
- [P2 – Concurrent-work capacity measurement](development/phase-2-capacity-measurement.md) – measurement contract, profiles, integrity proof and local evidence; timings are environment-specific observations
- [P2 – Controlled update/recovery acceptance](development/phase-2-update-recovery-acceptance.md) – forward-only 0010→0011 upgrade on populated data, encrypted restore point before migration, preservation, HTTP smoke and isolated recovery fencing; no downgrade or activation promise
- [P1b.8 – Published-shift cancellation](development/phase-1b-8-shift-cancellation.md) – pre-execution cancellation contract, evidence, idempotency and verification scope; [ADR 0013](adr/0013-published-shift-cancellation.md)
- [Milestone health check 2026-10-02](development/milestone-health-check-2026-10-02.md) – cross-cutting review of baseline `512ac64`, findings M1-M4 and L1-L12, pilot readiness and the mandatory M3 containment for the next API-adding slice; independently reviewed APPROVE and committed as `0ddcd4f`
- [P1 – Authenticated self-service password change](development/phase-1-self-service-password-change.md) – self-only password change, UTF-8 byte policy, all-session revocation, per-account verification limiter and local verification; independent review and remote CI pending
