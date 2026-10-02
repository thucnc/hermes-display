import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

abstract interface class LinkOpener {
  /// False when no app could open [uri].
  Future<bool> open(Uri uri);
}

/// Hands links to the YouTube app or browser.
final class ExternalLinkOpener implements LinkOpener {
  const ExternalLinkOpener();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}
