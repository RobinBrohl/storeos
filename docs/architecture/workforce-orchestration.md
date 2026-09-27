# Workforce Orchestration

Status: fachliche Regeln für die spätere Aufgabensteuerung. Der erste Slice implementiert nur die hier gekennzeichnete Minimalform.

## Zweck und Zuständigkeit

Workforce Orchestration beantwortet, welche zulässige Arbeit einer Person in ihrer Schicht als Nächstes angeboten werden sollte. Sie führt Schichtdaten aus `workforce` und Aufgaben aus `tasks` zusammen, ohne selbst deren Wahrheit zu besitzen. Einsatzentscheidungen mit Auswirkungen auf Menschen bleiben nachvollziehbare Vorschläge. Eine Führungskraft kann zuweisen oder übersteuern; das System verschiebt keine Person automatisch in einen anderen Bereich und bewertet niemanden allein anhand der Taskdauer.

Dienstplanung, tatsächliche Arbeitszeiterfassung und dynamische Aufgabenreihenfolge sind getrennte Probleme. Eine veröffentlichte Schicht belegt geplante Anwesenheit, nicht tatsächliches Einstempeln. Solange eine verlässliche Anwesenheitsquelle fehlt, zeigt die Oberfläche diese Unsicherheit und bezeichnet eine Empfehlung nicht als sichere Verfügbarkeit.

Im ersten Slice ist die Vorschlagslogik ein begrenzter Application-Use-Case von `tasks`, der veröffentlichte Schichtdaten über einen Port abfragt. Dafür entsteht weder eine allgemeine Optimierungsengine noch ein zusätzlicher Dienst.

## Erster Slice: deterministische Vorschläge

1. Eine passende Vorlage ist vor Veröffentlichung der Schicht freigegeben. Der P1-Veröffentlichungs-Use-Case wählt die freigegebenen Vorlagenrevisionen und speichert Schicht, zugehörige Instanzen mit Snapshot und Mitarbeiterzuordnung sowie Audit gemeinsam; siehe [ADR 0011](../adr/0011-atomare-schichtveroeffentlichung.md). Eine Wiederholung nach Commit liefert die bereits erzeugten Instanzen. Zusätzlich zur Kommando-Idempotenz wird die fachliche Eindeutigkeit des Vorkommens geprüft: Eine neue Schicht- oder Vorlagenrevision allein legitimiert keine zweite Aufgabe für dieselbe Arbeit. Änderungen und Stornierungen veröffentlichter Schichten bleiben gesperrt, bis der Abgleich vorhandener Instanzen definiert und getestet ist.
2. Employee Home lädt nur die eigene, berechtigt sichtbare Schicht und offene Aufgaben am betroffenen Standort. Zwingende Filter sind Standort, Zeitfenster, explizite Zuordnung und später Skill beziehungsweise Geräteanforderung.
3. Eine stabile Sortierung berücksichtigt zunächst fällige und sicherheitsrelevante Aufgaben, danach Deadline, Vorlagenpriorität und Erzeugungszeit. Die Oberfläche kann den Grund der Reihenfolge in verständlicher Form nennen. Gleichstände werden deterministisch gebrochen.
4. Eine begonnene Aufgabe bleibt sichtbar und wird nicht still verdrängt. Bei neuer dringender Arbeit wird ein Vorschlag zum Unterbrechen angezeigt; Abbruch und Wiederaufnahme sind ausdrückliche, auditierte Aktionen.
5. Serverbefehle prüfen Zustände, erwartete Version und Rechte erneut. Ein alter Clientvorschlag kann keine gesperrte Folgeaufgabe freischalten.

Die erste Demo kann eine Aufgabe „Bistro morgens vorbereiten“ aus einer veröffentlichten Schicht erzeugen, sie auf Employee Home anzeigen und nach erfolgreichem Abschluss die nächste zulässige Aufgabe anbieten. Die im Master-Prompt skizzierte automatische Erkennung von Anwesenheit, Kundenaufkommen, Pausen oder Standortüberlastung ist noch kein Teil dieses Slice.

## Spätere Regeln

Eine ausgereifte Orchestrierung bildet Aufgaben als gerichteten Abhängigkeitsgraphen ab. Vor einer Veröffentlichung wird auf Zyklen geprüft. Eine Aufgabe ist erst startbar, wenn alle notwendigen Vorgänger erfolgreich abgeschlossen oder durch eine ausdrücklich geregelte Alternative ersetzt sind. Zeitfenster unterscheiden `earliestStart`, `preferredStart`, `deadline` und `latestFinish`; wiederkehrende Regeln werden in der Standortzeitzone ausgewertet und behandeln Sommerzeitwechsel explizit.

Eignung ist ein harter Filter für gültige Qualifikation, Berechtigung, Standort, Zeitfenster und gegebenenfalls Gerät oder Ort. Priorisierung innerhalb geeigneter Aufgaben kann Risiko, Frist, Kundenwirkung, Dauer und aktuelle Belastung berücksichtigen. Jede Regel besitzt einen erklärbaren Grund und eine Version. Gewichtungen sind Standortkonfiguration mit Audit, keine verborgene KI-Entscheidung. Abwesenheit und Pausen dürfen nur aus dafür autoritativen Daten stammen. Schichttausch oder Personalumsetzung benötigen eine menschliche Freigabe sowie eine separate arbeitsrechtliche Prüfung.

Ereignisse können später Aufgaben auslösen oder eine Priorität neu berechnen, etwa Lieferung, Temperaturabweichung oder Krankmeldung. Doppelte und verspätete Ereignisse sind normal; Handler arbeiten idempotent. Wiederholungen können eine noch offene Empfehlung aktualisieren, aber nie still eine abgeschlossene Ausführung umschreiben. Ereignisse mit Compliance- oder Sicherheitsfolgen erfordern definierte Eskalationspfade, selbst wenn keine geeignete Person verfügbar ist.

## Nachvollziehbarkeit und Grenzen

Die Anzeige einer Empfehlung enthält nach Möglichkeit fällige Zeit, Abhängigkeit, Prioritätsgrund und Stand der Daten. Führungskräfte sehen Engpässe als Hinweis mit Quelle, nicht als objektiven Leistungswert. Persönliche Taskzeiten sind kein automatischer Sanktionsauslöser. Protokolliert werden Entscheidungen und Änderungen, nicht unnötiges Mikromanagement oder Bewegungsprofile.

Bei unterbrochener Verbindung zum Standortserver darf der Client zuletzt geladene Arbeit anzeigen und ausdrücklich freigegebene Aktionen vormerken. Eine veraltete Reihenfolge wird als solche markiert. Für neue dringende Ereignisse kann offline keine Vollständigkeit zugesichert werden; serverseitige Konfliktprüfung erfolgt beim Synchronisieren. Die [Offline-Strategie](offline-strategy.md) regelt die erlaubten Operationen.

## Vor dem Ausbau zu klären

- Welche Quelle belegt tatsächliche Anwesenheit und wie werden Datenschutzrechte begrenzt?
- Welche Skills sind rechtliche Voraussetzung, welche nur Erfahrungswert?
- Was gilt bei Schichtänderung für bereits erzeugte, begonnene oder erledigte Aufgaben?
- Welche Regeln haben Vorrang, wenn Sicherheitsrisiko, Frist und personelle Überlastung kollidieren?
