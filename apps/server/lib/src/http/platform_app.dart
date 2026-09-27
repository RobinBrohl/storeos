import 'package:shelf/shelf.dart';

import '../application/auth_service.dart';
import '../platform/identity_service.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import 'platform_identity_routes.dart';
import 'employee_routes.dart';
import 'task_template_routes.dart';
import '../tasks/task_template_service.dart';
import '../application/employee_application.dart';
import 'platform_plugin_routes.dart';

/// Composition only; authorization and mutations remain in application services.
Handler createPlatformHandler(AuthService auth, PlatformDatabase database) =>
    Cascade()
        .add(
          TaskTemplateRoutes(auth, TaskTemplateService(database)).router.call,
        )
        .add(EmployeeRoutes(auth, EmployeeApplication(database)).router.call)
        .add(
          PlatformIdentityRoutes(
            auth: auth,
            organization: OrganizationService(database),
            identity: IdentityService(database, auth.passwordHasher),
          ).router.call,
        )
        .add(PlatformPluginRoutes(auth: auth, database: database).router.call)
        .handler;
