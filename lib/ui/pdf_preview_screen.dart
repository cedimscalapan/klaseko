import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/export/share.dart';

/// Shows a generated PDF with Print and Share buttons. Printing uses the phone's own print
/// service (Wi-Fi or USB printers, or Save as PDF), so no internet is needed.
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({super.key, required this.title, required this.fileName, required this.build});
  final String title;
  final String fileName;
  final Future<Uint8List> Function() build;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  late final Future<Uint8List> _bytes = widget.build();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Share or save',
            icon: const Icon(Icons.ios_share),
            onPressed: () async => saveAndShare(await _bytes, widget.fileName, pdfMime),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => _bytes,
        pdfFileName: safeFileName(widget.fileName),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowSharing: false,
        allowPrinting: true,
        loadingWidget: const Center(child: CircularProgressIndicator()),
        onError: (context, error) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not make the PDF: $error'))),
      ),
    );
  }
}
