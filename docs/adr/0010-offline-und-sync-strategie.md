# ADR 0010: Offline- und Synchronisationsstrategie

## Status

Beschlossen als Grundregel; der Offlineumfang wird pro Anwendungsfall freigegeben.

## Kontext

Der Standortserver muss bei Internetausfall weiterlaufen. Handhelds sollen kurze Unterbrechungen zum Standortserver überstehen. Gleichzeitige Bearbeitung, Berechtigungsänderungen und fachlich kritische Vorgänge machen eine pauschale Offlinefreigabe unsicher.

## Entscheidung

Die Standortsynchronisation zum Unternehmensserver und die Gerätesynchronisation zum Standortserver sind getrennte Protokolle. Der Standortserver ist für operative Standortdaten maßgeblich. Ein Gerät hält verschlüsselt und zeitlich begrenzt nur benötigte Daten sowie eine persistente Warteschlange zulässiger Operationen. Jede Operation besitzt stabile ID, lokalen Zeitpunkt, Benutzer- und Gerätekontext sowie bei Änderungen bestehender Aggregate eine Basisversion; Neuerfassungen brauchen eine eigene stabile Identitätszuordnung. Der Server prüft bei Wiederverbindung Berechtigung, gegebenenfalls Basisversion und Fachregeln erneut; wiederholte Übertragung bleibt idempotent. Konflikte werden sichtbar und mit einer fachlichen Entscheidung aufgelöst. Stilles Last-write-wins ist ausgeschlossen. Kritische Aktionen können pro Anwendungsfall onlinepflichtig sein.

## Alternativen

- Alle Schreiboperationen onlinepflichtig: einfacher, aber Handheldarbeit stoppt bei kurzen lokalen Netzstörungen.
- Automatische Feldzusammenführung: für manche Stammdaten denkbar, für Abschlüsse, Messwerte und Geld ohne Fachsemantik gefährlich.

## Konsequenzen

- Die UI unterscheidet „lokal erfasst“, „synchronisiert“, „abgelehnt“ und „Konflikt“ deutlich.
- Widerrufene Rechte und alte SOP-Versionen erfordern Ablaufregeln für Offlinezugriff.
- Zeitsynchronisation, Geräteverlust, doppelte Abschlüsse und serverseitig erzeugte Aufgaben müssen gezielt getestet werden.
- Idempotenznachweise und Annahmeergebnis werden mit der Fachänderung atomar gespeichert. Unterstützte Wiederholungsdauer, Cursor-Neustart und Restore-Abgleich begrenzen das Sync-Versprechen; Details stehen in [Offline-Strategie](../architecture/offline-strategy.md) und [Deployment](../architecture/deployment.md).

## Offene Prüfungen

- Vor der Geräte-Offlinephase P2 festlegen, welche Guided-Work-Eingaben und Completion-Anfragen zulässig sind. P1 verlangt Standortautonomie bei WAN-Ausfall; ein verbindlicher Änderungsnachweis entsteht erst bei Serverannahme.
- Maximale Offlinedauer, Queue-Größe und Verhalten bei veralteter Berechtigung bestimmen.
