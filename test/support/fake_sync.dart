import 'package:hermes_display/core/media/rich_content.dart';
import 'package:hermes_display/services/hermes_sync_service.dart';

class FakeSync implements HermesSyncService {
  FakeSync({this.result = SaveResult.saved});

  final SaveResult result;
  final List<(Uri, NoteDraft)> saved = [];

  @override
  Future<SaveResult> save(Uri uri, NoteDraft note) async {
    saved.add((uri, note));
    return result;
  }
}
