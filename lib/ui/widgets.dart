import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40),
              const SizedBox(height: 12),
              const Text('Unable to load this screen'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return widget.builder(context, _data as T);
  }
}

/// White card with a soft shadow. The building block of every screen.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = 18,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(150),
        ),
        boxShadow: color == null ? softShadow(context) : const [],
      ),
      child: Material(
        color: color ?? cardColor(context),
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// Rounded square with a tinted icon, used for actions and list rows.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color, this.size = 46});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? brandBlue;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(isDark(context) ? 50 : 28),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// A tappable row: icon, title, subtitle, chevron. Large touch target.
class NavRow extends StatelessWidget {
  const NavRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.color,
    this.trailing,
    this.highlight = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  final Widget? trailing;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? brandBlue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        color: highlight ? color.withAlpha(isDark(context) ? 46 : 22) : null,
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(
          children: [
            IconBadge(icon, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: mutedText(context)),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: mutedText(context),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Big square action used in grids (class hub, quick actions).
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
    this.badge,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? brandBlue;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon, color: color, size: 44),
              const Spacer(),
              if (badge != null) Pill(badge!, color: color),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: mutedText(context)),
          ),
        ],
      ),
    );
  }
}

/// Blue gradient header used at the top of the main screens.
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 20),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: heroGradient,
      borderRadius: BorderRadius.circular(26),
      boxShadow: isDark(context)
          ? const []
          : const [
              BoxShadow(
                color: Color(0x2E0F2D57),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          // Soft circles for depth.
          Positioned(right: -40, top: -50, child: _circle(170, 0.10)),
          Positioned(right: 40, bottom: -70, child: _circle(140, 0.07)),
          Padding(
            padding: padding,
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _circle(double size, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withAlpha((opacity * 255).round()),
    ),
  );
}

/// White translucent button that sits on the hero header.
class HeroAction extends StatelessWidget {
  const HeroAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: Colors.white.withAlpha(38),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: brandBlue.withAlpha(isDark(context) ? 50 : 22),
            ),
            child: Icon(icon, size: 42, color: brandBlue),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText(context), height: 1.45),
          ),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    ),
  );
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.color,
    this.pen = false,
    this.onTap,
    this.icon,
  });
  final String label;
  final String value;
  final String? sub;
  final Color? color;
  final bool pen;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: color ?? brandBlue),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: mutedText(context),
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              fontStyle: pen ? FontStyle.italic : FontStyle.normal,
              color: color ?? (pen ? penRed : null),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (sub != null)
          Text(
            sub!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: mutedText(context)),
          ),
      ],
    ),
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
    child: Text(
      text,
      style: TextStyle(
        color: penRed,
        fontSize: size,
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(isDark(context) ? 60 : 30),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// Thin rounded progress bar.
class SlimProgress extends StatelessWidget {
  const SlimProgress({
    super.key,
    required this.value,
    this.color,
    this.height = 8,
  });
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? brandBlue;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: height,
        color: color,
        backgroundColor: color.withAlpha(isDark(context) ? 50 : 26),
      ),
    );
  }
}

Color gradeColor(int? g) => g == null
    ? Colors.grey
    : g >= 90
    ? goodGreen
    : g >= 75
    ? brandBlue
    : penRed;

void toast(BuildContext context, String message, {bool success = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (success) ...[
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: success ? goodGreen : null,
      ),
    );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
  bool danger = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: penRed,
                  minimumSize: const Size(64, 46),
                )
              : FilledButton.styleFrom(minimumSize: const Size(64, 46)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Runs a slow job (making a PDF or Excel file) behind a small progress dialog.
Future<T?> withProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function() job,
) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 18),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await job();
  } catch (e) {
    if (context.mounted)
      toast(
        context,
        e is FormatException
            ? e.message
            : 'That did not work. Please try again.',
      );
    return null;
  } finally {
    nav.pop();
  }
}

/// A screen title with the class under it, so the teacher always sees which class this is.
class ClassTitle extends StatelessWidget {
  const ClassTitle(this.title, this.cls, {super.key});
  final String title;
  final SchoolClass cls;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, overflow: TextOverflow.ellipsis),
      Text(
        '${cls.subject} · ${cls.title}',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: mutedText(context),
        ),
      ),
    ],
  );
}

/// The grade as a short badge: "8", or "K" for Kindergarten.
String gradeShort(String grade) {
  final digits = grade.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? 'K' : digits;
}

/// Lets the teacher choose a class, or goes straight on when there is only one.
void pickClass(
  BuildContext context,
  List<SchoolClass> classes,
  String title,
  void Function(SchoolClass) open,
) {
  if (classes.length == 1) {
    open(classes.first);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
          ),
          for (var i = 0; i < classes.length; i++)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: palette
                    .classColors[i % palette.classColors.length]
                    .withAlpha(30),
                child: Text(
                  gradeShort(classes[i].grade),
                  style: TextStyle(
                    color: palette.classColors[i % palette.classColors.length],
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                classes[i].title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(classes[i].subject),
              onTap: () {
                Navigator.pop(ctx);
                open(classes[i]);
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

String two(int n) => n.toString().padLeft(2, '0');

String fmtScore(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
