import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/core/backup_crypto.dart';
import 'package:klaseko/core/teaching.dart';
import 'package:klaseko/core/models.dart';

void main() {
  test('Grade conversion preserves institution scale and boundaries', () {
    final p = TeachingPolicy(
      sector: 'Higher Education',
      periods: 2,
      bands: [
        {'minimum': 0, 'grade': '5.0'},
        {'minimum': 75, 'grade': '3.0'},
        {'minimum': 95, 'grade': '1.0'},
      ],
    );
    final copy = TeachingPolicy.decode(p.encode());
    expect(copy.convert(95), '1.0');
    expect(copy.convert(94.99), '3.0');
    expect(copy.convert(74.99), '5.0');
    expect(copy.periods, 2);
  });
  test(
    'Outcome evidence excludes unassessed work without reporting mastery',
    () {
      final a = Activity(
        id: 'a',
        classId: 'c',
        term: 1,
        comp: 'pt',
        title: 'Task',
        hps: 20,
        created: 0,
      );
      expect(outcomePercent([a], {}, 's'), isNull);
      expect(
        outcomePercent(
          [a],
          {
            'a': {'s': 10},
          },
          's',
        ),
        50,
      );
      expect(
        outcomePercent(
          [a],
          {
            'a': {'s': 0},
          },
          's',
        ),
        0,
      );
    },
  );
  test('Encrypted backups authenticate password and ciphertext', () async {
    final sealed = await BackupCrypto.seal(
      '{"app":"KlaseKo"}',
      'long secure password',
    );
    expect(sealed, isNot(contains('"app"')));
    expect(
      await BackupCrypto.open(sealed, 'long secure password'),
      '{"app":"KlaseKo"}',
    );
    await expectLater(
      BackupCrypto.open(sealed, 'wrong password'),
      throwsFormatException,
    );
    expect(
      await BackupCrypto.seal('same', 'long secure password'),
      isNot(await BackupCrypto.seal('same', 'long secure password')),
    );
  });
}
