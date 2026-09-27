# ADR 0007: Plugin-Architektur

## Status

Beschlossen als Erweiterungsvertrag; Ausführung fremder Plugins wird erst nach Sicherheitsnachweis freigegeben.

## Kontext

StoreOS soll Geräte, Lieferanten, Kassen und andere Fremdsysteme anbinden. Plugins können sensible Daten lesen, Aufgaben erzeugen und externe Effekte auslösen. „Plugin first“ ohne Grenzen würde den Kern und seine Datenintegrität gefährden.

## Entscheidung

Plugins verwenden versionierte APIs, Events und deklarierte Fähigkeiten. Direkter Zugriff auf Datenbanktabellen oder interne Modulklassen ist ausgeschlossen. Ein Manifest nennt Identität, Hersteller, kompatible Core-Version, Berechtigungen, Event-Abonnements und Konfigurationsschema. Installation und Rechtevergabe erfolgen durch befugte Administratoren; Berechtigungen werden zur Laufzeit serverseitig geprüft. Fremde Plugins werden ausschließlich mit erzwungener Prozess- oder Containerisolation, begrenzten Ressourcen und ausdrücklich freigegebenen Netzwerkzielen ausgeführt. Ohne diese Schutzgrenzen erfolgt keine Aktivierung; Einzelheiten stehen im [Plugin-System](../architecture/plugin-system.md). Pluginfehler dürfen Kerntransaktionen nicht stillschweigend verändern.

## Alternativen

- Plugins als beliebiger Code im Serverprozess: einfacher, aber unzureichende Isolation bei Fehlern und Angriffen.
- Nur feste Integrationen im Kern: geringere Angriffsfläche, aber dauerhaft hohe Kopplung an Anbieter.

## Konsequenzen

- SDK, Signierung oder Herkunftsnachweis, Kompatibilitätstests und Update-/Widerrufsprozess werden Produktbestandteile.
- Ein Berechtigungskatalog allein isoliert keinen bösartigen Prozess; Betriebssystem- und Netzwerkgrenzen sind nötig.
- Für den ersten Durchstich genügt ein dokumentierter Erweiterungsvertrag; ein offener Plugin-Marktplatz ist nicht erforderlich.

## Offene Prüfungen

- Bedrohungsmodell für Plugininstallation, Geheimnisse, Dateizugriff und externe Netzverbindungen erstellen.
- Vertrauensstufen für eigene, kundeneigene und fremde Plugins festlegen.
