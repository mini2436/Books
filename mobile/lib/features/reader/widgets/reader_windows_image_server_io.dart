import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class WindowsReaderImageServer {
  WindowsReaderImageServer._(this._server, this._sessionToken) {
    _subscription = _server.listen(_handleRequest);
  }

  final HttpServer _server;
  final String _sessionToken;
  final Map<String, _WindowsReaderImageResource> _resources = {};
  late final StreamSubscription<HttpRequest> _subscription;

  String urlFor(String fileName) => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    pathSegments: [_sessionToken, fileName],
  ).toString();

  void put(String fileName, String mediaType, Uint8List bytes) {
    _resources[fileName] = _WindowsReaderImageResource(mediaType, bytes);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (request.method != 'GET' ||
        segments.length != 2 ||
        segments.first != _sessionToken) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final resource = _resources[segments.last];
    if (resource == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.headers
      ..contentType = ContentType.parse(resource.mediaType)
      ..set(HttpHeaders.cacheControlHeader, 'private, max-age=3600')
      ..set(HttpHeaders.accessControlAllowOriginHeader, '*');
    request.response.contentLength = resource.bytes.length;
    request.response.add(resource.bytes);
    await request.response.close();
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _server.close(force: true);
    _resources.clear();
  }
}

Future<WindowsReaderImageServer?> createWindowsReaderImageServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final random = Random.secure();
  final token = base64UrlEncode(
    List<int>.generate(18, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
  return WindowsReaderImageServer._(server, token);
}

class _WindowsReaderImageResource {
  const _WindowsReaderImageResource(this.mediaType, this.bytes);

  final String mediaType;
  final Uint8List bytes;
}
