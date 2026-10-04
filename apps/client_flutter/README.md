# StoreOS Standortclient

Current Flutter Web client for the local StoreOS API: platform administration,
Employee Home, guided confirmation/numeric work, exception resolution, bounded
shift cancellation/amendment, Article, location Assortment and manual Stock.
See [actual status](../../docs/roadmap/status.md) for delivered scope and acceptance.
Native runners, automatic recommendations and persistent offline queues are future.
P4.3 Stock is committed but its retry/dialog/mock defects require a separate code
correction before acceptance; see [technical debt](../../docs/development/technical-debt.md).
Authorization remains server-side; hiding a UI action does not grant or deny rights.

Die Sitzung liegt nur im Arbeitsspeicher; ein Reload verlangt eine neue Anmeldung. Der Client trennt HTTP-Transport, Anwendungszustand und Widgets. Rollen steuern sichtbare Bereiche und Aktionen, der Server prüft jede Berechtigung erneut. Schreibanfragen verwenden Versionen beziehungsweise stabile Client-IDs; nach Konflikten oder unklaren Ausgängen lädt der Client den Serverstand neu. Stock's duplicate-submission retry identity is a known exception requiring correction; do not claim that flow is fully accepted. Verbindungsverlust wird sichtbar und ein alter Status nicht als gesund angezeigt. Ein Plugin-Zugangstoken erscheint nur direkt nach der Freigabe und wird nicht gespeichert.

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
