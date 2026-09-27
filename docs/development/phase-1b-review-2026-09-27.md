# Review des P1b.1-Entwicklungszyklus

Datum: 2026-09-27. Gegenstand sind ausschließlich die Änderungen seit
`bfd6898` (Review und Härtung des Plattformkerns), einschließlich der noch
nicht versionierten P1b.1-Dateien. Maßstab sind AGENTS.md, Produktprinzipien,
Modulgrenzen, ADRs und die [P1b.1-Abnahme](phase-1b-employee.md).
Keine neuen Features, Abhängigkeiten oder Datenbankmigrationen im Review.

## Gefundene und behobene Probleme

| Priorität | Befund | Korrektur und Nachweis |
| --- | --- | --- |
| P2 | Nach Abmeldung und erneuter Anmeldung konnte ein alter Create-, Rename- oder Link-Aufruf seine nachgelagerten Leseanfragen mit der neuen Sitzung fortsetzen und deren Ansicht überschreiben. Die abschließende Benachrichtigungsprüfung allein verhinderte das nicht. | Der Controller bindet jeden Schritt an die ursprüngliche Sitzungsgeneration und verwirft alte Fortsetzungen auch nach fehlgeschlagenen Schreibantworten. Drei Regressionen prüfen, dass weder neue Requests noch Änderungen am neuen Ansichtsstand erfolgen. Eine Umgehung der serverseitigen Rechte wurde nicht festgestellt. |
| P2 | Nach einer Profilanlage mit anschließend gescheitertem Nachladen blieben alte Listen und Details sichtbar, obwohl der Commit-Ausgang nicht bestätigt war. | Verwaltungsprojektionen werden vor der Anlage und beim erneuten Laden entfernt. Eine Regression prüft den Fehler nach erfolgreicher Speicherung: keine alte Liste, Auswahl oder Account-Zuordnung, keine Erfolgsmeldung. |
| P2 | Beim Wechsel von der Eigenansicht in die Verwaltung während einer laufenden Anfrage wurde der erste Verwaltungsabruf wegen `busy` verworfen. Die Ansicht blieb ungeladen. | Die neu geöffnete Ansicht wartet auf den laufenden Controller-Aufruf und lädt danach. Ein Widget-Test bildet den Wechsel während einer offenen Profilantwort ab. Geschlossene Ansichten lösen nach Dialog- oder Ladeantworten keine Aktionen mehr aus. |
| P3 | Ohne eingerichteten Standort war „Mitarbeiter anlegen“ aktiv, der Aufruf endete jedoch kommentarlos. | Der Controller liefert die vorhandene Voraussetzung und eine Erklärung; die Ansicht deaktiviert die Aktion und verweist auf die Organisationseinrichtung. Widget-Test für den unkonfigurierten Standort. |
| P3 | Bereits bestehende Verknüpfungen, inaktive Identitäten und erreichte Datensatzgrenzen wurden über die allgemeine 409-Meldung als Versionsänderung erklärt. | Die Mitarbeiteransicht übersetzt die vorhandenen Fehlercodes in passende Meldungen. Regression für einen Verknüpfungskonflikt ohne falsche Erfolgsanzeige. |

Die ersten sechs neuen Client-Regressionen wurden vor der jeweiligen Korrektur
ausgeführt und schlugen fehl. Zusätzlich wurde ein echter PostgreSQL-/HTTP-Test
für Auditfehler bei Umbenennung und Verknüpfung ergänzt: Anzeigename, Version,
Zuordnung, vorhandene Sitzungen und Auditbestand bleiben nach dem Rollback
unverändert. Eine unveränderte Umbenennung erzeugt keinen zusätzlichen Audit-Eintrag.
Hier bestand eine Nachweislücke; eine Änderung am produktiven Backend war nicht nötig.

## Geprüfte Schutzlinien

- **Architektur:** People besitzt Profile, Identity die Account-Verknüpfung und
  Sitzungen. Der Application-Koordinator verwendet deren öffentliche Ports in
  einer autorisierten Transaktion. Routen und Widgets delegieren Fachentscheidungen.
  Keine zusätzliche Plattformabstraktion oder neue Event-Infrastruktur nötig.
- **Rechte und Datenschutz:** Aktuelle Sitzung und Rolle werden nach dem
  Company-Lock geprüft. Verwaltung bleibt administrativ; Eigenzugriff setzt
  aktives Profil, aktive Verknüpfung und denselben Company-/Location-Scope voraus.
  Viewer, Auditoren und Plugins erhalten keine Mitarbeiterrechte. Neue Profile
  erweitern weder Plugin-Manifeste noch deren Payloads.
- **Integrität:** Zusammengesetzte Fremdschlüssel, partielle Unique-Indizes und
  Versionsprüfungen sichern Standortgrenzen und aktive Eins-zu-eins-Verknüpfungen.
  Parallele Verknüpfungen und Verknüpfung gegen Deaktivierung sind integrationstestet.
  Stabile Client-IDs vermeiden Doppelanlage nach Antwortverlust; der Client liest
  den tatsächlichen Serverstand. Keine Mengen- oder Geldberechnung in diesem Slice.
- **Audit und Events:** Anlage, Umbenennung, Deaktivierung, Verknüpfung und Entzug
  schreiben Audit innerhalb derselben Transaktion; erforderliche Sitzungswiderrufe
  gehören dazu. Namen werden nicht in Auditänderungen kopiert. Korrelation verbindet
  neue HTTP-, Audit- und bestehende Outbox-Einträge, historische Werte bleiben `null`.
  Keine fehlenden Mitarbeiter-Events ohne konkreten Verbraucher ergänzt.
- **Migration und API:** Upgrade aus P1 erhält IDs, Hashes und Auditbestand;
  Migration 0004 bleibt unverändert. Ungültige Eingaben, Fremdzugriffe,
  Versionskonflikte und Datenbankfehler sind abgedeckt. Fehlerantworten enthalten
  keine Datenbankdetails oder Geheimnisse.
- **Performance:** Kein Abfrageaufruf pro Zeile in der Mitarbeiterliste.
  Die Detailauswahl verwendet drei begrenzte API-Abfragen. Die bestehenden
  200-Datensatz-Grenzen und der Company-Lock begrenzen den Umfang; der Review
  ist kein Last- oder Mehrstandort-Skalierungsnachweis.

## Finale Prüfungen

Vollständiger lokaler Lauf über `scripts/dev.ps1 check`, mit gesetztem
`STOREOS_TEST_DATABASE` gegen PostgreSQL. Keine Datenbanktests übersprungen.

| Prüfung | Ergebnis |
| --- | --- |
| `dart format` und Formatprüfung aller vier Packages | bestanden, keine verbleibenden Änderungen |
| `dart analyze` für Server und API-Verträge | keine Befunde |
| `flutter analyze` für Client und Designsystem | keine Befunde |
| Server einschließlich PostgreSQL-/HTTP-Integration | 33 Tests bestanden |
| API-Verträge | 13 Tests bestanden |
| Flutter-Client | 44 Tests bestanden |
| Designsystem | 2 Tests bestanden |
| `docker compose config --quiet` | bestanden |
| Flutter-Web-Release mit lokalen Webressourcen | bestanden |
| API-Smoke am laufenden Server | bestanden: Health, Readiness, Anmeldung, Rechte, Audit/Events/Plugins, Fremdzugriff und Sitzungswiderruf |
| `git diff --check` | bestanden |

Insgesamt **92 bestandene Tests**, davon acht im Review hinzugefügt.
Die UI-Korrekturen wurden mit Controller- und Widget-Regressionen geprüft;
ein neuer manueller Browser-Durchlauf wurde in diesem Review nicht durchgeführt.

## Verbleibende bekannte Grenzen

Ein lokaler Schreiber, eine Company pro Datenbank, keine Standortreplikation und
kein Offline-Schreiben. Company-weite Serialisierung und die begrenzte Liste sind
bewusste Grenzen; größere Installationen brauchen eine separate Lastabnahme.
Ein entfernt entzogenes Profil kann bis zur nächsten Prüfung im Browser sichtbar
bleiben; die sichtbare Eigenansicht prüft alle 30 Sekunden erneut.

Profildeaktivierung ersetzt weder Accountdeaktivierung noch Löschung.
Aufbewahrung/Löschung und Wiederanwendung neuerer Sperren nach Restore bleiben
vor Einsatz mit echten Beschäftigtendaten zu klären. Audit schützt vor Änderungen
durch die Runtime-Rolle, nicht vor dem Datenbank-Owner. Native Geräte, LAN-TLS,
externe Sicherheitsprüfung und Lasttests wurden in diesem Review nicht abgenommen.
Die frühere Backup-/Restoreprobe wurde nicht wiederholt, da der Review weder
Schema noch Backend- oder Backupverhalten verändert.

## Im Review geänderte Dateien

- `apps/client_flutter/lib/src/application/employee_controller.dart`
- `apps/client_flutter/lib/src/ui/employee_section.dart`
- `apps/client_flutter/test/employee_test.dart`
- `apps/server/test/employee_integration_test.dart`
- `docs/development/phase-1b-employee.md`
- `docs/development/phase-1b-verification.md`
- `docs/development/phase-1b-review-2026-09-27.md`
- `docs/README.md`
