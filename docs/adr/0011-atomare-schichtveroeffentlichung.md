# ADR 0011: Atomare Schichtveröffentlichung im ersten Slice

## Status

Beschlossen für P1. Präzisiert die Transaktionsgrenze aus [ADR 0008](0008-event-system.md); das Event-System für spätere Folgereaktionen bleibt bestehen.

## Kontext

Der bisherige Entwurf erzeugt Aufgaben nach `shift.published` asynchron. Damit benötigt bereits der erste Slice einen Verbraucher, eine Anzeige für ausstehende Generierung und eine historische Auswahl der damals gültigen Vorlagen. Nach Veröffentlichung kann eine Schicht vorübergehend ohne ihre erforderlichen Aufgaben sichtbar sein. Der modulare Monolith besitzt dafür bereits eine gemeinsame lokale PostgreSQL-Datenbank.

## Entscheidung

Ein Application-Use-Case veröffentlicht im ersten Slice eine einzelne Schicht und erzeugt ihre konfigurierte, begrenzte Menge von Aufgaben **in einer lokalen Transaktion**. Er koordiniert öffentliche Ports von `workforce`, `tasks` und `audit`; die Module behalten ihre Regeln und privaten Tabellen. Die Ports verwenden denselben Transaktionskontext, ohne sich gegenseitig auf interne Klassen zu stützen.

Der Use Case prüft Rechte und erwartete Version, wählt freigegebene Vorlagenrevisionen, speichert Instanzen samt Snapshot und Mitarbeiterzuordnung sowie Audit und benötigte Outbox-Einträge. Erst der gemeinsame Commit bestätigt die Veröffentlichung. Fehler rollen den gesamten Vorgang zurück. Eine Wiederholung eines bereits bestätigten Kommandos liefert dessen Ergebnis mit denselben Instanz-IDs; sie wählt keine neuen Vorlagen aus.

`shift.published` und andere erforderliche Ereignisse beschreiben danach den bestätigten Zustand. Kein zusätzlicher P1-Event-Handler erzeugt dieselben Aufgaben erneut. Die Transaktion enthält keine Netzwerk-, Plugin- oder Medienverarbeitung. Ein Überschreiten der unterstützten Aufgabenmenge führt zu einem sichtbaren Fehler, nicht zu teilweiser Veröffentlichung.

## Alternativen

- Asynchrone Aufgabenerzeugung: geeignet für spätere Massenplanung, Wiederholungsregeln oder unabhängige Auslöser; für P1 entstehen unnötige Zwischenzustände und Wiederanlaufregeln.
- Direkter Zugriff von `workforce` auf Task-Tabellen: einfacher Aufrufpfad, verletzt aber fachliche Eigentümerschaft und erschwert spätere Änderungen.

## Konsequenzen

- Employee Home kann nach erfolgreicher Veröffentlichung Schicht und konfigurierte Aufgaben unmittelbar abfragen. Ein eigener Generierungsstatus und ein P1-Task-Event-Verbraucher entfallen.
- Veröffentlichungen hängen vom erfolgreichen Erzeugen der zugehörigen Aufgaben ab; Dauer und Größe der Transaktion müssen begrenzt sein.
- Der erste Slice benötigt keine allgemeine Workflow- oder Scheduling-Engine. Spätere asynchrone Erzeuger brauchen eigene Verträge und dürfen die fachliche Eindeutigkeit eines Vorkommens nicht umgehen.

## Offene Prüfungen

- Unterstützte Anzahl von Vorlagen und Schritten pro Veröffentlichung anhand des Pilotfalls bestimmen.
- Rollback bei Task-/Auditfehler, konkurrierende Veröffentlichung und verlorene Antwort nach Commit prüfen.
