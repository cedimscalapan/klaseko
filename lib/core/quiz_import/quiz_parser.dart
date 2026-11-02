/// Turns messy quiz text (typed, pasted, from a Word file, or read from a photo or PDF) into exam
/// items with choices and answers. Works offline with rules, no AI service.
///
/// Understands, among others:
///  - numbered questions: "1.", "1)", "1 -", "Q1", "No. 1", "Bilang 1", or unnumbered lines ending in "?"
///  - choices on separate lines or on one line: "a.", "a)", "(a)", "A -", even squashed like "?a.atom b.cell"
///  - answers from an answer key ("Answer key", "Susi sa Pagwawasto", "1. B 2. C", "1-A, 2-B"),
///    from lines like "Answer: B" or "Sagot: B", or from a choice marked with "*", "(correct)" or bold text
///  - True/False and Tama/Mali sections
///  - identification, essay and matching items are skipped and counted
library;

/// Marks bold or highlighted text extracted from a Word file.
const markOn = '\u0001';
const markOff = '\u0002';

class ParsedItem {
  int? number;
  String type; // 'mc' or 'tf'
  String question;
  List<String> choices;
  int? answer;
  final int section;

  ParsedItem({this.number, required this.type, required this.question, required this.choices, this.answer, required this.section});
}

class ParseResult {
  final List<ParsedItem> items;
  final List<String> warnings;
  final int skipped;
  ParseResult(this.items, this.warnings, this.skipped);
}

final _choiceRe = RegExp(r'(^|\s)(\*?)(?:\(([a-dA-D])\)|([a-dA-D])[\.\)](?=\s|$)|([a-dA-D])\s-\s)\s*');
final _choiceLooseRe = RegExp(r'(^|[\s?:])(\*?)(?:\(([a-dA-D])\)|([a-dA-D])[\.\)])\s*');
final _keyHeader = RegExp(r'^(answer\s*key|answers?|key\s*(to|for)\s*correction|answer\s*sheet\s*key|susi(\s*sa\s*pagwawasto)?|mga\s*sagot)\s*[:.\-]?\s*$', caseSensitive: false);
final _keyHeaderWithPairs = RegExp(r'^(answer\s*key|answers?|key|susi(\s*sa\s*pagwawasto)?|mga\s*sagot)\s*[:.\-]\s*(.+)$', caseSensitive: false);
final _section = RegExp(r'^(test|part|section|bahagi|pagsusulit|type)\s+([ivx]+|\d+|[a-e])\b|^(i{1,3}|iv|v|vi{0,3})\.\s+[a-z]', caseSensitive: false);
final _directions = RegExp(r'^(directions?|panuto|instructions?)\b', caseSensitive: false);
final _tfHint = RegExp(r'true\s*(or|/)\s*false|tama\s*(o|/)\s*mali|write\s+(t|true)\b|isulat\s+(ang\s+)?tama', caseSensitive: false);
final _skipHint = RegExp(r'identification|enumerat|essay|matching|pagtutugma|sanaysay|fill\s*in|completion', caseSensitive: false);
final _qNum = RegExp(r'^(?:(?:q|question|no\.?|bilang)\s*)?(\d{1,3})\s*[\.\):\-]\s*(.*)$', caseSensitive: false);
final _qNumLoose = RegExp(r'^(\d{1,3})\s+(\S.*)$');
final _qNumPrefix = RegExp(r'^\s*(?:(?:q|question|no\.?|bilang)\s*)?\d{1,3}\s*[\.\):\-]?\s*', caseSensitive: false);
final _inlineAnswer = RegExp(r'^(?:correct\s*answer|answer|ans|sagot|tamang\s*sagot)\s*[:.\-]\s*\(?([a-dA-D]|true|false|tama|mali|t|f)\)?\b', caseSensitive: false);
final _keyPair = RegExp(r'(\d{1,3})\s*[\.\)\-:=]?\s*\(?\b([a-dA-D]|true|false|tama|mali|t|f)\b\)?', caseSensitive: false);
final _markedCorrect = RegExp(r'^\*|\*$|\(correct\)|\[correct\]|✓|✔', caseSensitive: false);
final _pageLine = RegExp(r'^(page\s*\d+(\s*of\s*\d+)?|-\s*\d+\s*-|\d+\s*/\s*\d+)$', caseSensitive: false);

List<String> _normalize(String text) => text
    .replaceAll(RegExp(r'\r\n?'), '\n')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp('[•●▪■‣⁃·]'), ' ')
    .replaceAll('\t', ' ')
    .replaceAll(RegExp('[  ]+'), ' ')
    .split('\n')
    .map((l) => l.trim())
    .where((l) => !_pageLine.hasMatch(l))
    .toList();

String _strip(String s) => s.replaceAll(RegExp('[\u0001\u0002]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

bool _isMarked(String s) {
  var on = false;
  var marked = 0, total = 0;
  for (final ch in s.split('')) {
    if (ch == markOn) {
      on = true;
      continue;
    }
    if (ch == markOff) {
      on = false;
      continue;
    }
    if (ch.trim().isEmpty) continue;
    total++;
    if (on) marked++;
  }
  return (total > 0 && marked / total > 0.6) || _markedCorrect.hasMatch(_strip(s));
}

String _cleanChoice(String s) =>
    _strip(s).replaceAll(RegExp(r'^\*+|\*+$'), '').replaceAll(RegExp(r'\(correct\)|\[correct\]|[✓✔]', caseSensitive: false), '').trim();

int? _answerCode(String token, String type) {
  final t = token.toLowerCase();
  if (const ['true', 'tama', 't'].contains(t)) return type == 'mc' ? null : 0;
  if (const ['false', 'mali', 'f'].contains(t)) return type == 'mc' ? null : 1;
  if (RegExp(r'^[a-d]$').hasMatch(t)) return type == 'tf' ? null : t.codeUnitAt(0) - 97;
  return null;
}

class _Choice {
  final String letter;
  final String text;
  _Choice(this.letter, this.text);
}

class _Split {
  final String prefix;
  final List<_Choice> parts;
  _Split(this.prefix, this.parts);
}

String _letterOf(RegExpMatch m) => (m.group(3) ?? m.group(4) ?? m.group(5))!.toLowerCase();

_Split? _splitWith(String line, RegExp re) {
  final ms = re.allMatches(line).toList();
  if (ms.isEmpty) return null;
  List<RegExpMatch>? best;
  for (var i = 0; i < ms.length; i++) {
    final start = _letterOf(ms[i]);
    if (start != 'a' && !(i == 0 && ms[i].start == 0)) continue;
    final run = [ms[i]];
    for (var j = i + 1; j < ms.length; j++) {
      if (_letterOf(ms[j]).codeUnitAt(0) == _letterOf(run.last).codeUnitAt(0) + 1) run.add(ms[j]);
    }
    if (best == null || run.length > best.length) best = run;
  }
  if (best == null) return null;
  final firstStartsLine = best.first.start == 0;
  if (best.length < 2 && !firstStartsLine) return null;
  final prefix = line.substring(0, best.first.start + best.first.group(1)!.length).trim();
  final parts = <_Choice>[];
  for (var k = 0; k < best.length; k++) {
    final from = best[k].end;
    final to = k + 1 < best.length ? best[k + 1].start + best[k + 1].group(1)!.length : line.length;
    final star = (best[k].group(2) ?? '').isNotEmpty ? '*' : '';
    parts.add(_Choice(_letterOf(best[k]), star + line.substring(from, to < from ? from : to).trim()));
  }
  return _Split(prefix, parts);
}

_Split? _splitChoices(String line) {
  final a = _splitWith(line, _choiceRe);
  if (a != null && (a.parts.length >= 2 || a.prefix.isEmpty)) return a;
  final b = _splitWith(line, _choiceLooseRe);
  return (b != null && b.parts.length >= 3) ? b : a;
}

class _Open {
  final int? number;
  final List<String> question = [];
  final Map<int, String> choices = {}; // index -> text (choices may arrive out of order from OCR)
  int? answer;
  final String mode;
  final int section;
  _Open(this.number, this.mode, this.section);

  int get choiceCount => choices.length;
}

ParseResult parseQuiz(String text) {
  final lines = _normalize(text);
  final items = <ParsedItem>[];
  final keyByNumber = <String, String>{};
  final keyOrder = <String>[];
  var skipped = 0;
  var mode = 'mc';
  var section = 0;
  var inKey = false;
  _Open? cur;

  void finish() {
    final c = cur;
    if (c == null) return;
    final q = _strip(c.question.join(' '));
    final hasAB = c.choices.containsKey(0) && c.choices.containsKey(1);
    if (hasAB) {
      final ordered = [for (var i = 0; i < 4; i++) c.choices[i] ?? ''];
      final cleaned = ordered.map(_cleanChoice).toList();
      final tfChoices = c.choices.length == 2 &&
          RegExp(r'^(true|tama)$', caseSensitive: false).hasMatch(cleaned[0]) &&
          RegExp(r'^(false|mali)$', caseSensitive: false).hasMatch(cleaned[1]);
      var answer = c.answer;
      if (answer == null) {
        for (var i = 0; i < 4; i++) {
          final t = c.choices[i];
          if (t != null && _isMarked(t)) {
            answer = i;
            break;
          }
        }
      }
      items.add(ParsedItem(
        number: c.number,
        type: tfChoices ? 'tf' : 'mc',
        question: q,
        choices: tfChoices ? ['', '', '', ''] : cleaned,
        answer: tfChoices ? (answer != null && answer < 2 ? answer : null) : answer,
        section: c.section,
      ));
    } else if (c.mode == 'tf' && q.isNotEmpty) {
      items.add(ParsedItem(number: c.number, type: 'tf', question: q, choices: ['', '', '', ''], answer: c.answer, section: c.section));
    } else if (q.isNotEmpty) {
      skipped++;
    }
    cur = null;
  }

  void addKeyPairs(String s, {bool bySection = false}) {
    for (final p in _keyPair.allMatches(s)) {
      if (bySection) keyByNumber['$section:${p.group(1)}'] = p.group(2)!;
      keyByNumber['any:${p.group(1)}'] = p.group(2)!;
      keyOrder.add(p.group(2)!);
    }
  }

  for (final line in lines) {
    if (line.isEmpty) continue;
    final plain = _strip(line);

    if (_keyHeader.hasMatch(plain)) {
      finish();
      inKey = true;
      continue;
    }
    final hp = _keyHeaderWithPairs.firstMatch(plain);
    if (hp != null && _keyPair.hasMatch(hp.group(3)!)) {
      finish();
      addKeyPairs(hp.group(3)!);
      inKey = true;
      continue;
    }
    if (inKey) {
      if (_keyPair.hasMatch(plain) && plain.length < 120) {
        addKeyPairs(plain, bySection: true);
        continue;
      }
      if (_section.hasMatch(plain)) {
        section++;
        continue;
      }
      if (plain.length < 25) continue;
      inKey = false;
    }

    // A bare key line: "1. B 2. C 3. A" (3 or more pairs and nothing else).
    final pairCount = _keyPair.allMatches(plain).length;
    if (pairCount >= 3 && plain.replaceAll(_keyPair, '').replaceAll(RegExp(r'[\s,;|]+'), '').isEmpty) {
      finish();
      addKeyPairs(plain);
      continue;
    }

    if (_section.hasMatch(plain) || _directions.hasMatch(plain)) {
      finish();
      if (_section.hasMatch(plain)) section++;
      if (_tfHint.hasMatch(plain)) {
        mode = 'tf';
      } else if (_skipHint.hasMatch(plain)) {
        mode = 'skip';
      } else if (_section.hasMatch(plain)) {
        mode = 'mc';
      }
      continue;
    }
    if (_tfHint.hasMatch(plain) && plain.length < 160 && !_qNum.hasMatch(plain)) {
      finish();
      mode = 'tf';
      continue;
    }

    final inline = _inlineAnswer.firstMatch(plain);
    final open = cur;
    if (inline != null && open != null) {
      open.answer = _answerCode(inline.group(1)!, open.choiceCount >= 2 ? 'mc' : open.mode);
      continue;
    }

    final q = _qNum.firstMatch(plain) ?? ((open != null && open.choiceCount >= 2) ? _qNumLoose.firstMatch(plain) : null);
    final split = _splitChoices(line);
    final startsWithChoice = split != null && split.prefix.isEmpty;

    if (q != null && !(startsWithChoice && open != null)) {
      finish();
      final body = line.replaceFirst(_qNumPrefix, '');
      final c = _Open(int.tryParse(q.group(1)!), mode, section);
      final sp = _splitChoices(body);
      if (sp != null && sp.parts.length >= 2) {
        if (sp.prefix.isNotEmpty) c.question.add(sp.prefix);
        for (final p in sp.parts) {
          c.choices[p.letter.codeUnitAt(0) - 97] = p.text;
        }
      } else {
        c.question.add(body);
      }
      cur = c;
      continue;
    }

    if (split != null && open != null) {
      if (split.prefix.isNotEmpty && open.choices.isEmpty) open.question.add(split.prefix);
      for (final p in split.parts) {
        final idx = p.letter.codeUnitAt(0) - 97;
        open.choices[idx] = open.choices.containsKey(idx) ? '${open.choices[idx]} ${p.text}' : p.text;
      }
      continue;
    }

    // An unnumbered question: a line ending with "?" when no question is open or the open one has choices.
    if (RegExp(r'\?\s*$').hasMatch(plain) && (open == null || open.choiceCount >= 2)) {
      finish();
      cur = _Open(null, mode, section)..question.add(line);
      continue;
    }

    if (open != null) {
      if (open.choices.isNotEmpty) {
        final last = open.choices.keys.reduce((a, b) => a > b ? a : b);
        open.choices[last] = '${open.choices[last]} $line'; // a choice that wraps to the next line
      } else {
        open.question.add(line);
      }
    }
  }
  finish();

  // Apply the answer key: by position when numbering restarts across sections and the key covers
  // every item, otherwise by question number.
  final numbers = items.map((i) => i.number).toList();
  final useOrder = keyOrder.isNotEmpty && keyOrder.length == items.length && numbers.toSet().length != numbers.length;
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    if (it.answer != null) continue;
    String? tok;
    if (useOrder) {
      tok = keyOrder[i];
    } else if (it.number != null) {
      tok = keyByNumber['${it.section}:${it.number}'] ?? keyByNumber['any:${it.number}'];
    }
    if (tok != null) it.answer = _answerCode(tok, it.type);
  }

  final warnings = <String>[];
  final missing = items.where((i) => i.answer == null).length;
  if (missing > 0) warnings.add('$missing item(s) have no answer yet. Tap the correct letter for each.');
  if (skipped > 0) warnings.add('$skipped item(s) without choices were skipped (identification, essay or matching).');
  return ParseResult(items, warnings, skipped);
}
