import 'package:hermes_display/core/media/rich_content.dart';
import 'package:hermes_display/services/hermes_sync_service.dart';
import 'package:hermes_display/services/link_opener.dart';

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

class FakeLinks implements LinkOpener {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}
