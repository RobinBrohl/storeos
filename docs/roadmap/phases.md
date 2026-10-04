# Entwicklungsfahrplan

For actual implementation and verification, use [status](status.md) and [HANDOVER](../HANDOVER.md). The phases below describe intended direction and acceptance gates, not a completion checklist.

Status: Reihenfolge und Abnahmekriterien, keine Zeit- oder Lieferzusage. Die Produktvision beschreibt viele mögliche Domänen; jedes Feld wird erst nach Domainmodell, Use Cases, Berechtigungen, Events, Auditbedarf, Tests und gegebenenfalls Compliance-Prüfung begonnen. Eine Phase kann in kleine Releases zerfallen. Änderungen der Reihenfolge brauchen eine dokumentierte Begründung und dürfen die Abnahme-Gates nicht umgehen.

## D0 – Dokumentation und Repository-Grundlage

Vision, Prinzipien, Architektur, ADRs, Risiko- und Compliance-Überblick, Monorepo-Skelett und dieser Fahrplan. **Abnahme:** Alle benannten Dokumente sind im Repository, Entscheidungen und offene Punkte sind auffindbar, der erste fachliche Slice ist definiert. In D0 entstehen keine Anwendungen oder Fachmodule.

## P0 – Dünne technische Grundlage

Dart-Serverstart, PostgreSQL-Migrationen, Flutter-App-Grundgerüst, lokale Konfiguration und Secret-Verwaltung, authentifizierte API mit standortbezogener Autorisierung, strukturierte lokale Logs, CI und Testwerkzeuge. Installation auf einem Standortserver, lokales TLS, Backup und nachgewiesener Restore werden von Anfang an mitgedacht. Gemeinsame API-Verträge und ein kleines Design-System entstehen nur für den ersten Use Case. **Abnahme:** Eine frische selbst gehostete Installation startet reproduzierbar, migriert die Datenbank, authentifiziert einen Benutzer und lässt sich aus einem Backup wiederherstellen; keine externe Cloud ist nötig. Eine allgemeine Plugin-Runtime, Unternehmensserver-Sync und umfangreiche Admin-Oberflächen sind hier nicht nötig.

Die implementierte Einzelstandort-Grundlage und ihre Grenzen sind in [Phase 0](../development/phase-0.md) dokumentiert. Der aktuelle Clientdurchstich verwendet Flutter Web; native Runner benötigen eine gesonderte Geräteabnahme. [Prüfnachweise](../development/phase-0-verification.md) halten den getesteten Stand fest. Fachmodule beginnen erst mit P1b.

## P1 – Plattformverwaltung

Die ausdrückliche Freigabe vom 2026-09-27 zieht Company, Location, User/Authentication, feste Rollen, Audit Trail, lokalen Event Bus, Plugin-Manifest und eine minimale externe Plugin-API vor. Begründung: [ADR 0012](../adr/0012-phase-1-plattform-und-plugin-api.md). [Umfang, Verträge und Abnahme](../development/phase-1.md) beschreiben die Implementierung. Workforce, Tasks und alle weiteren Fachmodule sind ausgenommen.

**Abnahme:** Bestehende P0-Daten werden ohne neue Identitäten migriert. Ein Administrator richtet Organisation und Benutzer ein; serverseitige Rechte, Versionskonflikte, letzter Administrator, Sitzungswiderruf und atomarer Audit werden mit echter Datenbank geprüft. Freigegebene externe API-Clients erhalten ausschließlich die genehmigten Organisationsdaten/Events; Deaktivierung widerruft Tokens und ausstehende Zustellungen. Formatter, Analyzer, Tests und Smoke-Test bestehen. Keine Plugin-Codeausführung und keine Standortreplikation.

## P1b – Erster fachlicher Vertical Slice (teilweise implementiert)

Der freigegebene Teilslice [P1b.1 – Mitarbeiteridentität und Eigenansicht](../development/phase-1b-employee.md) implementiert Employee, eine feste Standortzuordnung, die explizite Account-Verknüpfung, administrative Verwaltung, das eigene Profil und Audit. Schichten und Aufgaben wurden in den folgenden, separat freigegebenen Teilslices ergänzt.

Der separat freigegebene Teilslice [P1b.2 – Arbeitsvorlagen](../development/phase-1b-templates.md) ergänzt standortgebundene Entwürfe, versionierte Freigaben, Historie und Audit. Er bildet die Vorlagenbasis für die ab P1b.3 erzeugten Instanzen. [Prüfnachweis](../development/phase-1b-templates-verification.md).

Der separat freigegebene [P1b.3-Slice](../development/phase-1b-shifts.md) ergänzt Einzelschichten, atomare Veröffentlichung mit Aufgaben-Snapshots und zunächst lesendes Employee Home. Guided Work und Completion folgen in P1b.4; Änderungen veröffentlichter Schichten bleiben offen. [Prüfnachweis](../development/phase-1b-shifts-verification.md).

Der freigegebene [P1b.4-Teilslice](../development/phase-1b-execution.md) ergänzt Start, geordnete Bestätigungsschritte, Wiederaufnahme und Abschluss eigener Aufgaben. Manuelle Hindernisse und ihr Umgang werden durch P1b.5/P1b.6 ergänzt; Zahlen-/Grenzwertschritte mit automatischer Blockierung werden durch P1b.7 ergänzt.

Der freigegebene [P1b.5-Teilslice](../development/phase-1b-blocking.md) ergänzt manuelles Blockieren eigener laufender Aufgaben und administrative Klärung mit Wiederaufnahme. Die alternative Stornierung blockierter Aufgaben ist in P1b.6 implementiert.

Der freigegebene [P1b.6-Teilslice](../development/phase-1b-cancellation.md) ergänzt ausschließlich die administrative Stornierung blockierter Aufgaben, inklusive Historie und lesbaren Stornierungslisten. [Abnahme](../development/phase-1b-cancellation-verification.md) und [Review](../development/phase-1b-cancellation-review-2026-09-27.md) dokumentieren die Prüfung. P1b.7 ergänzt Zahlen-/Grenzwertschritte; P1b ist weiterhin teilweise implementiert. Änderungen oder Stornierungen veröffentlichter Schichten sowie Offline-Schreiben sind dadurch nicht freigegeben oder implementiert.

Der freigegebene [P1b.7-Teilslice](../development/phase-1b-7-numeric-steps.md) ergänzt gemischte Vorlagen mit numerischen Schritten, feste inklusive Grenzen, unveränderliche Versuche und automatische Blockierung. Nach Wiederaufnahme muss erneut gemessen werden. Keine Overrides, Sensoren, weiteren Schrittarten oder Offline-Schreibfunktionen.

**Verbindliche Ende-zu-Ende-Reise:**

`Company → Location → Employee → Shift → TaskTemplate → TaskInstance → Employee Home → Guided Work → Completion → Audit Log`

Ein berechtigter Nutzer legt Company, Location und Employee an, gibt ein passendes versioniertes TaskTemplate frei und veröffentlicht anschließend die Shift. Derselbe lokale Use Case erzeugt die konfigurierten TaskInstances für den Mitarbeiter dieser Schicht atomar und idempotent gemäß [ADR 0011](../adr/0011-atomare-schichtveroeffentlichung.md). Der angemeldete Mitarbeiter sieht seine Schicht und die nächste Aufgabe, folgt den benötigten Schritten, gibt erforderliche Daten ein und schließt sie ab. Persistierter Status und Audit sind für berechtigte Führungskräfte sichtbar. Fehlerpfade umfassen fehlende Berechtigung, ungültige Eingabe, doppelte Generierung, geändertes Template und fachliche Abweichung. Eine Abweichung blockiert einen unzutreffenden Normalabschluss und ermöglicht nach dokumentierter Klärung eine berechtigte Wiederaufnahme oder begründete Stornierung; ein vollständiges HACCP-Modul ist nicht Teil dieses Slice. Änderungen und Stornierungen veröffentlichter Schichten werden erst nach definiertem und getestetem Aufgabenabgleich angeboten.

**Abnahme:** Automatisierte Ende-zu-Ende- und Rechteprüfungen belegen den gesamten Weg mit echter Datenbank. Ein Neustart erhält alle Zustände. Audit und fachliche Transaktion sind konsistent. Das Standortsystem funktioniert ohne Internet zur Zentrale. Eine kurzzeitig getrennte Handheld-Verbindung und spätere Synchronisation sind ein eigener Freigabeschritt in P2; P1 darf diese Fähigkeit nicht vortäuschen.

Besonders zu prüfen sind der gemeinsame Rollback von Schicht und Aufgaben bei Task-/Auditfehler, konkurrierende Veröffentlichungen/Abschlüsse, Absturz vor/nach Commit, verlorene Antwort und Wiederholung sowie der berechtigte Ausweg aus `blocked`. Ein Wiederholungsaufruf erzeugt weder einen zweiten Abschluss noch eine zweite TaskInstance. Ein Generierungs-Event-Handler und eine allgemeine Scheduling-Engine sind für P1 nicht erforderlich.

## P2 – Betriebsfestigkeit und explizite Offline-Grenzen

Update und Rollback, Restore-Übungen, Systemzustand, Geräteverwaltung und sichere lokale Sitzungen werden betrieblich abgesichert. Für klar benannte Handheld-Aktionen werden Cache, ausstehende Operationen, idempotente Übernahme, Konfliktanzeige und Verlust-/Widerrufsverhalten spezifiziert und getestet. Der optionale Unternehmensserver folgt erst nach festgelegter Daten-Ownership je Aggregat und Proben mit WAN-Ausfall, Wiederverbindung und konkurrierenden Änderungen. **Abnahme:** Ein Standort arbeitet während längerer Internettrennung weiter; zulässige Geräteaktionen werden nach Wiederverbindung korrekt bestätigt oder sichtbar abgewiesen; Restore und Update sind reproduzierbar. Nicht freigegebene kritische Aktionen bleiben onlinepflichtig.

Das unterstützte Betriebsfenster wird mit Trennungsdauer, Rechtegültigkeit, Datenrate und Speicherbedarf festgelegt. Die jeweilige Sync-Freigabe umfasst abgelaufene Rechte, zu alte Cursor/Queues und den Wiederanschluss nach Restore an Gegenstellen mit neuerem Stand. Ein zweiter aktiver Schreiber und stiller Verlust bestätigter Daten sind unzulässig.

Die Unternehmenssynchronisation ist ein separat freizugebender optionaler Ausbau. Sie ist keine Voraussetzung für weitere Einzelstandortfunktionen oder deren Release. Ihre Abnahme prüft zusätzlich globale Regeln über mehrere Standorte, Eigentümerwechsel sowie Versionsunterschiede zwischen Zentrale und Standort. Restoretests prüfen auch Schlüsselwiederherstellung und die erneute Anwendung von Sperr-/Löschentscheidungen.

## P3 – Workforce und Wissensabläufe erweitern

Skills, Qualifikationsgültigkeit, wiederkehrende Aufgaben, Abhängigkeiten, Zeitfenster, Schichtübergabe, Abwesenheiten im nötigen Umfang und Schulung durch Arbeit. Priorisierung startet regelbasiert und zeigt Gründe, Sperren und manuelle Eingriffe. **Abnahme:** Eine qualifizierte Person erhält nur ausführbare Aufgaben; ein dringendes Ereignis ändert die Reihenfolge nachvollziehbar, ohne laufende Arbeit oder Pausen still zu überschreiben. Gesundheits- und HR-Daten bleiben auf das Erforderliche beschränkt.

## P4 – Artikel, Einkauf und Bestand

Produktstamm, Einheiten, Lieferanten, Bestellungen, Wareneingang, Chargen/MHD, Bestands-Ledger und Inventur. Geldbeträge verwenden Decimal oder Minor Units mit Währung; Mengen und Umrechnungen besitzen definierte Einheiten. **Abnahme:** Der Warenfluss von Bestellung bis Bestandsbewegung ist durchgängig nachvollziehbar und doppelte Buchung verhindert; Bestandskorrekturen bleiben sichtbar.

Der committete Teilslice [P4.1 – Artikelstamm](../development/phase-4-1-article-master.md) ergänzt einen unternehmensweiten Artikel-/Produktstamm mit SKU, optionalem Barcode, Einheit, aktiv/inaktiv-Lebenszyklus, Audit und Flutter-Verwaltung. Der committete Teilslice [P4.2 – Standort-Sortiment](../development/phase-4-2-location-assortment.md) ergänzt eine standortbezogene Freigabe, welche Unternehmensartikel ein Standort führt; Sortiments- und Artikelstatus sind unabhängig, wirksam ist nur die Konjunktion. Der uncommittete Teilslice [P4.3 – Manueller Bestand](../development/phase-4-3-manual-stock.md) ergänzt ein eigenes `stock`-Modul mit einer Bestandsebene je Artikel und Standort, Öffnungs-/Korrekturbewegungen im unveränderlichen Ledger, exakten Tausendstelmengen, eingefrorener Einheit und der Flutter-Sektion **Bestand**. Wareneingang, Inventur, Bewertung, Lieferanten, Bestellungen und Chargen/MHD bleiben ausdrücklich offen; `unit` ist weiterhin eine Bezeichnung ohne Umrechnung. [ADR 0015](../adr/0015-company-wide-article-master.md), [ADR 0016](../adr/0016-article-location-assortment.md), [ADR 0017](../adr/0017-manual-stock-foundation.md).

## P5 – Lebensmittelsicherheit und Geräte

Kontrollpläne, Messungen, Abweichungen, Korrekturmaßnahmen, Reinigung, Rückruf-/Rückverfolgbarkeitsabläufe und Gerätewartung. Aufgaben und Kontrollen werden verknüpft, bleiben aber fachlich getrennte Records. **Abnahme:** Ein Grenzwertverstoß kann nicht als erfolgreiche Kontrolle verschwinden; Nachweis, Verantwortliche und Nachkontrolle sind belegbar. Land- und branchenspezifische Aussagen werden vor Pilotbetrieb geprüft.

## P6 – Produktion, Rezepte und Kennzeichnung

Versionierte Rezepturen, Chargenbezug, Produktionsauftrag, automatische Bestandsbewegungen, Kalkulation und Etiketten. **Abnahme:** Herkunft und Version jeder Zutat und Kennzeichnung sind nachvollziehbar; Allergene werden nur aus überprüften Daten abgeleitet und fachlich freigegeben.

## P7 – Erweiterte Personalplanung und Zeiterfassung

Arbeitszeit, Korrekturen und Freigaben, Verfügbarkeit, Schichttausch, Personalbedarfsprognose und erklärbare Einsatzvorschläge. **Abnahme:** Korrekturen und Entscheidungen sind prüfbar, lokale Regeln und Beteiligungsrechte sind vor Einsatz geklärt, Vorschläge ändern Pläne nicht ohne verantwortliche Person.

## P8 – Analyse und Prognose

Verlässliche KPIs, Drilldown, Export und einfache Prognose-Baselines. ML und Autodisposition folgen nur bei nachgewiesenem Mehrwert und expliziter Aktivierung. **Abnahme:** Jede Zahl besitzt Definition, Datenquelle, Gültigkeitsbereich und Aktualitätsstatus; Prognosen zeigen Fehler und Unsicherheit.

## P9 – POS und Bargeld

Kasse, Retouren, Bargeld, Fiskalisierungs- und Terminaladapter als gesondert gehärteter Bereich. **Abnahme:** Buchungen, Storno und Ausfallfälle sind testbar, externe Pflichtkomponenten und Jurisdiktion sind geklärt, Geld- und Rechteprüfungen bestehen. Kein POS-Release ohne passende regulatorische Prüfung.

## P10 – Gastronomie

Tische, Bestellungen, Küche/Kitchen Display, Reservierung und Take-away auf bereits belastbaren POS- und Produktverträgen. **Abnahme:** Eine Bestellung durchläuft Stationen und Abrechnung ohne doppelte oder verlorene Transaktionen.

## P11 – Dokumente und Finanzen

Strukturierte Geschäftsdokumente, Rechnungen, E-Rechnungsformate und Buchhaltung mit gesonderten Aufbewahrungs-, Export- und Korrekturregeln. **Abnahme:** Beleg und Buchung sind nachvollziehbar, Import und Export werden mit den für die Zielregion geltenden Vorgaben geprüft.

## P12 – Öffentliche Kanäle und optionale KI

Öffentliche Website, Vorbestellung, zusätzliche Integrationen und lokale KI als eigenständig abgesicherte Erweiterungen. **Abnahme:** Öffentliche Dienste exponieren keine internen Verwaltungs-APIs; KI antwortet nur aus freigegebenen Quellen im Berechtigungskontext und trifft keine fachlich kritischen Entscheidungen autonom.

## Übergreifende Release-Gates

Jeder Release benötigt dokumentierte Rechte, serverseitige Validierung, Migrationen, sinnvolle Tests, Fehlerbehandlung, Auditentscheidung, sichere Konfiguration, Export-/Backup-Auswirkung und verständliche Bedienung. Updates prüfen vorhandene Daten, laufende Guided-Work-Snapshots und unterstützte ältere Vertragsversionen; ein erfolgreicher Neuaufbau allein ist kein Migrationsnachweis. Zusätzliche regulatorische Gates stehen im [Compliance-Überblick](../compliance/overview.md). Die größten offenen Architekturfragen stehen in der [kritischen Prüfung](../risks-and-open-questions.md).

**Aktueller Umsetzungsumfang:** [P1b.1 – Mitarbeiteridentität](../development/phase-1b-employee.md), [P1b.2 – Arbeitsvorlagen](../development/phase-1b-templates.md), [P1b.3 – Schichten und Employee Home](../development/phase-1b-shifts.md), [P1b.4 – Ausführung](../development/phase-1b-execution.md), [P1b.5 – Blockierung](../development/phase-1b-blocking.md) und [P1b.6 – Stornierung blockierter Aufgaben](../development/phase-1b-cancellation.md). Hinzu kommen [P1b.7 – Numerische Schritte](../development/phase-1b-7-numeric-steps.md), der committete, remote CI-verifizierte [P4.1 – Artikelstamm](../development/phase-4-1-article-master.md), der committete [P4.2 – Standort-Sortiment](../development/phase-4-2-location-assortment.md) und der uncommittete [P4.3 – Manueller Bestand](../development/phase-4-3-manual-stock.md). Weitere Teile der Mitarbeiterreise und der Warenwirtschaft benötigen eine eigene Scope-Freigabe.
