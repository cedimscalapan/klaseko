import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../theme.dart';
import '../widgets.dart';

/// A 4-digit PIN, kept salted and hashed in the phone's secure storage (never in backups).
class AppLock {
  static const _storage = FlutterSecureStorage();
  static const _key = 'klaseko_pin';

  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<bool> hasPin() async => (await _storage.read(key: _key)) != null;

  static Future<void> setPin(String pin) async {
    final salt = base64Url.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    await _storage.write(key: _key, value: '$salt\$${_hash(salt, pin)}');
  }

  static Future<void> clear() => _storage.delete(key: _key);

  static Future<bool> check(String pin) async {
    final saved = await _storage.read(key: _key);
    if (saved == null) return true;
    final parts = saved.split(r'$');
    return parts.length == 2 && _hash(parts[0], pin) == parts[1];
  }
}

/// Number pad with four dots. Calls [onDone] with the PIN after the fourth digit.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.title, this.message, required this.onDone});
  final String title;
  final String? message;

  /// Return false to shake off the entry and start again.
  final Future<bool> Function(String pin) onDone;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  Future<void> _tap(String d) async {
    if (_pin.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == 4) {
      final ok = await widget.onDone(_pin);
      if (mounted) {
        if (!ok) HapticFeedback.heavyImpact();
        setState(() => _pin = '');
      }
    }
  }

  Widget _key(String label, VoidCallback? onTap, {IconData? icon}) => SizedBox(
        width: 84,
        height: 72,
        child: onTap == null
            ? null
            : InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Center(child: icon != null ? Icon(icon) : Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600))),
              ),
      );

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        SizedBox(height: 20, child: Text(widget.message ?? '', textAlign: TextAlign.center, style: TextStyle(color: penRed, fontSize: 13))),
        const SizedBox(height: 14),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(shape: BoxShape.circle, color: i < _pin.length ? brandBlue : Colors.transparent, border: Border.all(color: brandBlue, width: 1.6)),
            ),
        ]),
        const SizedBox(height: 18),
        for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) _key(d, () => _tap(d))]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _key('', null),
          _key('0', () => _tap('0')),
          _key('', _pin.isEmpty ? null : () => setState(() => _pin = _pin.substring(0, _pin.length - 1)), icon: Icons.backspace_outlined),
        ]),
      ]);
}

/// Covers the whole app with the PIN screen when it opens, and again after a minute in the background.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _checked = false;
  bool _locked = false;
  bool _wrong = false;
  bool _forgot = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _relock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _relock() async {
    final has = await AppLock.hasPin();
    if (mounted) {
      setState(() {
        _checked = true;
        _locked = has;
        _wrong = false;
        _forgot = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      if (left != null && DateTime.now().difference(left).inSeconds >= 60) _relock();
      _leftAt = null;
    }
  }

  Future<void> _eraseAll() async {
    await store.repo.wipe();
    await AppLock.clear();
    await store.reloadProfile();
    if (mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        widget.child,
        // Nothing shows until the lock has been checked.
        if (!_checked) ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        if (_locked)
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    PinPad(
                      title: 'Enter your PIN',
                      message: _wrong ? 'That PIN is not right. Try again.' : null,
                      onDone: (pin) async {
                        final ok = await AppLock.check(pin);
                        if (mounted) {
                          setState(() {
                            _wrong = !ok;
                            if (ok) _locked = false;
                          });
                        }
                        return ok;
                      },
                    ),
                    const SizedBox(height: 8),
                    if (!_forgot)
                      TextButton(onPressed: () => setState(() => _forgot = true), child: const Text('Forgot your PIN?'))
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(children: [
                          const Text('A PIN cannot be recovered. To use KlaseKo again, erase the data on this phone, then restore your latest backup.', textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          TextButton(onPressed: _eraseAll, child: Text('Erase everything on this phone', style: TextStyle(color: penRed))),
                        ]),
                      ),
                  ]),
                ),
              ),
            ),
          ),
      ]);
}

/// Choosing a new PIN: enter it twice.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  String? _first;
  String? _message;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('App lock')),
        body: Center(
          child: SingleChildScrollView(
            child: PinPad(
              title: _first == null ? 'Choose a 4-digit PIN' : 'Enter it again',
              message: _message,
              onDone: (pin) async {
                final first = _first;
                if (first == null) {
                  setState(() {
                    _first = pin;
                    _message = null;
                  });
                  return true;
                }
                if (first != pin) {
                  setState(() {
                    _first = null;
                    _message = 'They did not match. Start again.';
                  });
                  return false;
                }
                await AppLock.setPin(pin);
                if (mounted) {
                  toast(context, 'App lock is on.', success: true);
                  Navigator.pop(context);
                }
                return true;
              },
            ),
          ),
        ),
      );
}
