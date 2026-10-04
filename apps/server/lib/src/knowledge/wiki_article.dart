import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';

/// Aggregate lifecycle decisions are independent of HTTP and Flutter.
class WikiArticle {
  const WikiArticle(this.state);
  final WikiArticleDto state;
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
        'Article is retired.',
      );
    }
  }

  void requireDraft(WikiRevisionDto revision) {
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
        'Article already has a draft.',
      );
    }
  }

  static void requirePublication(WikiContent content) {
    try {
      content.validate(publication: true);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_publication',
        'Publication requires valid nonblank title and body.',
      );
    }
  }
}
