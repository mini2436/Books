import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

bool get usesPlatformPdfFileViewer =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS;

Future<Object?> preparePlatformPdfFile(Uint8List bytes) async {
  if (!usesPlatformPdfFileViewer) {
    return null;
  }

  final directory = await getTemporaryDirectory();
  final signature = bytes.isEmpty
      ? 'empty'
      : '${bytes.length}-${bytes.first}-${bytes.last}';
  final file = File('${directory.path}/private_reader_pdf_$signature.pdf');
  if (!await file.exists() || await file.length() != bytes.length) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return file;
}

Widget buildPlatformPdfViewer({
  required Uint8List bytes,
  required Object? file,
  required PdfViewerController controller,
  required int initialPageNumber,
  required PdfDocumentLoadedCallback onDocumentLoaded,
  required PdfPageChangedCallback onPageChanged,
  required PdfDocumentLoadFailedCallback onDocumentLoadFailed,
}) {
  final commonInitialPage = initialPageNumber.clamp(1, 999999);
  if (usesPlatformPdfFileViewer && file is File) {
    return SfPdfViewer.file(
      file,
      key: ValueKey(file.path),
      controller: controller,
      initialPageNumber: commonInitialPage,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      enableDoubleTapZooming: true,
      enableTextSelection: true,
      pageSpacing: 10,
      onDocumentLoaded: onDocumentLoaded,
      onPageChanged: onPageChanged,
      onDocumentLoadFailed: onDocumentLoadFailed,
    );
  }

  return SfPdfViewer.memory(
    bytes,
    key: ValueKey('memory-${bytes.length}'),
    controller: controller,
    initialPageNumber: commonInitialPage,
    canShowScrollHead: true,
    canShowScrollStatus: true,
    enableDoubleTapZooming: true,
    enableTextSelection: true,
    pageSpacing: 10,
    onDocumentLoaded: onDocumentLoaded,
    onPageChanged: onPageChanged,
    onDocumentLoadFailed: onDocumentLoadFailed,
  );
}
