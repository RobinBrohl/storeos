# P1b.7: Numerische Guided-Work-Schritte

## Verbindlicher Umfang

Ein `number`-Schritt besitzt Anleitung, Einheit als Anzeigetext und feste inklusive
Unter-/Obergrenzen. Schema 2 ergänzt Schema 1; veröffentlichte Revisionen,
Instanz-Snapshots und alte Command-Receipts bleiben unverändert. Dezimalstrings
werden exakt als Tausendstel verarbeitet (maximal drei Nachkommastellen,
-999999.999 bis 999999.999), ohne Rundung oder Einheitenumrechnung.

`record-number` verlangt operationId, expectedVersion und value am aktuellen
eigenen Schritt. Ein gültiger Wert erzeugt einen unveränderlichen Versuch und
ein Schrittresultat; ein darstellbarer Wert außerhalb der Grenzen erzeugt einen
Versuch und eine Blockierung, aber kein Resultat. Resume verlangt einen neuen
Versuch; Cancel erhält sämtliche Nachweise. Ungültige Eingaben ändern nichts.
Versuch, Resultat/Blockierung, Version, Audit und Receipt werden atomar gespeichert.

Es gelten bestehende Rechte: templates.manage, instances.self.execute,
instances.self.read, instances.read, instances.resolve und instances.cancel
(jeweils Präfix `tasks.`). Rechte und Standort-/Mitarbeiterzuordnung werden auch
bei Wiederholung geprüft. Keine neuen Rollen, Pluginrechte oder Domain Events.
Audit: `tasks.step.number_recorded` plus `tasks.step.confirmed` beziehungsweise
`tasks.instance.blocked`, mit Referenzen und Bewertung, ohne Rohmesswert.

Flutter unterstützt gemischte Vorlagen, Komma oder Punkt als Dezimaltrenner ohne
Tausenderseparatoren, Ergebnisanzeige und paginierte Versuchshistorie (50).
Bestehende Konflikt-, Retry-, Logout- und Blockierungsabläufe bleiben erhalten.

## Abnahmekriterien und Tests

- Inklusive Grenzen, negative Werte, Präzision, Überlauf und ungültige Syntax;
  Schema 1/2, maximal 20 Schritte und 8 KiB.
- Falscher Schritt/Typ/Status, Rechte und Scope werden serverseitig abgewiesen.
- Bad → Block → Resume → Good → Complete; Cancel erhält Versuche.
- Gleicher normalisierter Command ist idempotent; geänderter Wert mit gleicher
  operationId ist ein Konflikt. Rennen und Schreibfehler rollen atomar zurück.
- Laufzeit-SQL kann numerische Schritte nicht ohne passenden Versuch bestätigen.
- Migration einer befüllten 0009-Datenbank erhält alte Inhalte und Receipts.
- Unit-, PostgreSQL-/HTTP-, Flutter- und Smoke-Tests, Neustart und Restore.

Keine weiteren Schrittarten, Regelengine, Overrides, Sensoren, HACCP-Zusagen,
Offline-Queue, Synchronisation oder Änderungen an Workforce/Retention/Company-Lock.

Status: Implementiert. Automatisierte Tests, API-Smoke, Neustart und Restore sind
erfolgreich. Ein eingecheckter Browser-Ende-zu-Ende-Test hat auch den Abschluss
über den echten Flutter-Client nachgewiesen. Der Test baut die App neu auf und
meldet sich erneut an; ein wörtlicher Seiten-Reload und der Remote-CI-Lauf
sind noch nicht nachgewiesen. Details stehen im
[Prüfnachweis](phase-1b-7-numeric-verification.md).
