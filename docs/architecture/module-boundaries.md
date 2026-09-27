# Modulgrenzen und Monorepo

Status: geplanter Zuschnitt. Verzeichnisse können zunächst nur dokumentiert sein. Fachmodule werden erst mit ihrem jeweiligen Vertical Slice implementiert.

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

Offen bleibt, ob Authentifizierung und Autorisierung später eigene Pakete oder interne Serverkomponenten werden. Ebenso ist die konkrete technische Grenze zwischen `people` und einem künftig stärker getrennten HR-Modul erst nach Datenschutz- und Berechtigungsmodell verbindlich zu ziehen.
