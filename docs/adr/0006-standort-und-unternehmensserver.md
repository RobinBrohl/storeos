# ADR 0006: Standortserver mit optionalem Unternehmensserver

## Status

Beschlossen als Zieltopologie; zentrale Synchronisation wird stufenweise eingeführt.

## Kontext

Mehrere Filialen brauchen gemeinsame Stammdaten und Auswertung. Zugleich muss jede Filiale bei unterbrochener Internetverbindung ihre Arbeit fortsetzen können. Eine einzige globale „Single Source of Truth“ ist bei zeitweise getrennten Systemen ohne festgelegte Datenverantwortung widersprüchlich.

## Entscheidung

Jeder Standortserver ist für operative Standortdaten und lokale Vorgänge zuständig. Ein optionaler Unternehmensserver verwaltet unternehmensweite Daten und aggregiert freigegebene Informationen. Für jeden synchronisierten Datentyp werden Eigentümer, Schreibrechte, Verteilrichtung, Versionsregeln und Konfliktverfahren dokumentiert. Während einer Trennung arbeitet der Standort mit der letzten gültigen Kopie zentraler Vorgaben weiter und kennzeichnet deren Stand. Zentrale Änderungen werden erst nach erfolgreicher Übernahme vor Ort wirksam.

## Alternativen

- Zentralserver als Pflicht für jede Schreiboperation: verworfen wegen WAN-Abhängigkeit.
- Unbeschränktes Schreiben derselben Entität an allen Standorten: verworfen wegen unauflösbarer Fachkonflikte.
- Direkte Datenbankreplikation als Integrationsvertrag: verworfen wegen fehlender Fachsemantik und Berechtigungsgrenzen.

## Konsequenzen

- Es gibt mehrere klar begrenzte Quellen der Wahrheit statt einer physischen Gesamtdatenbank.
- Zentrale Dashboards können bei Trennung veraltete Werte anzeigen und müssen Stand und Vollständigkeit offenlegen.
- Verteilung von Rollen, Mitarbeitern, Preisen und Arbeitsanweisungen erfordert jeweils eigene Autoritätsregeln.

## Offene Prüfungen

- Eigentumsmatrix für Company, Location, Employee, Shift und Task festlegen.
- Soll ein Mitarbeiter standortübergreifend eine Identität besitzen, und wie funktionieren Rechte bei WAN-Ausfall?
