# Review des P1b.3-Entwicklungszyklus

Stand: 2026-09-27. Geprüft wurden ausschließlich die Änderungen seit
`922a45f`: Schichtentwurf, atomare Veröffentlichung, Aufgaben-Snapshots und
lesendes Employee Home gemäß [Scope](phase-1b-shifts.md). Keine neuen Funktionen,
Rechte, Ereignisse oder Datenbankmigrationen im Review ergänzt. Migration 0006
bleibt unverändert.

## Gefundene und behobene Probleme

1. **Veraltete Revisionsauswahl im Client.** Nach dem Neuladen der Vorlagen konnte
   eine noch angezeigte Revision auf eine nicht mehr geladene Vorlage verweisen.
   `singleWhere` löste dann einen unbehandelten Fehler aus. Ein neuer Entwurf
   übernahm außerdem die Revisionsauswahl des vorherigen Editors. Der Controller
   verwirft diese Auswahl jetzt bei Kontextwechsel und prüft vor dem Hinzufügen
   Veröffentlichung, Standort, aktuelle Auswahl, Dubletten und Mengengrenze.
   Das Widget verwendet dieselbe Controllerentscheidung für den Buttonzustand.
2. **Fehlgeschlagene Schreibversuche wurden als Konkurrenzkonflikt angezeigt.**
   Wenn Bearbeitung oder Veröffentlichung den Server nicht verändert hatte,
   zeigte der anschließende Abgleich des unveränderten Entwurfs einen Konflikt.
   Das blockierte eine bewusste Wiederholung. Bei identischer vorheriger Version
   und identischem Inhalt bleibt nun exakt der ursprüngliche Befehl unbestätigt
   und ausdrücklich wiederholbar. Echte Abweichungen bleiben Konflikte; es gibt
   keine automatische erneute Übertragung.
3. **Unnötige Einzelabfragen während der Revisionsprüfung.** Bis zu zehn
   Revisionen benötigten jeweils eine Vorlagen- und Revisionsabfrage unter dem
   Company-Lock. Tasks lädt die fest ausgewählten veröffentlichten Revisionen
   jetzt in einer nach Company und Standort begrenzten Abfrage. Die Prüfung der
   Vorlagen-ID und die ursprüngliche Auswahlreihenfolge bleiben erhalten.
   Fremde Modultabellen werden weiterhin nicht gelesen.

Vier neue Clienttests reproduzierten die beiden funktionalen Fehler vor den
Korrekturen. Danach bestanden sie. Ein zusätzlicher PostgreSQL-/HTTP-Test weist
nach, dass vertauschte Vorlagen-/Revisionsreferenzen und veröffentlichte Revisionen
eines anderen Standorts mit 422 ohne Schicht- oder Auditänderung abgewiesen werden.
Der bestehende Test mit zehn Instanzen sichert Reihenfolge und atomaren Rollback.

## Architektur, Integrität und Security

Im geprüften Slice kein weiterer konkret nachgewiesener Fehler bei Modulgrenzen,
Authentifizierung, Rollen, Eigenzugriff, Plugin-Abweisung oder Audit. Die
Application koordiniert öffentliche Ports in derselben autorisierten Transaktion;
Widgets und HTTP-Routen entscheiden keine Fachregeln. Die Prüfungen decken
Rollback an Task-/Auditpunkten, Versionskonflikte, Veröffentlichungswiederholungen,
konkurrierende Überschneidungen, Mitarbeiterdeaktivierung, Sitzungswiderruf und
Runtime-Schutz veröffentlichter Daten ab. Zeiten werden als explizite Instants
transportiert; Mengen-/Geldrundungen sind nicht Bestandteil dieses Slice.

## Finale Prüfungen

Vollständiger Lauf von `scripts/dev.ps1 check` mit echtem PostgreSQL und
`STOREOS_TEST_DATABASE`; keine übersprungenen Integrationstests.

| Paket | Bestanden |
| --- | ---: |
| API-Verträge | 20 |
| Server inklusive PostgreSQL-/HTTP-Tests | 57 |
| Flutter-Client inklusive Controller-/Widgettests | 81 |
| Design-System | 2 |
| Gesamt | **160** |

- Alle Dart-Formatter und Dart-/Flutter-Analyzer ohne Befund.
- `docker compose config --quiet` erfolgreich.
- Flutter-Web-Release einschließlich Wasm-Dry-Run erfolgreich.
- HTTP-Smoke und vollständiger Zwei-Benutzer-Prozess über echte HTTP-Endpunkte
  und PostgreSQL erneut bestanden.
- `git diff --check` erfolgreich; nur bekannte Windows-Zeilenendenhinweise.
- Lokale Protokolle: `.local/shifts-review-check.log`,
  `.local/shifts-review-build.log`; ursprünglicher Fehlernachweis:
  `.local/shifts-review-red.log`.

Der frühere [Browser-/Restore-Nachweis](phase-1b-shifts-verification.md) gehört
zur Implementierung vor diesem Review. Der Browser-Smoke wurde im Review nicht
wiederholt: Die frühere isolierte Instanz auf Port 8087 war nicht mehr erreichbar.
Die neuen Clientkorrekturen wurden durch Controller-/Widgettests und den
erfolgreichen Release-Build geprüft. Backup/Restore wurde ohne Schemaänderung
nicht erneut ausgeführt.

## Verbleibende Grenzen

- Der vorhandene Company-Lock serialisiert auch Lesezugriffe; kein Lastnachweis
  für große Installationen. Die gebündelte Revisionsabfrage verkürzt nur einen
  Teil der Transaktion.
- Mitarbeiterlisten übernehmen die bestehende Begrenzung. UTC-Eingabe ersetzt
  noch keine Standortzeitzonen-/Kalenderverwaltung.
- Keine Korrektur veröffentlichter Schichten, Guided Work, Completion,
  Offline-Schreibqueue oder Multi-Location-Synchronisation in diesem Scope.
- Nicht gespeicherte Eingaben überleben keinen Clientneustart. Native Clients
  sind nicht separat abgenommen. DB-Owner liegen außerhalb des Runtime-Schutzes.

Diese Grenzen wurden nicht durch angrenzende Features oder horizontale Umbauten
erweitert. Die Änderungen bleiben uncommitted zur Prüfung bereit.
