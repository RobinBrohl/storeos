# PostgreSQL-Backup und isolierte Restoreprobe

Die PowerShell-7.4+-Skripte sichern die laufende PostgreSQL-Datenbank als `pg_dump`-Custom-Format und verschlüsseln den Datenstrom während des Schreibens mit AES-256-GCM. Jeder Chunk und das Ende des Datenstroms werden authentifiziert. Es entsteht keine unverschlüsselte Dump-Datei auf dem Host. Die Sicherung erhält eine JSON-Datei mit Prüfsumme. Der Schlüssel ist `.local/secrets/backup_key.bin` oder ein ausdrücklich angegebener anderer 32-Byte-Schlüssel.

Das versionierte Format `STOREOS2` enthält einen zufälligen 32-Byte-Salt und einen zufälligen 8-Byte-Nonce-Präfix. HKDF-SHA256 leitet daraus und dem Master-Schlüssel für jede Sicherung einen eigenen AES-Schlüssel ab. Es folgen authentifizierte 4-MiB-Chunks mit Sequenznummer und Längenfeld sowie eine authentifizierte Endmarke. Ältere Formatversionen werden bewusst abgelehnt; eine spätere Formatmigration muss ausdrücklich implementiert und getestet werden. `Test-BackupCrypto.ps1` prüft Roundtrip sowie falschen Schlüssel, veränderte Daten, Abschneiden und vertauschte Chunks.

```powershell
pwsh ./infra/backup/Backup-StoreOS.ps1
pwsh ./infra/backup/Restore-StoreOS.ps1 -BackupPath ./.local/backups/storeos-YYYYMMDD-HHMMSS-XXXXXXXX.sodb
```

Restore legt ausschließlich eine **neue** Datenbank `storeos_restore_*` an und entzieht vor dem Kopieren `PUBLIC` und dem Runtime-Account `storeos` das Verbindungsrecht. Das Skript löscht oder überschreibt die Originaldatenbank nicht. Es prüft Prüfsumme, Entschlüsselung, PostgreSQL-Restore, vorhandene Accounts und Bootstrapstatus. Bevor die wiederhergestellte Datenbank einem Client dienen könnte, widerruft es alle darin gespeicherten Benutzer-Sessions und, falls die Plugin-Tabellen schon existieren, sämtliche Plugin-Tokens; beide Widerrufe werden verifiziert. Der Runtime-Account erhält keine Verbindung zur Zieldatenbank. Eine fehlgeschlagene Probe kann eine unvollständige isolierte Testdatenbank zurücklassen; sie wird nicht automatisch als produktiver Ersatz aktiviert. Der Name der Testdatenbank wird ausgegeben und kann nach Prüfung gezielt durch den Betreiber entfernt werden.

Der automatisierte Nachweis, dass ein verschlüsseltes Backup den beschriebenen
Mitarbeiterablauf vollständig wiederherstellt, steht im
[Acceptance-Runbook](acceptance.md) (English).

Für einen echten Wiederanlauf sind zusätzlich eine aktuelle, separat gesicherte Kopie des Backup-Schlüssels, der Konfiguration, Secrets, TLS-CA und später aller Anhänge nötig. Das P0-Skript sichert **nur PostgreSQL**; es behauptet keinen vollständigen Standort-Restore, sobald Dateien oder Plugins produktive Daten besitzen. Schlüssel niemals nur auf demselben Server oder ausschließlich im verschlüsselten Backup aufbewahren. Backups außerhalb des primären Datenträgers speichern und Restore regelmäßig auf einem getrennten Host üben.

Ein älteres Backup kann bereits quittierte Geräteaktionen oder neuere Kontosperren verlieren. Vor produktiver Freigabe eines Ersatzservers gelten der Abgleich und die Sperrregeln aus der [Deployment-Strategie](../../docs/architecture/deployment.md). Die isolierte Restoreprobe schaltet keine produktiven Sync- oder Pluginverbindungen frei.
