# ADR 0009: Audit Trail für relevante Fachänderungen

## Status

Beschlossen als Querschnittsanforderung.

## Kontext

Änderungen an Aufgabenabschlüssen, Arbeitszeiten und später an Bestand, HACCP, Preisen oder Geld müssen nachvollziehbar sein. Ein technisches Log allein belegt weder fachlichen Kontext noch berechtigte Korrekturen. Auditdaten können selbst personenbezogene oder besonders sensible Informationen enthalten.

## Entscheidung

Relevante Schreiboperationen erzeugen in derselben Transaktion wie die Fachänderung einen Auditdatensatz mit Akteur oder Systemidentität, Zeitpunkt, Standort, Anwendungsfall, Entität, Änderungsart, Korrelations-ID und bei Bedarf begründetem Vorher-/Nachher-Bezug. Korrekturen erfolgen als neue nachvollziehbare Vorgänge. Ausfälle der Auditpersistenz lassen auditpflichtige Änderungen scheitern. Zugriff auf Auditdaten ist gesondert berechtigt und protokolliert; Inhalte und Aufbewahrung werden nach Datentyp begrenzt. Auditdaten werden nicht als pauschaler Beweis für gesetzliche Konformität bezeichnet.

## Alternativen

- Nur Anwendungslogs: verworfen, weil Rotation und freie Texte keine verlässliche Fachhistorie bieten.
- Vollständige Kopie aller Entitäten bei jeder Änderung: verworfen wegen Datenminimierung und Speicherlast.

## Konsequenzen

- Auditabfragen und Exporte brauchen Rechte, Zweckbindung und Schutz vor nachträglicher Manipulation.
- Automatische Folgeaktionen unterscheiden ausführende System-/Plugin-Identität und ursprünglichen Auslöser. Nötige Ablehnungsnachweise werden getrennt von einer zurückgerollten Fachtransaktion gespeichert; sie sind keine erfolgreichen Änderungsnachweise.
- Lösch- und Berichtigungsanforderungen müssen mit möglichen Aufbewahrungspflichten pro Datentyp bewertet werden.
- Die Integrität des Audit Trails hängt auch von Datenbank-, Schlüssel-, Backup- und Administratorrechten ab.

## Offene Prüfungen

- Auditmatrix für den ersten Durchstich: welche Felder und Aktionen, welche Aufbewahrungsdauer, wer darf lesen?
- Technische Manipulationserkennung und organisatorische Trennung administrativer Rollen prüfen.
