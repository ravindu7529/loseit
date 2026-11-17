import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'profile_setup_screen.dart';
import 'progress_screen.dart';
import 'recipe_details_screen.dart';

/// Profile, plan summary, favourites and settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.profile;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ---- Clean Profile Hero Card ------------------------------------
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primaryDeep, AppColors.primary],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDeep.withValues(alpha: 0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.mint,
                              AppColors.mint.withValues(alpha: 0.7),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _initials(p.name),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDeep,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              (p.email.isEmpty || state.isGuest)
                                  ? 'Guest session (Offline)'
                                  : p.email,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.72),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _WhitePill(p.dietaryPref),
                                _WhitePill('${p.spicePref} spice'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ---- Body -------------------------------------------------------
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // --- Calorie snapshot mini-bar --------------------------
                _SnapshotBar(state: state),
                const SizedBox(height: 16),

                // --- Plan summary: Targets ------------------------------
                _SectionLabel(label: 'YOUR TARGETS'),
                const SizedBox(height: 8),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const ProfileSetupScreen(isEditing: true),
                              ),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Edit'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      _PlanRow('Daily calorie target',
                          '${p.dailyCalorieTarget.round()} kcal'),
                      _PlanRow('Per main meal',
                          '${p.perMealTarget.round()} kcal'),
                      _PlanRow('BMR (Mifflin-St Jeor)',
                          '${p.bmr.round()} kcal'),
                      _PlanRow('Maintenance (TDEE)',
                          '${p.maintenanceCalories.round()} kcal'),
                      _PlanRow(
                          'Protein / carbs / fat',
                          '${p.proteinTargetG.round()} / '
                              '${p.carbsTargetG.round()} / '
                              '${p.fatTargetG.round()} g',
                          isLast: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- Plan summary: Body Stats ---------------------------
                _SectionLabel(label: 'BODY STATS'),
                const SizedBox(height: 8),
                AppCard(
                  child: Column(
                    children: [
                      _PlanRow('Height', '${p.heightCm.round()} cm'),
                      _PlanRow('Current weight',
                          '${state.latestWeight.toStringAsFixed(1)} kg'),
                      _PlanRow('Target weight',
                          '${p.targetWeightKg.toStringAsFixed(1)} kg'),
                      _PlanRow('BMI',
                          '${p.bmi.toStringAsFixed(1)} (${p.bmiCategory})'),
                      _PlanRow('Activity level', p.activityLevel),
                      _PlanRow('Allergies / Avoided',
                          p.allergies.isEmpty ? 'None set' : p.allergies),
                      _PlanRow('Time to goal',
                          '${p.estimatedWeeksToGoal} weeks',
                          isLast: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- Quick links ----------------------------------------
                _SectionLabel(label: 'MY ACCOUNT'),
                const SizedBox(height: 8),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _LinkTile(
                        icon: Icons.timeline_rounded,
                        iconColor: AppColors.primary,
                        title: 'Progress & weigh-ins',
                        subtitle:
                            '${state.weightHistory.length} entries recorded',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProgressScreen(),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      _LinkTile(
                        icon: Icons.favorite_border_rounded,
                        iconColor: AppColors.accent,
                        title: 'Favourite recipes',
                        subtitle: '${state.favourites.length} saved',
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: AppColors.background,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(24)),
                          ),
                          builder: (_) => const _FavouritesSheet(),
                        ),
                      ),
                      const Divider(height: 1),
                      _LinkTile(
                        icon: Icons.settings_outlined,
                        iconColor: AppColors.textSecondary,
                        title: 'Backend & assistant',
                        subtitle: state.assistantUsesLlm
                            ? 'Claude enabled'
                            : 'Offline assistant',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- How it works ---------------------------------------
                AppCard(
                  color: AppColors.mintSoft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.psychology_outlined,
                              size: 20, color: AppColors.primary),
                          const SizedBox(width: 9),
                          Text('How recommendations work',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your profile is turned into a calorie target using the '
                        'Mifflin-St Jeor equation with a 500 kcal deficit. Recipes '
                        'outside your dietary preference are removed by a hard '
                        'filter that the model never sees. The remaining recipes '
                        'are ranked by a neural network trained on 528,801 '
                        'synthetic user-recipe pairs. If the server is '
                        'unreachable, the app falls back to a simpler on-device '
                        'rule and tells you it has done so.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.55,
                              color: AppColors.primaryDeep,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                OutlinedButton.icon(
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    state.signOut();
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'LI';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// Calorie snapshot mini-bar
// ---------------------------------------------------------------------------

class _SnapshotBar extends StatelessWidget {
  const _SnapshotBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final consumed = state.caloriesConsumedToday;
    final target = state.profile.dailyCalorieTarget.round();
    final remaining = state.caloriesRemainingToday;
    final overBudget = remaining < 0;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's intake",
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(letterSpacing: 0.8),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '$consumed',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: overBudget
                            ? AppColors.accentDeep
                            : AppColors.primaryDeep,
                      ),
                    ),
                    Text(
                      ' / $target kcal',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (state.calorieProgress).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      overBudget ? AppColors.accent : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            children: [
              Text(
                overBudget ? 'Over' : '${remaining.abs()}',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: overBudget
                      ? AppColors.accentDeep
                      : AppColors.primaryDeep,
                ),
              ),
              Text(
                overBudget ? 'budget' : 'kcal left',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// White pill (used on dark hero background)
// ---------------------------------------------------------------------------

class _WhitePill extends StatelessWidget {
  const _WhitePill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: AppRadius.pill,
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan row
// ---------------------------------------------------------------------------

class _PlanRow extends StatelessWidget {
  const _PlanRow(this.label, this.value, {this.isLast = false});

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 10, bottom: isLast ? 4 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Link tile
// ---------------------------------------------------------------------------

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(subtitle,
          style: Theme.of(context).textTheme.bodyMedium),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textMuted),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Favourites sheet
// ---------------------------------------------------------------------------

class _FavouritesSheet extends StatelessWidget {
  const _FavouritesSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final favourites = state.favouriteRecipes;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('Favourites',
                      style: Theme.of(context).textTheme.headlineMedium),
                ),
                Pill('${favourites.length} saved'),
              ],
            ),
          ),
          Expanded(
            child: favourites.isEmpty
                ? const EmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: 'No favourites yet',
                    message: 'Tap the heart on any recipe to save it here.',
                  )
                : ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    itemCount: favourites.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final r = favourites[i];
                      return AppCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RecipeDetailsScreen(recipe: r),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              height: 52,
                              child: RecipeThumbnail(
                                recipe: r,
                                height: 52,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.name,
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
                                    '${r.calories} kcal  •  '
                                    '${r.protein.toStringAsFixed(0)}g protein',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.favorite,
                                  color: AppColors.accent),
                              tooltip: 'Remove from favourites',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                state.toggleFavourite(r.id);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings screen
// ---------------------------------------------------------------------------

/// Backend URL, optional Claude key, and data reset.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrl =
      TextEditingController(text: context.read<AppState>().apiBaseUrl);
  final _apiKey = TextEditingController();
  bool _obscureKey = true;

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text('Recommendation backend',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Where the trained neural network is served from. Leave the '
            'default for a local run; the app falls back to on-device '
            'scoring if this is unreachable.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'API base URL',
              hintText: 'http://127.0.0.1:8000',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () async {
                    await state.setApiBaseUrl(_baseUrl.text.trim());
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          state.scoreSource == ScoreSource.trainedModel
                              ? 'Connected to the trained-model API'
                              : 'Saved - server still unreachable, using '
                                  'on-device scoring',
                        ),
                      ),
                    );
                  },
                  child: const Text('Save & test'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ModelSourceBanner(
            source: state.scoreSource,
            onRetry: () => state.refreshRecommendations(),
          ),
          const SizedBox(height: 28),

          Text('AI Assistant',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'The assistant works offline using the bundled recipe dataset. '
            'Adding an Anthropic API key switches it to Claude, which still '
            'receives the same recipes as grounding context. The key is '
            'stored on this device only and never written into the source '
            'code - you can also supply it at build time with '
            '--dart-define=ANTHROPIC_API_KEY=...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKey,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'Anthropic API key (optional)',
              hintText: 'sk-ant-...',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(_obscureKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    state.setAssistantApiKey(_apiKey.text);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_apiKey.text.trim().isEmpty
                            ? 'Cleared - using the offline assistant'
                            : 'Claude enabled for this session'),
                      ),
                    );
                  },
                  child: const Text('Apply key'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    _apiKey.clear();
                    state.setAssistantApiKey(null);
                  },
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          const Divider(),
          const SizedBox(height: 16),
          Text('Data', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Meals, weigh-ins, favourites and chat history are stored on '
            'this device only.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Reset all data'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger, width: 1.4),
            ),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Reset all data?'),
                  content: const Text(
                    'This permanently deletes your profile, logged meals, '
                    'weigh-ins, favourites and chat history on this device. '
                    'It cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(true),
                      child: const Text('Reset everything'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
              await state.resetAllData();
              if (!context.mounted) return;
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
    );
  }
}
