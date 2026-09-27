# Produktvision

Status: Zielbild. Grundlage ist der vom Projektgründer bereitgestellte StoreOS-Master-Prompt. Diese Fassung fasst ihn für die langfristige Entwicklung zusammen; sie ist kein Versprechen, alle beschriebenen Domänen gleichzeitig bereitzustellen.

## Problem und Produktversprechen

Standortbetriebe verteilen Dienstpläne, Aufgaben, Anleitungen, Warenbewegungen, Kontrollen und Entscheidungen heute auf viele Systeme und Papier. Informationen werden mehrfach eingegeben, fehlen am Arbeitsort oder gehen beim Schichtwechsel verloren. StoreOS soll einen durchgehenden Arbeitskontext schaffen: Mitarbeitende sehen, **wann, wo, mit wem, was und wie** sie arbeiten; Führungskräfte sehen konkrete Abweichungen und können eingreifen. Das System soll Wissen aus Köpfen und Dateien in versionierte, ausführbare Arbeitsabläufe überführen.

Der erste sichtbare Nutzen entsteht im Alltag der Mitarbeitenden. Eine Person öffnet die App, sieht die veröffentlichte Schicht, startet eine passende Aufgabe, wird Schritt für Schritt geführt und dokumentiert ihren Abschluss. Die nächste Aufgabe wird anhand transparenter Regeln angeboten. Führungskräfte sehen den Fortschritt mit angemessenen Berechtigungen und Kontext, ohne automatisierte Leistungsbestrafung.

## Langfristiger Umfang

Die gemeinsame Plattform kann später Produktstamm, Einkauf, Bestand, Produktion, Lebensmittelsicherheit, Kasse, Finanzen, Reporting und weitere Standortprozesse tragen. Externe Pflichtsysteme und Hardware werden über begrenzte Schnittstellen eingebunden. Eine gemeinsame Datenbasis bedeutet **eindeutige fachliche Eigentümerschaft je Datensatz**; bei mehreren Standortservern ist sie keine einzelne physische Datenbank. Standorte arbeiten ohne Internet zum Unternehmensserver weiter. Ein zentraler Unternehmensserver ist optional.

StoreOS soll selbst betrieben und ohne verpflichtenden Cloudaccount, Abonnement, externe Telemetrie oder KI genutzt werden können. Kunden müssen ihre Daten in dokumentierten Formaten exportieren und wiederherstellen können. Die Oberfläche nutzt eine gemeinsame Designsprache, passt Bedienung und Informationsdichte aber an Handheld, Desktop und später POS an.

## Erste überprüfbare Produktreise

`Company → Location → Employee → Shift → TaskTemplate → TaskInstance → Employee Home → Guided Work → Completion → Audit Log`

Ein veröffentlichter Dienstplan erzeugt die passende konkrete Aufgabe genau einmal. Der Mitarbeiter sieht Schicht und nächsten Schritt, gibt erforderliche Werte ein und schließt die Aufgabe ab. Das System prüft Berechtigung und Eingaben serverseitig, speichert Ergebnis und Audit-Eintrag und zeigt der Führungskraft den fachlich nötigen Status. Eine Abweichung wird sichtbar und kann nicht durch einen normalen Abschluss verdeckt werden. Diese Reise wird **erst in einer späteren Entwicklungsphase** implementiert; die aktuelle Phase erstellt nur Dokumentation und Struktur.

## Bewusste Grenzen

Die Vision ist breiter als ein verantwortbarer erster Release. POS, TSE, Zahlungsabwicklung, Buchhaltung, E-Rechnung, HACCP-Prüfmodus, komplexe Optimierung, autonome Disposition, öffentliche Website und KI benötigen eigene Domänen-, Sicherheits- und Compliance-Freigaben. Eine frühe Demo darf diese Funktionen nicht durch hart kodierte Zahlen oder inaktive UI vortäuschen. Digitale Anleitung ersetzt keine vorgeschriebene Qualifikation, Einweisung oder menschliche Entscheidung.

Die messbaren Produktziele sind weniger Medienbrüche, verlässlichere Aufgabenerledigung und verständliche Entscheidungen. Auswertungen über Beschäftigte müssen auf einen rechtmäßigen, klaren betrieblichen Zweck begrenzt bleiben. [Produktprinzipien](product-principles.md), [Fahrplan](roadmap/phases.md) und [kritische Prüfung](risks-and-open-questions.md) konkretisieren diese Grenzen.
