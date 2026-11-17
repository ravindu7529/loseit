import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/tracking.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'log_meal_sheet.dart';

/// Weight journey, quick daily stats, weigh-in entry and history.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _weight = TextEditingController();
  bool _showAllHistory = false;

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_weight.text.trim());
    if (value == null || value < 25 || value > 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a weight between 25 and 300 kg')),
      );
      return;
    }
    await context.read<AppState>().logWeight(value);
    if (!mounted) return;
    _weight.clear();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Logged ${value.toStringAsFixed(1)} kg')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.weightHistory;
    final shown = _showAllHistory ? history : history.take(5).toList();
    final change = state.totalWeightChange;

    return Scaffold(
      appBar: AppBar(title: const Text('Your Progress')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => showLogMealSheet(context),
        tooltip: 'Log a meal',
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OVERVIEW',
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text('Weight Journey',
                        style: Theme.of(context).textTheme.headlineMedium),
                  ],
                ),
              ),
              Pill(
                change == 0
                    ? 'No change'
                    : '${change > 0 ? '+' : '-'}${change.abs().toStringAsFixed(1)} kg',
                icon: change <= 0
                    ? Icons.trending_down_rounded
                    : Icons.trending_up_rounded,
                background:
                    change <= 0 ? AppColors.mint : const Color(0xFFFBE4D8),
                foreground:
                    change <= 0 ? AppColors.primaryDeep : AppColors.accentDeep,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // --- Chart ------------------------------------------------
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Weight over time',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    Text(
                      history.isEmpty
                          ? '-'
                          : 'Last ${history.length} entries',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                WeightLineChart(
                  values: state.weightSeries.map((w) => w.weightKg).toList(),
                ),
                const SizedBox(height: 10),
                if (state.weightSeries.length >= 2)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _shortDate(state.weightSeries.first.recordedAt),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text('Today',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // --- Quick stats ------------------------------------------
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.local_fire_department_outlined,
                  iconColor: AppColors.accent,
                  label: 'Eaten today',
                  value: '${state.caloriesConsumedToday}',
                  unit: 'kcal',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.flag_outlined,
                  iconColor: AppColors.primary,
                  label: 'To goal',
                  value: state.profile.weightToLose.toStringAsFixed(1),
                  unit: 'kg',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.event_available_outlined,
                  iconColor: const Color(0xFF6B5FA8),
                  label: 'Est. weeks',
                  value: '${state.profile.estimatedWeeksToGoal}',
                  unit: 'wks',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // --- Log weight -------------------------------------------
          AppCard(
            color: AppColors.surfaceMuted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Log Today's Weight",
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weight,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d{0,3}\.?\d{0,1}')),
                        ],
                        onSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          hintText: '00.0',
                          suffixText: 'kg',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(110, 56),
                        ),
                        onPressed: _save,
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Saving also updates your calorie target, since it is '
                  'derived from your current weight.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- History ----------------------------------------------
          SectionHeader(
            title: 'Recent History',
            trailing: history.length > 5
                ? (_showAllHistory ? 'Show less' : 'View All')
                : null,
            onTrailingTap: () =>
                setState(() => _showAllHistory = !_showAllHistory),
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.monitor_weight_outlined,
                title: 'No weigh-ins yet',
                message: 'Log your first weight above to start the chart.',
              ),
            )
          else
            for (var i = 0; i < shown.length; i++) ...[
              _HistoryRow(
                entry: shown[i],
                previous: i + 1 < history.length ? history[i + 1] : null,
              ),
              if (i != shown.length - 1) const SizedBox(height: 10),
            ],

          const SizedBox(height: 24),

          // --- Today's meals ----------------------------------------
          SectionHeader(title: "Today's Meals"),
          const SizedBox(height: 12),
          if (state.todaysMeals.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.restaurant_outlined,
                title: 'Nothing logged today',
                message: 'Tap the + button to log a meal.',
              ),
            )
          else
            for (final meal in state.todaysMeals.reversed) ...[
              AppCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meal.recipeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${meal.mealType}  •  '
                            '${DateFormat.jm().format(meal.loggedAt)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${meal.calories} kcal',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDeep,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, size: 19),
                      color: AppColors.textMuted,
                      onPressed: () => state.removeMeal(meal.id),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  static String _shortDate(DateTime d) => DateFormat('d MMM').format(d);
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 12.5,
                ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDeep,
                  ),
                ),
                TextSpan(
                  text: unit,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, this.previous});

  final WeightEntry entry;

  /// The next-older entry, used to show the delta.
  final WeightEntry? previous;

  @override
  Widget build(BuildContext context) {
    final delta = previous == null ? null : entry.weightKg - previous!.weightKg;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('d').format(entry.recordedAt),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDeep,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(entry.recordedAt).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.weightKg.toStringAsFixed(1)} kg',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat.jm().format(entry.recordedAt),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Text(
            delta == null
                ? '--'
                : '${delta > 0 ? '+' : delta < 0 ? '-' : ''}'
                    '${delta.abs().toStringAsFixed(1)}kg',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: delta == null || delta == 0
                  ? AppColors.textMuted
                  : delta < 0
                      ? AppColors.primary
                      : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
