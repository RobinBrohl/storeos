# Event-System und Audit

## Zweck und Grenze

Fachmodule veröffentlichen abgeschlossene Tatsachen als versionierte Events. Andere Module können darauf reagieren, ohne Tabellen des auslösenden Moduls zu lesen oder dessen interne Klassen zu importieren. Ein Event ist weder ein Befehl noch der alleinige Datenspeicher: Der fachliche Zustand bleibt in den jeweils zuständigen Modellen. Entscheidungen, die unmittelbar konsistent sein müssen, gehören in einen expliziten Use Case und dürfen nicht von einer späteren Event-Zustellung abhängen.

Mögliche Fakten heißen `shift.published.v1`, `task.instance_created.v1` und `task.completed.v1`. Die Großbuchstaben-Namen des Master-Prompts sind fachliche Beispiele, kein festes Wire-Format. Interne Domain-Ereignisse bleiben im jeweiligen Modul. Nur bewusst veröffentlichte Integrationsereignisse erhalten versionierte Verträge in `packages/api_contracts/`; eine interne Änderung wird dadurch nicht automatisch zu einer öffentlichen API oder einem Plugin-Abonnement. Externe Payloads sind für den Empfänger freigegebene, minimale Projektionen.

## Veröffentlichungs- und Zustellvertrag

Eine Mutation, die ein Event veröffentlicht, speichert innerhalb **einer lokalen PostgreSQL-Transaktion** den neuen Zustand, den erforderlichen Audit-Eintrag und einen Outbox-Eintrag. Ein Hintergrundprozess stellt Outbox-Einträge nach Commit zu. Ein Rollback veröffentlicht nichts. Diese Kopplung verhindert, dass der Zustand ohne dazugehöriges Event gespeichert wird. Nicht jede Mutation benötigt ein Integrationsereignis. Ein Event enthält mindestens:

| Feld | Bedeutung |
| --- | --- |
| `eventId`, `type`, `schemaVersion` | Eindeutige Identität und auswertbarer Vertrag |
| `aggregateType`, `aggregateId`, `aggregateVersion` | Zuordnung und Reihenfolge innerhalb eines fachlichen Objekts |
| `companyId`, `locationId`, `originNodeId` | Berechtigungs- und Herkunftskontext; `locationId` kann bei Unternehmensdaten fehlen |
| `occurredAt`, `recordedAt` | Fachlicher Zeitpunkt und Zeitpunkt der Annahme am zuständigen Server, jeweils UTC |
| `actorId`, `correlationId`, `causationId` | Auslöser und nachvollziehbare Ereigniskette |
| `payload` | Minimal nötige, typisierte Daten ohne unnötige Personal- oder Geheimdaten |

Zustellung erfolgt **mindestens einmal**. Ein interner Verbraucher speichert seine Deduplizierungsmarkierung für `eventId` und Subscription atomar mit seiner lokalen Fachänderung, deren Audit und etwaigen Folgeevents. Eine eindeutige Datenbankbedingung schützt auch bei parallelen Versuchen. Ein Absturz vor Commit darf das Event erneut versuchen; nach Commit darf eine verlorene Quittung keine zweite Wirkung erzeugen. Für externe Effekte ist diese lokale Transaktion nicht ausreichend: Der Adapter braucht einen stabilen Idempotenzschlüssel beim Ziel oder einen Abgleich unklarer Ergebnisse vor erneutem Auslösen. Einmalige externe Wirkung wird nicht pauschal versprochen.

Zustellreihenfolge ist auch innerhalb eines Aggregats nicht allgemein garantiert, etwa nach Retry oder Replay. `aggregateVersion` beschreibt den fachlichen Stand und ist keine lückenlose Event-Sequenz, da nicht jede Änderung ein Event erzeugt. Jeder Verbraucher legt fest, wie er verspätete Events behandelt. Benötigt er zwingend Vorgänger, muss sein Vertrag eine prüfbare Reihenfolge vorsehen und bei fehlendem Vorgänger anhalten oder den zuständigen Owner abgleichen; Fehlerablage darf diese Voraussetzung nicht umgehen. Eigenständige Fakten dürfen nicht allein wegen ihres Alters verworfen werden.

Fehler führen zu begrenzten Wiederholungen, danach in eine überprüfbare Fehlerablage mit manuellem Replay unter denselben IDs und Deduplizierungsregeln. Der Betreiber sieht Rückstand, Alter des ältesten Events und fehlgeschlagene Verbraucher. Schemaänderungen bleiben innerhalb einer Hauptversion rückwärtskompatibel; inkompatible Änderungen erhalten einen neuen Event-Typ oder eine neue Hauptversion.

Events über Standortgrenzen werden über den Synchronisationskanal weitergegeben, aber nur nach den Schreib- und Sichtbarkeitsregeln aus [Datenhoheit](data-ownership.md). Ein Plugin erhält ausschließlich freigegebene Events und darf Folgeaktionen nur über autorisierte Commands/API-Aufrufe anfordern. Ein externer Sensorwert ist zunächst eine unbestätigte Beobachtung; das zuständige Modul validiert und entscheidet, ob daraus eine Abweichung entsteht.

## Audit ist ein eigener Vertrag

Der Audit Trail dokumentiert sicherheits- und fachlich relevante Änderungen: handelnde Person beziehungsweise Systemidentität, Kontext, Zeitpunkt, Aktion, Objekt, Ergebnis, gegebenenfalls Begründung und eine für den Zweck angemessene Änderungsdarstellung. Er wird im selben Commit wie die Änderung geschrieben. Fach-Events sind dafür kein Ersatz, weil sie nur für Integration nötige Informationen enthalten und wiederholt zugestellt werden können. Audit-Einträge werden über die Anwendungs-API nicht nachträglich geändert; Korrekturen sind neue Einträge mit Bezug auf den ursprünglichen Vorgang. Für sensible Felder werden alte/neue Werte gezielt maskiert oder getrennt geschützt. Eine Datenbank allein macht den Trail nicht manipulationssicher; externe Integritätsanker und unveränderliche Aufbewahrung sind spätere, regulatorisch zu prüfende Schritte.

Der Server leitet den ausführenden Akteur aus der authentifizierten Sitzung oder der begrenzten System-/Plugin-Identität ab. Bei einer automatischen Folgeaktion werden der ausführende Handler und das auslösende Event einschließlich ursprünglichem Akteur getrennt festgehalten. Gerätekennung sowie gemeldete Erfassungszeit werden von Serverannahmezeit und gesicherter Identität unterschieden. Abgelehnte Befehle erzeugen keinen erfolgreichen Änderungsnachweis; nach Audit-/Sicherheitsrichtlinie nötige Ablehnungsnachweise werden separat vom zurückgerollten Fachvorgang gespeichert und enthalten keine unnötigen Eingabedaten. Das Anwendungskonto erhält keine Änderungs- oder Löschrechte an Audit-Einträgen; eine geregelte Aufbewahrungsbereinigung ist ein gesondert berechtigter Vorgang.

## Ausbaustufen und Risiken

Die Plattformphase P1 besitzt einen konkreten Verbraucher: Ein lokaler Outbox-Worker verteilt freigegebene Organisationsereignisse an persistente Plugin-Inboxen. Externe Clients holen diese mit eigenen eingeschränkten Tokens ab und bestätigen die eventId. Das ist kein Standort-Synchronisationsprotokoll. Eine eigene, bei Installation persistierte Node-ID bleibt von Location-IDs getrennt. Der [P1-Vertrag](../development/phase-1.md) konkretisiert Payload, Rechte, Retry und Deaktivierung.

Im ersten Slice entstehen Schicht und konfigurierte Aufgaben bereits atomar gemäß [ADR 0011](../adr/0011-atomare-schichtveroeffentlichung.md); ein Event-Verbraucher für diesen Erzeugungsweg entfällt. Dauerhafte Events und ein lokaler Outbox-Verarbeiter werden nur für konkret benötigte Folgereaktionen angelegt, nicht vorsorglich für jede Mutation. Audit gilt unabhängig davon für die relevanten Änderungen. Eine frei konfigurierbare `WHEN/IF/THEN`-Engine, standortübergreifendes Replay und Drittanbieter-Subscriptions folgen erst mit Berechtigungs-, Last- und Fehlerkonzept. Zyklen durch Event-Reaktionen, Event-Stürme und unbemerkte Verbraucherfehler sind konkrete Risiken; Kausalitäts-IDs, Wiederholungsgrenzen und Überwachung müssen sie beherrschbar machen.
