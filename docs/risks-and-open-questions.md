# Kritische Prüfung der Produktvision

Status: Architektur- und Produkthypothesen. Dieser Katalog macht Zielkonflikte sichtbar und hält Entscheidungen offen, die der Master-Prompt noch nicht ausreichend bestimmt. Er ist vor jedem relevanten Modul und vor Pilotbetrieb zu aktualisieren. Die [ADRs](adr/) halten bereits beschlossene Grundrichtungen fest; offene Detailfragen sind keine stillen Implementierungsaufträge.

## Spannungen und größte Risiken

| ID | Spannung oder Risiko | Konsequenz bei Fehlentscheidung | Leitplanke und Prüfpunkt |
| --- | --- | --- | --- |
| R1 | „Eine Datenbasis“ bei autonomen Standortservern und optionaler Zentrale | Zwei Instanzen ändern denselben Datensatz; Bericht und operativer Zustand widersprechen sich | Schreibautorität je Aggregat und Replikationsrichtung festlegen; ein neuer Schreiber wird erst nach Ausschluss des alten aktiv. Mehrstandort-Sync braucht Konflikt- und Wiederanlaufproben. |
| R2 | Standortbetrieb ohne Internet und kurzzeitig offline Handhelds | Aktionen werden doppelt, verspätet oder mit veralteten Berechtigungen übernommen | Standortserver bleibt operative Autorität. Geräteaktionen erhalten IDs, Versionsprüfung und sichtbaren Status „ausstehend“; kritische Aktionen werden offline begrenzt. |
| R3 | Dynamische Aufgaben und Abhängigkeiten versus verlässliche, faire Arbeit | Nicht erklärbare Prioritäten, verhinderte Pausen oder verdeckte Mitarbeiterbewertung | Deterministische Regeln mit Begründung, Sperrgründen und manueller Führungskraftentscheidung; keine Sanktionen aus Nutzungsdaten. |
| R4 | „Plugin first“ versus Least Privilege und Verfügbarkeit | Erweiterung liest HR-Daten, verändert Bestände oder legt den Standort lahm | Fremde Plugins nur mit erzwungener Isolation, freigegebenen Netzwerkzielen, begrenzten API-Rechten und widerrufbaren Zugangsdaten. Runtime erst nach konkretem Adapterbedarf. |
| R5 | Ein Flutter-Client für Web, Android, Windows, Linux und später POS | Unterschiedliche Offline-, Scanner-, Drucker-, Tastatur- und Sicherheitsfähigkeiten bleiben ungetestet | Gemeinsame Fach- und Designsprache, plattformspezifische Adapter; pro Zielgerät reale Hardware- und Update-Tests. |
| R6 | Auditierbarkeit versus Datenschutz und Datenminimierung | Audit speichert Gesundheitsdaten, Freitext, Fotos oder alte Werte länger als nötig | Zweck, Feldumfang, Schutz, Zugriff, Aufbewahrung und Lösch-/Sperrverfahren je Ereignistyp festlegen; keine pauschalen Voll-Snapshots sensibler Daten. |
| R7 | „Einmal eingeben“ versus korrigierbare und rechtssichere Vorgänge | Korrekturen löschen historische Sachverhalte oder propagieren falsche Daten | Versionierte Änderung/Korrektur mit Grund und Provenienz; zuständiger Fachbereich entscheidet über Wirksamkeit. |
| R8 | Umfang von ERP, POS, HACCP, HR, Finance und KI | Zu viele halbfertige Funktionen, Sicherheits- und Compliance-Schulden | Phasen mit Abnahmekriterien; erst tägliche Mitarbeiterreise, dann fachliche Erweiterungen. Keine Dummy-Funktionen als Release. |
| R9 | Komplexe Synchronisation von Dienstplan, Aufgaben und Nachweisen | Veröffentlichung erzeugt doppelte oder unvollständige Aufgaben; ungeprüfte Vorlagenänderung beeinflusst laufende Arbeit | P1 veröffentlicht Schicht und Aufgaben atomar nach ADR 0011. Snapshots und explizite Änderungs-/Storno-Semantik bleiben erforderlich; spätere asynchrone Erzeuger brauchen eigene Verträge. |
| R10 | Regulatorisch sensible Nutzung in mehreren Branchen/Ländern | Allgemeine Workflows werden als rechtlich gültige Nachweise missverstanden | Compliance-Packs erst nach fachlicher und juristischer Prüfung je Jurisdiktion; im ersten Slice nur generische Werteingabe und Ausnahmebehandlung, kein HACCP-Zertifizierungsversprechen. |
| R11 | Self-hosting im Betrieb mit wenig IT-Personal | Fehlende Backups, Patches oder Zertifikate machen Standort und Daten verwundbar | Unterstütztes Deployment, sichere Defaults, Restore-Übung, Update-/Rollback-Verfahren und lokale Statusanzeigen als Betriebs-Gates. |
| R12 | Open Source, AGPLv3 und kundenspezifische Plugins | Lizenzinkompatibilität oder unklare Veröffentlichungspflichten | Beiträge und Abhängigkeiten prüfen; Rechtsbewertung für Plugin-Verteilung und Integrationsmodelle vor kommerziellem Angebot. |
| R13 | Wiederholung oder verspätete Zustellung von Events und Offline-Kommandos | Doppelte Wirkung trotz Deduplizierung, verlorene Wirkung bei falscher Commit-Reihenfolge | Deduplizierung, Fachänderung und Audit atomar speichern; verlorene Quittung, Crash und Replay prüfen. Externe Effekte brauchen gesonderte Idempotenz oder Abgleich. |
| R14 | Restore eines älteren Standorts mit neueren Gegenstellen | Versionsrücksprung, verlorene Bestätigungen sowie reaktivierte Zugriffe oder gelöschte Personendaten | Sync-, Sperr- und Löschstände vor Wiederöffnung abgleichen; alte Zugänge invalidieren und Schlüssel-Recovery prüfen. Zentrale Projektionen ersetzen kein Standortbackup. |
| R15 | Unbegrenztes Offlineversprechen bei endlichem Speicher | Outbox oder Anhänge füllen den Datenträger und stoppen lokale Transaktionen | Unterstützte Trennungsdauer und Datenrate bemessen; Aufbewahrung, Cursor-Neustart und Warnschwellen vor P2 festlegen. |
| R16 | Lokale Schreiber bei standortübergreifenden Regeln | Zwei Standorte planen unabhängig dieselbe Person zur gleichen Zeit | Vor Freigabe pro Regel zwischen lokalem Hinweis und verbindlicher globaler Prüfung unterscheiden; letztere braucht Koordination oder vorherige verbindliche Zuteilung. |
| R17 | Updates bei aktiven Aufgaben und getrennten Knoten | Alte Snapshots werden anders interpretiert oder noch ausstehende Kommandos passen nicht mehr zum Server | Schrittsemantik und öffentliche Verträge separat versionieren, vorhandene Daten/aktive Instanzen testen und ein begrenztes Kompatibilitätsfenster festlegen. |

## Offene Entscheidungen mit Termin im Fahrplan

| Frage | Benötigt vor |
| --- | --- |
| Darf eine Installation mehrere Companies enthalten, oder ist zunächst eine Company pro Installation vorgesehen? Wie werden Mandanten administrativ getrennt? | Persistenzschema und Berechtigungstest des ersten Slice |
| Wie werden Accounts, Employee-Stammdaten und Rollen zwischen mehreren Standorten verantwortet und bei getrennter Zentrale widerrufen? | Zentrale Synchronisation; lokale Authentifizierung bereits vor erstem Pilot |
| Welche Schichtänderung erzeugt, ändert oder storniert TaskInstances? Wie wird eine laufende Aufgabe behandelt? | Erster Vertical Slice |
| Teilantwort (2026-10-02): Ein Beginn-/Ende-Wechsel veröffentlichter Schichten vor Ausführungsbeginn ändert keine Instanzen; Änderungen an Mitarbeiter/Vorlagen sowie begonnene Arbeit bleiben offen ([ADR 0014](adr/0014-pre-execution-shift-interval-amendment.md)). | Weiterhin vor Mitarbeiter-/Vorlagenänderung oder Wiederaufnahme begonnener Arbeit |
| Welche Schritte und Nachweise dürfen auf Handhelds offline erstellt werden? Was sieht der Nutzer bis zur Annahme durch den Server? | Geräte-Offlinephase |
| Wie lange werden getrennte Geräte/Standorte und alte Wiederholungen unterstützt? Wie passen Rechtegültigkeit, Speicherbedarf und Deduplizierungsaufbewahrung zusammen? | Geräte- und Standort-Sync-Freigabe |
| Wie lange bleiben Aufgaben-, Geräte-, Audit- und HR-Daten gespeichert, und wer darf sie exportieren? | Erster Pilot mit realen Beschäftigtendaten |
| Wer darf eine Abweichung schließen oder eine abgeschlossene Aufgabe korrigieren? | Guided Work und spätere HACCP-Funktion |
| Welche Geräteklassen, Betriebssystemversionen und Scanner/Drucker sind für die erste unterstützte Installation verbindlich? | Pilotbetrieb |
| Welche maximal tolerierbaren Datenverluste und Wiederherstellungszeiten gelten je Standort? | Backup-/Restore-Abnahme |
| Welche API- und Plugin-Fähigkeiten braucht der erste reale Integrationsfall; wer prüft fremde Plugins? | Plugin-Runtime |
| Welche alten Client-/Plugin-/Sync- und Guided-Work-Versionen unterstützt ein Release, und wie werden aktive Instanzen vor einer inkompatiblen Änderung behandelt? | Erster entsprechender Versionswechsel |

Der [Fahrplan](roadmap/phases.md) ordnet diese Fragen Lieferphasen zu. [Compliance](compliance/overview.md) vertieft die regulatorischen Prüfungen, ohne generelle Rechtskonformität zu behaupten.
