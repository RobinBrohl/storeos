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

## Future Wiki and Planogram guidance

Tasks may pin approved Wiki revisions and assigned published Planogram revisions
as guidance. Knowledge/Merchandising own publication, assignment and content;
Tasks owns execution, feedback/evidence linkage and permissions. Employee suggestions
or deviations require authorized review; they do not silently republish instructions.
Live Article/Assortment/Stock drill-down is a separate authorized query with freshness,
not a replacement of the pinned execution content. Print/PDF identifies the selected
revision. None of these content integrations exists in current task schema.
