# ADR 0001: Modularer Monolith

## Status

Beschlossen für die Startarchitektur.

## Kontext

StoreOS verbindet viele Fachbereiche. Der erste fachliche Durchstich führt von Company und Location über Employee, Shift und Aufgaben bis zum Audit Log. Diese Schritte benötigen konsistente Berechtigungen und Transaktionen. Ein verteiltes System würde dafür früh Netzabhängigkeit, Betriebsaufwand und Fehlermodi einführen.

## Entscheidung

Der Standortserver startet als ein deploybares Dart-Backend mit klar getrennten Fachmodulen. Jedes Modul besitzt seine Anwendungsfälle, Domainregeln, Datenzugriffe und öffentlichen Verträge. Zugriffe zwischen Modulen laufen über dokumentierte Schnittstellen oder Domain-Events; fremde Tabellen und interne Klassen sind keine Integrationspunkte. HTTP-Routen und Flutter-Widgets enthalten keine Fachlogik. Die physische Trennung von Modulen darf später geändert werden, ohne ihre fachlichen Verträge neu zu erfinden.

## Alternativen

- Microservices je Fachbereich: verworfen wegen verteilter Transaktionen, Betriebslast und erschwerter Offlinefähigkeit.
- Ein ungegliederter Monolith: verworfen wegen enger Kopplung und unklarer Datenverantwortung.

## Konsequenzen

- Ein Prozess und eine lokale Datenbank erleichtern den ersten End-to-End-Prozess.
- Modulgrenzen müssen durch Abhängigkeitsregeln, Reviews und Vertragstests geschützt werden; Verzeichnisnamen allein genügen nicht.
- Skalierung einzelner Module ist zunächst an die Skalierung des gesamten Servers gebunden.

## Offene Prüfungen

- Welche Modulgrenzen benötigen eigene Datenbankschemas oder getrennte Repository-Schnittstellen?
- Ab welcher Last oder organisatorischen Grenze wäre eine spätere Prozessaufteilung gerechtfertigt?
