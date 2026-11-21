import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart' as pc;

/// Loads (or creates once and caches) a self-signed certificate used by the
/// FTPS servers. Key generation is CPU heavy, so it runs in a worker isolate.
class TlsCert {
  TlsCert(this.dir);
  final Directory dir;
  SecurityContext? _ctx;
  Future<SecurityContext>? _pending;

  Future<SecurityContext> context() {
    if (_ctx != null) return Future.value(_ctx!);
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  Future<SecurityContext> _load() async {
    await dir.create(recursive: true);
    final certFile = File(p.join(dir.path, 'cert.pem'));
    final keyFile = File(p.join(dir.path, 'key.pem'));
    if (!(await certFile.exists() && await keyFile.exists())) {
      final pems = await Isolate.run(_generate);
      await certFile.writeAsString(pems[0]);
      await keyFile.writeAsString(pems[1]);
    }
    final ctx = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(await certFile.readAsBytes())
      ..usePrivateKeyBytes(await keyFile.readAsBytes());
    _ctx = ctx;
    return ctx;
  }

  /// SHA-256 style fingerprint is not needed; the user just accepts the
  /// self-signed certificate in their FTP client.
  static List<String> _generate() {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final priv = pair.privateKey as pc.RSAPrivateKey;
    final pub = pair.publicKey as pc.RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'PocketServer', 'O': 'PocketServer'},
      priv,
      pub,
    );
    final cert = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
    final key = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
    return [cert, key];
  }
}
