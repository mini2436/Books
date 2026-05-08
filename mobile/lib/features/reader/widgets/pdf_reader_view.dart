import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../shared/theme/reader_theme_extension.dart';
import 'pdf_viewer_source.dart';

class PdfReaderView extends StatefulWidget {
  const PdfReaderView({
    super.key,
    required this.bytes,
    required this.initialPage,
    required this.palette,
    required this.onPageChanged,
    required this.onDocumentLoaded,
  });

  final Uint8List bytes;
  final int initialPage;
  final AppReaderPalette palette;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onDocumentLoaded;

  @override
  State<PdfReaderView> createState() => _PdfReaderViewState();
}

class _PdfReaderViewState extends State<PdfReaderView> {
  late final PdfViewerController _controller;
  bool _didJumpToInitialPage = false;
  Object? _platformFile;
  bool _isPreparingPlatformFile = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _preparePlatformFile();
  }

  @override
  void didUpdateWidget(covariant PdfReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) {
      _didJumpToInitialPage = false;
      _platformFile = null;
      _loadError = null;
      _preparePlatformFile();
      return;
    }
    if (oldWidget.initialPage != widget.initialPage &&
        _controller.pageNumber != widget.initialPage) {
      _controller.jumpToPage(widget.initialPage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.palette.background,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isPreparingPlatformFile && usesPlatformPdfFileViewer) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _loadError!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: widget.palette.inkSecondary,
            ),
          ),
        ),
      );
    }

    return buildPlatformPdfViewer(
      bytes: widget.bytes,
      file: _platformFile,
      controller: _controller,
      initialPageNumber: widget.initialPage,
      onDocumentLoaded: (details) {
        final pageCount = details.document.pages.count;
        widget.onDocumentLoaded(pageCount);
        if (!_didJumpToInitialPage && widget.initialPage > 1) {
          _didJumpToInitialPage = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _controller.jumpToPage(widget.initialPage);
            }
          });
        }
      },
      onPageChanged: (details) {
        widget.onPageChanged(details.newPageNumber);
      },
      onDocumentLoadFailed: (details) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loadError = 'PDF 加载失败：${details.description}';
        });
      },
    );
  }

  Future<void> _preparePlatformFile() async {
    if (!usesPlatformPdfFileViewer) {
      return;
    }

    setState(() {
      _isPreparingPlatformFile = true;
    });

    try {
      final file = await preparePlatformPdfFile(widget.bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _platformFile = file;
        _isPreparingPlatformFile = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPreparingPlatformFile = false;
        _loadError = 'PDF 临时文件准备失败：$error';
      });
    }
  }
}
