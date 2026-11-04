import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const pdfMime = 'application/pdf';

String safeFileName(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');

/// Saves a generated file in the app's documents folder and opens the share sheet,
/// so the teacher can save it to Files or Drive, or send it through Messenger or email.
/// Returns false when the teacher closed the share sheet without choosing anything.
Future<bool> saveAndShare(Uint8List bytes, String fileName, String mime) async {
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'exports'));
  if (!await dir.exists()) await dir.create(recursive: true);
  final file = File(p.join(dir.path, safeFileName(fileName)));
  await file.writeAsBytes(bytes, flush: true);
  final result = await Share.shareXFiles([XFile(file.path, mimeType: mime)], subject: fileName);
  return result.status != ShareResultStatus.dismissed;
}
