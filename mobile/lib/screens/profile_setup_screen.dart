import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/user_profile.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Collects the inputs the recommender needs: age, gender, height,
/// weight, target weight, activity level, dietary preference and spice
/// preference. These map one-to-one onto the model's input features.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.isEditing = false});

  /// When true the screen is opened from Settings rather than onboarding,
  /// so it shows a back button and "Save changes" instead of a stepper.
  final bool isEditing;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();

  int _currentStep = 0; // 0: Body & Goals, 1: Diet & Spice, 2: Allergies & Avoidances

  late TextEditingController _age;
  late TextEditingController _height;
  late TextEditingController _weight;
  late TextEditingController _targetWeight;
  late TextEditingController _allergies;

  late String _gender;
  late String _activity;
  late String _diet;
  late String _spice;

  bool _busy = false;

  static const List<Map<String, String>> _commonAllergens = [
    {'label': '🥜 Peanuts & Nuts', 'value': 'nuts'},
    {'label': '🥛 Dairy & Milk', 'value': 'dairy'},
    {'label': '🦐 Shellfish & Prawns', 'value': 'shellfish'},
    {'label': '🥚 Eggs', 'value': 'egg'},
    {'label': '🌾 Gluten / Wheat', 'value': 'gluten'},
    {'label': '🍈 Bitter Gourd (Karawila)', 'value': 'karawila'},
    {'label': '🍄 Mushrooms', 'value': 'mushroom'},
    {'label': '🥥 Coconut Milk/Pol', 'value': 'coconut'},
    {'label': '🍯 Kithul Treacle', 'value': 'kithul'},
    {'label': '🐟 Fish / Sprats', 'value': 'fish'},
  ];

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().profile;
    _age = TextEditingController(text: '${p.age}');
    _height = TextEditingController(text: p.heightCm.round().toString());
    _weight = TextEditingController(text: _trim(p.weightKg));
    _targetWeight = TextEditingController(text: _trim(p.targetWeightKg));
    _allergies = TextEditingController(text: p.allergies);
    _gender = p.gender;
    _activity = p.activityLevel;
    _diet = p.dietaryPref;
    _spice = p.spicePref;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  void dispose() {
    _pageController.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _targetWeight.dispose();
    _allergies.dispose();
    super.dispose();
  }

  bool _isAllergenSelected(String value) {
    final currentText = _allergies.text.trim();
    if (currentText.isEmpty) return false;
    final items = currentText.split(',').map((s) => s.trim().toLowerCase()).toList();
    return items.contains(value.toLowerCase());
  }

  void _toggleAllergen(String value) {
    final currentText = _allergies.text.trim();
    final items = currentText.isEmpty
        ? <String>[]
        : currentText.split(',').map((s) => s.trim().toLowerCase()).toList();

    final valLow = value.toLowerCase();
    if (items.contains(valLow)) {
      items.remove(valLow);
    } else {
      items.add(valLow);
    }

    setState(() {
      _allergies.text = items.join(', ');
    });
  }

  void _nextStep() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_currentStep == 0) {
      if (!_formKey.currentState!.validate()) return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  void _prevStep() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);

    final appState = context.read<AppState>();
    final age = int.tryParse(_age.text.trim()) ?? 25;
    final height = double.tryParse(_height.text.trim()) ?? 170.0;
    final weight = double.tryParse(_weight.text.trim()) ?? 70.0;
    final target = double.tryParse(_targetWeight.text.trim()) ?? 65.0;

    final prevProfile = appState.profile;
    final updated = prevProfile.copyWith(
      name: prevProfile.name,
      email: prevProfile.email,
      age: age,
      gender: _gender,
      heightCm: height,
      weightKg: weight,
      targetWeightKg: target,
      activityLevel: _activity,
      dietaryPref: _diet,
      spicePref: _spice,
      allergies: _allergies.text.trim(),
    );

    await appState.saveProfile(updated, completeOnboarding: !widget.isEditing);

    if (!mounted) return;
    setState(() => _busy = false);

    if (widget.isEditing) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nutrition plan updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepTitles = ['Body & Goals', 'Diet & Spice', 'Allergies & Avoidances'];
    final progressValue = (_currentStep + 1) / 3.0;

    return Scaffold(
      appBar: widget.isEditing
          ? AppBar(title: const Text('Edit Your Nutrition Plan'))
          : null,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // --- Fixed Top Step Header & Progress Bar --------------
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Step ${_currentStep + 1} of 3 • ${stepTitles[_currentStep]}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDeep,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '${(progressValue * 100).round()}%',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 8,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E5E3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: constraints.maxWidth * progressValue,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // --- Wizard Step Content -------------------------------
              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey('step_page_$_currentStep'),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // =================================================
                      // STEP 1: Body & Goals
                      // =================================================
                      if (_currentStep == 0) ...[
                        Text('Tell us about yourself',
                            style: Theme.of(context).textTheme.displayLarge),
                        const SizedBox(height: 8),
                        Text(
                          "We'll compute your baseline metabolic rate (Mifflin-St Jeor) "
                          "and safe calorie deficit.",
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                        const SizedBox(height: 24),

                        // --- Age + gender ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _Field(
                                label: 'Age',
                                child: TextFormField(
                                  controller: _age,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  validator: (v) => _validateRange(v, 13, 100, 'age'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _Field(
                                label: 'Gender',
                                child: _SegmentedChoice(
                                  options: kGenders,
                                  selected: _gender,
                                  onChanged: (v) => setState(() => _gender = v),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // --- Height + Current Weight ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _Field(
                                label: 'Height (cm)',
                                child: TextFormField(
                                  controller: _height,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  validator: (v) => _validateRange(v, 100, 250, 'height'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _Field(
                                label: 'Current Weight (kg)',
                                child: TextFormField(
                                  controller: _weight,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [_decimalFormatter],
                                  validator: (v) => _validateRange(v, 25, 300, 'weight'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // --- Target weight ---
                        _Field(
                          label: 'Target Weight (kg)',
                          child: TextFormField(
                            controller: _targetWeight,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [_decimalFormatter],
                            validator: (v) => _validateRange(v, 25, 300, 'target weight'),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // --- Activity Level ---
                        Text('Activity Level',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        for (final level in kActivityLevels) ...[
                          _ActivityOption(
                            level: level,
                            selected: _activity == level,
                            onTap: () => setState(() => _activity = level),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],

                      // =================================================
                      // STEP 2: Diet & Spice Preferences
                      // =================================================
                      if (_currentStep == 1) ...[
                        Text('Taste & Dietary Rules',
                            style: Theme.of(context).textTheme.displayLarge),
                        const SizedBox(height: 8),
                        Text(
                          'Condition recommendations and AI recipe creations to your taste profile.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                        const SizedBox(height: 24),

                        // --- Dietary preference ---
                        Text('Dietary Preference',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          'Applied as a hard filter — recipes outside this boundary are strictly excluded.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final d in kDietaryPrefs)
                              _ChoiceChipTile(
                                key: ValueKey('diet_$d'),
                                label: d == 'Non-Vegetarian' ? 'Non-Veg' : d,
                                selected: _diet == d,
                                onTap: () => setState(() => _diet = d),
                              ),
                          ],
                        ),
                        const SizedBox(height: 28),

                        // --- Spice preference ---
                        Text('Spice Preference',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          'Guides the AI neural recommender to match authentic Sri Lankan spice heat.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final s in kSpicePrefs)
                              _ChoiceChipTile(
                                key: ValueKey('spice_$s'),
                                label: s == 'Mild'
                                    ? '🟢 Mild'
                                    : s == 'Medium'
                                        ? '🟡 Medium'
                                        : '🔴 Hot & Spicy',
                                selected: _spice == s,
                                onTap: () => setState(() => _spice = s),
                              ),
                          ],
                        ),
                      ],

                      // =================================================
                      // STEP 3: Allergies & Food Avoidances
                      // =================================================
                      if (_currentStep == 2) ...[
                        Text('Allergies & Avoidances',
                            style: Theme.of(context).textTheme.displayLarge),
                        const SizedBox(height: 8),
                        Text(
                          'Tell us any foods, allergens, or ingredients you want to avoid. '
                          'Our recommender and generative AI models will strictly exclude them.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                        const SizedBox(height: 22),

                        // Quick allergen chips
                        Text('Quick Allergen Select',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          'Tap any item to quickly add or remove it from your avoidance list:',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in _commonAllergens)
                              _AllergenChip(
                                key: ValueKey('allergen_${item['value']}'),
                                label: item['label']!,
                                selected: _isAllergenSelected(item['value']!),
                                onTap: () => _toggleAllergen(item['value']!),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Freeform text input
                        _Field(
                          label: 'Foods or Ingredients to Avoid (Comma-separated)',
                          child: TextFormField(
                            controller: _allergies,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'e.g. peanuts, dairy, shellfish, mushrooms, bitter gourd, kithul...',
                              hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
                              filled: true,
                              fillColor: AppColors.surfaceMuted,
                              border: OutlineInputBorder(
                                borderRadius: AppRadius.card,
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined, size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Active filter: Any recipe containing these terms will be hidden.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontSize: 12.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // --- Fixed Bottom Navigation Bar -----------------------
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border, width: 1)),
                ),
                child: Row(
                  children: [
                    if (_currentStep > 0) ...[
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _busy ? null : _prevStep,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_rounded, size: 18),
                            SizedBox(width: 6),
                            Text('Back'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        key: const ValueKey('wizard_next_button'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _busy ? null : _nextStep,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _currentStep < 2
                                        ? 'Next'
                                        : (widget.isEditing ? 'Save Changes' : 'Calculate My Plan'),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                  ),
                                  if (_currentStep < 2) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.arrow_forward_rounded, size: 18),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static final _decimalFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,1}'));

  static String? _validateRange(String? v, num lo, num hi, String label) {
    final value = double.tryParse((v ?? '').trim());
    if (value == null) return 'Enter your $label';
    if (value < lo || value > hi) return 'Enter a $label between $lo and $hi';
    return null;
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ActivityOption extends StatelessWidget {
  const _ActivityOption({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final String level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      color: selected ? AppColors.mint : AppColors.surface,
      border: Border.all(
        color: selected ? AppColors.primary : AppColors.border,
        width: selected ? 1.6 : 1.2,
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.textMuted,
                width: 2,
              ),
              color: selected ? AppColors.primary : Colors.transparent,
            ),
            child: selected
                ? const Center(
                    child: Icon(Icons.circle, size: 8, color: Colors.white),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  level,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppColors.primaryDeep
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kActivityBlurb[level] ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedChoice extends StatelessWidget {
  const _SegmentedChoice({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.card,
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final opt in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(opt),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: opt == selected ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: opt == selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      opt,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: opt == selected
                            ? AppColors.primaryDeep
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChoiceChipTile extends StatelessWidget {
  const _ChoiceChipTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      color: selected ? AppColors.mint : AppColors.surface,
      border: Border.all(
        color: selected ? AppColors.primary : AppColors.border,
        width: selected ? 1.6 : 1.2,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.primaryDeep : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _AllergenChip extends StatelessWidget {
  const _AllergenChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: selected ? AppColors.mint : AppColors.surface,
      border: Border.all(
        color: selected ? AppColors.primary : AppColors.border,
        width: selected ? 1.6 : 1.1,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            const Icon(Icons.check_rounded, size: 14, color: AppColors.primaryDeep),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primaryDeep : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
