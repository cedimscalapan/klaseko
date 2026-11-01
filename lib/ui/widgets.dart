import 'package:flutter/material.dart';

import '../core/store.dart';
import 'theme.dart';

AppStore get store => AppStore.instance;

/// Loads data and reloads it whenever the store changes, keeping the last data on screen
/// while the new data arrives (no flicker).
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? _data;
  bool _loaded = false;
  Object? _error;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    store.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    store.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final t = ++_ticket;
    try {
      final d = await widget.load();
      if (mounted && t == _ticket) {
        setState(() {
          _data = d;
          _loaded = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && t == _ticket) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && !_loaded) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Something went wrong: $_error')));
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return widget.builder(context, _data as T);
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.color});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? (Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xFF161D2C)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant.withAlpha(140))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 34, backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(icon, size: 34)),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ]),
        ),
      );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub, this.color, this.pen = false, this.onTap});
  final String label;
  final String value;
  final String? sub;
  final Color? color;
  final bool pen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                fontStyle: pen ? FontStyle.italic : FontStyle.normal,
                color: color ?? (pen ? penRed : null),
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          if (sub != null) Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}

/// A red-pen score like a teacher writes on a paper.
class PenScore extends StatelessWidget {
  const PenScore(this.text, {super.key, this.size = 22});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: -0.08,
        child: Text(text, style: TextStyle(color: penRed, fontSize: size, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic)),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withAlpha(36), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

Color gradeColor(int? g) => g == null ? Colors.grey : g >= 90 ? goodGreen : g >= 75 ? brandBlue : penRed;

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String action = 'Delete', bool danger = true}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: penRed, minimumSize: const Size(64, 44)) : FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Runs a slow job (making a PDF or Excel file) behind a small progress dialog.
Future<T?> withProgress<T>(BuildContext context, String message, Future<T> Function() job) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 18), Expanded(child: Text(message))])),
    ),
  );
  try {
    return await job();
  } catch (e) {
    if (context.mounted) toast(context, 'Could not finish: $e');
    return null;
  } finally {
    nav.pop();
  }
}

Future<T?> push<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

String two(int n) => n.toString().padLeft(2, '0');

String fmtScore(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
