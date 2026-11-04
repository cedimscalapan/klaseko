import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/core/plan.dart';

void main() {
  // Made by the same steps as tool/make_code.js, with a throwaway key.
  const key = 'eyaMQhTpW8hw7gqQzGKTVZUQiKoDWb3Q9HQjhSX1oZw=';
  const code = 'KK-SzF8QUIyM0NENDV8eXwyMDI3MDYzMA0MgkXmq74DAJ8bCbmCihjz8KUgtOuvgEL_LhT4OZlMbhD7lcbIFk8iYRQKAKXprvbX6ouKa2v9Bb4RMS6u2gw';

  test('reads a genuine code', () async {
    final c = await readPlanCode(code, publicKey: key);
    expect(c, isNotNull);
    expect(c!.phoneId, 'AB23CD45');
    expect(c.term, 'y');
    expect(c.expires.year, 2027);
    expect(c.expires.month, 6);
    expect(c.expires.day, 30);
  });

  test('ignores spaces and line breaks from a chat message', () async {
    final broken = '${code.substring(0, 40)}\n ${code.substring(40)}';
    expect(await readPlanCode(broken, publicKey: key), isNotNull);
  });

  test('refuses an edited code', () async {
    // The same code with its text part changed: AB23CD45 becomes another phone.
    final edited = code.replaceFirst('SzF8QUIy', 'SzF8QUIz');
    expect(await readPlanCode(edited, publicKey: key), isNull);
  });

  test('refuses a code signed with another key', () async {
    expect(await readPlanCode(code), isNull);
  });

  test('refuses text that is not a code', () async {
    expect(await readPlanCode('hello', publicKey: key), isNull);
    expect(await readPlanCode('KK-abc', publicKey: key), isNull);
  });

  test('a code works only on its phone and before it ends', () async {
    final c = (await readPlanCode(code, publicKey: key))!;
    expect(planCodeProblem(c, 'AB23CD45', DateTime(2027, 1, 1)), isNull);
    expect(planCodeProblem(c, 'ZZZZZZZZ', DateTime(2027, 1, 1)), isNotNull);
    expect(planCodeProblem(c, 'AB23CD45', DateTime(2027, 6, 30, 12)), isNull);
    expect(planCodeProblem(c, 'AB23CD45', DateTime(2027, 7, 1)), isNotNull);
  });

  test('free scans run out and Plus has no limit', () {
    final now = DateTime(2026, 11, 5);
    expect(PlanStatus(plus: false, phoneId: 'X', scansUsed: 39, now: now).canScan, isTrue);
    expect(PlanStatus(plus: false, phoneId: 'X', scansUsed: 40, now: now).canScan, isFalse);
    expect(PlanStatus(plus: true, phoneId: 'X', scansUsed: 500, now: now).canScan, isTrue);
  });
}
