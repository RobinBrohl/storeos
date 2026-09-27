# P1b.1 – Mitarbeiteridentität und Eigenansicht

Freigegebener Teilslice: Employee → Account-Verknüpfung → eigenes Profil → Audit.
Schichten, Aufgaben, Employee Home, Guided Work und Offline-Schreiben bleiben ausgenommen.

## Modell und Eigentümer

`people` besitzt ein operatives Employee-Profil: UUID, Company, Anzeigename,
Aktivstatus, Version, Erstellungs-/Änderungszeit und genau eine unveränderliche
Location-Zuordnung. Deren Gültigkeit beginnt bei der serverseitigen Anlage und
endet bei Deaktivierung (halboffenes Intervall). Keine Rückdatierung,
Standortwechsel, Reaktivierung, Personalnummern oder HR-Felder in diesem Slice.
Profile sind unabhängig von Accounts; Namen sind keine Identität.

Identity besitzt die versionierte Account-Employee-Verknüpfung mit eigener UUID,
Company, Location, Anlage- und Entzugszeit. Partielle Unique-Constraints erlauben
höchstens eine aktive Verbindung je Account beziehungsweise Employee.
Zusammengesetzte Fremdschlüssel sichern denselben Company-/Location-Scope.
Verknüpfung und Entzug verändern keine Rolle. Eine neue Verknüpfung nach Entzug
hat eine neue ID; alte Verknüpfungen bleiben erhalten.

Ein kleiner Application-Koordinator verbindet die öffentlichen People- und
Identity-Services in der bestehenden lokalen Transaktion. Repositorytypen und
Tabellen bleiben beim Eigentümer. Deaktivierung beendet die Standortgültigkeit,
entzieht eine bestehende Verbindung und widerruft betroffene Sitzungen atomar.
Auch Verknüpfen und Entziehen widerrufen Sitzungen des betroffenen Accounts.

## Rechte und API

Alle Routen liegen unter `/api/v1/platform`, verwenden Benutzer-Bearer-Sitzungen
und die bestehenden JSON-Fehlerverträge. Jede Operation prüft aktuelle Rechte
nach dem Company-Lock. Ein Admin verwaltet Profile an konfigurierten Locations
derselben Company. Die feste Rolle `employee` liest Organisation nur am eigenen
Standort und das eigene aktive, aktuell verknüpfte Profil. Auch ein Admin darf
sein eigenes Profil lesen, sofern verknüpft. Viewer/Auditoren erhalten keine
Profilrechte. Plugin-Berechtigungen und Payloads bleiben unverändert.

| Operation | Vertrag | Recht |
| --- | --- | --- |
| GET `/employees` | höchstens 200 Profile, keine still abgeschnittene Liste | people.manage |
| GET `/employees/me` | eigenes Profil; 404 wenn keine aktive Zuordnung | people.self.read |
| GET `/employees/{id}` | einzelnes Profil | people.manage |
| POST `/employees` | id, displayName, locationId | people.manage |
| POST `/employees/{id}/rename` | displayName, expectedVersion | people.manage |
| POST `/employees/{id}/deactivate` | expectedVersion | people.manage |
| GET `/employees/{id}/account-link` | `{link: ... oder null}` | people.manage |
| POST `/employees/{id}/account-link` | id, accountId, expectedEmployeeVersion, expectedAccountVersion | people.manage |
| POST `/employee-links/{id}/revoke` | expectedVersion | people.manage |

Accounts und Profile müssen beim Verknüpfen aktiv sein und denselben Standort
besitzen. Deaktivierte Profile sind nur administrativ lesbar. Änderungen prüfen
Versionen, widersprüchliche Anfragen liefern 409. Erstellungen verwenden stabile
Client-UUIDs; dieselbe ID erzeugt keinen zweiten Datensatz (409 bei Wiederholung).
Nach unklarem Ausgang lädt der Client den Serverstand und behält die ID für einen
unbestätigten Wiederholungsversuch. Kein generisches Command-/Sync-Framework.

## Audit, Datenminimierung und Client

Anlage, Namensänderung, Deaktivierung, Verknüpfung und Entzug werden atomar
auditiert. Audit enthält IDs, Versionen, geänderte Feldnamen und Status, keine
Kopien von Mitarbeiter-Anzeigenamen oder Anmeldegeheimnissen. Neue Vorgänge haben
eine serverseitige Korrelations-UUID; HTTP-Antwort/Log, Audit und gegebenenfalls
Organisationsevents desselben Vorgangs teilen sie. Historische Auditzeilen
behalten `null`, ohne erfundene rückwirkende Korrelation. Audit bleibt separat
für Admin/Auditor berechtigt; es gibt keinen Mitarbeiter-Auditexport.

Flutter erhält eine administrative Mitarbeiteransicht und „Mein Mitarbeiterprofil“.
Beim Laden werden alte Profildaten entfernt. Nach Sessionwechsel werden verspätete
Antworten und nachgelagerte Anfragen alter Vorgänge verworfen. Ein Ansichtswechsel
wartet bei laufender Anfrage auf deren Abschluss, bevor die neue Ansicht lädt.
Ohne bestätigten, eingerichteten Standort ist die Profilanlage mit einer Erklärung
deaktiviert. Eine periodische Aktualisierung der sichtbaren Eigenansicht
erkennt serverseitigen Entzug. Ohne Verbindung wird kein veraltetes Profil als
aktuell bestätigt angezeigt. Ein bereits angezeigter Inhalt kann ohne erneute
Serverkommunikation nicht unmittelbar aus einem entfernten Browser gelöscht werden.

Keine Mitarbeiter-Integrationsereignisse ohne konkreten Verbraucher. Backups
enthalten die neuen PostgreSQL-Tabellen. Aufbewahrung/Löschung und Wiederanwendung
neuerer Sperren nach Restore bleiben vor Einsatz mit echten Beschäftigtendaten
betriebsbezogen festzulegen; Deaktivierung ist keine datenschutzrechtliche Löschung.

## Abnahme

Echter HTTP-/PostgreSQL-Ablauf unter Runtime-Rolle, Upgrade aus P1 ohne geänderte
IDs/Hashes/Auditdaten, Constraints, konkurrierende Verknüpfung/Deaktivierung,
Versionskonflikte, Antwortverlust und Wiederholung, Sitzungsentzug, Fremdzugriffe,
Audit-Rollback/-Korrelation und Flutter-Fehlerzustände werden geprüft.
Bestehende Tests und Analyzer bleiben erfolgreich. P1b insgesamt bleibt offen.
