# Review der Implementierung nach Phase 1

Datum: 2026-09-27. Grundlage: AGENTS.md, Produktprinzipien, Modulgrenzen, Sicherheits-, Event-, Plugin- und Datenhoheitsdokumentation sowie der konkrete P1-Vertrag. Prüfung des lokalen Arbeitsstands; keine neuen Fachfeatures, keine Änderung bereits angewendeter Migrationen.

## Befunde und Korrekturen

| Priorität | Befund | Korrektur und Nachweis |
| --- | --- | --- |
| P1 | Benutzer- und Plugin-Ablaufprüfungen verwendeten PostgreSQL `now()`. Dieser Zeitpunkt liegt bei einer wartenden Transaktion vor dem Erwerb des Company-Locks; ein während der Wartezeit abgelaufenes Token konnte danach noch Daten lesen. Auch Logout verwendete diesen veralteten Zeitpunkt. | Ablaufprüfungen verwenden `clock_timestamp()`. Drei echte PostgreSQL-Regressionen warten nachweislich auf den Advisory Lock und setzen den Ablauf zwischen Transaktionsbeginn und Freigabe. Sie schlugen vor der Korrektur fehl und bestehen danach. |
| P2 | Der Flutter-HTTP-Adapter verbot jede Zeichenfolge `..`, während der Manifest-Vertrag IDs wie `test..reader` erlaubt. Solche Registrierungen konnten über die UI nicht freigegeben oder deaktiviert werden. | Der Adapter unterscheidet gültige Punkte innerhalb einer ID von verbotenen Pfadsegmenten und URI-Steuerzeichen. Tests prüfen gültige IDs und abgewiesene Traversal-, Query- und Fragment-Eingaben. |
| P2 | Manifest-Namen und Anbieter akzeptierten eingebettete Steuerzeichen. Insbesondere NUL führte erst beim Speichern in PostgreSQL-JSONB zum Fehler und wurde als Datenbankausfall gemeldet. | Gemeinsame Manifest-Validierung weist Steuerzeichen vor der Transaktion ab; HTTP antwortet mit 400. Contract-Test und echter HTTP-Smoke prüfen die Ablehnung. OpenAPI beschreibt die Grenzen. |
| P2 | Login, Logout und Bootstrap schrieben direkt in die fremde Audit-Tabelle und umgingen damit den bestehenden gemeinsamen Schreibvertrag. | Alle drei Pfade nutzen jetzt `AuditRepository.append` innerhalb ihrer bisherigen Transaktion. Die Akteur-Art wird dort validiert. Bootstrap bleibt ein Systemeintrag, Login/Logout bleiben Benutzereinträge. Bestehende Bootstrap-, Auth- und Rollbacktests sichern diese Pfade ab. |
| P3 | Nach verlorener Erstellungsantwort bestätigte das Neuladen zwar den Standort bzw. Benutzer, der Controller gab trotzdem `false` zurück. Ergebnis und Erfolgsmeldung widersprachen sich. | Bestätigte Existenz derselben Client-UUID liefert `true`; Ergebnisse einer inzwischen beendeten Sitzung bleiben verworfen. Zwei Regressionen prüfen verlorene Antworten nach erfolgreicher Speicherung. Die bestehenden Dialoge schließen bereits vor dem Aufruf; eine direkte Dialog-Doppelanlage wurde nicht nachgewiesen. |

## Geprüfte Schutzlinien

- **Authentifizierung:** Argon2id mit Salt, zufällige Bearer-Tokens, ausschließlich Token-Digests in PostgreSQL, aktuelle Account-Prüfung und Passwortstand vor Sitzungserstellung, Widerruf bei sicherheitsrelevanten Benutzeränderungen. Keine Secrets in Antworten außerhalb der einmaligen Token-Ausgabe oder in strukturierten Logs.
- **Autorisierung und Scope:** Rechteprüfung im Application-Pfad nach Company-Lock; Rollen und Sitzung werden erneut gelesen. Viewer sehen ihren Heimatstandort, Administratoren/Auditoren die dokumentierten firmenweiten Daten. Plugin-Tokens und Benutzersitzungen sind getrennt. Zusätzliche Tests prüfen unzulässige Manifest-Rechte, Teilfreigaben und Ablehnung einer anderen konfigurierten Company.
- **Datenintegrität und Transaktionen:** Versionsprüfungen, Fremdschlüssel, Singleton-Company und serialisierte administrative Änderungen bleiben erhalten. Tests prüfen letzten aktiven Administrator, Migration bestehender Identitäten, konkurrierenden Bootstrap, Sitzungswiderruf und gemeinsamen Rollback von Zustand, Audit und Event.
- **Audit:** Runtime darf ergänzen und lesen, aber nicht ändern, löschen oder truncaten. Änderungen verwenden begrenzte Auditfelder. Mehrseitiges Lesen wurde zusätzlich geprüft; Lesezugriffe erzeugen weiterhin eigene Audit-Einträge.
- **Plugins und Events:** Keine Fremdcodeausführung, keine Plugin-Netzwerkaufrufe und keine direkten Datenbankzugänge. Freigaben begrenzen Standort, Rechte und Abonnements. Zusätzliche Integration prüft zwei konkurrierende Dispatcher, 54 Events, deduplizierte Zustellungen, Cursor-Grenzen einschließlich gleicher Zeitstempel und Ausschluss des Events vor der Freigabe. Retry, Dead-Letter, Replay und Widerruf bleiben abgedeckt.
- **API und Architektur:** HTTP-Routen delegieren an Services; Widgets verwenden Controller. SQL liegt in den zuständigen Repository-/Infrastrukturkomponenten. Gemeinsame Transaktionsgrenzen bleiben im modularen Monolithen; kein neuer Broker, kein allgemeiner Policy-Editor und keine Fachmodule.

## Bewusste Grenzen und Folgearbeit

Die Installation unterstützt eine Company pro Datenbank. Dies ist keine freigegebene Mehrmandanten-Datenbank mit Row-Level Security. Zusätzliche Locations bleiben Stammdaten desselben Schreibers; der Review belegt keine Standortreplikation oder Offline-Schreibfähigkeit.

Company-weite Serialisierung einschließlich Passwortänderungen ist für den begrenzten P1-Betrieb dokumentiert, aber kein Skalierungsnachweis. Login-Limits gelten pro Prozess; Mehrprozessbetrieb benötigt ein übergreifendes Limit. Audit, Sitzungen, Outbox und Inbox besitzen noch keine geregelte Aufbewahrungsbereinigung. Diese Punkte bleiben Betriebs- und Lastabnahmen, bevor größere Installationen freigegeben werden.

Audit schützt nicht gegen den Datenbankadministrator. Eine positive lokale Testabnahme ersetzt weder eine externe Sicherheitsprüfung noch Native-/LAN-TLS-Gerätetests. Abgewiesene HTTP-Anfragen erscheinen in strukturierten Logs; ein weitergehendes persistentes Security-Incident-Modell ist hier nicht ergänzt worden.

## Prüfungen nach den Änderungen

Der vollständige lokale Prüflauf bestand mit Flutter 3.47.5, Dart 3.13.4 und PostgreSQL 17:

| Prüfung | Ergebnis |
| --- | --- |
| Formatter in allen vier Packages | bestanden |
| `dart analyze` (Server, API-Contracts) | keine Befunde |
| `flutter analyze` (Client, Design-System) | keine Befunde |
| API-Contract-Tests | 10 bestanden |
| Server-Tests einschließlich echter PostgreSQL-/HTTP-Integration | 22 bestanden, keine übersprungen |
| Flutter-Client-Tests | 29 bestanden |
| Design-System-Tests | 2 bestanden |
| `docker compose config --quiet` | bestanden |
| Setup- und Backup-Kryptografietests | bestanden |
| Flutter-Web-Release ohne externe Ressourcen-CDN | erfolgreich neu gebaut |
| HTTP-Smoke nach Neustart der lokalen Installation | bestanden |
| OpenAPI-JSON-Parsing und `git diff --check` | bestanden |

Insgesamt bestehen **63 Dart-/Flutter-Tests**. PostgreSQL-Tests verwenden isolierte Schemas in der Testdatenbank mit getrennten Owner-/Runtime-Zugängen. Die laufende lokale API und der bereitgestellte Web-Build wurden aktualisiert. Die bestehende Datenbank benötigte keine zusätzliche Migration. Ein entfernter CI-Lauf, erneuter manueller Browserdurchlauf und Lasttest waren nicht Teil dieses Reviews.
