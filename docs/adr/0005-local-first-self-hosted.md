# ADR 0005: Local-first und Self-hosted

## Status

Beschlossen als Produktgrundsatz.

## Kontext

Ein Standort soll bei Internetausfall arbeiten können. Kunden sollen ihre Daten und Infrastruktur kontrollieren und keine verpflichtende Cloudanmeldung benötigen. Gleichzeitig benötigen mobile Geräte zeitweise eine Offlinewarteschlange.

## Entscheidung

Der reguläre Standortbetrieb läuft mit einem vor Ort oder kundenseitig betriebenen Standortserver und lokalen Daten. Authentifizierung, Kern-API und der erste fachliche Durchstich dürfen keine dauerhaft erreichbare Herstellercloud voraussetzen. Updates, Support, Fernzugriff und Telemetrie sind getrennte, ausdrücklich konfigurierte Betriebsoptionen. Export, Backup und dokumentierter Restore gehören zum Betriebsmodell. „Local-first“ bezeichnet hier vor allem die Betriebsfähigkeit des Standorts; für Handhelds gilt der eingeschränkte Offlineumfang aus ADR 0010.

## Alternativen

- Cloudpflicht für Authentifizierung und Daten: verworfen wegen Ausfallabhängigkeit und fehlender Selbstbetriebsmöglichkeit.
- Vollständig unabhängige gleichberechtigte Datenhaltung auf jedem Handheld: verworfen wegen schwieriger Konflikt- und Integritätsregeln.

## Konsequenzen

- Installations-, Update-, Backup- und Schlüsselverwaltung müssen für Betreiber verständlich und testbar sein.
- Standorte tragen operative Verantwortung für ihre lokale Infrastruktur; das Produkt braucht sichtbare Gesundheits- und Wiederherstellungsinformationen.
- Cloudfreie Nutzung schließt optionale externe Integrationen nicht aus.

## Offene Prüfungen

- Minimalprofil für einen Standort mit einem Serverausfall und Netzwerksegmenten definieren.
- Welche Funktionen bleiben bei Ausfall des Standortservers selbst verfügbar, und wie wird dann auf Papier oder Ersatzverfahren gewechselt?
