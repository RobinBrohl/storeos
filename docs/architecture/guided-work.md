# Guided Work

Status: Zielkonzept. [P1b.4](../development/phase-1b-execution.md) implementiert ausschließlich geordnete Bestätigungsschritte, Start, Wiederaufnahme und Abschluss. [P1b.5](../development/phase-1b-blocking.md) ergänzt manuelle Blockierungen und administrative Freigabe zur Wiederaufnahme. [P1b.6](../development/phase-1b-cancellation.md) ergänzt die begründete Stornierung blockierter Aufgaben. [P1b.7](../development/phase-1b-7-numeric-steps.md) ergänzt Zahleneingaben mit festen inklusiven Grenzen und automatischer Blockierung.

## Ziel und fachlicher Vertrag

Guided Work führt eine Person durch eine konkrete `TaskInstance`. Die Vorlagenversion erklärt Ort, Zweck, Handlung, benötigte Informationen und Abschlussbedingungen. Eine Anleitung ist zugleich nutzbare Unterstützung und Grundlage einer nachvollziehbaren Durchführung. Sie ersetzt weder fachliche Qualifikation noch vorgeschriebene Einweisung oder Schulung.

`TaskTemplate` enthält geordnete, versionierte Schrittdefinitionen. Eine `TaskInstance` speichert beim Erzeugen die verwendete Revision als Snapshot. `TaskExecution` hält innerhalb dieser Instanz pro Schritt Eingabe, Zeit, Akteur, gegebenenfalls Nachweis und Ergebnis fest. Die UI zeigt eine Aufgabe beziehungsweise einen Schritt im Handheldmodus und passende Übersichten auf Desktop. Jeder serverseitige Befehl prüft Mandant, Standort, Berechtigung, die in der Instanz gespeicherte Vorlagenrevision, Status und erwartete Version. Eine neu veröffentlichte Vorlage verändert die Abschlussbedingungen einer bestehenden Instanz nicht.

## Ablauf im ersten Slice

1. Mitarbeiter öffnet eine berechtigt sichtbare Aufgabe aus Employee Home. Die Anleitung nennt Kontext und Schritte; der Start wird gespeichert.
2. Schritte können zunächst Informationstext, explizite Bestätigung und eine validierte Zahleneingabe enthalten. Ein Messwert wird mit Einheit, Eingabezeit, Grenzregel und Regelversion erfasst. Pflichtschritte lassen sich nicht durch ein bloßes „Fertig“ umgehen.
3. Die Auswertung erfolgt auf dem Server. Liegt ein Wert außerhalb einer für die Vorlage festgelegten Grenze, wird die Instanz `blocked`; der Sachverhalt wird nachvollziehbar erfasst und eine verantwortliche Person muss ihn bearbeiten. Ein normales `completed` ist in diesem Zustand nicht zulässig. Nach dokumentierter Klärung kann eine berechtigte Person die Wiederaufnahme freigeben oder die Aufgabe begründet stornieren. Die ursprüngliche Abweichung bleibt erhalten; der spätere Abschluss erfordert weiterhin gültige Pflichtnachweise.
4. Erfolgreicher Abschluss speichert Ergebnis, Endzeit und Audit-Eintrag konsistent. Danach fragt Employee Home die nächste zulässige Aufgabe erneut ab.

Im Beispiel „Bistro morgens vorbereiten“ wird die Kühltemperatur eingegeben. Der erste Slice darf bei Abweichung eine generische Ausnahme und Eskalation zeigen. Er bezeichnet diese Erfassung nicht als rechtskonforme HACCP-Kontrolle. Dafür fehlen zunächst ControlPlan, Messgerätekontext, freigegebene Korrekturmaßnahme, erneute Prüfung und branchenspezifische Nachweispflichten. Diese gehören in das spätere HACCP-Modul.

## Erweiterbares Schrittmodell

Der Instanz-Snapshot hält neben der Vorlagenrevision auch Schritt-/Regelschema und Auswertungssemantik in der verwendeten Version fest. Referenzen auf SOPs und Medien zeigen auf unveränderliche Inhaltsversionen, nicht auf einen Link zur jeweils neuesten Fassung. Ein Update muss laufende Instanzen mit ihren bisherigen Regeln weiter ausführen können oder eine ausdrücklich freigegebene, auditierte Migration bereitstellen. Ist beides nicht möglich, wird der inkompatible Release für diese Installation blockiert. Historische Eingaben und Ergebnisse werden nicht nach neuen Regeln still neu bewertet; eine allgemeine Regelengine ist dafür im ersten Slice nicht nötig.

Spätere Schrittarten können Bilder, Videos, Warnhinweise, Checklisten, Scanner-Eingaben, QR-Kontext, Foto, Signatur und Freigabe umfassen. Sie erhalten jeweils ein eigenes validiertes Datenschema und explizite Speicher- und Berechtigungsregeln. Ein Freitext oder Foto ist kein Ersatz für strukturierte Pflichtdaten. Medien werden versioniert, gegen unerlaubte Dateitypen geprüft und nur mit angemessener Aufbewahrung gespeichert.

Kontextregeln werden als begrenzte, deklarative Bedingungen über erlaubte Eingaben und freigegebene Referenzdaten modelliert, nicht als beliebig ausführbarer Vorlagencode. Ein Schritt kann einen Pfad verzweigen, eine begründete Auslassung erlauben oder eine Eskalation verlangen. Die Regelversion und die tatsächlich gewählte Verzweigung bleiben an der Ausführung nachvollziehbar. Bei fehlender Ware oder defektem Gerät muss die Person einen Grund angeben können; eine solche Ausnahme wird nicht als regulär erfolgreich erledigt kaschiert.

Abhängige Aufgaben werden erst nach dem serverseitig gültigen Abschluss freigeschaltet. Wiederaufnahmen verwenden die gespeicherte Ausführung und führen nicht zu doppelten Schrittresultaten. Änderungen an einer Vorlage wirken nur auf neue Instanzen; Korrekturen an einer laufenden Ausführung sind eigene, auditierte Aktionen. Bei einem Offline-Client steht ein lokal erfasster Schritt bis zur Serverannahme auf `ausstehend`. Die UI darf daraus keinen rechtsrelevanten bestätigten Abschluss ableiten. Konflikte werden sichtbar gelöst; die [Offline-Strategie](offline-strategy.md) legt den konkreten Umfang fest.

## Bedienung und Datenschutz

Die Handheldführung nutzt kurze Anweisungen, große Aktionen, klare Fehler und möglichst wenige Eingaben. Scanner liefern Kontext, lösen aber keine Berechtigung aus. Mitarbeiter sehen eigene Aufgaben und für die Arbeit nötige Informationen; Führungskräfte erhalten nur zweckgebundene Fortschrittsansichten. Kommentare und Nachweise dürfen nicht unbegrenzt sensible Personal- oder Kundendaten sammeln. Zugriff und Aufbewahrung richten sich nach Datentyp und Standort.

## Remaining decisions

- Current template publication/bound editing is an authorized admin command. Who may correct a running/terminal instance or future safety evidence remains undecided; existing snapshots are immutable.
- Welche Schrittarten und Nachweise sind im ersten produktiven Einsatz tatsächlich nötig?
- Wann ist eine Auslassung fachlich zulässig, und wer genehmigt sie?
- Welche Offline-Schritte sind bei möglichem Risiko sicher zulässig?

## Implementierte Zahlenbewertung (P1b.7)

Schema 2 erlaubt `number` neben `confirmation`; Schema 1 bleibt ausführbar. Einheit
und Grenzen gehören zum unveränderlichen Snapshot. API-Dezimalstrings werden als
exakte Tausendstel gespeichert; mehr als drei Nachkommastellen werden abgewiesen.
Tasks bewertet die Grenzen, ohne Float-Arithmetik, Einheitenumrechnung oder Regelengine.

Jeder angenommene Versuch erhält Akteur, Serverzeit und Instanzversion. Erfolg erzeugt
ein Schrittresultat mit Versuchreferenz; Abweichung erzeugt eine Blockierung mit
Versuchreferenz. Fehlgeschlagene Versuche zählen nie als bestätigte Schritte. Resume
behält denselben offenen Schritt; Cancel beendet die Aufgabe unter Erhalt der Historie.
SQL-Invarianten verhindern Bestätigungen ohne passenden erfolgreichen Versuch sowie
verwaiste Versuche. Audit und Receipt werden in derselben Transaktion geschrieben.
Werte sind nur über die berechtigte Versuchshistorie verfügbar, nicht im Audit/Log.

## Assigned Knowledge guidance (P4.6)

P4.6 is **DONE/CLOSED**, with bounded F01 remediation, targeted review APPROVE,
64/64 PASS, focused Codex Security SECURITY APPROVE and green changed-commit CI.
Task content schema 3 retains confirmation/numeric semantics and adds required,
nullable `knowledgeGuidance`, containing exactly `articleId` and `revisionId`.
Schemas 1/2 and their persisted snapshots/receipts remain unchanged.

Draft selection captures the current approved revision; publication freezes the
explicit selection. Template and Shift publication validate same-Company published
revision and active Article atomically. A newer publication leaves retained older
published pins valid while the Article stays active. Task snapshots retain identity
without copying Knowledge title/body. Generated columns/composite FKs and the
published Template correspondence guard protect durable identity, never Article activity.

Create/replacement selection invalidity returns 422 `guidance_selection_unavailable`.
Fresh Template/Shift publication of an unusable retained pin returns 422
`guidance_unavailable`. Unchanged retained editing/cloning and committed replay do
not perform fresh selection; committed replay returns neither availability error.

Tasks/Workforce first authorize the visible Shift/Task, then use the Knowledge-owned
port to read its stored pin. Contextual employee reads require current session,
active Employee link, configured execution Location, own visible Task and Knowledge
read. Manager reads require existing authorized Task scope and Knowledge read.
Clients cannot supply a historical revision. Current supersession/retirement indicators
are separate from exact frozen instruction content.

Retirement is not emergency withdrawal: it blocks fresh publication, while already
published Tasks remain readable and executable. Exact publication replay returns
committed evidence after fresh authorization. The plain-text instruction panel creates
no acknowledgment or Task mutation and returns to the same execution state.
See [ADR 0020](../adr/0020-task-knowledge-guidance.md) and
[P4.6 evidence](../development/phase-4-6-task-knowledge-guidance.md).

## Future guidance extensions

Assigned exact Planogram deployment guidance is delivered in P4.7 below. Future feedback, deviation and media workflows require separate contracts.
Knowledge/Merchandising own publication, assignment and content;
Tasks owns execution, feedback/evidence linkage and permissions. Employee suggestions
or deviations require authorized review; they do not silently republish instructions.
Live Article/Assortment/Stock drill-down is a separate authorized query with freshness,
not a replacement of the pinned execution content. Print/PDF identifies the selected
revision. P4.6 adds no Planogram guidance, feedback workflow or live drill-down integration.

## Assigned Planogram deployment guidance (P4.7)

P4.7 is **DONE/CLOSED**. Schema 4 supports independent nullable `knowledgeGuidance`
and `planogramGuidance`; schemas 1–3 remain unchanged. One Template may retain one
optional concrete PlanogramGuidance with exactly `fixtureId`, `assignmentId` and
`revisionId`. There is no generic guidance/reference framework.

Fixture identifies the physical target and Location; Assignment identifies the exact
deployment occurrence; Revision freezes the published structure. Explicit selection
captures F/A1/R1, Template publication validates and freezes it, and fresh Shift
publication revalidates it and copies it into immutable Task content. After F/A2/R2,
the existing Task resolves A1/R1 while standalone Merchandising shows A2/R2. Publishing
R2 alone leaves A1/R1 valid. Returning R1 as A3 does not revive A1. No automatic rebase
occurs. Retirement blocks fresh publication but preserves authorized historical Task
evidence; it is not emergency withdrawal.

Current Company, configured execution Location and capability/resource authorization
precede every retained read and committed replay. Management/Template work Location
must equal the currently configured Location; mismatch is `403 forbidden`. Employees
need a valid session, active Employee link, own visible Shift/Task, Task self-read and
Merchandising read. Managers need legitimate scoped Shift/Task access and Merchandising
read. The server derives the exact tuple from stored content; this is no general
Assignment/Revision history browser. Returning legitimately to the work Location
restores access if all normal authorization passes.

Committed Template/Shift replay may return original evidence after reassignment or
retirement only after current authorization. It bypasses fresh lifecycle validation,
never current Location scope, and duplicates neither Tasks nor audit nor changes pins.
Selection failure is `422 planogram_selection_unavailable`; fresh retained-pin failure
is `422 planogram_guidance_unavailable`. The removed unreachable selector
`409 invalid_lifecycle` stays removed; reachable Template/Shift conflicts remain.

Frozen evidence includes F/A/R, Zones, placements, Article identities, ordering and
facings. Fixture descriptors, Article labels/status, Assortment, optional Stock,
lifecycle indicators and query time are explicitly current enrichment. Missing,
zero and unavailable Stock remain distinct; supported optional failure preserves
retained layout. No Stock writes are introduced. Knowledge lifecycle/authorization
remains independent from the Planogram pin.

Opening Assigned layout does not start, confirm, record numeric input, complete,
acknowledge or track readership, emit an event or mutate Task execution. Returning
preserves execution state; completion retains the immutable tuple. Migration 0019
protects durable scope/identity and Template correspondence without encoding current
Assignment, active lifecycle or transient configured Location in permanent FKs.
See [ADR 0021](../adr/0021-task-planogram-assignment-guidance.md) and
[P4.7 closure evidence](../development/phase-4-7-task-planogram-guidance.md#final-documentation-closure--2026-10-05).
