# Produktprinzipien

Diese Reihenfolge hilft bei Zielkonflikten. Eine spätere ADR darf technische Details festlegen, aber keine der Schutzlinien still aufheben.

1. **Sicherheit und fachliche Integrität vor Bequemlichkeit.** Kritische Werte, Geld, Zeiten und Nachweise werden validiert; Korrekturen bleiben nachvollziehbar. Ein Offline-Konflikt wird nicht still überschrieben.
2. **Mitarbeitende unterstützen.** Die App erklärt die nächste relevante Arbeit und macht Wissen zugänglich. Dauer und Klickzahlen allein begründen keine Sanktion, Bewertung oder automatische Personalentscheidung.
3. **Der Standort bleibt arbeitsfähig.** Kernprozesse funktionieren mit lokalem Server ohne Verbindung zum Unternehmensserver. Für Handhelds werden nur ausdrücklich freigegebene Offline-Aktionen zugelassen.
4. **Daten gehören dem Betreiber.** Betrieb, Backup, Restore, Export und Migration sind ohne Herstellerkonto möglich. Datenformate und Schnittstellen werden dokumentiert.
5. **Rechte gelten überall.** Der Server prüft jede Aktion im Kontext von Unternehmen, Standort, Rolle und Zweck. Sensible Beschäftigtendaten werden getrennt und sparsam verarbeitet; LAN und Plugins sind keine Vertrauensgrenzen.
6. **Eine fachliche Quelle je Datum.** Jedes Aggregat besitzt einen schreibenden Owner. Andere Module verwenden öffentliche Verträge oder Events. Eine verteilte Installation braucht explizite Synchronisationsregeln.
7. **Automatisierung bleibt erklärbar und steuerbar.** Prioritäten und Vorschläge zeigen Gründe; verantwortliche Personen können begründet eingreifen. KI ist optional und erhält nie mehr Rechte als der Nutzer.
8. **Eine Designsprache, passende Bedienformen.** Handhelds priorisieren Scan und einen Arbeitsschritt; Desktop unterstützt Planung und Tabellen. Einheitlichkeit bedeutet gemeinsame Begriffe, Zustände und Barrierefreiheit.
9. **Erweiterbarkeit unter Kontrolle.** Plugins nutzen versionierte APIs mit minimalen Rechten und werden isoliert betrieben. Ein Ausfall darf Kernabläufe nicht still verändern.
10. **Schrittweise, prüfbare Lieferung.** Jede Phase endet mit einem echten Ende-zu-Ende-Ablauf und Betriebsnachweisen. Breite Plattform-Abstraktionen werden erst gebaut, wenn konkrete Use Cases sie benötigen.
