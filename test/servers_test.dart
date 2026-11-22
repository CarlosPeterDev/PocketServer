import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocketserver/config.dart';
import 'package:pocketserver/host/dav_server.dart';
import 'package:pocketserver/host/ftp_server.dart';
import 'package:pocketserver/host/login_guard.dart';
import 'package:pocketserver/host/share_store.dart';
import 'package:pocketserver/host/tls_cert.dart';
import 'package:pocketserver/host/web_server.dart';

Future<int> freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

/// Tiny FTP client used to exercise the server over real sockets.
class Ftp {
  Ftp._(this.sock);
  Socket sock;
  StreamSubscription<String>? _sub;
  final _lines = <String>[];
  Completer<void>? _wake;
  String _partial = '';

  static Future<Ftp> connect(int port, {bool implicit = false}) async {
    final Socket s = implicit
        ? await SecureSocket.connect('127.0.0.1', port, onBadCertificate: (_) => true)
        : await Socket.connect('127.0.0.1', port);
    final c = Ftp._(s).._attach();
    return c;
  }

  void _attach() {
    _sub = sock.cast<List<int>>().transform(utf8.decoder).listen((t) {
      _partial += t;
      while (true) {
        final i = _partial.indexOf('\n');
        if (i < 0) break;
        _lines.add(_partial.substring(0, i).replaceAll('\r', ''));
        _partial = _partial.substring(i + 1);
      }
      _wake?.complete();
    });
  }

  Future<String> _line() async {
    while (_lines.isEmpty) {
      _wake = Completer<void>();
      await _wake!.future.timeout(const Duration(seconds: 15), onTimeout: () => throw 'timeout waiting for reply');
    }
    return _lines.removeAt(0);
  }

  Future<String> reply() async {
    var l = await _line();
    if (l.length > 3 && l[3] == '-') {
      final code = l.substring(0, 3);
      while (true) {
        final n = await _line();
        if (n.startsWith('$code ')) {
          l = n;
          break;
        }
      }
    }
    return l;
  }

  Future<String> cmd(String c) async {
    sock.write('$c\r\n');
    return reply();
  }

  Future<void> startTls() async {
    _sub!.pause(); // cancelling would close the socket
    sock = await SecureSocket.secure(sock, onBadCertificate: (_) => true);
    _attach();
  }

  Future<bool> login(String u, String pw) async {
    var r = await cmd('USER $u');
    if (!r.startsWith('331')) return false;
    r = await cmd('PASS $pw');
    return r.startsWith('230');
  }

  Future<Socket> _data() async {
    final r = await cmd('EPSV');
    final m = RegExp(r'\(\|\|\|(\d+)\|\)').firstMatch(r);
    if (m == null) throw 'bad EPSV: $r';
    return Socket.connect('127.0.0.1', int.parse(m.group(1)!));
  }

  bool protP = false;

  Future<Socket> _maybeTls(Socket d) async {
    if (!protP) return d;
    final Socket s = await SecureSocket.secure(d, onBadCertificate: (_) => true);
    return s;
  }

  Future<List<int>> download(String cmdLine) async {
    var d = await _data();
    final r = await cmd(cmdLine);
    if (!r.startsWith('150')) {
      await d.close();
      throw 'download refused: $r';
    }
    d = await _maybeTls(d);
    final bytes = await d.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final done = await reply();
    if (!done.startsWith('226')) throw 'transfer failed: $done';
    return bytes;
  }

  Future<String> upload(String cmdLine, List<int> data) async {
    var d = await _data();
    final r = await cmd(cmdLine);
    if (!r.startsWith('150')) {
      await d.close();
      return r;
    }
    d = await _maybeTls(d);
    d.add(data);
    await d.flush();
    await d.close();
    return reply();
  }

  Future<void> close() async {
    try {
      await sock.close();
    } catch (_) {}
  }
}

FtpServerConfig ftpCfg(int port,
        {FtpMode mode = FtpMode.ftp, bool readOnly = false, bool anonymous = false, List<String>? folderIds}) =>
    FtpServerConfig(
      id: 'ftp$port',
      name: 'test',
      username: 'carlos',
      password: 'secret1',
      port: port,
      mode: mode,
      readOnly: readOnly,
      anonymous: anonymous,
      folderIds: folderIds,
    );

void main() {
  late Directory tmp;
  late SecurityContext tls;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pocketserver_test');
    tls = await TlsCert(Directory(p.join(tmp.path, 'tls'))).context();
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() => LoginGuard.i.clear());

  Future<(FtpServer, Directory)> startFtp(FtpServerConfig cfg) async {
    final root = await tmp.createTemp('ftproot');
    final s = FtpServer(cfg, [FtpRoot('root', root.path)], tls: cfg.mode == FtpMode.ftp ? null : tls);
    await s.start();
    return (s, root);
  }

  group('FTP', () {
    test('login, upload, download, list, rename, delete, mkdir', () async {
      final port = await freePort();
      final (srv, root) = await startFtp(ftpCfg(port));
      addTearDown(srv.stop);
      final c = await Ftp.connect(port);
      addTearDown(c.close);
      expect((await c.reply()).startsWith('220'), isTrue);
      expect(await c.login('carlos', 'wrong'), isFalse);
      expect(await c.login('carlos', 'secret1'), isTrue);
      expect(await c.cmd('PWD'), startsWith('257 "/"'));
      expect(await c.cmd('MKD docs'), startsWith('257'));
      expect(await c.upload('STOR docs/a.txt', utf8.encode('hello world')), startsWith('226'));
      expect(File(p.join(root.path, 'docs', 'a.txt')).readAsStringSync(), 'hello world');
      expect(await c.cmd('SIZE docs/a.txt'), '213 11');
      expect(utf8.decode(await c.download('RETR docs/a.txt')), 'hello world');
      expect(utf8.decode(await c.download('LIST docs')), contains('a.txt'));
      expect(utf8.decode(await c.download('MLSD docs')), contains('type=file;size=11'));
      expect(utf8.decode(await c.download('NLST docs')).trim(), 'a.txt');
      expect(await c.cmd('RNFR docs/a.txt'), startsWith('350'));
      expect(await c.cmd('RNTO docs/b.txt'), startsWith('250'));
      expect(File(p.join(root.path, 'docs', 'b.txt')).existsSync(), isTrue);
      expect(await c.cmd('DELE docs/b.txt'), startsWith('250'));
      expect(await c.cmd('RMD docs'), startsWith('250'));
      expect(Directory(p.join(root.path, 'docs')).existsSync(), isFalse);
      // resume
      File(p.join(root.path, 'big.bin')).writeAsBytesSync(List.generate(1000, (i) => i % 256));
      expect(await c.cmd('REST 990'), startsWith('350'));
      final tail = await c.download('RETR big.bin');
      expect(tail.length, 10);
      expect(tail.first, 990 % 256);
    });

    test('cannot escape the root and hidden files are invisible', () async {
      final port = await freePort();
      final (srv, root) = await startFtp(ftpCfg(port));
      addTearDown(srv.stop);
      File(p.join(root.path, '.secret')).writeAsStringSync('x');
      final c = await Ftp.connect(port);
      addTearDown(c.close);
      await c.reply();
      await c.login('carlos', 'secret1');
      await c.cmd('CWD ../../..');
      expect(await c.cmd('PWD'), startsWith('257 "/"'));
      expect(await c.cmd('SIZE .secret'), startsWith('550'));
      expect(await c.cmd('SIZE ../../etc/passwd'), startsWith('550'));
      expect(utf8.decode(await c.download('LIST')), isNot(contains('.secret')));
    });

    test('read-only server refuses writes', () async {
      final port = await freePort();
      final (srv, _) = await startFtp(ftpCfg(port, readOnly: true));
      addTearDown(srv.stop);
      final c = await Ftp.connect(port);
      addTearDown(c.close);
      await c.reply();
      await c.login('carlos', 'secret1');
      expect(await c.upload('STOR x.txt', [1, 2, 3]), startsWith('550'));
      expect(await c.cmd('MKD d'), startsWith('550'));
    });

    test('anonymous login is read-only', () async {
      final port = await freePort();
      final (srv, root) = await startFtp(ftpCfg(port, anonymous: true));
      addTearDown(srv.stop);
      File(p.join(root.path, 'pub.txt')).writeAsStringSync('pub');
      final c = await Ftp.connect(port);
      addTearDown(c.close);
      await c.reply();
      expect(await c.login('anonymous', 'a@b.c'), isTrue);
      expect(utf8.decode(await c.download('RETR pub.txt')), 'pub');
      expect(await c.upload('STOR no.txt', [1]), startsWith('550'));
    });

    test('merged folders appear as top-level directories', () async {
      final port = await freePort();
      final a = await tmp.createTemp('mA');
      final b = await tmp.createTemp('mB');
      File(p.join(b.path, 'in_b.txt')).writeAsStringSync('b');
      final srv = FtpServer(ftpCfg(port), [FtpRoot('Alpha', a.path), FtpRoot('Beta', b.path)]);
      await srv.start();
      addTearDown(srv.stop);
      final c = await Ftp.connect(port);
      addTearDown(c.close);
      await c.reply();
      await c.login('carlos', 'secret1');
      final top = utf8.decode(await c.download('LIST'));
      expect(top, contains('Alpha'));
      expect(top, contains('Beta'));
      expect(await c.upload('STOR /Alpha/x.txt', utf8.encode('x')), startsWith('226'));
      expect(File(p.join(a.path, 'x.txt')).existsSync(), isTrue);
      expect(utf8.decode(await c.download('RETR /Beta/in_b.txt')), 'b');
      expect(await c.cmd('CWD /Beta'), startsWith('250'));
      expect(utf8.decode(await c.download('NLST')), contains('in_b.txt'));
    });

    test('too many failed logins lock the address out', () async {
      final port = await freePort();
      final (srv, _) = await startFtp(ftpCfg(port));
      addTearDown(srv.stop);
      for (var i = 0; i < LoginGuard.maxFails; i++) {
        final c = await Ftp.connect(port);
        await c.reply();
        expect(await c.login('carlos', 'bad$i'), isFalse);
        await c.close();
      }
      final c = await Ftp.connect(port);
      addTearDown(c.close);
      await c.reply();
      await c.cmd('USER carlos');
      expect(await c.cmd('PASS secret1'), contains('Too many'));
    });

    test('explicit FTPS (AUTH TLS) with encrypted data channel', () async {
      final port = await freePort();
      final (srv, root) = await startFtp(ftpCfg(port, mode: FtpMode.ftpsExplicit));
      addTearDown(srv.stop);
      final c = await Ftp.connect(port);
      addTearDown(c.close);
      await c.reply();
      expect(await c.cmd('USER carlos'), startsWith('530')); // TLS required first
      expect(await c.cmd('AUTH TLS'), startsWith('234'));
      await c.startTls();
      expect(await c.login('carlos', 'secret1'), isTrue);
      expect(await c.cmd('PBSZ 0'), startsWith('200'));
      expect(await c.cmd('PROT P'), startsWith('200'));
      c.protP = true;
      expect(await c.upload('STOR t.txt', utf8.encode('tls data')), startsWith('226'));
      expect(File(p.join(root.path, 't.txt')).readAsStringSync(), 'tls data');
      expect(utf8.decode(await c.download('RETR t.txt')), 'tls data');
      expect(utf8.decode(await c.download('LIST')), contains('t.txt'));
    });

    test('implicit FTPS', () async {
      final port = await freePort();
      final (srv, root) = await startFtp(ftpCfg(port, mode: FtpMode.ftpsImplicit));
      addTearDown(srv.stop);
      final c = await Ftp.connect(port, implicit: true);
      addTearDown(c.close);
      expect((await c.reply()).startsWith('220'), isTrue);
      expect(await c.login('carlos', 'secret1'), isTrue);
      await c.cmd('PBSZ 0');
      await c.cmd('PROT P');
      c.protP = true;
      expect(await c.upload('STOR i.txt', utf8.encode('implicit')), startsWith('226'));
      expect(File(p.join(root.path, 'i.txt')).readAsStringSync(), 'implicit');
    });
  });

  group('WebDAV', () {
    late DavServer dav;
    late Directory root;
    late int port;
    late HttpClient http;
    final auth = 'Basic ${base64.encode(utf8.encode('carlos:secret1'))}';

    setUp(() async {
      root = await tmp.createTemp('davroot');
      port = await freePort();
      dav = DavServer(
          DavConfig(id: 'dav', name: 'dav', username: 'carlos', password: 'secret1', port: port), root.path);
      await dav.start();
      http = HttpClient();
    });
    tearDown(() async {
      http.close(force: true);
      await dav.stop();
    });

    Future<(int, String, HttpHeaders)> req(String method, String path,
        {String? body, Map<String, String>? headers, bool authed = true}) async {
      final r = await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
      if (authed) r.headers.set('authorization', auth);
      headers?.forEach(r.headers.set);
      if (body != null) r.add(utf8.encode(body));
      final res = await r.close();
      final text = await res.transform(utf8.decoder).join();
      return (res.statusCode, text, res.headers);
    }

    test('auth required', () async {
      expect((await req('PROPFIND', '/', authed: false)).$1, 401);
      final bad = await http.openUrl('GET', Uri.parse('http://127.0.0.1:$port/'));
      bad.headers.set('authorization', 'Basic ${base64.encode(utf8.encode('carlos:nope'))}');
      expect((await bad.close()).statusCode, 401);
      expect((await req('OPTIONS', '/', authed: false)).$1, 200);
    });

    test('full file lifecycle', () async {
      expect((await req('MKCOL', '/docs')).$1, 201);
      expect((await req('PUT', '/docs/a.txt', body: 'dav hello')).$1, 201);
      expect(File(p.join(root.path, 'docs', 'a.txt')).readAsStringSync(), 'dav hello');
      expect((await req('PUT', '/docs/a.txt', body: 'dav hello 2')).$1, 204);
      final get = await req('GET', '/docs/a.txt');
      expect(get.$1, 200);
      expect(get.$2, 'dav hello 2');
      final ranged = await req('GET', '/docs/a.txt', headers: {'range': 'bytes=4-8'});
      expect(ranged.$1, 206);
      expect(ranged.$2, 'hello');
      final pf = await req('PROPFIND', '/docs/', headers: {'depth': '1'});
      expect(pf.$1, 207);
      expect(pf.$2, contains('a.txt'));
      expect(pf.$2, contains('<D:getcontentlength>11</D:getcontentlength>'));
      expect((await req('COPY', '/docs/a.txt', headers: {'destination': 'http://127.0.0.1:$port/docs/c.txt'})).$1, 201);
      expect((await req('MOVE', '/docs/c.txt', headers: {'destination': 'http://127.0.0.1:$port/docs/d.txt'})).$1, 201);
      expect(File(p.join(root.path, 'docs', 'd.txt')).existsSync(), isTrue);
      expect(File(p.join(root.path, 'docs', 'c.txt')).existsSync(), isFalse);
      expect((await req('LOCK', '/docs/d.txt')).$1, 200);
      expect((await req('DELETE', '/docs/d.txt')).$1, 204);
      expect((await req('DELETE', '/docs')).$1, 204);
      expect((await req('GET', '/docs/a.txt')).$1, 404);
    });

    test('hidden files and traversal are blocked', () async {
      File(p.join(root.path, '.hidden')).writeAsStringSync('h');
      expect((await req('GET', '/.hidden')).$1, 403);
      expect((await req('GET', '/%2e%2e/%2e%2e/etc/passwd')).$1, anyOf(403, 404));
    });

    test('read-only server refuses writes', () async {
      final ro = DavServer(
          DavConfig(id: 'r', name: 'r', username: 'carlos', password: 'secret1', port: await freePort(), readOnly: true),
          root.path);
      await ro.start();
      addTearDown(ro.stop);
      final r = await http.openUrl('PUT', Uri.parse('http://127.0.0.1:${ro.cfg.port}/x.txt'));
      r.headers.set('authorization', auth);
      r.add([1]);
      expect((await r.close()).statusCode, 403);
    });
  });

  group('Web hub', () {
    late WebServer web;
    late Directory root;
    late int port;
    late HttpClient http;
    String cookie = '';

    setUp(() async {
      root = await tmp.createTemp('webroot');
      port = await freePort();
      web = WebServer(ShareStore(root.path), port, id: 'webtest');
      await web.start();
      http = HttpClient();
      cookie = '';
    });
    tearDown(() async {
      http.close(force: true);
      await web.stop();
    });

    Future<(int, String, HttpHeaders)> call(String method, String path,
        {Object? json, List<int>? raw, String? contentType, Map<String, String>? headers}) async {
      final r = await http.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
      if (cookie.isNotEmpty) r.headers.set('cookie', cookie);
      headers?.forEach(r.headers.set);
      if (json != null) {
        r.headers.contentType = ContentType.json;
        r.add(utf8.encode(jsonEncode(json)));
      } else if (raw != null) {
        r.headers.set('content-type', contentType ?? 'application/octet-stream');
        r.add(raw);
      }
      final res = await r.close();
      final text = await res.transform(utf8.decoder).join();
      final sc = res.headers['set-cookie'];
      if (sc != null && sc.isNotEmpty) cookie = sc.first.split(';').first;
      return (res.statusCode, text, res.headers);
    }

    Future<(int, String, HttpHeaders)> upload(String name, String content, {String path = ''}) {
      const b = '----pocketboundary';
      final body = BytesBuilder()
        ..add(utf8.encode('--$b\r\nContent-Disposition: form-data; name="path"\r\n\r\n$path\r\n'))
        ..add(utf8.encode(
            '--$b\r\nContent-Disposition: form-data; name="files[]"; filename="$name"\r\nContent-Type: text/plain\r\n\r\n'))
        ..add(utf8.encode(content))
        ..add(utf8.encode('\r\n--$b--\r\n'));
      return call('POST', '/api/upload', raw: body.toBytes(), contentType: 'multipart/form-data; boundary=$b');
    }

    test('serves the web UI and the TV page', () async {
      final home = await call('GET', '/');
      expect(home.$1, 200);
      expect(home.$2, contains('PocketServer'));
      final tv = await call('GET', '/tv');
      expect(tv.$1, 200);
      expect(tv.$2, contains('PocketServer TV'));
    });

    test('register, login, upload, list, download, range, delete', () async {
      expect((await call('GET', '/api/me')).$1, 200);
      expect((await call('POST', '/api/register', json: {'username': 'carlos', 'password': 'secret1'})).$1, 200);
      expect((await upload('hello.txt', 'hello from web')).$1, 200);
      expect(File(p.join(root.path, 'hello.txt')).readAsStringSync(), 'hello from web');
      final list = await call('GET', '/api/files?path=');
      expect(list.$1, 200);
      final items = (jsonDecode(list.$2) as Map)['items'] as List;
      expect(items.any((e) => (e as Map)['name'] == 'hello.txt'), isTrue);
      final file = await call('GET', '/file/hello.txt');
      expect(file.$1, 200);
      expect(file.$2, 'hello from web');
      // text files are served whole; binary / media files honour Range (video seeking)
      expect((await upload('clip.mp4', 'abcdefghij')).$1, 200);
      final ranged = await call('GET', '/file/clip.mp4', headers: {'range': 'bytes=2-5'});
      expect(ranged.$1, 206);
      expect(ranged.$2, 'cdef');
      expect(ranged.$3.value('content-range'), 'bytes 2-5/10');
      final dl = await call('GET', '/download/hello.txt');
      expect(dl.$1, 200);
      expect(dl.$3.value('content-disposition'), contains('hello.txt'));
      expect((await call('POST', '/api/folder', json: {'path': '', 'name': 'sub'})).$1, 200);
      expect(Directory(p.join(root.path, 'sub')).existsSync(), isTrue);
    });

    test('wrong password is rejected and repeated failures lock out', () async {
      await call('POST', '/api/register', json: {'username': 'carlos', 'password': 'secret1'});
      cookie = '';
      expect((await call('POST', '/api/login', json: {'username': 'carlos', 'password': 'nope'})).$1, 401);
      for (var i = 0; i < LoginGuard.maxFails; i++) {
        await call('POST', '/api/login', json: {'username': 'carlos', 'password': 'bad$i'});
      }
      expect((await call('POST', '/api/login', json: {'username': 'carlos', 'password': 'secret1'})).$1, 429);
    });

    test('path traversal is refused', () async {
      await call('POST', '/api/register', json: {'username': 'carlos', 'password': 'secret1'});
      final r = await call('GET', '/file/..%2f..%2f..%2fetc%2fpasswd');
      expect(r.$1, anyOf(400, 403, 404));
      final r2 = await call('GET', '/api/files?path=../../..');
      expect(r2.$2, isNot(contains('passwd')));
    });
  });
}
