import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/plan.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shows the current plan and how to get KlaseKo Plus: pay by GCash, send the receipt, paste the code.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, this.reason});

  /// Why the teacher was brought here, such as reaching the month's scans.
  final String? reason;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final _code = TextEditingController();
  bool _yearly = true;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) setState(() => _code.text = data!.text!.trim());
  }

  Future<void> _activate() async {
    final problem = await Plan.activate(_code.text);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    _code.clear();
    setState(() => _error = null);
    store.changed();
    toast(context, 'KlaseKo Plus is on. Salamat po!', success: true);
  }

  String _request() => 'Hello! I would like KlaseKo Plus for ${_yearly ? 'one year (P$priceYear)' : 'one month (P$priceMonth)'}. My GCash receipt is attached.';

  Widget _compare(String label, String free, String plus) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(flex: 3, child: Text(label)),
          Expanded(flex: 2, child: Text(free, textAlign: TextAlign.center, style: TextStyle(color: mutedText(context)))),
          Expanded(flex: 2, child: Text(plus, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _step(int n, String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('$n · $title', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your plan')),
      body: Loader<PlanStatus>(
        load: Plan.status,
        builder: (context, st) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), children: [
          if (widget.reason != null && !st.plus)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(color: lateAmber.withAlpha(isDark(context) ? 46 : 24), child: Text(widget.reason!, style: const TextStyle(fontWeight: FontWeight.w600))),
            ),
          AppCard(
            color: st.plus ? goodGreen.withAlpha(isDark(context) ? 46 : 24) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(st.plus ? 'KlaseKo Plus' : 'Free plan', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              if (st.plus)
                Text(st.expires == null ? 'Unlimited classes and scans.' : 'Unlimited classes and scans until ${DateFormat('MMMM d, y').format(st.expires!)}.')
              else ...[
                Text('${st.scansUsed} of $freeScansPerMonth scanned papers used this month.'),
                const SizedBox(height: 8),
                SlimProgress(value: st.scansUsed / freeScansPerMonth, color: st.scansLeft == 0 ? penRed : brandBlue),
              ],
            ]),
          ),
          const SectionTitle('Free and Plus'),
          AppCard(
            child: Column(children: [
              Row(children: [
                const Expanded(flex: 3, child: SizedBox()),
                Expanded(flex: 2, child: Text('Free', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: mutedText(context)))),
                const Expanded(flex: 2, child: Text('Plus', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800))),
              ]),
              const Divider(),
              _compare('Classes', '$freeClasses', 'Unlimited'),
              _compare('Scanned papers', '$freeScansPerMonth a month', 'Unlimited'),
              _compare('Checking by tapping', 'Yes', 'Yes'),
              _compare('School forms and reports', 'Yes', 'Yes'),
              _compare('Exam maker and question bank', 'Yes', 'Yes'),
            ]),
          ),
          const SizedBox(height: 8),
          Text('Your records are always yours. If a plan ends, everything stays and you can still open, edit and print it.', style: TextStyle(fontSize: 12.5, color: mutedText(context))),
          SectionTitle(st.plus ? 'Extend your plan' : 'Get Plus'),
          _step(
            1,
            'Choose and pay by GCash',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('₱$priceYear a year')),
                  ButtonSegment(value: false, label: Text('₱$priceMonth a month')),
                ],
                selected: {_yearly},
                onSelectionChanged: (s) => setState(() => _yearly = s.first),
              ),
              if (payGcashNumber.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Send ₱${_yearly ? priceYear : priceMonth} to GCash $payGcashNumber${payGcashName.isEmpty ? '' : ' ($payGcashName)'}.'),
              ],
            ]),
          ),
          _step(
            2,
            'Send your GCash receipt',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (payContact.isNotEmpty) ...[Text('Send it to $payContact.'), const SizedBox(height: 8)],
              OutlinedButton.icon(onPressed: () => Share.share(_request()), icon: const Icon(Icons.send_rounded), label: const Text('Write the message')),
            ]),
          ),
          _step(
            3,
            'Paste your activation code',
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _code,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'KK-...',
                  errorText: _error,
                  errorMaxLines: 3,
                  suffixIcon: IconButton(tooltip: 'Paste', icon: const Icon(Icons.content_paste_rounded), onPressed: _paste),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 10),
              FilledButton(onPressed: _activate, child: const Text('Turn on Plus')),
            ]),
          ),
          // Only needed if the seller makes a code for this one phone.
          Center(
            child: SelectableText('Phone ID ${formatPhoneId(st.phoneId)}', style: TextStyle(fontSize: 11.5, color: mutedText(context))),
          ),
        ]),
      ),
    );
  }
}
