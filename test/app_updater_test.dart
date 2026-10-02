import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_display/core/constants/app_constants.dart';
import 'package:hermes_display/core/dimming/dim_schedule.dart';
import 'package:hermes_display/services/update/app_platform.dart';
import 'package:hermes_display/services/update/app_updater.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_app_platform.dart';

void main() {
  final endpoint = Uri.parse('http://192.168.1.5:8901/api/app/latest');
  final apk = utf8.encode('PK-fake-apk-bytes');
  final apkSha = sha256.convert(apk).toString();
  late Directory cache;
  late FakeAppPlatform platform;
  late List<Uri> requests;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('updater');
    platform = FakeAppPlatform();
    requests = [];
  });

  tearDown(() => cache.delete(recursive: true));

  String latest({int code = 5, String? sha, String url = 'apk/5.apk'}) {
    return jsonEncode({
      'versionCode': code,
      'versionName': '0.5.$code',
      'url': url,
      'sha256': sha ?? apkSha,
      'notes': '',
    });
  }

  AppUpdater updater({String? body, int status = 200, List<int>? apkBytes}) {
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path.endsWith('.apk')) {
        return http.Response.bytes(apkBytes ?? apk, 200);
      }
      return http.Response(body ?? latest(), status);
    });
    return AppUpdater(
      platform: platform,
      client: client,
      cacheRoot: () async => cache,
    );
  }

  Directory updates() => Directory('${cache.path}/${UpdateDefaults.dirName}');

  test('downloads and verifies a newer APK, then installs it', () async {
    final service = updater();
    expect(await service.check(endpoint: endpoint), UpdateCheck.ready);
    final state = service.state.value;
    expect(state.phase, UpdatePhase.ready);
    expect(state.release!.versionName, '0.5.5');
    expect(requests.last, endpoint.resolve('apk/5.apk'));
    expect(await File(state.path!).readAsBytes(), apk);
    expect(updates().listSync(), hasLength(1));

    expect(await service.install(), InstallResult.started);
    expect(platform.installs, [state.path]);
  });

  test('same or older versionCode is up to date and clears old APKs', () async {
    final stale = File('${updates().path}/hermes-display-3.apk');
    await stale.create(recursive: true);
    final service = updater(body: latest(code: 4));
    expect(await service.check(endpoint: endpoint), UpdateCheck.upToDate);
    expect(service.state.value.phase, UpdatePhase.idle);
    expect(requests, hasLength(1));
    expect(await stale.exists(), isFalse);
    expect(await service.install(), InstallResult.unsupported);
  });

  test('no release on the endpoint (404) is up to date', () async {
    final service = updater(body: '{"error":"no release"}', status: 404);
    expect(await service.check(endpoint: endpoint), UpdateCheck.upToDate);
  });

  test('hash mismatch discards the download', () async {
    final service = updater(apkBytes: utf8.encode('tampered'));
    expect(await service.check(endpoint: endpoint), UpdateCheck.failed);
    expect(service.state.value.phase, UpdatePhase.failed);
    expect(updates().listSync(), isEmpty);
    expect(await service.install(), InstallResult.unsupported);
  });

  test('server errors and malformed bodies fail', () async {
    expect(
      await updater(status: 500).check(endpoint: endpoint),
      UpdateCheck.failed,
    );
    expect(
      await updater(body: '{"versionCode":5}').check(endpoint: endpoint),
      UpdateCheck.failed,
    );
  });

  test('without a known installed version nothing is fetched', () async {
    platform.installed = null;
    final service = updater();
    expect(await service.check(endpoint: endpoint), UpdateCheck.unsupported);
    expect(requests, isEmpty);
  });

  test('a verified APK on disk is reused, not downloaded again', () async {
    final service = updater();
    await service.check(endpoint: endpoint);
    requests.clear();
    expect(await updater().check(endpoint: endpoint), UpdateCheck.ready);
    expect(requests, [endpoint]);
  });

  test('a failing later check keeps the ready APK', () async {
    var status = 200;
    final service = AppUpdater(
      platform: platform,
      client: MockClient((request) async {
        if (request.url.path.endsWith('.apk')) {
          return http.Response.bytes(apk, 200);
        }
        return http.Response(latest(), status);
      }),
      cacheRoot: () async => cache,
    );
    expect(await service.check(endpoint: endpoint), UpdateCheck.ready);
    status = 503;
    expect(await service.check(endpoint: endpoint), UpdateCheck.ready);
    expect(service.state.value.phase, UpdatePhase.ready);
    expect(await service.install(), InstallResult.started);
  });

  test('checks on start, then once inside the night window', () {
    fakeAsync((async) {
      var now = DateTime(2026, 10, 2, 20);
      final calls = <Uri>[];
      final service = AppUpdater(
        platform: platform,
        client: MockClient((request) async {
          calls.add(request.url);
          // 404 keeps the check free of file IO, which fakeAsync stalls.
          return http.Response('', 404);
        }),
        cacheRoot: () async => cache,
        clock: () => now,
      )..start(endpoint, DimSettings.defaults);
      async.flushMicrotasks();
      expect(calls, hasLength(1));

      async.elapse(const Duration(hours: 2));
      expect(calls, hasLength(1));

      now = DateTime(2026, 10, 2, 23, 5);
      async.elapse(UpdateDefaults.tick);
      async.elapse(UpdateDefaults.tick * 4);
      expect(calls, hasLength(2));

      now = DateTime(2026, 10, 3, 23, 5);
      async.elapse(UpdateDefaults.tick);
      expect(calls, hasLength(3));
      service.dispose();
    });
  });

  test('parseUrl accepts only absolute http(s)', () {
    expect(AppUpdater.parseUrl(' https://x.dev/latest.json '), isNotNull);
    expect(AppUpdater.parseUrl('ftp://x.dev/a'), isNull);
    expect(AppUpdater.parseUrl('/api/app/latest'), isNull);
  });
}
