import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// KlaseKo Plus. The free plan never locks a teacher out of their records: only adding classes past
/// the limit and scanning past the limit wait for Plus. Checking by tapping and every form stay free.
const freeClasses = 2;
const freeScansPerMonth = 40;
const priceMonth = 49;
const priceYear = 399;

/// Where teachers pay and send their receipt. Empty values are simply not shown.
const payGcashNumber = '';
const payGcashName = '';
const payContact = '';

/// Verifies activation codes. Its private half stays with the seller, outside this project
/// (see docs/SELLING.md), so a code cannot be made from anything inside the app.
const _publicKey = 'fOehKM8yHdNg/CECRgTNoLf7NT+ck2dyxKdLL1c4ags=';

class PlanCode {
  /// The phone this code is for, or 'ANY' for a code from a ready-to-sell batch.
  final String phoneId;

  /// 'm' for a month, 'y' for a year.
  final String term;

  /// When the plan ends. For an any-phone code, the last day it can be entered instead: its days
  /// start when it is entered.
  final DateTime expires;

  /// Tells any-phone codes apart, so one cannot be entered twice on a phone.
  final String serial;
  const PlanCode(this.phoneId, this.term, this.expires, [this.serial = '']);

  bool get anyPhone => phoneId == anyPhoneId;
}

const anyPhoneId = 'ANY';

/// When a plan from an any-phone code ends, counted from [from].
DateTime anyPhoneEnd(DateTime from, String term) {
  final d = from.add(Duration(days: term == 'y' ? 365 : 31));
  return DateTime(d.year, d.month, d.day, 23, 59, 59);
}

/// Reads an activation code: "KK-" and the base64url of a message followed by its 64-byte Ed25519
/// signature. The message is "K1|PHONEID|term|ENDS" for one phone, or "K2|ANY|term|SERIAL|ENTER-BY"
/// for any phone, with dates as YYYYMMDD. Returns null unless the signature is genuine.
Future<PlanCode?> readPlanCode(String text, {String publicKey = _publicKey}) async {
  final clean = text.replaceAll(RegExp(r'\s'), '');
  if (!clean.startsWith('KK-')) return null;
  try {
    final bytes = base64Url.decode(base64Url.normalize(clean.substring(3)));
    if (bytes.length <= 64) return null;
    final message = bytes.sublist(0, bytes.length - 64);
    final signature = bytes.sublist(bytes.length - 64);
    final genuine = await Ed25519().verify(
      message,
      signature: Signature(signature, publicKey: SimplePublicKey(base64.decode(publicKey), type: KeyPairType.ed25519)),
    );
    if (!genuine) return null;
    final parts = ascii.decode(message).split('|');
    final batch = parts.length == 5 && parts[0] == 'K2' && parts[1] == anyPhoneId;
    if (!batch && (parts.length != 4 || parts[0] != 'K1')) return null;
    final date = parts.last;
    if (date.length != 8) return null;
    final y = int.parse(date.substring(0, 4)), m = int.parse(date.substring(4, 6)), d = int.parse(date.substring(6));
    return PlanCode(parts[1], parts[2], DateTime(y, m, d, 23, 59, 59), batch ? parts[3] : '');
  } catch (_) {
    return null;
  }
}

/// Why a genuine code cannot be used on this phone, or null when it can.
String? planCodeProblem(PlanCode code, String phoneId, DateTime now) {
  if (code.anyPhone) return code.expires.isBefore(now) ? 'This code is too old to use. Ask for a new one.' : null;
  if (code.phoneId != phoneId) return 'This code was made for a different phone. Send your phone ID to get the right one.';
  if (code.expires.isBefore(now)) return 'This code has already ended.';
  return null;
}

/// Shows a phone ID in two groups, so it is easy to read out: AB23-CD45.
String formatPhoneId(String id) => id.length == 8 ? '${id.substring(0, 4)}-${id.substring(4)}' : id;

class PlanStatus {
  final bool plus;
  final DateTime? expires;
  final String phoneId;
  final int scansUsed;
  final DateTime now;
  const PlanStatus({required this.plus, this.expires, required this.phoneId, required this.scansUsed, required this.now});

  int get scansLeft => max(0, freeScansPerMonth - scansUsed);
  bool get canScan => plus || scansLeft > 0;
  int? get daysLeft => plus && expires != null ? expires!.difference(now).inDays : null;
}

/// Plan details live in the phone's secure storage, not in the database, so a code stays with its
/// phone and restoring a backup does not change the plan or reset the month's count.
class Plan {
  static const _storage = FlutterSecureStorage();
  static const _idKey = 'klaseko_phone_id';
  static const _codeKey = 'klaseko_plan_code';
  static const _countKey = 'klaseko_scan_count';
  static const _seenKey = 'klaseko_last_seen';
  static const _endKey = 'klaseko_plan_end';
  static const _usedKey = 'klaseko_used_codes';

  static String _month(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static Future<String> phoneId() async {
    final saved = await _storage.read(key: _idKey);
    if (saved != null) return saved;
    const letters = '23456789ABCDEFGHJKMNPQRSTVWXYZ'; // none that look alike
    final random = Random.secure();
    final id = String.fromCharCodes(List.generate(8, (_) => letters.codeUnitAt(random.nextInt(letters.length))));
    await _storage.write(key: _idKey, value: id);
    return id;
  }

  /// Today, or the latest day this phone has seen, so setting the clock back does not extend a plan.
  static Future<DateTime> _today() async {
    final now = DateTime.now();
    final seen = DateTime.tryParse(await _storage.read(key: _seenKey) ?? '');
    if (seen != null && seen.isAfter(now)) return seen;
    if (seen == null || now.difference(seen).inHours >= 6) await _storage.write(key: _seenKey, value: now.toIso8601String());
    return now;
  }

  static Future<int> _scans(DateTime now) async {
    final parts = (await _storage.read(key: _countKey) ?? '').split(':');
    return parts.length == 2 && parts[0] == _month(now) ? int.tryParse(parts[1]) ?? 0 : 0;
  }

  static Future<PlanStatus> status() async {
    final now = await _today();
    final id = await phoneId();
    final saved = await _storage.read(key: _codeKey);
    final code = saved == null ? null : await readPlanCode(saved);
    // An any-phone code's end date was set on this phone when it was entered.
    final ends = code == null ? null : (code.anyPhone ? DateTime.tryParse(await _storage.read(key: _endKey) ?? '') : code.expires);
    final plus = code != null && ends != null && ends.isAfter(now) && (code.anyPhone || code.phoneId == id);
    return PlanStatus(plus: plus, expires: ends, phoneId: id, scansUsed: await _scans(now), now: now);
  }

  /// Saves a code. Returns what went wrong, or null when Plus is on.
  static Future<String?> activate(String text) async {
    final code = await readPlanCode(text);
    if (code == null) return 'This code is not valid. Copy the whole code and try again.';
    final st = await status();
    final problem = planCodeProblem(code, st.phoneId, st.now);
    if (problem != null) return problem;
    if (code.anyPhone) {
      final used = (await _storage.read(key: _usedKey) ?? '').split(',');
      if (used.contains(code.serial)) return 'This code was already used on this phone.';
      // Renewing early keeps the days left on the current plan.
      final from = st.plus && st.expires != null ? st.expires! : st.now;
      await _storage.write(key: _endKey, value: anyPhoneEnd(from, code.term).toIso8601String());
      await _storage.write(key: _usedKey, value: [...used.where((s) => s.isNotEmpty), code.serial].join(','));
    } else if (st.plus && st.expires != null && code.expires.isBefore(st.expires!)) {
      return 'Your plan already runs longer than this code.';
    }
    await _storage.write(key: _codeKey, value: text.replaceAll(RegExp(r'\s'), ''));
    return null;
  }

  /// Counts one paper newly scanned and recorded.
  static Future<void> countScan() async {
    final now = await _today();
    await _storage.write(key: _countKey, value: '${_month(now)}:${await _scans(now) + 1}');
  }
}
