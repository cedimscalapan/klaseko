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

  // Made by the same steps as tool/make_batch.js, with a throwaway key.
  const batchKey = '7e/D4A5dw+DPxeNpsUOsZqr0ei2V8TW8zJiIldQXWOk=';
  const batchYear = 'KK-SzJ8QU5ZfHl8QUIyM0NENDV8MjAyNzA2MzAj6IEgco4AJBdNEhUmAe3apyqv9--VMJJ82H0oA_GCBU1waFkf2nNF9qMk4Dmxu8EPP7z-lokRcZ_erjNgMZsF';
  const batchMonth = 'KK-SzJ8QU5ZfG18WlgyM0NENDV8MjAyNzA2MzBYAJs6FgMnvyeMuMdyx7PjhD4OzHFeK-cX3WCFkXjYXLP-vuIzGwAQe5ztmMjFo6BfswfphfePHUS-HvZbmwcE';

  test('reads a batch code that works on any phone', () async {
    final c = (await readPlanCode(batchYear, publicKey: batchKey))!;
    expect(c.anyPhone, isTrue);
    expect(c.term, 'y');
    expect(c.serial, 'AB23CD45');
    expect(planCodeProblem(c, 'WHATEVER', DateTime(2027, 1, 1)), isNull);
    expect(planCodeProblem(c, 'SOMEOTHER', DateTime(2027, 1, 1)), isNull);
  });

  test('a batch code must be entered by its last day', () async {
    final c = (await readPlanCode(batchYear, publicKey: batchKey))!;
    expect(planCodeProblem(c, 'X', DateTime(2027, 6, 30, 12)), isNull);
    expect(planCodeProblem(c, 'X', DateTime(2027, 7, 1)), isNotNull);
  });

  test('a batch code refuses a different key', () async {
    expect(await readPlanCode(batchYear), isNull);
    expect(await readPlanCode(batchYear, publicKey: key), isNull);
  });

  test('a batch plan runs from the day it is entered', () async {
    final year = (await readPlanCode(batchYear, publicKey: batchKey))!;
    final month = (await readPlanCode(batchMonth, publicKey: batchKey))!;
    final end = anyPhoneEnd(DateTime(2026, 11, 5), year.term);
    expect([end.year, end.month, end.day], [2027, 11, 5]);
    final short = anyPhoneEnd(DateTime(2026, 11, 5), month.term);
    expect([short.year, short.month, short.day], [2026, 12, 6]);
  });

  test('free scans run out and Plus has no limit', () {
    final now = DateTime(2026, 11, 5);
    expect(PlanStatus(plus: false, phoneId: 'X', scansUsed: 39, now: now).canScan, isTrue);
    expect(PlanStatus(plus: false, phoneId: 'X', scansUsed: 40, now: now).canScan, isFalse);
    expect(PlanStatus(plus: true, phoneId: 'X', scansUsed: 500, now: now).canScan, isTrue);
  });
}
