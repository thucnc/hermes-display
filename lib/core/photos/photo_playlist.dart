import 'dart:math';

import 'on_this_day.dart';
import 'photo_manifest.dart';

/// Slideshow order: today's memories first (fewest years ago first),
/// then photos of the active member, then everything else; each group
/// shuffled so the frame does not repeat the same run every day.
List<FamilyPhoto> buildPlaylist(
  List<FamilyPhoto> photos, {
  required String memberId,
  required DateTime today,
  Random? random,
}) {
  final memories = <FamilyPhoto>[];
  final mine = <FamilyPhoto>[];
  final rest = <FamilyPhoto>[];
  for (final photo in photos) {
    if (OnThisDay.of(photo, today) != null) {
      memories.add(photo);
      continue;
    }
    if (photo.features(memberId)) {
      mine.add(photo);
      continue;
    }
    rest.add(photo);
  }
  final shuffled = random ?? Random();
  memories
    ..shuffle(shuffled)
    ..sort(
      (a, b) => OnThisDay.of(a, today)!.compareTo(OnThisDay.of(b, today)!),
    );
  return [
    ...memories,
    ...(mine..shuffle(shuffled)),
    ...(rest..shuffle(shuffled)),
  ];
}
