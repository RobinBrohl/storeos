# ADR 0002: Flutter als gemeinsamer Client

## Status

Beschlossen für die Startarchitektur.

## Kontext

Die Vision verlangt eine gemeinsame Designsprache für Web, Android, Windows und Linux. Handheld, Desktop, Management und später POS haben unterschiedliche Bedienmuster. Der erste Durchstich benötigt eine Mitarbeiteransicht und geführte Arbeit.

## Entscheidung

Eine Flutter-Codebasis stellt die Clients bereit. Die Clients teilen UI-Bausteine und veröffentlichte API-Verträge; serverinterne Domain- und Persistenzmodelle bleiben privat. Oberflächen werden je Gerät und Aufgabe angepasst. Der Handheld zeigt wenige, große Aktionen und Scanabläufe; Desktop bietet Tabellen und Tastaturbedienung. iOS, macOS und POS bleiben spätere Zielplattformen. Geschäftsentscheidungen und Berechtigungsprüfungen liegen auf dem Server; lokale Clientregeln dienen der Bedienung und der kontrollierten Offlineerfassung.

## Alternativen

- Native Clients je Plattform: mehr plattformspezifische Freiheit, aber hoher Pflegeaufwand.
- Eine reine Webanwendung: einfachere Verteilung, aber die Anforderungen an Scan, Geräteeinbindung und kontrollierte Offlineabläufe müssten gesondert gelöst werden.

## Konsequenzen

- Designsystem und API-Verträge können über Geräte hinweg konsistent bleiben.
- Plattformunterschiede bei Scanner, Drucker, Dateisystem, Browsercache und Barrierefreiheit erfordern gezielte Adapter und Tests.
- Eine gemeinsame Codebasis garantiert keine identische oder gute UX auf allen Geräten.

## Offene Prüfungen

- Früh einen realen Android-Handheld und die vorgesehenen Web-/Desktopplattformen mit Scan, lokaler Speicherung und Bedienbarkeit testen.
- Unterstützte Betriebssystem- und Browserstände festlegen.
