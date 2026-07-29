import 'package:web/web.dart' as web;

Future<void> startSystemBackupDownload(String url, String fileName) async {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  anchor.style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
