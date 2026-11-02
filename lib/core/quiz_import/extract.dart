import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import 'docx_text.dart';

/// Reads quiz text from a file or a photo, fully offline.
///  - .txt: decoded as text.
///  - .docx: paragraphs, Word numbering and bold answers (docx_text.dart).
///  - .pdf: every page is rendered and read with on-device text recognition, so typed and scanned
///    PDFs both work.
///  - photos: on-device text recognition (Google ML Kit, Latin script, bundled with the app).
class QuizExtractor {
  static const supported = ['txt', 'docx', 'pdf', 'jpg', 'jpeg', 'png', 'webp'];

  static Future<String> fromFile(String name, Uint8List bytes, {void Function(String)? progress}) async {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    switch (ext) {
      case 'txt':
        return utf8.decode(bytes, allowMalformed: true);
      case 'docx':
        return docxToText(bytes);
      case 'doc':
        throw const FormatException('Old Word files (.doc) cannot be read. In Word, use Save As > Word Document (.docx), then import again.');
      case 'pdf':
        return _pdf(bytes, progress);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return fromImageBytes(bytes, ext);
      default:
        throw FormatException('KlaseKo can read .docx, .pdf, .txt and photos. This file is .$ext.');
    }
  }

  static Future<String> fromImagePath(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      return _readingOrder(result);
    } finally {
      await recognizer.close();
    }
  }

  static Future<String> fromImageBytes(Uint8List bytes, String ext) async {
    final file = File(p.join((await getTemporaryDirectory()).path, 'quiz_${DateTime.now().microsecondsSinceEpoch}.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    try {
      return await fromImagePath(file.path);
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static Future<String> _pdf(Uint8List bytes, void Function(String)? progress) async {
    final out = StringBuffer();
    var page = 0;
    await for (final raster in Printing.raster(bytes, dpi: 200)) {
      page++;
      progress?.call('Reading page $page...');
      final png = await raster.toPng();
      out.writeln(await fromImageBytes(png, 'png'));
    }
    if (page == 0) throw const FormatException('The PDF has no pages.');
    return out.toString();
  }

  /// Puts recognised lines in reading order and joins pieces that sit on the same line, so choices
  /// printed side by side ("A. 5   B. 7") stay together.
  static String _readingOrder(RecognizedText result) {
    final lines = <TextLine>[for (final b in result.blocks) ...b.lines];
    if (lines.isEmpty) return '';
    lines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final rows = <List<TextLine>>[];
    for (final l in lines) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null) {
        final ref = row.first.boundingBox;
        final centre = l.boundingBox.center.dy;
        if (centre > ref.top && centre < ref.bottom) {
          row.add(l);
          continue;
        }
      }
      rows.add([l]);
    }
    final b = StringBuffer();
    for (final row in rows) {
      row.sort((a, c) => a.boundingBox.left.compareTo(c.boundingBox.left));
      b.writeln(row.map((l) => l.text).join('   '));
    }
    return b.toString();
  }
}
