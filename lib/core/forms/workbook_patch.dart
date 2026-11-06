import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Preserve every ZIP member except worksheets containing explicitly assigned cells.
/// This keeps drawings, formulas outside the assignments, print settings and styles.
Uint8List patchWorkbook(
    Uint8List source, Map<String, Map<String, String>> edits,
    {Set<String> textFields = const {}}) {
  final zip = ZipDecoder().decodeBytes(source);
  XmlDocument document(String path) =>
      XmlDocument.parse(utf8.decode(zip.findFile(path)!.content as List<int>));
  final book = document('xl/workbook.xml');
  final names =
      book.findAllElements('sheet').map((s) => s.getAttribute('name')).toSet();
  if (edits.keys.any((name) => !names.contains(name)))
    throw const FormatException(
        'Mapped worksheet is missing from this source edition.');
  final rels = document('xl/_rels/workbook.xml.rels');
  final targets = {
    for (final r in rels.findAllElements('Relationship'))
      r.getAttribute('Id')!: r.getAttribute('Target')!
  };
  final replacements = <String, List<int>>{};
  for (final sheet in book.findAllElements('sheet')) {
    final changes = edits[sheet.getAttribute('name')];
    if (changes == null || changes.isEmpty) continue;
    final rid = sheet.getAttribute('id',
        namespace:
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships');
    final target = targets[rid];
    if (target == null)
      throw const FormatException('Worksheet relationship is missing.');
    final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final doc = document(path);
    final data = doc.findAllElements('sheetData').single;
    for (final e in changes.entries) {
      final rowNo = int.parse(RegExp(r'\d+$').firstMatch(e.key)!.group(0)!);
      final row = data
              .findElements('row')
              .where((r) => r.getAttribute('r') == '$rowNo')
              .firstOrNull ??
          XmlElement(XmlName('row'), [XmlAttribute(XmlName('r'), '$rowNo')]);
      if (row.parent == null) {
        final following = data
            .findElements('row')
            .where((r) => int.parse(r.getAttribute('r')!) > rowNo)
            .firstOrNull;
        if (following == null) {
          data.children.add(row);
        } else {
          data.children.insert(data.children.indexOf(following), row);
        }
      }
      final cell = row
              .findElements('c')
              .where((c) => c.getAttribute('r') == e.key)
              .firstOrNull ??
          XmlElement(XmlName('c'), [XmlAttribute(XmlName('r'), e.key)]);
      if (cell.parent == null) row.children.add(cell);
      // Assignments are deliberate values, never user-provided executable formulas.
      cell.children.removeWhere(
          (n) => n is XmlElement && ['v', 'f', 'is'].contains(n.name.local));
      cell.attributes.removeWhere((a) => a.name.local == 't');
      if (e.value.isNotEmpty) {
        final number =
            textFields.contains('${sheet.getAttribute('name')}!${e.key}')
                ? null
                : num.tryParse(e.value);
        if (number != null && number.isFinite) {
          cell.children.add(XmlElement(XmlName('v'), [], [XmlText(e.value)]));
        } else {
          cell.attributes.add(XmlAttribute(XmlName('t'), 'inlineStr'));
          cell.children.add(XmlElement(XmlName('is'), [], [
            XmlElement(
                XmlName('t'),
                [XmlAttribute(XmlName('space', 'xml'), 'preserve')],
                [XmlText(e.value)])
          ]));
        }
      }
    }
    // Excel expects cells in column order, including newly inserted input cells.
    int column(String address) {
      var n = 0;
      for (final c
          in RegExp(r'^[A-Z]+').firstMatch(address)!.group(0)!.codeUnits) {
        n = n * 26 + c - 64;
      }
      return n;
    }

    for (final row in data.findElements('row')) {
      final cells = row.findElements('c').toList()
        ..sort((a, b) => column(a.getAttribute('r')!)
            .compareTo(column(b.getAttribute('r')!)));
      row.children.removeWhere((n) => n is XmlElement && n.name.local == 'c');
      row.children.addAll(cells);
    }
    replacements[path] = utf8.encode(doc.toXmlString());
  }
  final out = Archive();
  // Request recalculation in Excel without evaluating or replacing source formulas.
  final calculation = book.rootElement.findElements('calcPr').firstOrNull ??
      XmlElement(XmlName('calcPr'));
  if (calculation.parent == null) book.rootElement.children.add(calculation);
  calculation.setAttribute('fullCalcOnLoad', '1');
  calculation.setAttribute('forceFullCalc', '1');
  calculation.setAttribute('calcMode', 'auto');
  replacements['xl/workbook.xml'] = utf8.encode(book.toXmlString());
  final sheetNames =
      book.findAllElements('sheet').map((s) => s.getAttribute('name')).toList();
  final focus = edits.keys.where((k) => edits[k]!.isNotEmpty).firstOrNull;
  if (focus != null) {
    for (final view in book.findAllElements('workbookView')) {
      view.setAttribute('activeTab', '${sheetNames.indexOf(focus)}');
    }
    replacements['xl/workbook.xml'] = utf8.encode(book.toXmlString());
  }
  for (final file in zip) {
    final content = replacements[file.name];
    out.addFile(content == null
        ? file
        : ArchiveFile(file.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(out)!);
}
