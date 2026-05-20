import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  await runZonedGuarded(
    () => _runServer(args),
    (error, stackTrace) {
      _writeLog('Serverfehler: $error\n$stackTrace');
    },
  );
}

Future<void> _runServer(List<String> args) async {
  final port = _readIntArg(args, '--port', 52733);
  final rootPath = _readStringArg(args, '--root', 'build/web');
  final root = Directory(rootPath).absolute;

  if (!root.existsSync()) {
    stderr.writeln('Preview root not found: ${root.path}');
    exitCode = 1;
    return;
  }

  final server = await HttpServer.bind(
    InternetAddress.anyIPv6,
    port,
    v6Only: false,
  );
  final keepAlive = Timer.periodic(const Duration(hours: 1), (_) {});
  _writeStatus('Vorschau laeuft auf http://localhost:$port');
  server.listen((request) async {
    try {
      await _handleRequest(request, root);
    } catch (error, stackTrace) {
      _writeLog('Requestfehler: $error\n$stackTrace');
      try {
        await request.response.close();
      } catch (_) {
        // Client already disconnected.
      }
    }
  });
  await Completer<void>().future;
  keepAlive.cancel();
}

void _writeStatus(String message) {
  try {
    stdout.writeln(message);
  } catch (_) {
    // Hidden preview processes may not have a writable console.
  }
}

void _writeLog(String message) {
  try {
    File('preview_server_errors.log')
        .writeAsStringSync('$message\n', mode: FileMode.append);
  } catch (_) {
    // Best effort only.
  }
}

Future<void> _handleRequest(HttpRequest request, Directory root) async {
  final uriPath = Uri.decodeComponent(request.uri.path);
  final relativePath = uriPath == '/' ? 'index.html' : uriPath.substring(1);
  final requested = File('${root.path}${Platform.pathSeparator}$relativePath');
  final file = requested.existsSync()
      ? requested
      : File('${root.path}${Platform.pathSeparator}index.html');

  request.response.headers
    ..set(HttpHeaders.cacheControlHeader, 'no-store')
    ..contentType = _contentType(file.path);
  await file.openRead().pipe(request.response);
}

ContentType _contentType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html')) return ContentType.html;
  if (lower.endsWith('.js')) {
    return ContentType('application', 'javascript', charset: 'utf-8');
  }
  if (lower.endsWith('.css')) {
    return ContentType('text', 'css', charset: 'utf-8');
  }
  if (lower.endsWith('.json')) return ContentType.json;
  if (lower.endsWith('.png')) return ContentType('image', 'png');
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return ContentType('image', 'jpeg');
  }
  if (lower.endsWith('.svg')) return ContentType('image', 'svg+xml');
  if (lower.endsWith('.wasm')) return ContentType('application', 'wasm');
  return ContentType.binary;
}

int _readIntArg(List<String> args, String name, int fallback) {
  final value = _readStringArg(args, name, '$fallback');
  return int.tryParse(value) ?? fallback;
}

String _readStringArg(List<String> args, String name, String fallback) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return fallback;
  }
  return args[index + 1];
}
