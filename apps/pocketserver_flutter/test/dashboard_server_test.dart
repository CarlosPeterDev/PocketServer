import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketserver_flutter/dashboard_server.dart';
import 'package:pocketserver_flutter/file_library.dart';

void main() {
  test('requires login and streams an imported file after authorization', () async {
    final root = await Directory.systemTemp.createTemp('pocket-dashboard-');
    addTearDown(() => root.delete(recursive: true));
    final source = File.fromUri(root.uri.resolve('sample.txt'));
    await source.writeAsString('PocketServer file');
    final library = FileLibrary(Directory.fromUri(root.uri.resolve('library')));
    await library.importFile(XFile(source.path));
    final server = await DashboardServer.start(library);
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final anonymous = await (await client.getUrl(server.url)).close();
    expect(anonymous.statusCode, HttpStatus.unauthorized);
    await anonymous.drain<void>();

    Future<HttpClientResponse> get(Uri url) async {
      final request = await client.getUrl(url);
      final credentials = base64.encode(utf8.encode('pocketserver:${server.password}'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $credentials');
      return request.close();
    }

    Future<int> upload(String origin) async {
      final uri = server.url.resolve('/upload?name=from-browser.txt');
      final request = await client.putUrl(uri);
      final credentials = base64.encode(
        utf8.encode('pocketserver:${server.password}'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $credentials');
      request.headers.set('origin', origin);
      request.headers.set('x-pocketserver-upload', '1');
      request.write('Browser import');
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    expect(await upload('https://other.example'), HttpStatus.forbidden);
    expect(await upload(server.url.origin), HttpStatus.created);
    final imported = (await library.list()).firstWhere(
      (file) => FileLibrary.nameOf(file) == 'from-browser.txt',
    );
    expect(await imported.readAsString(), 'Browser import');

    final dashboard = await get(server.url);
    expect(dashboard.statusCode, HttpStatus.ok);
    final html = await utf8.decoder.bind(dashboard).join();
    final path = RegExp(r'href="(/download/[^"]+)">sample.txt').firstMatch(html)!.group(1)!;
    final downloaded = await get(server.url.resolve(path));
    expect(downloaded.statusCode, HttpStatus.ok);
    expect(await utf8.decoder.bind(downloaded).join(), 'PocketServer file');
    final missing = await get(server.url.resolve('/download/missing'));
    expect(missing.statusCode, HttpStatus.notFound);
    await missing.drain<void>();
  });

  test('refuses to bind plaintext HTTP to a LAN interface', () async {
    final library = FileLibrary(Directory.systemTemp);
    await expectLater(
      DashboardServer.start(library, address: InternetAddress('192.168.1.99')),
      throwsArgumentError,
    );
  });
}
