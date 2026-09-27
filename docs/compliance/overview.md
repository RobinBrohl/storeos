# Compliance: Geltungsbereich und Risikokarte

Diese Übersicht ist eine Architektur- und Priorisierungshilfe, keine Rechtsberatung oder Konformitätserklärung. Ausgangsannahme ist ein Standortbetrieb in Deutschland mit EU-Rechtsrahmen, wie ihn die Produktvision anhand von Kassel, TSE, HACCP und E-Rechnung beschreibt. Vor Einsatz in anderen Ländern, Branchen oder Betriebsformen ist eine eigene Prüfung nötig. Der jeweilige Betreiber verantwortet seine konkreten Prozesse; StoreOS muss dafür überprüfbare Funktionen und Nachweise bereitstellen.

## Vor dem ersten fachlichen Durchstich klären

| Thema | Warum bereits relevant | Entwurfsfolge |
| --- | --- | --- |
| Beschäftigtendaten und Datenschutz | Employee, Shift, Aufgabenstatus, Gerätekennungen und Auditdaten lassen Rückschlüsse auf Personen und Verhalten zu. Die [DSGVO](https://eur-lex.europa.eu/eli/reg/2016/679/oj/deu) verlangt unter anderem Zweckbindung, Datenminimierung, Datenschutz durch Technikgestaltung und angemessene Sicherheit. | Datenfelder und Zwecke je Anwendungsfall erfassen; Rollen und Standortrechte serverseitig prüfen; HR-Daten gesondert schützen; Aufbewahrung und Löschung je Kategorie festlegen. Krankheitsdetails gehören nicht in allgemeine Schichtnotizen. |
| Mitarbeiterüberwachung und Mitbestimmung | Aufgabenzeiten und Dashboards können zur Leistungsbeobachtung verwendet werden. In deutschen Betrieben kann [§ 87 Abs. 1 Nr. 6 BetrVG](https://www.gesetze-im-internet.de/betrvg/__87.html) bei entsprechenden technischen Einrichtungen Mitbestimmung auslösen. | Keine automatische Sanktion oder Rangliste; nur erforderliche Kennzahlen; transparente Zwecke, Rollen und Zugriffe; Einführung mit Betreiber und gegebenenfalls Arbeitnehmervertretung abstimmen. |
| Arbeitszeit und Schichtplanung | Shift ist Teil des ersten Durchstichs; spätere Zeiterfassung und Korrekturen berühren arbeitsrechtliche Vorgaben. Das [Arbeitszeitgesetz](https://www.gesetze-im-internet.de/arbzg/) enthält Regeln zu Arbeitszeit, Ruhezeiten und Nachweisen. | Shift zunächst als Planung von tatsächlicher Zeit trennen; Zeiterfassung und Regelprüfungen nicht durch einen Kalenderbildschirm vorwegnehmen; Korrekturen auditieren. |
| Audit, Sicherheit und Betriebsfähigkeit | Ein Abschluss muss nachvollziehbar und nach Ausfall wiederherstellbar sein, ohne unnötige personenbezogene Vollkopien zu sammeln. | Auditmatrix, Berechtigungstest, Backup/Restore und Konfliktfälle als Abnahmekriterien definieren; siehe [ADR 0009](../adr/0009-audit-trail.md) und [ADR 0010](../adr/0010-offline-und-sync-strategie.md). |

## Vor Aktivierung späterer Fachmodule gesondert prüfen

| Bereich | Regulatorische Sensibilität | Einführungsgrenze |
| --- | --- | --- |
| HACCP, Temperatur, Reinigung | [Art. 5 Verordnung (EG) 852/2004](https://eur-lex.europa.eu/legal-content/DE/TXT/?uri=CELEX%3A32004R0852) betrifft Verfahren auf Basis der HACCP-Grundsätze. Grenzwerte, Korrekturmaßnahmen und Verantwortlichkeiten sind betriebs- und produktabhängig. | Erst nach fachlicher Freigabe von Kontrollplänen, Messgeräten, Abweichungswegen, Nachweisen und Restoreverhalten als Compliance-Funktion anbieten. Ein Guided-Work-Beispiel ist noch kein validiertes HACCP-Verfahren. |
| Chargen und Rückruf | [Art. 18 Verordnung (EG) 178/2002](https://eur-lex.europa.eu/legal-content/DE/TXT/?uri=CELEX%3A32002R0178) behandelt Rückverfolgbarkeit in der Lebensmittelkette. | Herkunfts- und Weitergabebeziehungen sowie Rückrufproben vor produktivem Einsatz nachweisen. |
| Zutaten, Allergene und Etiketten | Die [Verordnung (EU) 1169/2011](https://eur-lex.europa.eu/legal-content/DE/TXT/?uri=CELEX%3A32011R1169) regelt Verbraucherinformationen zu Lebensmitteln. Falsche Daten können direkt Kundinnen und Kunden betreffen. | Kein autonomes Erzeugen oder Veröffentlichen von Allergenangaben; Rezeptversionen, Freigabe und Ausgabekanal prüfen. |
| POS, Kasse und Bargeld | Für elektronische Kassensysteme sind [§ 146a AO](https://www.gesetze-im-internet.de/ao_1977/__146a.html) und die [KassenSichV](https://www.gesetze-im-internet.de/kassensichv/) relevant. Ein generischer Adapter allein belegt keine Erfüllung. | POS erst nach TSE-/Schnittstellenprüfung, Beleg- und Exporttests sowie Prüfung des konkreten Einsatzszenarios freigeben. |
| Buchhaltung und E-Rechnung | Aufzeichnung, Aufbewahrung und Datenzugriff sind Gegenstand der [GoBD im AO-Handbuch des BMF](https://ao.bundesfinanzministerium.de/ao/2026/Anhaenge/BMF-Schreiben-und-gleichlautende-Laendererlasse/Anhang-33/inhalt.html). Das [BMF erläutert die E-Rechnung](https://www.bundesfinanzministerium.de/Content/DE/FAQ/e-rechnung.html) samt Übergangsregeln. | Fachliche Prüfung der dann geltenden Fassungen, Formate, Validierung, Originalaufbewahrung, Korrektur, Export und Verfahrensdokumentation vor Aktivierung. |
| KI und automatische Personalentscheidungen | Die Vision begrenzt KI bewusst auf Assistenz mit Quellen und menschlicher Freigabe. Beim Einsatz personenbezogener Daten sind Datenschutz und arbeitsrechtlicher Kontext gesondert zu bewerten. | KI erst nach Rechteprüfung pro Anfrage, Quellenbindung, Protokollierung und Freigaberegeln; keine autonomen Sanktionen oder endgültigen Dienstplanänderungen. |

## Querschnittliche Prüfungen

- **Rechts- und Regelversionen:** CompliancePacks können landes- und branchenbezogene Regeln versionieren. Sie ersetzen keine fachliche Freigabe. Jede Regel braucht Quelle, Geltungsbereich, Stand, verantwortliche Person und Migrationsweg.
- **Datenhoheit:** Export und Löschung müssen mit Aufbewahrungspflichten und Auditbedarf pro Datenklasse vereinbart werden. „Alle Daten unbegrenzt behalten“ und „alles jederzeit löschen“ können nicht zugleich gelten.
- **Offlinebetrieb:** Ein lokal gespeicherter Messwert oder Aufgabenabschluss ist noch kein bestätigter Servernachweis. Die UI muss diesen Zustand kenntlich machen; Konflikte und Zeitabweichungen sind zu prüfen.
- **Plugins:** Externe Erweiterungen dürfen Compliancevorgaben nicht umgehen. Für sensible Schreibrechte sind Freigabe, Herkunft, Isolation, Test und Widerruf nötig.
- **Inspektionsmodus:** Darf nur tatsächlich vorhandene und freigegebene Nachweise zeigen; fehlende Daten oder Synchronisationslücken müssen sichtbar bleiben.

## Offene Fragen für Betreiber und Fachprüfung

1. Welche Länder, Branchen und Unternehmenstypen sollen die ersten produktiven Installationen abdecken?
2. Welche Datenkategorien verarbeitet der erste Durchstich genau, und wer ist für welche Zwecke zugriffsberechtigt?
3. Gibt es einen Betriebsrat oder betriebliche Vereinbarungen zu Schicht-, Aufgaben- und Leistungsdaten?
4. Welche Aufbewahrungs- und Löschfristen gelten je Datentyp im konkreten Einsatz?
5. Welche späteren Funktionen sollen als verbindliche Nachweise dienen, welche nur als Arbeitshilfe?
6. Wer darf HACCP-Grenzen, Allergenangaben, Kassenkonfiguration und CompliancePack-Versionen fachlich freigeben?

**Reihenfolge:** Zuerst Datenschutz, Rechte, Audit und Ausfallverhalten des Workforce-Durchstichs prüfen. Lebensmittel-, Kassen- und Finanzfunktionen erhalten vor ihrer jeweiligen Implementierung eigene fachliche und rechtliche Abnahme; sie sind kein impliziter Bestandteil des ersten Durchstichs.
