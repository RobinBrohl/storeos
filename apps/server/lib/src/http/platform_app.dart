import 'shift_routes.dart';
import 'purchasing_routes.dart';
import '../purchasing/purchasing_service.dart';
import 'shift_transfer_routes.dart';
import '../application/shift_transfer_application.dart';
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
import 'article_quantity_routes.dart';
import '../inventory/article_quantity_service.dart';
import '../stock/stock_quantity_service.dart';
import 'stock_count_routes.dart';
import '../stock/stock_count_service.dart';
import 'merchandising_routes.dart';
import '../merchandising/merchandising_service.dart';
import '../knowledge/knowledge_service.dart';
import 'knowledge_routes.dart';
import 'recipe_routes.dart';
import 'preparation_batch_routes.dart';
import 'preparation_assignment_routes.dart';
import '../production/preparation_assignment_service.dart';
import '../production/preparation_batch_service.dart';
import '../production/recipe_service.dart';
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
    .add(
      ArticleQuantityRoutes(
        auth,
        ArticleQuantityService(database),
        StockQuantityService(database),
      ).router.call,
    )
    .add(PurchasingRoutes(auth, PurchasingService(database)).router.call)
    .add(ShiftRoutes(auth, ShiftApplication(database)).router.call)
    .add(
      ShiftTransferRoutes(auth, ShiftTransferApplication(database)).router.call,
    )
    .add(TaskTemplateRoutes(auth, TaskTemplateService(database)).router.call)
    .add(ArticleRoutes(auth, ArticleService(database)).router.call)
    .add(
      ArticleAssortmentRoutes(
        auth,
        ArticleAssortmentService(database),
      ).router.call,
    )
    .add(StockRoutes(auth, StockService(database)).router.call)
    .add(StockCountRoutes(auth, StockCountService(database)).router.call)
    .add(MerchandisingRoutes(auth, MerchandisingService(database)).router.call)
    .add(KnowledgeRoutes(auth, KnowledgeService(database)).router.call)
    .add(RecipeRoutes(auth, RecipeService(database)).router.call)
    .add(
      PreparationAssignmentRoutes(
        auth,
        PreparationAssignmentService(database),
      ).router.call,
    )
    .add(
      PreparationBatchRoutes(
        auth,
        PreparationBatchService(database),
      ).router.call,
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
