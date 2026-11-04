import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();
int now() => DateTime.now().millisecondsSinceEpoch;

const _tables = [
  'classes', 'learners', 'attendance', 'activities', 'scores', 'exams', 'items', 'responses',
  'overrides', 'sf9', 'sf9_values', 'settings', 'form_templates',
];

/// Tables added after the first version. The archive holds made files, which can be made again, so
/// it stays out of backups.
Future<void> _createFormTables(Database db) async {
  await db.execute('CREATE TABLE IF NOT EXISTS form_templates(id TEXT PRIMARY KEY, form TEXT, name TEXT, mapping TEXT, created INTEGER)');
  await db.execute('''CREATE TABLE IF NOT EXISTS form_archive(id TEXT PRIMARY KEY, class_id TEXT, class_title TEXT, subject TEXT, sy TEXT,
    form TEXT, term INTEGER, period TEXT, title TEXT, mime TEXT, created INTEGER)''');
}

/// All data lives in one SQLCipher-encrypted SQLite file on the phone.
/// The key is generated once and kept in the Android Keystore / iOS Keychain.
class Repo {
  Repo._(this.db);
  final Database db;

  static Future<Repo> open() async {
    const storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
    var key = await storage.read(key: 'db_key');
    if (key == null) {
      final r = Random.secure();
      key = base64UrlEncode(List<int>.generate(32, (_) => r.nextInt(256)));
      await storage.write(key: 'db_key', value: key);
    }
    final path = p.join(await getDatabasesPath(), 'klaseko.db');
    final db = await openDatabase(path, password: key, version: 2, onUpgrade: (db, from, to) => _createFormTables(db), onCreate: (db, v) async {
      final b = db.batch();
      b.execute('''CREATE TABLE classes(id TEXT PRIMARY KEY, sy TEXT, grade TEXT, section TEXT, subject TEXT,
        preset TEXT, ww REAL, pt REAL, ex REAL, ex_split INTEGER, transmute TEXT, mode TEXT, advisory INTEGER,
        created INTEGER, archived INTEGER DEFAULT 0)''');
      b.execute('''CREATE TABLE learners(id TEXT PRIMARY KEY, class_id TEXT, num INTEGER, lrn TEXT, last TEXT,
        first TEXT, middle TEXT, sex TEXT, birth TEXT, address TEXT, guardian TEXT, contact TEXT, status TEXT,
        remarks TEXT)''');
      b.execute('CREATE INDEX learners_class ON learners(class_id)');
      b.execute('''CREATE TABLE attendance(learner_id TEXT, class_id TEXT, day TEXT, status TEXT,
        PRIMARY KEY(learner_id, day))''');
      b.execute('CREATE INDEX attendance_class ON attendance(class_id, day)');
      b.execute('''CREATE TABLE activities(id TEXT PRIMARY KEY, class_id TEXT, term INTEGER, comp TEXT, sub TEXT,
        title TEXT, hps REAL, day TEXT, exam_id TEXT, created INTEGER)''');
      b.execute('CREATE INDEX activities_class ON activities(class_id)');
      b.execute('CREATE TABLE scores(activity_id TEXT, learner_id TEXT, score REAL, PRIMARY KEY(activity_id, learner_id))');
      b.execute('''CREATE TABLE exams(id TEXT PRIMARY KEY, class_id TEXT, term INTEGER, comp TEXT, sub TEXT,
        title TEXT, instructions TEXT, created INTEGER)''');
      b.execute('''CREATE TABLE items(id TEXT PRIMARY KEY, exam_id TEXT, idx INTEGER, type TEXT, question TEXT,
        choices TEXT, answer INTEGER, competency TEXT)''');
      b.execute('CREATE INDEX items_exam ON items(exam_id)');
      b.execute('''CREATE TABLE responses(exam_id TEXT, learner_id TEXT, answers TEXT, score INTEGER, source TEXT,
        updated INTEGER, PRIMARY KEY(exam_id, learner_id))''');
      b.execute('''CREATE TABLE overrides(class_id TEXT, learner_id TEXT, term INTEGER, value TEXT,
        PRIMARY KEY(class_id, learner_id, term))''');
      b.execute('CREATE TABLE sf9(learner_id TEXT, area TEXT, term INTEGER, grade TEXT, PRIMARY KEY(learner_id, area, term))');
      b.execute('''CREATE TABLE sf9_values(learner_id TEXT, behavior INTEGER, term INTEGER, rating TEXT,
        PRIMARY KEY(learner_id, behavior, term))''');
      b.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
      await b.commit(noResult: true);
      await _createFormTables(db);
    });
    return Repo._(db);
  }

  // ---------- settings ----------
  Future<Map<String, String>> settings() async {
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: (r['value'] ?? '') as String};
  }

  Future<void> putSettings(Map<String, String> values) async {
    final b = db.batch();
    values.forEach((k, v) => b.insert('settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace));
    await b.commit(noResult: true);
  }

  // ---------- classes ----------
  Future<List<SchoolClass>> classes({bool archived = false}) async {
    final rows = await db.query('classes', where: 'archived = ?', whereArgs: [archived ? 1 : 0], orderBy: 'created');
    return rows.map(SchoolClass.fromMap).toList();
  }

  Future<SchoolClass?> classById(String id) async {
    final rows = await db.query('classes', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : SchoolClass.fromMap(rows.first);
  }

  Future<void> saveClass(SchoolClass c) => db.insert('classes', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteClass(String id) async {
    await db.transaction((t) async {
      final exams = await t.query('exams', columns: ['id'], where: 'class_id = ?', whereArgs: [id]);
      for (final e in exams) {
        await t.delete('items', where: 'exam_id = ?', whereArgs: [e['id']]);
        await t.delete('responses', where: 'exam_id = ?', whereArgs: [e['id']]);
      }
      final acts = await t.query('activities', columns: ['id'], where: 'class_id = ?', whereArgs: [id]);
      for (final a in acts) {
        await t.delete('scores', where: 'activity_id = ?', whereArgs: [a['id']]);
      }
      final learners = await t.query('learners', columns: ['id'], where: 'class_id = ?', whereArgs: [id]);
      for (final l in learners) {
        await t.delete('sf9', where: 'learner_id = ?', whereArgs: [l['id']]);
        await t.delete('sf9_values', where: 'learner_id = ?', whereArgs: [l['id']]);
      }
      for (final table in ['exams', 'activities', 'learners', 'attendance', 'overrides']) {
        await t.delete(table, where: 'class_id = ?', whereArgs: [id]);
      }
      await t.delete('classes', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------- learners ----------
  Future<List<Learner>> learners(String classId) async {
    final rows = await db.query('learners', where: 'class_id = ?', whereArgs: [classId]);
    return sortForForms(rows.map(Learner.fromMap));
  }

  Future<int> nextLearnerNum(String classId) async {
    final r = await db.rawQuery('SELECT MAX(num) AS m FROM learners WHERE class_id = ?', [classId]);
    return ((r.first['m'] as int?) ?? 0) + 1;
  }

  Future<void> saveLearner(Learner l) => db.insert('learners', l.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> addLearners(String classId, List<Learner> list) async {
    var n = await nextLearnerNum(classId);
    final b = db.batch();
    for (final l in list) {
      l.num = n++;
      b.insert('learners', l.toMap());
    }
    await b.commit(noResult: true);
  }

  Future<void> deleteLearner(String id) async {
    await db.transaction((t) async {
      for (final table in ['learners']) {
        await t.delete(table, where: 'id = ?', whereArgs: [id]);
      }
      for (final table in ['attendance', 'scores', 'responses', 'overrides', 'sf9', 'sf9_values']) {
        await t.delete(table, where: 'learner_id = ?', whereArgs: [id]);
      }
    });
  }

  // ---------- attendance ----------
  /// day (yyyy-mm-dd) -> learnerId -> status (P, L, A)
  Future<Map<String, Map<String, String>>> attendance(String classId, {String? from, String? to}) async {
    var where = 'class_id = ?';
    final args = <Object?>[classId];
    if (from != null) {
      where += ' AND day >= ?';
      args.add(from);
    }
    if (to != null) {
      where += ' AND day <= ?';
      args.add(to);
    }
    final rows = await db.query('attendance', where: where, whereArgs: args);
    final out = <String, Map<String, String>>{};
    for (final r in rows) {
      (out[r['day'] as String] ??= {})[r['learner_id'] as String] = r['status'] as String;
    }
    return out;
  }

  Future<void> setAttendance(String classId, String day, Map<String, String?> statuses) async {
    final b = db.batch();
    statuses.forEach((lid, s) {
      if (s == null) {
        b.delete('attendance', where: 'learner_id = ? AND day = ?', whereArgs: [lid, day]);
      } else {
        b.insert('attendance', {'learner_id': lid, 'class_id': classId, 'day': day, 'status': s},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await b.commit(noResult: true);
  }

  // ---------- activities & scores ----------
  Future<List<Activity>> activities(String classId) async {
    final rows = await db.query('activities', where: 'class_id = ?', whereArgs: [classId], orderBy: 'term, created');
    return rows.map(Activity.fromMap).toList();
  }

  Future<void> saveActivity(Activity a) => db.insert('activities', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteActivity(String id) async {
    await db.delete('scores', where: 'activity_id = ?', whereArgs: [id]);
    await db.delete('activities', where: 'id = ?', whereArgs: [id]);
  }

  /// activityId -> learnerId -> score
  Future<Map<String, Map<String, double>>> scores(String classId) async {
    final rows = await db.rawQuery(
        'SELECT s.activity_id, s.learner_id, s.score FROM scores s JOIN activities a ON a.id = s.activity_id WHERE a.class_id = ?',
        [classId]);
    final out = <String, Map<String, double>>{};
    for (final r in rows) {
      (out[r['activity_id'] as String] ??= {})[r['learner_id'] as String] = (r['score'] as num).toDouble();
    }
    return out;
  }

  Future<void> setScores(String activityId, Map<String, double?> values) async {
    final b = db.batch();
    values.forEach((lid, v) {
      if (v == null) {
        b.delete('scores', where: 'activity_id = ? AND learner_id = ?', whereArgs: [activityId, lid]);
      } else {
        b.insert('scores', {'activity_id': activityId, 'learner_id': lid, 'score': v}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await b.commit(noResult: true);
  }

  Future<Map<String, Map<int, String>>> overrides(String classId) async {
    final rows = await db.query('overrides', where: 'class_id = ?', whereArgs: [classId]);
    final out = <String, Map<int, String>>{};
    for (final r in rows) {
      (out[r['learner_id'] as String] ??= {})[r['term'] as int] = (r['value'] ?? '') as String;
    }
    return out;
  }

  Future<void> setOverride(String classId, String learnerId, int term, String? value) async {
    if (value == null || value.isEmpty) {
      await db.delete('overrides', where: 'class_id = ? AND learner_id = ? AND term = ?', whereArgs: [classId, learnerId, term]);
    } else {
      await db.insert('overrides', {'class_id': classId, 'learner_id': learnerId, 'term': term, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ---------- exams ----------
  Future<List<Exam>> exams({String? classId}) async {
    final rows = classId == null
        ? await db.query('exams', orderBy: 'created DESC')
        : await db.query('exams', where: 'class_id = ?', whereArgs: [classId], orderBy: 'created DESC');
    return rows.map(Exam.fromMap).toList();
  }

  Future<Exam?> examById(String id) async {
    final rows = await db.query('exams', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Exam.fromMap(rows.first);
  }

  Future<void> saveExam(Exam e) async {
    await db.insert('exams', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await syncExamActivity(e.id);
  }

  Future<void> deleteExam(String id) async {
    final acts = await db.query('activities', columns: ['id'], where: 'exam_id = ?', whereArgs: [id]);
    for (final a in acts) {
      await deleteActivity(a['id'] as String);
    }
    await db.delete('items', where: 'exam_id = ?', whereArgs: [id]);
    await db.delete('responses', where: 'exam_id = ?', whereArgs: [id]);
    await db.delete('exams', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ExamItem>> items(String examId) async {
    final rows = await db.query('items', where: 'exam_id = ?', whereArgs: [examId], orderBy: 'idx');
    return rows.map(ExamItem.fromMap).toList();
  }

  Future<void> saveItems(String examId, List<ExamItem> items) async {
    await db.transaction((t) async {
      await t.delete('items', where: 'exam_id = ?', whereArgs: [examId]);
      for (var i = 0; i < items.length; i++) {
        items[i].idx = i;
        await t.insert('items', items[i].toMap());
      }
    });
    await rescoreExam(examId);
  }

  Future<Map<String, ExamResponse>> responses(String examId) async {
    final rows = await db.query('responses', where: 'exam_id = ?', whereArgs: [examId]);
    return {for (final r in rows) r['learner_id'] as String: ExamResponse.fromMap(r)};
  }

  Future<void> saveResponse(ExamResponse r) async {
    await db.insert('responses', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await syncExamActivity(r.examId);
  }

  Future<void> deleteResponse(String examId, String learnerId) async {
    await db.delete('responses', where: 'exam_id = ? AND learner_id = ?', whereArgs: [examId, learnerId]);
    await syncExamActivity(examId);
  }

  /// Recomputes every saved response after the answer key changes.
  Future<void> rescoreExam(String examId) async {
    final its = await items(examId);
    final resp = await responses(examId);
    final b = db.batch();
    for (final r in resp.values) {
      r.score = scoreAnswers(its, r.answers);
      b.insert('responses', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
    await syncExamActivity(examId);
  }

  /// Keeps one class-record column per exam, so checked scores flow into the grades automatically.
  Future<void> syncExamActivity(String examId) async {
    final exam = await examById(examId);
    if (exam == null) return;
    final count = (await db.rawQuery('SELECT COUNT(*) AS c FROM items WHERE exam_id = ?', [examId])).first['c'] as int;
    final rows = await db.query('activities', where: 'exam_id = ?', whereArgs: [examId]);
    final act = rows.isEmpty
        ? Activity(id: newId(), classId: exam.classId, term: exam.term, comp: exam.comp, sub: exam.sub, title: exam.title, hps: count.toDouble(), examId: examId, created: now())
        : Activity.fromMap(rows.first);
    act
      ..term = exam.term
      ..comp = exam.comp
      ..sub = exam.sub
      ..title = exam.title
      ..hps = count.toDouble();
    await saveActivity(act);
    final resp = await responses(examId);
    await db.delete('scores', where: 'activity_id = ?', whereArgs: [act.id]);
    final b = db.batch();
    for (final r in resp.values) {
      b.insert('scores', {'activity_id': act.id, 'learner_id': r.learnerId, 'score': r.score.toDouble()});
    }
    await b.commit(noResult: true);
  }

  // ---------- SF9 extra data ----------
  /// learnerId -> area -> term -> grade text (term 0 = final grade)
  Future<Map<String, Map<String, Map<int, String>>>> sf9Grades(List<String> learnerIds) async {
    if (learnerIds.isEmpty) return {};
    final rows = await db.query('sf9', where: 'learner_id IN (${List.filled(learnerIds.length, '?').join(',')})', whereArgs: learnerIds);
    final out = <String, Map<String, Map<int, String>>>{};
    for (final r in rows) {
      ((out[r['learner_id'] as String] ??= {})[r['area'] as String] ??= {})[r['term'] as int] = (r['grade'] ?? '') as String;
    }
    return out;
  }

  Future<void> setSf9Grade(String learnerId, String area, int term, String grade) async {
    if (grade.isEmpty) {
      await db.delete('sf9', where: 'learner_id = ? AND area = ? AND term = ?', whereArgs: [learnerId, area, term]);
    } else {
      await db.insert('sf9', {'learner_id': learnerId, 'area': area, 'term': term, 'grade': grade}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// behaviorIndex -> term -> rating (AO, SO, RO, NO)
  Future<Map<int, Map<int, String>>> sf9Values(String learnerId) async {
    final rows = await db.query('sf9_values', where: 'learner_id = ?', whereArgs: [learnerId]);
    final out = <int, Map<int, String>>{};
    for (final r in rows) {
      (out[r['behavior'] as int] ??= {})[r['term'] as int] = (r['rating'] ?? '') as String;
    }
    return out;
  }

  Future<void> setSf9Value(String learnerId, int behavior, int term, String rating) async {
    await db.insert('sf9_values', {'learner_id': learnerId, 'behavior': behavior, 'term': term, 'rating': rating},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- form layouts and archive ----------
  Future<Directory> _filesIn(String name) async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'forms', name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _templateFile(String id) async => File(p.join((await _filesIn('templates')).path, '$id.xlsx'));

  Future<File> _archiveFile(String id) async => File(p.join((await _filesIn('archive')).path, id));

  Future<List<FormTemplate>> templates({String? form}) async {
    final rows = form == null ? await db.query('form_templates', orderBy: 'created') : await db.query('form_templates', where: 'form = ?', whereArgs: [form], orderBy: 'created');
    return rows.map(FormTemplate.fromMap).toList();
  }

  /// Saves a layout. [bytes] is the uploaded file, given the first time.
  Future<void> saveTemplate(FormTemplate t, Uint8List? bytes) async {
    if (bytes != null) await (await _templateFile(t.id)).writeAsBytes(bytes, flush: true);
    await db.insert('form_templates', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Uint8List?> templateBytes(FormTemplate t) async {
    final f = await _templateFile(t.id);
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> deleteTemplate(FormTemplate t) async {
    await db.delete('form_templates', where: 'id = ?', whereArgs: [t.id]);
    final f = await _templateFile(t.id);
    if (await f.exists()) await f.delete();
  }

  /// Files a made form. The same form made again replaces its older copy.
  Future<void> saveArchive(ArchiveEntry e, Uint8List bytes) async {
    final same = await db.query('form_archive',
        columns: ['id'],
        where: 'class_id = ? AND form = ? AND title = ? AND period = ? AND sy = ? AND mime = ?',
        whereArgs: [e.classId, e.form, e.title, e.period, e.sy, e.mime]);
    final id = same.isEmpty ? newId() : same.first['id'] as String;
    await (await _archiveFile(id)).writeAsBytes(bytes, flush: true);
    await db.insert('form_archive', e.toMap(id), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ArchiveEntry>> archiveEntries({String? classId}) async {
    final rows = classId == null
        ? await db.query('form_archive', orderBy: 'created DESC')
        : await db.query('form_archive', where: 'class_id = ?', whereArgs: [classId], orderBy: 'created DESC');
    return rows.map(ArchiveEntry.fromMap).toList();
  }

  Future<Uint8List?> archiveBytes(ArchiveEntry e) async {
    final f = await _archiveFile(e.id);
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> setArchiveTerm(String id, int? term) => db.update('form_archive', {'term': term}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteArchive(ArchiveEntry e) async {
    await db.delete('form_archive', where: 'id = ?', whereArgs: [e.id]);
    final f = await _archiveFile(e.id);
    if (await f.exists()) await f.delete();
  }

  // ---------- backup ----------
  Future<String> exportJson() async {
    final data = <String, Object?>{'app': 'KlaseKo', 'version': 1, 'exported': DateTime.now().toIso8601String()};
    for (final t in _tables) {
      data[t] = await db.query(t);
    }
    // The layouts themselves, so a restored phone can still fill them.
    final files = <String, String>{};
    for (final t in await templates()) {
      final bytes = await templateBytes(t);
      if (bytes != null) files[t.id] = base64Encode(bytes);
    }
    data['template_files'] = files;
    return jsonEncode(data);
  }

  Future<void> importJson(String text) async {
    final data = jsonDecode(text) as Map<String, dynamic>;
    if (data['app'] != 'KlaseKo') throw const FormatException('This file is not a KlaseKo backup.');
    await db.transaction((t) async {
      for (final table in _tables) {
        await t.delete(table);
        final rows = (data[table] as List?) ?? const [];
        for (final r in rows) {
          await t.insert(table, Map<String, Object?>.from(r as Map));
        }
      }
    });
    final files = data['template_files'];
    if (files is Map) {
      for (final e in files.entries) {
        await (await _templateFile(e.key as String)).writeAsBytes(base64Decode(e.value as String), flush: true);
      }
    }
  }

  Future<void> wipe() async {
    await db.transaction((t) async {
      for (final table in [..._tables, 'form_archive']) {
        await t.delete(table);
      }
    });
    final forms = Directory(p.join((await getApplicationSupportDirectory()).path, 'forms'));
    if (await forms.exists()) await forms.delete(recursive: true);
  }
}
