import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

bool get usesPlatformPdfFileViewer => false;

Future<Object?> preparePlatformPdfFile(Uint8List bytes) async => null;

Widget buildPlatformPdfViewer({
  required Uint8List bytes,
  required Object? file,
  required PdfViewerController controller,
  required int initialPageNumber,
  required PdfDocumentLoadedCallback onDocumentLoaded,
  required PdfPageChangedCallback onPageChanged,
  required PdfDocumentLoadFailedCallback onDocumentLoadFailed,
}) {
  return SfPdfViewer.memory(
    bytes,
    key: ValueKey('memory-${bytes.length}'),
    controller: controller,
    initialPageNumber: initialPageNumber,
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
