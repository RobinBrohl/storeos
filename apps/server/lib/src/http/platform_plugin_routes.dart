import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../application/auth_service.dart';
import '../platform/audit_service.dart';
import '../platform/event_service.dart';
import '../platform/platform_database.dart';
import '../platform/plugin_service.dart';
import 'api_support.dart';

class PlatformPluginRoutes {
  PlatformPluginRoutes({
    required this._auth,
    required PlatformDatabase database,
  }) : _audit = AuditService(database),
       _events = EventService(database),
       _plugins = PluginService(database) {
    _router.get('/api/v1/platform/audit', _listAudit);
    _router.get('/api/v1/platform/events', _listEvents);
    _router.post('/api/v1/platform/events/<eventId>/replay', _replayEvent);
    _router.get('/api/v1/platform/plugins', _listPlugins);
    _router.post('/api/v1/platform/plugins', _registerPlugin);
    _router.post('/api/v1/platform/plugins/<id>/approve', _approvePlugin);
    _router.post('/api/v1/platform/plugins/<id>/disable', _disablePlugin);
    _router.get('/api/plugin/v1/organization', _pluginOrganization);
    _router.get('/api/plugin/v1/events', _pluginEvents);
    _router.post('/api/plugin/v1/events/<eventId>/ack', _ackPluginEvent);
  }

  final AuthService _auth;
  final AuditService _audit;
  final EventService _events;
  final PluginService _plugins;
  final Router _router = Router();

  Router get router => _router;

  Future<Response> _listAudit(Request request) async => jsonResponse(
    200,
    await _audit.list(
      await _auth.authenticate(bearerToken(request)),
      after: request.url.queryParameters['after'],
    ),
  );

  Future<Response> _listEvents(Request request) async => jsonResponse(
    200,
    await _events.list(
      await _auth.authenticate(bearerToken(request)),
      after: request.url.queryParameters['after'],
    ),
  );

  Future<Response> _replayEvent(Request request, String eventId) async =>
      jsonResponse(
        200,
        await _events.replay(
          await _auth.authenticate(bearerToken(request)),
          eventId,
        ),
      );

  Future<Response> _listPlugins(Request request) async => jsonResponse(
    200,
    await _plugins.list(await _auth.authenticate(bearerToken(request))),
  );

  Future<Response> _registerPlugin(Request request) async => jsonResponse(
    201,
    await _plugins.register(
      await _auth.authenticate(bearerToken(request)),
      await readJson(request),
    ),
  );

  Future<Response> _approvePlugin(Request request, String id) async =>
      jsonResponse(
        200,
        await _plugins.approve(
          await _auth.authenticate(bearerToken(request)),
          id,
          await readJson(request),
        ),
      );

  Future<Response> _disablePlugin(Request request, String id) async =>
      jsonResponse(
        200,
        await _plugins.disable(
          await _auth.authenticate(bearerToken(request)),
          id,
          await readJson(request),
        ),
      );

  Future<Response> _pluginOrganization(Request request) async =>
      jsonResponse(200, await _plugins.organization(bearerToken(request)));

  Future<Response> _pluginEvents(Request request) async => jsonResponse(
    200,
    await _plugins.events(
      bearerToken(request),
      after: request.url.queryParameters['after'],
    ),
  );

  Future<Response> _ackPluginEvent(Request request, String eventId) async {
    await _plugins.acknowledge(bearerToken(request), eventId);
    return Response(204);
  }
}
