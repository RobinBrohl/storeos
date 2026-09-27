# ADR 0008: Internes Event-System

## Status

Beschlossen für modulübergreifende Reaktionen. Die Schichtveröffentlichung im ersten Slice wird durch [ADR 0011](0011-atomare-schichtveroeffentlichung.md) konkretisiert.

## Kontext

Ein fachlicher Vorgang kann Aufgaben, Benachrichtigungen, Schichtübergaben und später Buchungen auslösen. Diese Reaktionen sollen Module entkoppeln. Gleichzeitig darf ein bestätigter Vorgang nicht verschwinden, wenn ein Handler abstürzt.

## Entscheidung

Module veröffentlichen benannte, versionierte Fakten nach erfolgreicher Fachtransaktion. Dauerhafte Events werden mit dem Fachzustand in derselben Datenbanktransaktion in einer Outbox erfasst und danach zugestellt. Handler verarbeiten wiederholte Zustellungen idempotent; Fehler werden sichtbar, erneut versucht und nötigenfalls manuell geklärt. Event-Nutzdaten enthalten nur erforderliche Informationen und stabile IDs. Events ersetzen weder die zuständige Fachdatenhaltung noch den Audit Trail. Befehle mit Entscheidungs- oder Freigabebedarf bleiben explizite Anwendungsfälle.

## Alternativen

- Direkte synchrone Aufrufe für jede Folgereaktion: weniger Infrastruktur, aber enge Kopplung und Ausfallketten.
- Vollständiges Event Sourcing: verworfen für den Start wegen zusätzlicher Projektions-, Schema- und Migrationskomplexität.
- Externer Broker als Pflicht: verworfen für den lokalen Erstbetrieb.

## Konsequenzen

- Zustellung kann verzögert und mindestens einmal erfolgen; Verbraucher dürfen keine Einmaligkeit unterstellen.
- Interne Verbraucher koppeln Deduplizierung und Fachänderung atomar. Externe Effekte benötigen eigene Idempotenz oder Ergebnisabgleich.
- Versionsmetadaten garantieren keine Zustellreihenfolge. Reihenfolgeabhängige Verbraucher müssen fehlende Vorgänger behandeln; Rückstau und Fehler werden sichtbar. Der [Zustellvertrag](../architecture/event-system.md) konkretisiert dies.
- Im ersten Durchstich entstehen Schicht und konfigurierte TaskInstances gemeinsam gemäß ADR 0011. Events dienen nachgelagerten Reaktionen; sie sind kein zweiter Erzeugungsweg für dieselben Aufgaben.

## Offene Prüfungen

- Welche Reaktionen müssen in derselben Transaktion stattfinden, welche dürfen asynchron sein?
- Aufbewahrung und Wiederholung von Events gegen Datenschutz und Speicherbedarf abgleichen.
