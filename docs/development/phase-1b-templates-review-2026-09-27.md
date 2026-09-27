# Review des P1b.2-Entwicklungszyklus

Stand: 2026-09-27. Geprüft wurden ausschließlich die Arbeitsvorlagen-Änderungen
seit `3a8f710` einschließlich ihrer direkten Plattformintegration. Die vorhandenen
P0/P1/P1b.1-Komponenten wurden nur als Abhängigkeiten dieser Änderungen gelesen.
Verbindlicher Scope: [P1b.2](phase-1b-templates.md). Keine neuen Funktionen,
Berechtigungen, Events, Dependencies oder Datenbankschemaänderungen im Review.
Migration 0005 bleibt unverändert, weil sie bereits angewendet wurde.

## Bestätigte und behobene Probleme

### P2 – Falsche Freigabebestätigung bei Antwortverlust

Der Client prüfte beim Ergebnisabgleich einer Freigabe nur den Zustand
`published`. Bearbeitet und veröffentlicht ein anderer Administrator zwischenzeitlich
dieselbe Revision und geht die Konfliktantwort verloren, zeigte der Client
„Revision freigegeben und bestätigt“ und übernahm den abweichenden Inhalt.
Die serverseitige Versionsprüfung war korrekt; der Fehler lag im Clientabgleich.

Der Abgleich verlangt jetzt zusätzlich identischen normalisierten Inhalt.
Ein abweichender Stand mit neuer Aggregate-Version wird als Konflikt angezeigt,
die ursprünglichen Eingaben bleiben sichtbar und weitere Aktionen gesperrt,
bis der Serverstand ausdrücklich übernommen wird. Kein automatisches erneutes
Senden. Der neue Regressionstest reproduzierte die falsche Erfolgsmeldung vor
der Korrektur und besteht danach. Bestehende Antwortverlusttests aller vier
Schreibaktionen bestehen weiterhin.

### P2 – Übersicht blieb nach Neuanlage ungeladen

`create()` leerte die Vorlagenliste, lud sie aber nach bestätigter Anlage nicht
neu. Dadurch verschwanden die Listeneinträge bis zu einem manuellen Neuladen.

Nach bestätigter Anlage wird jetzt die erste begrenzte Metadatenseite geladen.
Schlägt nur diese Abfrage fehl, bleiben der bestätigte Datensatz und Editor
erhalten; der Listenfehler wird separat sichtbar und kann ohne erneute Anlage
behoben werden. Regressionstests prüfen automatische Aktualisierung und den
Fehlerpfad. Zusätzlich im echten Flutter-Web-Release mit isoliertem Testschema
geprüft: Der neue Listeneintrag erscheint unmittelbar nach „Anlegen“.

### P2 – Ungültiges Unicode passierte die Inhaltsvalidierung

Einzelne UTF-16-Surrogate wurden vom gemeinsamen Inhaltsvertrag akzeptiert.
Erst PostgreSQLs JSON-Auswertung lehnte sie ab. Dies führte zu einem Datenbankfehler
statt der vorgesehenen Inhaltsvalidierung; es wurden keine ungültigen Daten
persistiert.

Der Transportvertrag verwirft jetzt isolierte Surrogate in Textfeldern.
Gültige Zeichen außerhalb der BMP, etwa Emoji, bleiben erlaubt und zählen als
ein Unicode-Codepoint. Vertrags- und echte HTTP-/PostgreSQL-Tests prüfen Titel
und Anleitungstext, `400 invalid_template_content` und unveränderte Tabellen/Audit.
Keine globale Änderung der HTTP-Fehlerbehandlung.

## Weitere Prüfung

- **Architektur:** AGENTS.md, Produktprinzipien und ADR 0001/0004/0008/0009/0011/0012
  sowie Modul-, Sicherheits- und Offlinegrenzen eingehalten. Tasks bleibt Eigentümer;
  Organization wird über den vorhandenen Application-Port angesprochen. Keine
  Geschäftsentscheidungen in Routen/Widgets und keine zusätzliche Abstraktionsschicht.
- **Integrität:** Company-Lock, erwartete Aggregate-Version, ein Entwurf pro Vorlage,
  eindeutige Revisionen, atomarer Audit-Rollback und unveränderliche Freigaben geprüft.
  Wiederholungen erzeugen keine zweite Freigabe/Auditwirkung. Mengen/Geld/Rundung
  gehören nicht zum Scope; Größen und Revisionsnummern sind begrenzte Ganzzahlen.
- **Security:** Authentifizierung und erneute Rechte-/Sessionprüfung erfolgen
  serverseitig. Nur Admins derselben Company, nur eingerichtete Locations;
  gültige Plugin-Tokens erhalten keinen Zugriff. Parametrisierte SQL-Abfragen;
  keine Anleitungsinhalte in Audit oder technischen Logs.
- **Audit/Events:** Alle vier fachlichen Schreibaktionen besitzen atomaren Audit;
  No-op und identische Freigabewiederholung erzeugen bewusst keinen zweiten Eintrag.
  Kein Domain Event ohne konkreten Verbraucher; kein neuer Plugin-Zugriff.
- **Fehler/UX:** Nicht bestätigte Daten, Konflikt, Lade- und Fehlerzustand bleiben
  getrennt. Verlorene Antworten und Sitzungswechsel sind getestet. Leere Entwürfe
  dürfen gespeichert, aber nicht freigegeben werden.
- **Performance:** Keine unbeschränkte Liste oder Abfrage pro Schritt. Metadatenlisten
  sind auf 50 begrenzt; Inhalte werden nur im Detail geladen. Die korrelierten
  SQL-Lesezugriffe verwenden die vorhandenen Template-/Revisionsindizes. Der
  zusätzliche Listenabruf nach Anlage ist eine einzelne begrenzte Abfrage.

Keine weiteren bestätigten Befunde im geprüften Änderungsscope. Dies ersetzt
keinen Penetrations- oder Lasttest.

## Finale Prüfungen

Vollständiger Lauf von `scripts/dev.ps1 check` mit echter PostgreSQL-Testdatenbank:

| Paket | Tests |
| --- | ---: |
| API-Verträge | 17 |
| Server einschließlich PostgreSQL-/HTTP-Integration | 43 |
| Flutter-Client | 62 |
| Design-System | 2 |
| **Gesamt bestanden** | **124** |

Keine übersprungenen Datenbanktests. Formatierung angewendet; abschließender
Formatcheck ohne Änderungen. Alle Dart-/Flutter-Analyzer ohne Befund.
`docker compose config --quiet`, Flutter-Web-Release-Build und `git diff --check`
erfolgreich. Browser-Smoke mit isoliertem Schema: Anmeldung, Neuanlage, sofort
sichtbare Liste und Abmeldung. Testschema anschließend entfernt. Regulärer
Server neu gestartet; vollständiger API-Smoke erfolgreich. Keine Smoke-Vorlagen
in der regulären Entwicklungsdatenbank. Backup-/Restore-Nachweis des
[ursprünglichen Slice](phase-1b-templates-verification.md) bleibt gültig;
Datenmodell und Migration wurden im Review nicht verändert.

## Verbleibende bekannte Grenzen

Company-Lock serialisiert auch Lesezugriffe; die Eignung für große Installationen
ist nicht durch Lasttests belegt. Ungespeicherte Eingaben leben nur im Arbeitsspeicher;
Browserneuladen/Sitzungsende verwirft sie. Keine Offline-Schreibqueue oder
Standortreplikation. DB-Owner liegen außerhalb des Runtime-/Auditschutzes.
Native Runner wurden nicht abgenommen. Diese Grenzen wurden nicht durch neue
Funktionen oder horizontale Umbauten erweitert.

## Im Review geänderte Implementierungs- und Testdateien

- `apps/client_flutter/lib/src/application/task_template_controller.dart`
- `apps/client_flutter/test/task_template_test.dart`
- `packages/api_contracts/lib/src/task_templates.dart`
- `packages/api_contracts/test/task_template_contracts_test.dart`
- `apps/server/test/task_template_integration_test.dart`

Der Inhaltsvertrag/OpenAPI sowie Dokumentationsindex, Slice und Prüfnachweis
verweisen auf die präzisierte Validierung und diesen Review.
