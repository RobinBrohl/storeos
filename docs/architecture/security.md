# Sicherheitsarchitektur

Implementation boundary: local password authentication, in-memory client Bearer sessions, fixed roles, company/location/resource checks, revocation and audit exist. MFA, device management, central identity distribution and offline access expiry remain target controls. Read the [current status](../roadmap/status.md) and [P1 contract](../development/phase-1.md) before treating the target controls below as implemented.

## Schutzobjekte und Grundsatz

StoreOS verarbeitet Personal-, Betriebs- und später möglicherweise Zahlungs-, Gesundheits- und Lebensmittelsicherheitsdaten. Ein lokales Netz ist keine Vertrauensgrenze. Jeder Client, Standortserver, Unternehmensserver und Plugin-Aufruf benötigt eine authentifizierte Identität. Jede Schreib- und Leseoperation wird serverseitig autorisiert; die Oberfläche blendet unzulässige Aktionen nur zusätzlich aus.

Das Berechtigungsmodell kombiniert Rollen mit Company-, Location-, Department- und Ressourcengrenzen. Rollen sind keine pauschalen Datenfreigaben. Rechte für Personalstamm, Schicht, Zeit, Qualifikation, Abwesenheit/Krankheit, Entgelt und Personalakte bleiben getrennt. Auch Exporte, Suche, Reports, Benachrichtigungen, Event-Subscriptions und spätere KI-Abfragen wenden dieselben Sichtbarkeitsregeln an. Mitarbeitende sehen ihre eigenen Daten; Führungskräfte erhalten ausschließlich ihren fachlich begründeten Bereich. Besonders weitreichende Aktionen wie Rollenänderung, Datenexport und Plugin-Freigabe werden auditiert.

Fehlende Freigabe bedeutet verweigerten Zugriff. Vom Client, Plugin oder Event übermittelte Company-, Location- und Akteur-IDs verleihen keine Rechte. Der Application-Use-Case bindet sie an einen serverseitig geprüften Zugriffskontext und gibt diesen auch an interne Ports und Jobs weiter. Direkte Objektzugriffe, Anhänge, Fehlermeldungen und gespeicherte Wiederholungsergebnisse unterliegen demselben Scope. Die Plattformkomponente Identität/Berechtigungen besitzt und auditiert die Account-Employee-Verknüpfung; operative Module dürfen daraus keine zusätzlichen Rollen ableiten.

Für eine leere Installation ist die Erstanlage ausdrücklich geregelt: Ein lokal eingerichteter, installationsgebundener Setup-Akteur darf ausschließlich den ersten Administrator und die erste Company samt Rechtezuordnung anlegen. Der Zugang verwendet ein einmaliges lokal erzeugtes Secret und wird danach deaktiviert. Es gibt weder ein gemeinsames Standardpasswort noch eine öffentlich frei beanspruchbare Setup-Rolle; anschließend gelten normale Mandantenrechte. Damit erfordert die erste Company keine bereits bestehende Company-Berechtigung.

P0 führte das lokale Bootstrap-CLI mit separaten Datenbank-Owner-Rechten und einem persistierten Wiederholungsverbot ein. P1 übernimmt diese stabilen IDs in Company-/Location-Datensätze und vergibt ausschließlich an diesen ursprünglichen Account die Administratorrolle. Die authentifizierte Einrichtung benennt diese Organisation; sie ist kein öffentlich beanspruchbarer Setup-Zugang. Feste Rollen und ihre konkreten Grenzen stehen in [Phase 1](../development/phase-1.md). Ein User bleibt ein Login-Account ohne Personalakte.

## Technische Mindestkontrollen

- Passwörter werden mit einem aktuellen, langsam berechneten Passwort-Hash und individuellen Salts gespeichert. Sitzungen haben sichere Cookies beziehungsweise kurzlebige Tokens, Ablauf, Rotation und Widerruf; privilegierte Konten sollen Mehrfaktor-Authentifizierung erhalten.
- HTTPS/TLS gilt auch im LAN und für die Standort-Zentrale-Verbindung. Server- und Plugin-Secrets gehören in einen geschützten Secret Store; Backups und mobile Caches werden verschlüsselt.
- Eingaben werden serverseitig validiert. Datenbankzugriffe sind parametrisiert; Web-Oberflächen verhindern XSS und setzen passende Security Headers und CSRF-Schutz bei Cookie-Sitzungen. Datei-Uploads brauchen Typ-/Größenlimits, Quarantäne und Prüfung vor der Freigabe.
- Rate Limits, Session- und Geräteverwaltung, strukturierte Sicherheitsereignisse, regelmäßige Updates sowie getrennte Datenbank-/Dienstkonten reduzieren Missbrauch. Logs enthalten keine Passwörter, Tokens, unnötigen Personendaten oder vollständigen sensiblen Payloads.
- Restore und Sicherheitsvorfälle brauchen dokumentierte Verfahren. Backups müssen auch bei kompromittiertem Hauptserver erreichbar sein und regelmäßig wiederhergestellt werden.

## Standort- und Offlinegrenzen

Der Standortserver kann bei Internetausfall mit lokal gültigen, zuvor synchronisierten Rechten arbeiten. Ein Entzug am Unternehmensserver erreicht den Standort während der Trennung nicht sofort. Für privilegierte Rechte sind daher kurze Gültigkeit, lokale Sperrmöglichkeit und ein dokumentierter Notfallprozess nötig. Ein verlorenes Offline-Handheld kann erst bei erneuter Verbindung zuverlässig gesperrt werden; lokale Datenmenge, Cache-Lebensdauer und Offline-Berechtigungen werden begrenzt. Besonders sensible HR-Daten werden nicht standardmäßig auf Handhelds repliziert.

Standortautonomie setzt eine lokale Anmeldung und Sitzungserneuerung für ausdrücklich freigegebene Kernrechte voraus; ein nur zentral erreichbarer Token-Aussteller würde das WAN-Versprechen brechen. Für jede Rechteklasse werden Gültigkeitsdauer der lokalen Freigabe und Verhalten bei deren Ablauf festgelegt. Abgelaufene privilegierte Freigaben erlauben keine weitere privilegierte Aktion. Ein notwendiger lokaler Notfallzugang ist separat eingerichtet, eng begrenzt und auditiert; er entsteht nicht automatisch durch Netzausfall. Lokale Sperren haben Vorrang und werden durch einen älteren zentralen Stand nicht aufgehoben.

Cache und Queue sind pro Benutzer und Company getrennt. Vertrauliche Daten werden nur auf Plattformen offline freigegeben, auf denen Schlüsselablage, Benutzersperre und Cache-Lebensdauer geprüft sind. Für den Webclient wird insbesondere nicht dieselbe Speicher- und Verlustsicherheit wie für verwaltete Handhelds unterstellt; reine Verschlüsselung im Browser schützt nicht vor Code, der im angemeldeten Client auf die entschlüsselten Daten zugreifen kann.

Im ersten Slice müssen Authentifizierung, serverseitig geprüfte Scopes, Geräte-/Session-Widerruf, sichere Speicherung, Audit und die Trennung sensibler Mitarbeiterfelder funktionieren. Ein formales Bedrohungsmodell und externe Sicherheitsprüfung sind vor breitem produktivem Einsatz nötig. Die spätere Aufnahme von POS, Finanzen, TSE, Zahlungsdaten und KI erhöht die Schutzanforderungen; diese Module werden nicht durch die allgemeine Plattformfreigabe automatisch als sicher oder rechtskonform betrachtet.
