import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'quiz_parser.dart';

/// Extracts the text of a Word (.docx) file, one paragraph per line, offline.
///  - Bold or highlighted runs are wrapped in [markOn]/[markOff] so the parser can spot a correct
///    answer the teacher made bold.
///  - Word's automatic numbering ("1.", "a.") is not stored as text, so it is rebuilt from
///    numbering.xml; otherwise auto-numbered questions and choices would lose their numbers.
String docxToText(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String? read(String name) {
    final f = archive.findFile(name);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final doc = read('word/document.xml');
  if (doc == null) throw const FormatException('This file is not a Word document (.docx).');
  final formats = _numberFormats(read('word/numbering.xml'));
  final counters = <String, List<int>>{};

  final out = StringBuffer();
  for (final p in RegExp(r'<w:p[ >][\s\S]*?</w:p>').allMatches(doc)) {
    final para = p.group(0)!;
    final line = StringBuffer();

    final numId = RegExp(r'<w:numId w:val="(\d+)"').firstMatch(para)?.group(1);
    final ilvl = int.tryParse(RegExp(r'<w:ilvl w:val="(\d+)"').firstMatch(para)?.group(1) ?? '0') ?? 0;
    if (numId != null && numId != '0') {
      final c = counters.putIfAbsent(numId, () => List<int>.filled(9, 0));
      c[ilvl] = c[ilvl] + 1;
      for (var k = ilvl + 1; k < 9; k++) {
        c[k] = 0;
      }
      final fmt = formats['$numId:$ilvl'] ?? (ilvl == 0 ? 'decimal' : 'lowerLetter');
      final label = _label(fmt, c[ilvl]);
      if (label.isNotEmpty) line.write('$label ');
    }

    for (final r in RegExp(r'<w:r[ >][\s\S]*?</w:r>').allMatches(para)) {
      final run = r.group(0)!;
      final props = RegExp(r'<w:rPr>[\s\S]*?</w:rPr>').firstMatch(run)?.group(0) ?? '';
      final bold = RegExp(r'<w:b(?:\s+w:val="(?:1|true|on)")?\s*/>').hasMatch(props) || props.contains('<w:highlight');
      final text = StringBuffer();
      for (final t in RegExp(r'<w:t(?:\s[^>]*)?>([\s\S]*?)</w:t>|<w:tab\s*/>|<w:br\s*/>').allMatches(run)) {
        final whole = t.group(0)!;
        if (whole.startsWith('<w:tab')) {
          text.write(' ');
        } else if (whole.startsWith('<w:br')) {
          text.write('\n');
        } else {
          text.write(_unescape(t.group(1) ?? ''));
        }
      }
      if (text.isEmpty) continue;
      line.write(bold ? '$markOn$text$markOff' : text.toString());
    }
    out.writeln(line.toString());
  }
  return out.toString();
}

Map<String, String> _numberFormats(String? xml) {
  final result = <String, String>{};
  if (xml == null) return result;
  final abstractFormats = <String, Map<int, String>>{};
  for (final a in RegExp(r'<w:abstractNum [^>]*w:abstractNumId="(\d+)"[\s\S]*?</w:abstractNum>').allMatches(xml)) {
    final levels = <int, String>{};
    for (final l in RegExp(r'<w:lvl [^>]*w:ilvl="(\d+)"[\s\S]*?</w:lvl>').allMatches(a.group(0)!)) {
      final fmt = RegExp(r'<w:numFmt w:val="(\w+)"').firstMatch(l.group(0)!)?.group(1);
      if (fmt != null) levels[int.parse(l.group(1)!)] = fmt;
    }
    abstractFormats[a.group(1)!] = levels;
  }
  for (final n in RegExp(r'<w:num [^>]*w:numId="(\d+)"[\s\S]*?</w:num>').allMatches(xml)) {
    final abs = RegExp(r'<w:abstractNumId w:val="(\d+)"').firstMatch(n.group(0)!)?.group(1);
    final levels = abstractFormats[abs];
    if (levels == null) continue;
    levels.forEach((lvl, fmt) => result['${n.group(1)}:$lvl'] = fmt);
  }
  return result;
}

String _label(String fmt, int n) {
  switch (fmt) {
    case 'decimal':
      return '$n.';
    case 'lowerLetter':
      return '${String.fromCharCode(96 + ((n - 1) % 26) + 1)}.';
    case 'upperLetter':
      return '${String.fromCharCode(64 + ((n - 1) % 26) + 1)}.';
    case 'lowerRoman':
      return '${_roman(n).toLowerCase()}.';
    case 'upperRoman':
      return '${_roman(n)}.';
    default:
      return ''; // bullets and others carry no number
  }
}

String _roman(int n) {
  const values = [10, 9, 5, 4, 1];
  const symbols = ['X', 'IX', 'V', 'IV', 'I'];
  final b = StringBuffer();
  var x = n;
  for (var i = 0; i < values.length; i++) {
    while (x >= values[i]) {
      b.write(symbols[i]);
      x -= values[i];
    }
  }
  return b.toString();
}

String _unescape(String s) => s
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
