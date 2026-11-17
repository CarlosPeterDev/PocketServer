import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'file_library.dart';

class DashboardServer {
  DashboardServer._(this._server, this.library, this.password, this.url);

  final HttpServer _server;
  final FileLibrary library;
  final String password;
  final Uri url;
  bool _uploading = false;
  static const _maxUploadBytes = 1024 * 1024 * 1024;

  static Future<DashboardServer> start(
    FileLibrary library, {
    InternetAddress? address,
    SecurityContext? tls,
  }) async {
    final host = address ?? InternetAddress.loopbackIPv4;
    if (host.type != InternetAddressType.IPv4 ||
        (!host.isLoopback && (tls == null || !isPrivateIPv4(host)))) {
      throw ArgumentError('LAN access requires HTTPS on a private IPv4 address.');
    }
    final server = tls == null
        ? await HttpServer.bind(host, 0, backlog: 16)
        : await HttpServer.bindSecure(host, 0, tls, backlog: 16);
    server.idleTimeout = const Duration(seconds: 10);
    final random = Random.secure();
    final password = base64Url.encode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    final dashboard = DashboardServer._(
      server,
      library,
      password,
      Uri(scheme: tls == null ? 'http' : 'https', host: host.address, port: server.port),
    );
    server.listen(dashboard._serve);
    return dashboard;
  }

  static bool isPrivateIPv4(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  bool _authenticated(String? value) {
    final expected = 'Basic ${base64.encode(utf8.encode('pocketserver:$password'))}';
    if (value == null || value.length != expected.length) return false;
    var different = 0;
    for (var index = 0; index < expected.length; index++) {
      different |= value.codeUnitAt(index) ^ expected.codeUnitAt(index);
    }
    return different == 0;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    final headers = response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('X-Frame-Options', 'DENY')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
    try {
      final hosts = request.headers[HttpHeaders.hostHeader];
      if (hosts == null || hosts.length != 1 || hosts.single != url.authority) {
        response.statusCode = HttpStatus.badRequest;
        return;
      }
      final auth = request.headers[HttpHeaders.authorizationHeader];
      if (auth?.length != 1 || !_authenticated(auth!.single)) {
        response.statusCode = HttpStatus.unauthorized;
        headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="PocketServer"');
        return;
      }
      if (request.uri.path == '/upload') {
        await _upload(request);
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        return;
      }

      if (request.uri.path == '/upload.js') {
        headers.contentType = ContentType('application', 'javascript', charset: 'utf-8');
        if (request.method == 'GET') response.write(_uploadScript);
        return;
      }
      final files = await library.list();
      if (request.uri.path == '/') {
        headers.contentType = ContentType.html;
        if (request.method == 'GET') {
          response.write(_page(files));
        }
        return;
      }

      final parts = request.uri.pathSegments;
      if (parts.length == 2 && parts.first == 'download') {
        final matches = files.where((file) => _id(file) == parts.last);
        final file = matches.isEmpty ? null : matches.first;
        if (file != null) {
          final filename = Uri.encodeComponent(FileLibrary.nameOf(file)).replaceAll("'", '%27');
          headers.contentType = ContentType.binary;
          headers.set('Content-Disposition', "attachment; filename*=UTF-8''$filename");
          response.contentLength = await file.length();
          if (request.method == 'GET') await response.addStream(file.openRead());
          return;
        }
      }
      response.statusCode = HttpStatus.notFound;
    } on IOException {
      // I/O can fail after a response starts, for example when a device disconnects.
      // Closing the response also terminates any incomplete download.
    } finally {
      try {
        await response.close();
      } on IOException {
        // The client disconnected before the response finished.
      }
    }
  }

  Future<void> _upload(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'PUT') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'PUT');
      return;
    }
    final origin = request.headers['origin'];
    final marker = request.headers['x-pocketserver-upload'];
    if (origin == null || origin.length != 1 || origin.single != url.origin ||
        marker == null || marker.length != 1 || marker.single != '1') {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    final name = request.uri.queryParameters['name'] ?? '';
    if (name.trim().isEmpty || utf8.encode(name).length > 240) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    if (request.contentLength > _maxUploadBytes) {
      response.statusCode = HttpStatus.requestEntityTooLarge;
      return;
    }
    if (_uploading) {
      response.statusCode = HttpStatus.conflict;
      return;
    }

    _uploading = true;
    var written = 0;
    try {
      final bytes = request.timeout(const Duration(seconds: 30)).map((chunk) {
        written += chunk.length;
        if (written > _maxUploadBytes) throw const _UploadLimit();
        return chunk;
      });
      await library.importStream(name, bytes);
      response.statusCode = HttpStatus.created;
    } on _UploadLimit {
      response.statusCode = HttpStatus.requestEntityTooLarge;
    } on Exception {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      _uploading = false;
    }
  }

  static String _id(File file) =>
      file.parent.path.split(Platform.pathSeparator).last;

  static String _page(List<File> files) {
    final links = files.map((file) {
      final title = const HtmlEscape().convert(FileLibrary.nameOf(file));
      return '<li><a href="/download/${Uri.encodeComponent(_id(file))}">$title</a></li>';
    }).join();
    return '''
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PocketServer</title><script defer src="/upload.js"></script>
<style>
:root{color-scheme:light dark;font:16px system-ui,sans-serif}
body{max-width:56rem;margin:2rem auto;padding:0 1rem}
section{border:1px solid gray;border-radius:16px;padding:1rem 1.4rem}
li{padding:.5rem 0;overflow-wrap:anywhere} a{color:inherit}
</style></head><body>
<h1>PocketServer</h1><main><section><h2>Files</h2>
<label>Choose a file <input id="file" type="file"></label>
<button id="upload" type="button">Upload</button>
<p id="status" role="status"></p>
${files.isEmpty ? '<p>No files in this library.</p>' : '<ul>$links</ul>'}
</section></main></body></html>
''';
  }
}

class _UploadLimit implements Exception {
  const _UploadLimit();
}

const _uploadScript = r'''
const picker = document.querySelector('#file');
const button = document.querySelector('#upload');
const status = document.querySelector('#status');
button.addEventListener('click', async () => {
  const file = picker.files[0];
  if (!file) {
    status.textContent = 'Choose a file first.';
    return;
  }
  if (file.size > 1024 * 1024 * 1024) {
    status.textContent = 'Maximum file size is 1 GiB.';
    return;
  }
  button.disabled = true;
  status.textContent = 'Uploading…';
  try {
    const response = await fetch('/upload?name=' + encodeURIComponent(file.name), {
      method: 'PUT',
      headers: {'X-PocketServer-Upload': '1'},
      body: file,
      credentials: 'same-origin',
    });
    if (response.status === 201) {
      location.reload();
      return;
    }
    status.textContent = 'Upload failed (' + response.status + ').';
  } catch {
    status.textContent = 'Connection lost. Try again.';
  } finally {
    button.disabled = false;
  }
});
''';
