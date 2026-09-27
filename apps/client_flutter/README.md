# StoreOS Standortclient

P0-Webclient für die Anmeldung am lokalen Standortserver und den geschützten, tatsächlich abgerufenen Systemstatus. Die Sitzung liegt nur im Arbeitsspeicher; ein Reload verlangt eine neue Anmeldung. Die Anzeige erfindet bei Verbindungsverlust keinen gesunden Status. Fachmodule und Mitarbeiter-Home folgen erst im vorgesehenen Vertical Slice.

```powershell
cd apps/client_flutter
flutter pub get
flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8085 --dart-define=STOREOS_API_URL=http://127.0.0.1:8080
```

`STOREOS_API_URL` muss auf die API-Wurzel zeigen. Ohne Definition gilt `http://127.0.0.1:8080`, also der Rechner des Browsers. HTTP ist nur für `localhost`, `127.0.0.1` und `::1` erlaubt; andere Server benötigen HTTPS. Läuft der Flutter-Entwicklungsserver unter einer anderen Origin als die API, muss der Server diese Origin für `Authorization`, `Content-Type`, `GET`, `POST` und `OPTIONS` zulassen.

```powershell
flutter test
flutter analyze
flutter build web --no-web-resources-cdn --dart-define=STOREOS_API_URL=https://standort.example.org
```

Für eine vollständig lokal auslieferbare Web-Version ist `--no-web-resources-cdn` erforderlich; Flutter bündelt dann CanvasKit im Build. Der Client registriert Roboto Regular, Medium und Bold aus dem Flutter-SDK als lokale Assets. Die Lizenz liegt unter `assets/fonts/roboto_license.txt`. `web/flutter_bootstrap.js` lenkt auch eventuelle Engine-Fallback-Anfragen auf den lokalen Server. Der erste Client prüft nur deutschsprachige Oberfläche und lateinische Zeichen; zusätzliche Schriftsysteme brauchen vor Freigabe passende lokale Fonts und einen Darstellungscheck.

Der Client nutzt `storeos_api_contracts` und trennt HTTP-Repository, Sitzungssteuerung und Widgets. Status- und Loginfehler bleiben sichtbar. Eine fehlgeschlagene Serverabmeldung beendet trotzdem die lokale Sitzung und weist auf die ausstehende Bestätigung hin.
