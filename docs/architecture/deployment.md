# Bereitstellung und Betrieb

Implementation boundary: one local Dart server, PostgreSQL, Flutter Web, optional Caddy TLS and database-only encrypted backup/isolated restore tooling. Attachment storage, enterprise connections, comprehensive operating dashboards and automatic replacement-server activation below are planned. See [actual status](../roadmap/status.md) and [handover commands](../HANDOVER.md#how-to-run-storeos).

## Topologie

Jeder Standort betreibt zunächst einen Standortserver mit Dart-Backend, PostgreSQL und einem kontrollierten Speicher für Anhänge. Flutter-Clients verbinden sich über einen lokalen Reverse Proxy mit TLS. Der Server hat eine dauerhafte technische `nodeId`; Company und Location besitzen davon unabhängige fachliche IDs. Die Zuordnung des aktiven Schreibers kann kontrolliert wechseln, ohne Datensätze umzunummerieren. Eine Installation ohne Unternehmensserver ist ein unterstützter Betriebsmodus. Optional verbindet sich ein zentraler Unternehmensserver über einen verschlüsselten, authentifizierten Sync-Kanal mit mehreren Standorten; er muss für lokale Kernabläufe nicht erreichbar sein. Der zentrale Server ist keine öffentliche Verwaltungs-API.

`infra/docker/` beschreibt die P0-Referenzinstallation mit getrennten Runtime- und Migrationsrollen. `infra/reverse_proxy/` enthält den optionalen lokalen TLS-Proxy, `infra/backup/` verschlüsselte PostgreSQL-Sicherung und isolierte Restoreprobe. Die [Startanleitung](../../README.md) und [Prüfnachweise](../development/phase-0-verification.md) grenzen den aktuellen Stand ab. Eine Container-Installation vereinfacht Updates, ersetzt aber weder Host-Härtung noch überwachte Datenträger. Mindesthardware und unterstützte Betriebssysteme werden erst nach Lastmessungen für typische Standortgrößen festgelegt.

## Betriebsvertrag

- Konfiguration und Secrets bleiben getrennt von Images und Quellcode. Bei Neustart werden Daten, Anhänge, Plugin-Konfiguration und Schlüssel aus dauerhaftem Speicher geladen.
- PostgreSQL, Anhänge, Konfiguration und zur Wiederherstellung nötige Plugin-Versionen werden konsistent gesichert. Backups erhalten verschlüsselte Kopien außerhalb des primären Datenträgers. Restore wird regelmäßig in einer isolierten Umgebung getestet; ein bloß erfolgreiches Backup-Job-Log ist kein Wiederherstellungsnachweis.
- Die nötigen Entschlüsselungs- und Datenschlüssel besitzen einen getrennten, geschützten Wiederherstellungsweg. Ein Schlüssel darf nicht ausschließlich im Backup liegen, das er erst öffnen müsste. Der Restoretest verwendet diesen Weg nach simuliertem Verlust des ursprünglichen Hosts; er benötigt kein Herstellerkonto.
- Datenbankschema und API-/Event-Verträge werden versioniert. Updates prüfen Kompatibilität mit Clients und optionaler Zentrale, führen Migrationen kontrolliert aus und sichern vorher einen Restore-Punkt. Ein automatisches Downgrade nach einer Datenmigration wird nicht versprochen. Der abgenommene Einzelstandort-Ablauf (Quiesce, verschlüsselter Restore-Punkt vor der Migration, Forward-Only-Migration, isolierte Wiederherstellung ohne Aktivierung) ist mit echten
0010→0014-Daten in der [Update-/Recovery-Abnahme](../development/phase-2-update-recovery-acceptance.md) belegt; ein automatisiertes Upgrade-Werkzeug und Ersatzserver-Aktivierung bleiben außerhalb dieses Umfangs.
- Lokale Health-Ansichten zeigen Datenbank, Speicher, Jobs, Outbox, Backups, Plugins und Sync-Rückstand. Strukturierte Logs und Metriken verbleiben standardmäßig lokal; externe Telemetrie ist freiwillig.
- Administrationszugänge sind auf berechtigte Netze und Personen begrenzt. Fernwartung benötigt einen ausdrücklich eingerichteten sicheren Zugang; das LAN wird nicht als vertrauenswürdig vorausgesetzt.

## Daten- und Vertragsmigration

Datenbankschema, API-/Event-Verträge und die Semantik gespeicherter Guided-Work-Schritte sind verschiedene Versionen. Vor jedem Release wird festgelegt, welche Client-, Plugin- und Gegenstellenversionen sowie ausstehenden Offline-Kommandos unterstützt werden. Inkompatible Nachrichten werden mit erkennbarem Grund zurückgehalten; sie werden nicht durch Weglassen unbekannter Pflichtdaten passend gemacht. Eine inkompatible Zentrale darf einen ansonsten gültigen lokalen Standortbetrieb nicht allein wegen des Versionsunterschieds stoppen.

Schemaänderungen erweitern zunächst lesbare/schreibbare Formen, migrieren vorhandene Daten nachvollziehbar und entfernen alte Formen erst nach Ablauf des unterstützten Kompatibilitäts- und Offlinefensters. IDs und historische Referenzen bleiben erhalten. Tests prüfen neben einer leeren Installation auch das Upgrade eines vorhandenen Datenbestands einschließlich aktiver Aufgaben, alter Snapshots und noch ausstehender Vorgänge. Der erste Slice benötigt dafür keine allgemeine Migrationsengine; jede tatsächliche Schemaänderung erhält einen gezielten Migrationsschritt.

## Ausfall- und Ausbaugrenzen

Ein WAN-Ausfall bei funktionsfähigem Standortserver soll den Standortbetrieb nicht unterbrechen. Ein Ausfall des lokalen Servers, der Stromversorgung oder des lokalen Netzes erfordert dagegen Wiederherstellung oder einen dokumentierten manuellen Notbetrieb. Gleichzeitiger Datenverlust und WAN-Ausfall sind eine zusätzliche Wiederherstellungssituation; die Standortautonomie verspricht dafür keinen sofortigen, lückenlosen Wiederanlauf. Kritische Prozesse dürfen nur dann als offline unterstützt gelten, wenn die zugehörigen Nachweise und Konfliktregeln geprüft wurden. Verfügbarkeits- und Wiederanlaufziele werden mit Pilotbetrieben anhand von Datenverlust- und Ausfalltoleranz festgelegt.

Phase 0 liefert eine installierbare Einzelstandort-Referenzumgebung mit Migrationen, Logs, Backup und geprobtem Restore. Der erste fachliche Slice läuft darauf. Mehrstandortbetrieb, unterbrechungsfreie Upgrades und Hochverfügbarkeit sind spätere Vorhaben, die gesonderte Betriebs- und Synchronisationstests brauchen.

## Restore bei angeschlossenen Geräten und Zentrale

Ein älteres Backup kann hinter bereits bestätigten Geräteaktionen oder zentralen Projektionen liegen. Vor Wiederaufnahme betroffener Schreibvorgänge und des Sync-Betriebs müssen Restorepunkt, lokale Outbox und Deduplizierungsdaten sowie bekannte Versionen und Quittungen der Gegenstellen abgeglichen werden. Unerreichbare Gegenstellen bleiben als ungeklärt sichtbar; in davon betroffenen Datenbereichen kann auch lokales Schreiben bis zur Klärung gesperrt bleiben. Bereits bestätigte Vorgänge dürfen weder still verschwinden noch durch blindes Queue-Replay erneut ausgeführt werden. Die Zentrale besitzt möglicherweise nur Teilprojektionen und kann verlorene Originaldaten deshalb nicht grundsätzlich rekonstruieren. Nicht rekonstruierbare Lücken werden als Datenverlust ausgewiesen und nach dem festgelegten Wiederherstellungsziel behandelt.

Die bisherige Serverinstanz wird vor Aktivierung ihres Ersatzes zuverlässig vom Schreiben ausgeschlossen. Eine Testwiederherstellung erhält keine produktiven Sync- oder Plugin-Verbindungen. Wiederanlauf nach Restore, verlorene Quittung und Wiederverbindung eines alten Geräts sind eigene Abnahmefälle der späteren Sync-Freigabe.

Vor produktiver Wiederöffnung werden außerdem neuere Kontosperren, entzogene Rollen/Account-Employee-Verknüpfungen und Löschentscheidungen wieder angewendet. Alte von StoreOS ausgestellte Session- und Plugin-Zugänge werden ungültig gemacht und erst nach Prüfung neu ausgestellt; bloße Neuanmeldung mit einem zurückgerollten Accountstatus genügt nicht. Ist ein erforderlicher Sperr- oder Löschstand nicht rekonstruierbar, bleibt der betroffene Zugriff eingeschränkt. Wiederherstellbarkeit dieser Entscheidungen wird zusammen mit dem Backupplan getestet, damit ein Restore weder widerrufene Zugriffe noch gelöschte Daten still reaktiviert.

## Wachstum ohne vorzeitige Verteilung

Geplante maximale Trennungsdauer und Datenrate bestimmen den Speicherbedarf für Anhänge, Audit und nicht zugestellte Events. Warnschwellen müssen vor Speichererschöpfung eine Betreibermaßnahme ermöglichen. Nicht quittierte, notwendige Vorgänge werden nicht still verworfen, um Platz zu schaffen; die Offlinezusage gilt innerhalb dieses bemessenen Betriebsfensters.

Zunächst genügen eine lokale Datenbank und wenige Worker. Vor zusätzlicher Parallelität werden konkurrierende Jobverarbeitung und Idempotenz geprüft. Skalierungsentscheidungen stützen sich auf gemessene Antwortzeiten, Transaktionskonflikte, Datenvolumen und Rückstau: begrenzte Abfragen, passende Indizes und entkoppelte aufwendige Reports kommen vor einer Aufteilung in Microservices. Eigene Projektionen oder Dienste werden erst bei belegtem Bedarf eingeführt; fachliche Konsistenz und Schreibzuständigkeit bleiben dabei erhalten.
