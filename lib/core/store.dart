import 'package:flutter/foundation.dart';

import 'db.dart';
import 'models.dart';

/// One shared store. Screens read from [repo] and call [changed] after writing,
/// so every open screen reloads its data.
class AppStore extends ChangeNotifier {
  AppStore._(this.repo, this.profile, this.onboarded);

  static late AppStore instance;

  final Repo repo;
  SchoolProfile profile;
  bool onboarded;

  static Future<AppStore> init() async {
    final repo = await Repo.open();
    final s = await repo.settings();
    instance = AppStore._(repo, SchoolProfile.fromSettings(s), s['onboarded'] == '1');
    return instance;
  }

  void changed() => notifyListeners();

  Future<void> saveProfile(SchoolProfile p, {bool markOnboarded = false}) async {
    profile = p;
    final values = p.toSettings();
    if (markOnboarded) {
      values['onboarded'] = '1';
      onboarded = true;
    }
    await repo.putSettings(values);
    changed();
  }

  Future<void> reloadProfile() async {
    final s = await repo.settings();
    profile = SchoolProfile.fromSettings(s);
    onboarded = s['onboarded'] == '1';
    changed();
  }
}
