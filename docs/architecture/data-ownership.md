# Datenhoheit und Schreibzuständigkeit

## Grundregel

„Eine gemeinsame Datenbasis“ meint ein einheitliches fachliches Modell und nachvollziehbare Datenflüsse, nicht eine weltweit synchron beschreibbare Datenbank. Jeder Datensatz hat genau einen fachlich führenden Schreiber. Andere Knoten nutzen versionierte Projektionen oder explizite Commands an diesen Schreiber. Das vermeidet konkurrierende Änderungen bei Netzausfall. Der Betrieb behält Eigentum und Exportfähigkeit seiner Daten; [Synchronisation](offline-strategy.md) und [Sicherheit](security.md) setzen die technische Grenze für Kopien.

Die folgende Matrix ist eine **Arbeitsannahme für eine spätere Mehrstandortinstallation**, keine Freigabe der zentralen Synchronisation. Vor der Implementierung werden besonders Employee- und HR-Zuständigkeiten fachlich entschieden.

| Datenbereich | Vorgeschlagener führender Schreiber mit optionaler Zentrale | Standortnutzung |
| --- | --- | --- |
| Company und Verzeichnis der Locations | Unternehmensserver | Standort hält nötige, versionierte Kopie |
| Unternehmensweite Account-Identität, Account-Employee-Verknüpfung und Rollen | Unternehmensserver als Vorschlag; fachlicher Eigentümer ist die Plattformkomponente Identität/Berechtigungen | Standort hält begrenzte Zugriffs-Snapshots; lokale Sperre hat Vorrang |
| Employee-Profil | Unternehmensserver als Vorschlag; Beschäftigungsverhältnisse und HR-Akte sind später getrennte Referenzen | Standort hält nur benötigte Zuordnung und Felder |
| Schicht, standortbezogene Zuordnung, TaskInstance, Guided-Work-Ergebnisse | Zuständiger Standortserver | Zentrale erhält berechtigte Projektionen |
| TaskTemplate | Zentrale für unternehmensweite Vorlage; Standort für lokale Vorlage oder explizite Ableitung | Keine parallelen Änderungen an derselben Template-ID |
| Audit-Eintrag | Knoten, der die Aktion verbindlich annimmt | Zentrale kann berechtigte Kopien erhalten; Ursprung bleibt erkennbar |

Ohne Unternehmensserver übernimmt der Standortserver die Führung für Company, Location, Account, Account-Employee-Verknüpfung und Employee. Beim späteren Anschluss einer Zentrale ist die Übertragung der Zuständigkeit eine **explizite Migration** mit ID-Zuordnung, Dublettenprüfung, Versionierung und prüfbarem Cutover. Bestehende IDs und historische Verweise bleiben erhalten; notwendige Zusammenführungen erhalten eine nachvollziehbare Zuordnung statt pauschalem Umnummerieren. Eine automatische Zusammenführung gleichnamiger Personen, Produkte oder Vorlagen wäre unsicher. Das [Domänenmodell](domain-model.md) trennt bereits Mitarbeiterprofil, Login und späteres Beschäftigungsverhältnis; der konkrete HR-Ausbau folgt einer eigenen Fachmodellierung.

Eine neue Schreibzuständigkeit wird erst aktiv, wenn der bisherige Schreiber für diese Daten nachweislich nicht mehr schreiben kann. Nichterreichbarkeit allein ist kein Nachweis; bei WAN-Ausfall wird deshalb kein zweiter Schreiber automatisch eingesetzt. Dieselbe Grenze gilt beim Austausch oder Restore eines Standortservers. Herkunfts-IDs allein verhindern keine konkurrierenden Serverkopien.

Eine Schicht oder Aufgabe wechselt ihren führenden Standort nicht durch gewöhnliches Ändern von `locationId`. Eine spätere standortübergreifende Verlegung braucht eine bestätigte Übergabe der Zuständigkeit oder nachvollziehbar verknüpfte Stornierung und Neuanlage. Solange der alte Standort nicht verbindlich mitwirken kann, darf der neue Standort die übertragene Arbeit nicht als bereits freigegeben behandeln.

## Standortübergreifende Integrität

Ein führender Schreiber pro Aggregat verhindert keine Konflikte zwischen verschiedenen Aggregaten: Zwei getrennte Standorte könnten derselben Person zeitgleich jeweils eine lokale Schicht zuweisen. Für jede standortübergreifende Regel wird deshalb vor Freigabe festgelegt, ob sie nur einen Hinweis mit Aktualitätsstand liefert oder eine verbindliche, koordinierte Prüfung benötigt. Eine harte globale Zusage kann während einer Trennung nur mit zuvor verbindlich zugeteilten Befugnissen/Reservierungen oder erreichbarer zuständiger Instanz gelten; andernfalls bleibt die betroffene Freigabe ausstehend. Normale lokale Abläufe benötigen dafür keinen allgemeinen verteilten Transaktionsdienst.

## Grenzen zwischen Modulen

Ein Modul besitzt seine Tabellen und schreibt sie nur über seine Application Use Cases. Andere Module erhalten freigegebene Lesemodelle oder nutzen Commands und [Events](event-system.md). Gemeinsame Datenbanktechnik des modularen Monolithen ist keine Freigabe für direkte Fremdtabellenzugriffe. Jede neue Entität bekommt dokumentiert: Besitzer-Modul, führenden Knoten, Datenklassifikation, Aufbewahrungsregeln, Berechtigungen, Exportformat und Sync-Richtung. Replizierte Daten tragen Herkunft und Version, damit ein veralteter Stand erkennbar ist.

## Portabilität und Löschung

Ein vollständiger Kundenexport umfasst fachliche Datensätze, relevante Audit-Einträge, Anhänge und Metadaten wie IDs, Beziehungen, Zeitzonen, Einheiten, Schema-Version und Herkunft. Maschinenlesbare, dokumentierte Formate sind maßgeblich; CSV/XLSX/PDF sind zusätzliche nutzerfreundliche Sichten und können Beziehungen oder Nachweise nicht vollständig abbilden. Import validiert Referenzen und erzeugt einen Fehlerbericht, statt unbekannte Felder oder Konflikte still zu verwerfen. Plugin-Daten benötigen denselben Exportpfad.

Ein zentraler Export ist nicht automatisch vollständig, da die Zentrale nur freigegebene Projektionen besitzt. Ein Exportmanifest nennt pro Standort und Datenbereich enthaltene Daten, Stand, Schema-Version und fehlende Quellen. Für einen vollständigen Export werden auch autoritative Standort- und Plugin-Daten eingesammelt; unerreichbare Quellen oder ausgelassene Felder bleiben ausdrücklich als Lücke sichtbar. Ein Export ersetzt kein konsistentes Betriebsbackup.

Datenschutzrechtliche Lösch- und Auskunftspflichten stehen teilweise im Spannungsverhältnis zu Aufbewahrung und Audit. Deshalb werden operative Daten, Identifikatoren und Nachweise getrennt klassifiziert; Löschung, Sperrung, Pseudonymisierung und Aufbewahrungsfristen müssen je Datenart und Rechtsraum festgelegt werden. Unbegrenzte Audit-Aufbewahrung oder uneingeschränkte Mitarbeiter-Exports sind keine Voreinstellung. Vor Produktiveinsatz in regulierten Bereichen bedarf es dazu fachlicher und rechtlicher Prüfung.

Der Lösch- und Sperrplan umfasst auch Anhänge, Projektionen, Suche, Event-Payloads/Fehlerablagen, gespeicherte Kommandoergebnisse, Geräte und Plugin-Daten. Für Deduplizierung verbleibt nur die erforderliche technische Information, nicht vorsorglich der gesamte ursprüngliche Personenbezug oder Payload. Backups besitzen begrenzte Aufbewahrung; Lösch- und Sperrentscheidungen müssen über den ältesten noch zulässigen Restorepunkt hinweg separat nachvollziehbar bleiben und vor Wiederöffnung angewendet werden. Die Wiederherstellung eines Backups ist keine Freigabe, entfernte Daten erneut auszuliefern.
