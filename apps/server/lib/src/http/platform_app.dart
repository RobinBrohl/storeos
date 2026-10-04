import 'shift_routes.dart';
import '../application/shift_application.dart';
import 'package:shelf/shelf.dart';

import '../application/auth_service.dart';
import '../inventory/article_assortment_service.dart';
import '../inventory/article_service.dart';
import '../stock/stock_service.dart';
import '../platform/identity_service.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import 'article_assortment_routes.dart';
import 'article_routes.dart';
import 'stock_routes.dart';
import 'merchandising_routes.dart';
import '../merchandising/merchandising_service.dart';
import '../knowledge/knowledge_service.dart';
import 'knowledge_routes.dart';
import 'platform_identity_routes.dart';
import 'employee_routes.dart';
import 'task_template_routes.dart';
import '../tasks/task_template_service.dart';
import '../application/employee_application.dart';
import 'platform_plugin_routes.dart';

/// Composition only; authorization and mutations remain in application services.
Handler createPlatformHandler(
  AuthService auth,
  PlatformDatabase database,
) => Cascade()
    .add(ShiftRoutes(auth, ShiftApplication(database)).router.call)
    .add(TaskTemplateRoutes(auth, TaskTemplateService(database)).router.call)
    .add(ArticleRoutes(auth, ArticleService(database)).router.call)
    .add(
      ArticleAssortmentRoutes(
        auth,
        ArticleAssortmentService(database),
      ).router.call,
    )
    .add(StockRoutes(auth, StockService(database)).router.call)
    .add(MerchandisingRoutes(auth, MerchandisingService(database)).router.call)
    .add(KnowledgeRoutes(auth, KnowledgeService(database)).router.call)
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
