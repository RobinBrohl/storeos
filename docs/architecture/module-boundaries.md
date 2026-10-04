# Modulgrenzen und Monorepo

Status: fachlich geplanter Zuschnitt. P0 implementiert Server, Flutter-Client, API-Verträge und Designsystem. P1 ergänzt Organization, Identity, Audit, Events und Plugin-Registrierungen als logisch getrennte Komponenten unter `apps/server/lib/src/organization/`, `identity/` und `platform/`. Weitere Verzeichnisse sind zunächst nur dokumentiert; Fachmodule werden erst mit ihrem jeweiligen Vertical Slice implementiert.

P1b.1 ergänzt `apps/server/lib/src/people/` als logische Modulgrenze für Employee. Der Application-Koordinator `EmployeeApplication` verwendet die öffentlichen Ports `PeopleService`, `EmployeeLinks` (Identity) und `OrganizationService.requireConfiguredLocation` in einer gemeinsamen autorisierten Transaktion. People besitzt Profile und Standortgültigkeit; Identity besitzt Account-Verknüpfungen und Sitzungen. Nur API-Projektionen verlassen People, interne Domain- und Repositorytypen bleiben privat. Ein eigenes Package oder Event zur synchronen Verknüpfung ist nicht erforderlich. Details: [P1b.1](../development/phase-1b-employee.md).

## Repo-Zuschnitt

```text
apps/
  server/            # Dart-HTTP-Host, Konfiguration, Zusammensetzen der Module
  client_flutter/    # Flutter-Anwendung mit gerätespezifischer UX
packages/
  api_contracts/     # versionierte öffentliche DTOs und API-Schemata
  design_system/     # gemeinsame Flutter-Komponenten
  plugin_sdk/        # öffentliche Plugin-Verträge
  shared/            # kleine, stabile technische Primitive ohne Fachlogik
modules/
  organization/      # Company, Location; später Organisationshierarchie
  people/            # Employee und später Skills/Personalbereiche
  workforce/         # Shift und später Planung/Zeiterfassung
  tasks/             # Vorlagen, Instanzen, Guided Work
  audit/             # auf Anwendungsebene nur ergänzbare Historie
  ...                # spätere fachliche Module nach ADR und Slice
plugins/examples/    # Beispiele ohne Produktionsrechte
infra/
  docker/
  backup/
  reverse_proxy/
docs/
  architecture/
  adr/
  roadmap/
  compliance/
```

`apps/server` ist der Composition Root. Authentifizierung und Autorisierung sind dort als Plattformdienste beziehungsweise klar begrenzte interne Komponenten vorgesehen; deren endgültiger Paketort wird vor der Implementierung entschieden. `packages/shared` wird kein Sammelplatz für fachliche Modelle. `packages/api_contracts` enthält veröffentlichte Transportverträge, keine interne Datenbankstruktur. Ein Modul darf seine internen Domain- und Repositorytypen nicht zum allgemeinen Datenaustausch machen.

Die Grenzen sind zunächst logisch: Sie verlangen weder einen Prozess noch ein Dart-Package oder Datenbankschema pro Fachobjekt. Interne Application-Ports können direkte typisierte Aufrufe im selben Prozess sein. Für eine lokale Abfrage sind weder HTTP noch Event-Zustellung nötig. Auch Audit bleibt ein gemeinsam nutzbarer Bestandteil der lokalen Transaktion und wird kein separat erreichbarer Dienst.

## Fachliche Eigentümer

| Eigentümer | Schreibt | Stellt anderen bereit | Darf nicht besitzen |
| --- | --- | --- | --- |
| `organization` | Company, Location, spätere Struktur | Standort- und Mandantenstatus, IDs | Personalakten, Schichten |
| `people` | Employee, spätere Skill- und Personalnachweise | minimale Mitarbeiterreferenz und autorisierte Eignung | Account-Sessions, Aufgabenstatus |
| `workforce` | Shift und spätere Einsatzplanung | veröffentlichte Schichten, verfügbare Einsatzfenster | Guided-Work-Schritte, Arbeitszeit aus Plan ableiten |
| `tasks` | TaskTemplate, TaskInstance, Ausführung | Aufgabenstatus und begründete nächste Aufgabe | Personalakten, Schichtdatenhoheit, HACCP-Kontrollakte |
| `inventory` | Article (unternehmensweiter Produktstamm) und ArticleLocationAssortment (standortbezogene Sortimentsfreigabe) | freigegebene Artikel-/Standortprojektion (`inventory_article_location_projection`) und `InventoryArticlePort` für Bestandsfunktionen, ausdrückliche Standortreichweite | Bestände, Lieferanten, Preise |
| `stock` | StockLevel (aktuelle Projektion) und StockMovement (unveränderliches Bestands-Ledger) | aktueller Bestand, Bewegungshistorie und exact-decimal Mengen je Artikel und Standort | Article, Sortiment, Bewertung, Lieferanten, Preise |
| `audit` | AuditEntry | berechtigte Historie und Export | fachliche Zustandsentscheidung |
| Plattformkomponente Identität/Berechtigungen | Account, Account-Employee-Verknüpfung, Rollen und Grants | geprüfter Zugriffskontext und minimale Identitätsreferenzen | Personalakte, fachliche Schicht-/Aufgabenregeln |

Die Abhängigkeiten laufen über benannte Application-Ports, versionierte API-Verträge oder Ereignisse. Im ersten Slice koordiniert ein Application-Use-Case Schichtveröffentlichung, Task-Erzeugung und Audit über diese Ports in einer gemeinsamen lokalen Transaktion; siehe [ADR 0011](../adr/0011-atomare-schichtveroeffentlichung.md). `tasks` besitzt Vorlagen und Instanzen und darf keine `workforce`-Tabelle aktualisieren. Die Koordination schafft keine gegenseitige Abhängigkeit der Domainmodelle. `shift.published.v1` wird nach Commit für Folgereaktionen zugestellt und erzeugt die P1-Aufgaben nicht erneut. Modulübergreifende Lesemodelle enthalten nur für ihre Empfänger freigegebene Felder. Direkte Datenbank-Joins zwischen Modul-Schemas sind keine öffentliche Integrationsschnittstelle.

## Abhängigkeitsregeln

Employee Home ist ein zusammengesetztes Lesemodell: Ein Application-Query im Server kombiniert berechtigte Schicht- und Aufgabenabfragen. `tasks` besitzt die Aufgabenregeln, `workforce` die Schichtregeln. Die Ansicht begründet kein weiteres Fachmodul und zunächst keine eigene persistente Kopie dieser Daten. Eine materialisierte Projektion kommt erst bei nachgewiesenem Bedarf hinzu und braucht dann Aktualitäts- und Wiederaufbauregeln.

- UI ruft Application-Befehle und Queries über API-Verträge auf; HTTP-Routen und Widgets enthalten keine Geschäftsentscheidung.
- Domainmodelle hängen weder von Flutter noch von HTTP, SQL, Docker oder Plugins ab.
- Module besitzen Migrationen und Schemaobjekte für ihre Daten. Fremde Module greifen ausschließlich über Ports beziehungsweise dokumentierte Events zu.
- Gemeinsame technische Primitive werden nur dann in `shared` aufgenommen, wenn ihre Bedeutung stabil und fachlich neutral ist. Eine zyklische Modulabhängigkeit ist ein Architekturfehler.
- Ereignisse sind nach erfolgreichem Commit sichtbare Fakten. Ein Ereignis darf keinen synchronen Pflichtschritt ersetzen, wenn sonst ein ungültiger Gesamtzustand entstünde.
- Plugins verwenden `plugin_sdk`, APIs und abonnierte Ereignisse mit expliziten Rechten. Sie ändern keine Core-Tabellen und erhalten keine stillen Administratorrechte.

## Erster Slice und spätere Erweiterung

Der erste Slice benötigt nur `organization`, `people`, `workforce`, `tasks` und `audit` sowie minimale Plattformdienste. Manager-Dashboard, Skills, Abwesenheiten, Optimierung, Training und HACCP sind eigene spätere Änderungen. Beim Hinzufügen eines Moduls müssen Domainmodell, Anwendungsfälle, Berechtigungen, Ereignisse, Auditbedarf und Tests vor dem Code feststehen. [Workforce Orchestration](workforce-orchestration.md) erläutert die Vorschlagslogik; [Guided Work](guided-work.md) die Ausführung.

P0 setzt Authentifizierung und standortbezogene Autorisierung als interne Serverkomponenten um; eigene Pakete sind dafür noch nicht erforderlich. Die konkrete technische Grenze zwischen `people` und einem künftig stärker getrennten HR-Modul ist erst nach Datenschutz- und Berechtigungsmodell verbindlich zu ziehen.

P1b.2 implementiert unter `apps/server/lib/src/tasks/` ausschließlich Vorlagen und Revisionen. Der Application Service verwendet den Organization-Port für eingerichtete Standorte und die bestehende lokale Transaktion für Fachänderung und Audit. Vorlagen-Repository und Tabellen bleiben privat. Der gemeinsame Inhaltsvertrag definiert Schema und Validierung; Veröffentlichung und Konkurrenzregeln bleiben im Tasks-Modul. Ohne Folgeverbraucher entstehen keine neuen Domain Events. [Konkreter Vertrag](../development/phase-1b-templates.md).

P1b.3 ergänzt Workforce unter `apps/server/lib/src/workforce/` und Instanzen im bestehenden Tasks-Modul. `ShiftApplication` koordiniert öffentliche Ports mit derselben Transaktion; Employee Home kombiniert autorisierte Queries ohne eigene Speicherung. Es entsteht noch kein `shift.published.v1`-Outbox-Eintrag: Der oben beschriebene Zustellweg gilt erst bei konkretem Folgeverbraucher, gemäß Event-System. [P1b.3-Vertrag](../development/phase-1b-shifts.md).

P1b.4 ergänzt den Tasks-Port `TaskExecutionService`. `ShiftApplication` prüft eigene Mitarbeiter-/Standortzuordnung und reicht den veröffentlichten Schichtkontext an Tasks weiter. Tasks entscheidet Schrittfolge und Abschluss; Workforce schreibt keine Ausführungsdaten. Die laufenden Eigenaufgaben werden paginiert über den Tasks-Port gelesen. Kein neues Modul und kein Ereignisverbraucher.

P1b.5 erweitert denselben Tasks-Port um Blockierung, Klärung und Historie. Der Application-Koordinator prüft administrative Rechte, lokalen Standort und aktuelle People-Zuordnung; Tasks erhält diesen Check für neue Freigaben nach dem Replay-Abgleich. Kein neues Modul und kein Zugriff auf fremde Tabellen.

P1b.6 ergänzt Stornierung im bestehenden Tasks-Port. ShiftApplication prüft Adminrecht und lokalen Scope; aktive People-Zuordnung ist nur für Freigaben erforderlich. Workforce-Daten bleiben unverändert.

P1b.8 ergänzt die Stornierung veröffentlichter Schichten vor Ausführungsbeginn. `ShiftApplication` prüft Recht und Scope, lässt Tasks zuerst alle noch offenen Instanzen atomar stornieren (Tasks schreibt Zustand und Audit) und storniert danach die Schicht (Workforce schreibt Zustand und Audit) in derselben autorisierten Transaktion. Sind Instanzen bereits begonnen, blockiert, abgeschlossen oder storniert, lehnt der Tasks-Port den gesamten Vorgang mit 422 ab, ohne etwas zu schreiben. Kein neues Modul, kein Ereignis, keine fremden Tabellenzugriffe.

P4.1 ergänzt `apps/server/lib/src/inventory/` als logisches Modul für einen unternehmensweiten Artikel-/Produktstamm. Das Modul besitzt `articles` (keine Standortspalte), prüft Firmenzugehörigkeit ausschließlich über den revalidierten Principal und schreibt Änderung plus Audit in derselben autorisierten Transaktion. Bestand, Lieferanten, Bestellungen, Wareneingang, Chargen/MHD und Preise bleiben ausdrücklich außerhalb dieses Slice; spätere Kindtabellen binden über `(article_id, company_id)` an den vorhandenen Anker. Kein Ereignis, keine Plugin-Rechte. [P4.1-Vertrag](../development/phase-4-1-article-master.md).

P4.2 ergänzt im selben Modul `article_location_assortment` als standortbezogene Freigabe („welcher Unternehmensartikel wird an welchem Standort geführt"). Artikelidentität und -eigentümerschaft bleiben unverändert; die Standortvalidierung nutzt den bestehenden Organization-Port `requireConfiguredLocation`, Änderung und Audit teilen dieselbe autorisierte Transaktion. Sortimentsfreigabe (`is_active`) und globaler Artikelstatus (`articles.is_active`) sind unabhängig; wirksame Verfügbarkeit ist die Konjunktion beider Zustände, die nicht gespeichert wird. Spätere Bestands-/Einkaufssätze referenzieren `(article_id, location_id)` direkt und nicht die Sortiments-UUID. Kein Ereignis, keine Plugin-Rechte. [P4.2-Vertrag](../development/phase-4-2-location-assortment.md).

P4.3 ergänzt `apps/server/lib/src/stock/` als eigenes logisches Modul für den manuellen Bestand. `stock` besitzt ausschließlich `stock_levels` (transaktional gepflegte Projektion) und `stock_movements` (unveränderliches, autoritatives Ledger); Inventory behält Article und Sortiment. Inventory veröffentlicht dafür die lesende Sicht `inventory_article_location_projection` sowie den Dart-Port `InventoryArticlePort`; Stock joint nur die freigegebene Sicht und niemals Inventory-Basistabellen. Die Suche ist eine vollständige, keyset-paginierte Stock-Level-Abfrage über die Sicht (kein vorab gekürzter Artikelkandidatensatz). `stock_unit` friert die Artikeleinheit beim Anlegen ein; Menge, Delta und Saldo sind exakte Tausendstel als kanonische Dezimalstrings, manuelle Ziele sind nicht negativ. Öffnen erzeugt Ebene v1 mit genau einer Öffnungsbewegung; eine echte Korrektur speichert `delta = Ziel − aktuell` plus Saldo und Version, auditiert ohne Mengenwerte und ist über die clientgenerierte `movementId` exakt wiederholbar (409 `operation_conflict` bei abweichender Wiederverwendung). Bestehender Bestand bleibt nach Artikel- oder Sortimentsdeaktivierung les- und korrigierbar. Kein Ereignis, keine Plugin-Rechte, keine Bewertung, kein Wareneingang, keine Inventur, keine Umrechnung. [P4.3-Vertrag](../development/phase-4-3-manual-stock.md), [ADR 0017](../adr/0017-manual-stock-foundation.md).
