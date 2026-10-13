# Workforce Orchestration

P4.11 is **DONE/CLOSED** and adds an explicit one-way transfer of complete future,
pristine published work. Recipient acceptance leaves the schedule unchanged;
independent manager approval cancels originals and publishes exact new work through
Workforce/Tasks ports, retaining both lineage forms. It introduces no automatic
recommendation or roster changes. See [ADR 0025](../adr/0025-one-way-shift-transfer-before-execution.md)
and the [P4.11 record](../development/phase-4-11-one-way-shift-transfers.md).
F01/F02/F03 are CLOSED; targeted APPROVE, 177 PASS / 0 QUALIFIED / 0 FAIL, SECURITY APPROVE and green exact-commit CI 38125193187 establish closure. P4.12 remains UNSELECTED.

Status: target rules for future work recommendations. Current P1b provides explicit template selections, ordered task snapshots and scoped Employee Home queries through `ShiftApplication`; there is no priority/recommendation engine, attendance detection or task dependency graph. Deterministic prioritization described below remains planned. See [actual status](../roadmap/status.md).

## Zweck und Zuständigkeit

Workforce Orchestration beantwortet, welche zulässige Arbeit einer Person in ihrer Schicht als Nächstes angeboten werden sollte. Sie führt Schichtdaten aus `workforce` und Aufgaben aus `tasks` zusammen, ohne selbst deren Wahrheit zu besitzen. Einsatzentscheidungen mit Auswirkungen auf Menschen bleiben nachvollziehbare Vorschläge. Eine Führungskraft kann zuweisen oder übersteuern; das System verschiebt keine Person automatisch in einen anderen Bereich und bewertet niemanden allein anhand der Taskdauer.

Dienstplanung, tatsächliche Arbeitszeiterfassung und dynamische Aufgabenreihenfolge sind getrennte Probleme. Eine veröffentlichte Schicht belegt geplante Anwesenheit, nicht tatsächliches Einstempeln. Solange eine verlässliche Anwesenheitsquelle fehlt, zeigt die Oberfläche diese Unsicherheit und bezeichnet eine Empfehlung nicht als sichere Verfügbarkeit.

Current Employee Home is composed by `ShiftApplication` using authorized module ports. No Tasks recommendation engine queries Workforce today. A future recommendation use case can consume released shift information without owning it; its placement needs a concrete slice, not an assumed new service.

## Planned extension: deterministic recommendations

1. Eine passende Vorlage ist vor Veröffentlichung der Schicht freigegeben. Der P1-Veröffentlichungs-Use-Case wählt die freigegebenen Vorlagenrevisionen und speichert Schicht, zugehörige Instanzen mit Snapshot und Mitarbeiterzuordnung sowie Audit gemeinsam; siehe [ADR 0011](../adr/0011-atomare-schichtveroeffentlichung.md). Eine Wiederholung nach Commit liefert die bereits erzeugten Instanzen. Zusätzlich zur Kommando-Idempotenz wird die fachliche Eindeutigkeit des Vorkommens geprüft: Eine neue Schicht- oder Vorlagenrevision allein legitimiert keine zweite Aufgabe für dieselbe Arbeit. Current pristine cancellation and start/end-only amendment are defined by ADRs 0013/0014. General employee/template changes and begun-work reconciliation remain unsupported.
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

## Decisions before expansion

- Welche Quelle belegt tatsächliche Anwesenheit und wie werden Datenschutzrechte begrenzt?
- Welche Skills sind rechtliche Voraussetzung, welche nur Erfahrungswert?
- Existing pristine cancellation/interval amendment is answered; what applies to reassignment and begun/completed work remains open.
- Welche Regeln haben Vorrang, wenn Sicherheitsrisiko, Frist und personelle Überlastung kollidieren?

## Selected P4.16 bilateral swap coordination (design only)

P4.16 is SELECTED / DESIGN IN PROGRESS on 2026-10-13; implementation is NOT
AUTHORIZED. Protocol B: A requests using own Shift and named B; B deliberately
offers an own counterpart; A confirms that immutable pair; an independent manager
approves or rejects. Neither initial invitation nor either consent changes schedules.
Employees gain no general colleague-roster access.

Workforce owns request/leg/consent/decision/Shift lineage/receipt evidence and a
single active handoff-claim authority shared with P4.11. Requested swaps claim A;
offered/confirmed swaps claim both originals; terminal parents release all claims.
Staleness changes actionability, not persisted consent or claim occupancy. Existing
work execution and interval/cancellation commands can continue and stale a request.

One authorized Company coordinator revalidates both current Shift versions,
pristine Task sets, captured links/Account versions, incoming assignment intervals
and exact guidance. It checks the final roster excluding exactly both originals,
cancels both before replacement publication, and commits both exact legs, Tasks-owned
correspondences, audit/receipts and claim release atomically. A deferred final guard
checks complete effects and fresh database time before both captured starts.
This implements no labor-law, absence, qualification or availability validation.

See the [contract](../development/phase-4-16-bilateral-shift-swaps.md),
[ADR 0030](../adr/0030-bilateral-shift-consent-and-shared-handoff-claims.md) and
[implementation plan](../development/phase-4-16-implementation-plan.md). Broader
comments, recommendations, begun work, partial exchange, remote/offline/multi-site
access remain future. P4.11 historical closure above is unchanged.
