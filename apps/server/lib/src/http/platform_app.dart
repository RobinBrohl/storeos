import 'package:shelf/shelf.dart';

import '../application/auth_service.dart';
import '../platform/identity_service.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import 'platform_identity_routes.dart';
import 'platform_plugin_routes.dart';

/// Composition only; authorization and mutations remain in application services.
Handler createPlatformHandler(AuthService auth, PlatformDatabase database) =>
    Cascade()
        .add(
          PlatformIdentityRoutes(
            auth: auth,
            organization: OrganizationService(database),
            identity: IdentityService(database, auth.passwordHasher),
          ).router.call,
        )
        .add(PlatformPluginRoutes(auth: auth, database: database).router.call)
        .handler;
