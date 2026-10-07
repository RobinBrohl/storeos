import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';

/// Aggregate lifecycle decisions are independent of HTTP and Flutter.
class Recipe {
  const Recipe(this.state);
  final RecipeDto state;
  void requireActiveVersion(int expected) {
    if (state.version != expected) {
      throw const PlatformFailure(
        409,
        'stale_version',
        'State changed; reload and review.',
      );
    }
    if (state.status != 'active') {
      throw const PlatformFailure(
        409,
        'invalid_lifecycle',
        'Recipe is retired.',
      );
    }
  }

  void requireDraft(RecipeRevisionDto revision) {
    if (revision.status != 'draft' ||
        state.activeDraftRevisionId != revision.id) {
      throw const PlatformFailure(
        409,
        'invalid_lifecycle',
        'An active draft is required.',
      );
    }
  }

  void requireNoDraft() {
    if (state.activeDraftRevisionId != null) {
      throw const PlatformFailure(
        409,
        'draft_exists',
        'Recipe already has a draft.',
      );
    }
  }

  static void requirePublication(RecipeContent content) {
    try {
      content.validate(publication: true);
    } on FormatException {
      throw const PlatformFailure(
        422,
        'recipe_not_publishable',
        'Publication requires batch description, preparation and ingredients.',
      );
    }
  }
}
