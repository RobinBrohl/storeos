# Fachliche Module (geplant)

Hier werden später die unabhängigen Fachbereiche des modularen Monolithen angelegt. Für den ersten Slice sind `organization`, `people`, `workforce`, `tasks` und `audit` als fachliche Eigentümer vorgesehen; konkrete Package-Verzeichnisse entstehen erst mit der Implementierung. Weitere Domänen folgen dem [Fahrplan](../docs/roadmap/phases.md).

Ein Modul besitzt seine Domain-, Application- und Infrastructure-Schicht, private Persistenz und dokumentierte öffentliche Kommandos/Abfragen/Events. Abhängigkeiten und erlaubte Datenflüsse stehen in den [Modulgrenzen](../docs/architecture/module-boundaries.md).
