import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../data/profile_repository.dart';
import 'profile_tokens.dart';
import 'widgets/profile_card.dart';

/// `intl` bundles zero symbol data for "tg" (same gap
/// personal_details_screen.dart's own copy of this helper works around),
/// so DateFormat falls back to "ru" rather than throwing for that locale.
String _dateFormatLocale(BuildContext context) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.localeExists(locale) ? locale : 'ru';
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Full activity-history calendar (§ activity history calendar, 2026-09-05)
/// — reached via the "Все" button on the profile's week-activity card. That
/// card stays exactly what it was, a 7-day snapshot; this screen is where
/// the full, permanently-accumulating per-day history (kept server-side
/// regardless of how far back it goes) is actually browsable, one calendar
/// month at a time.
class ActivityHistoryScreen extends ConsumerStatefulWidget {
  const ActivityHistoryScreen({super.key});

  @override
  ConsumerState<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends ConsumerState<ActivityHistoryScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shiftMonth(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta, 1));

  void _showDayDetail(DayActivity day) {
    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    final date = DateTime.parse(day.date);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius), border: Border.all(color: c.border)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: day.active ? c.success : c.border)),
                  const SizedBox(width: 8),
                  Text(_capitalize(DateFormat.yMMMMd(_dateFormatLocale(context)).format(date)), style: ProfileTypography.sectionTitle(sheetContext)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                day.active ? l10n.activityHistoryMinutesActive(day.seconds ~/ 60) : l10n.activityHistoryNoActivity,
                style: ProfileTypography.body(sheetContext).copyWith(color: day.active ? c.text : c.textMuted),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    final isWide = MediaQuery.sizeOf(context).width >= ProfileMetrics.wideBreakpoint;
    final history = ref.watch(activityHistoryMonthProvider((year: _month.year, month: _month.month)));

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        title: Text(l10n.activityHistoryTitle, style: ProfileTypography.sectionTitle(context)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? ProfileMetrics.desktopContentMaxWidth : double.infinity),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ProfileMetrics.pageMarginMobile),
              child: ProfileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shiftMonth(-1)),
                        Text(_capitalize(DateFormat.yMMMM(_dateFormatLocale(context)).format(_month)), style: ProfileTypography.sectionTitle(context)),
                        IconButton(icon: const Icon(Icons.chevron_right), onPressed: _isCurrentMonth ? null : () => _shiftMonth(1)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    history.when(
                      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                      error: (err, st) => Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l10n.activityHistoryLoadError(err), style: ProfileTypography.body(context)),
                      ),
                      data: (days) => _MonthGrid(month: _month, days: days, onTapDay: _showDayDetail),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.days, required this.onTapDay});
  final DateTime month;
  final List<DayActivity> days;
  final ValueChanged<DayActivity> onTapDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final byDay = {for (final d in days) DateTime.parse(d.date).day: d};
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // month.weekday: Monday=1..Sunday=7 — this many blank leading cells
    // before day 1 keep every date under its real day-of-week column.
    final leadingBlanks = month.weekday - 1;
    final today = DateTime.now();
    final dayLabels = [
      l10n.weekActivityDayMon,
      l10n.weekActivityDayTue,
      l10n.weekActivityDayWed,
      l10n.weekActivityDayThu,
      l10n.weekActivityDayFri,
      l10n.weekActivityDaySat,
      l10n.weekActivityDaySun,
    ];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (final label in dayLabels) Expanded(child: Center(child: Text(label, style: ProfileTypography.caption(context))))],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
            for (var dayNum = 1; dayNum <= daysInMonth; dayNum++)
              _DayCell(
                dayNum: dayNum,
                activity: byDay[dayNum],
                isFuture: DateTime(month.year, month.month, dayNum).isAfter(DateTime(today.year, today.month, today.day)),
                onTap: onTapDay,
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.dayNum, required this.activity, required this.isFuture, required this.onTap});
  final int dayNum;
  final DayActivity? activity;
  final bool isFuture;
  final ValueChanged<DayActivity> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    // A future day (later this month than today) has no real answer yet —
    // rendered as a plain muted number, distinct from a past day that
    // genuinely had no recorded activity, and not tappable.
    final active = activity?.active ?? false;
    final fill = !isFuture && active ? c.success : Colors.transparent;
    final border = isFuture ? Colors.transparent : (active ? c.success : c.border);
    final textColor = isFuture ? c.textMuted : (active ? Colors.white : c.text);

    return Padding(
      padding: const EdgeInsets.all(3),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: isFuture || activity == null ? null : () => onTap(activity!),
        child: Container(
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: border, width: 1.5)),
          alignment: Alignment.center,
          child: Text('$dayNum', style: ProfileTypography.body(context).copyWith(color: textColor, fontSize: 13)),
        ),
      ),
    );
  }
}
