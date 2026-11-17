import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../screens/recipe_details_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Interactive modal studio to generate custom Sri Lankan recipes with Generative AI.
class AiRecipeGeneratorSheet extends StatefulWidget {
  const AiRecipeGeneratorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AiRecipeGeneratorSheet(),
    );
  }

  @override
  State<AiRecipeGeneratorSheet> createState() => _AiRecipeGeneratorSheetState();
}

class _AiRecipeGeneratorSheetState extends State<AiRecipeGeneratorSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _selectedMeal = 'Dinner';
  String? _selectedVibe;
  bool _loading = false;
  String? _error;
  int _loadingStepIndex = 0;
  Timer? _loadingTimer;

  static const List<String> _loadingMessages = [
    'Infusing authentic Ceylon spices & herbs...',
    'Calibrating coconut & oil ratios for your target...',
    'Calculating precise macro split and calories...',
    'Structuring step-by-step cooking method...',
  ];

  static const List<String> _quickIngredients = [
    '🍗 Chicken',
    '🐟 Fresh Fish / Tuna',
    '🥥 Coconut Milk',
    '🥦 Gotukola / Greens',
    '🍲 Dhal / Parippu',
    '🌶️ Spicy Kochchi & Miris',
    '🫚 Garlic & Ginger',
    '🌿 Curry Leaves (Karapincha)',
    '🥚 Eggs',
    '🍠 Sweet Potato / Manioc',
    '🧀 Tofu / Soya',
    '🍅 Tomato & Capsicum',
  ];

  static const List<String> _vibes = [
    '💪 High Protein',
    '🥗 Low Calorie',
    '⏱️ Quick (<20 min)',
    '🌶️ Extra Spicy',
    '🥥 Mild & Creamy',
    '🩺 Low GI / Diabetic Friendly',
  ];

  static const List<Map<String, String>> _inspirationCards = [
    {
      'title': 'High-Protein Spicy Kottu',
      'subtitle': 'Shredded rotti with lean chicken, eggs, leeks & crushed black pepper',
      'prompt': 'Spicy Chicken Kottu with extra eggs, shredded carrots, leeks and low oil',
      'meal': 'Dinner',
      'icon': '🌶️',
    },
    {
      'title': 'Creamy Cashew & Bean Curry',
      'subtitle': 'Tender raw cashews simmered with green beans in golden coconut milk',
      'prompt': 'Creamy Cashew and Green Bean Kiri Hodi with turmeric and fenugreek',
      'meal': 'Lunch',
      'icon': '🥥',
    },
    {
      'title': 'Devilled Seer Fish Bowl',
      'subtitle': 'Stir-fried seer fish cubes with capsicum, tomatoes & tangy chili sauce',
      'prompt': 'Devilled Seer Fish with crispy capsicum, red onions and chili paste',
      'meal': 'Dinner',
      'icon': '🐟',
    },
    {
      'title': 'Low-Cal Polos Jackfruit Curry',
      'subtitle': 'Village style tender baby jackfruit infused with roasted curry powder',
      'prompt': 'Low-calorie Village Style Polos Curry with roasted spices and minimal coconut milk',
      'meal': 'Lunch',
      'icon': '🍲',
    },
    {
      'title': 'Fresh Gotukola & Dhal Mallung',
      'subtitle': 'Finely sliced pennywort with tempered yellow lentils & fresh coconut',
      'prompt': 'Crisp Gotukola Mallung tossed with tempered red dhal and lime juice',
      'meal': 'Lunch',
      'icon': '🥗',
    },
    {
      'title': 'Healthy Kithul Chia Custard',
      'subtitle': 'Natural kithul treacle infused with coconut milk & chia seeds',
      'prompt': 'Healthy Kithul Treacle and Chia Seed Coconut Pudding with crushed cardamom',
      'meal': 'Snack',
      'icon': '🍯',
    },
  ];

  static const List<Map<String, String>> _meals = [
    {'name': 'Breakfast', 'icon': '🌅'},
    {'name': 'Lunch', 'icon': '☀️'},
    {'name': 'Dinner', 'icon': '🌙'},
    {'name': 'Snack', 'icon': '☕'},
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _loadingTimer?.cancel();
    super.dispose();
  }

  void _startLoadingCycle() {
    _loadingStepIndex = 0;
    _loadingTimer?.cancel();
    _loadingTimer = Timer.periodic(const Duration(milliseconds: 2200), (timer) {
      if (mounted && _loading) {
        setState(() {
          _loadingStepIndex = (_loadingStepIndex + 1) % _loadingMessages.length;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _addIngredient(String ingredientWithEmoji) {
    HapticFeedback.selectionClick();
    final clean = ingredientWithEmoji.replaceAll(RegExp(r'^[^\w]+'), '').trim();
    final current = _controller.text.trim();
    if (current.isEmpty) {
      _controller.text = clean;
    } else if (!current.toLowerCase().contains(clean.toLowerCase())) {
      _controller.text = '$current, $clean';
    }
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  void _applyVibe(String vibe) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedVibe == vibe) {
        _selectedVibe = null;
      } else {
        _selectedVibe = vibe;
        final cleanVibe = vibe.replaceAll(RegExp(r'^[^\w]+'), '').trim();
        final current = _controller.text.trim();
        if (current.isNotEmpty && !current.toLowerCase().contains(cleanVibe.toLowerCase())) {
          _controller.text = '$current ($cleanVibe)';
        }
      }
    });
  }

  Future<void> _generate(String promptText) async {
    final clean = promptText.trim().replaceFirst(RegExp(r'^[^\w]+'), '');
    if (clean.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe your craving or select some ingredients first.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _focusNode.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    _startLoadingCycle();

    final state = context.read<AppState>();
    final result = await state.generateRecipe(clean, mealType: _selectedMeal);

    _loadingTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    if (result != null) {
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecipeDetailsScreen(recipe: result.recipe),
        ),
      );
    } else {
      setState(() {
        _error = state.generationError ??
            'Could not connect to backend generator. Please ensure the server is active.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final state = context.watch<AppState>();
    final profile = state.profile;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      margin: const EdgeInsets.only(top: 40),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: AppShadows.floating,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Top Header Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryLight],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.mint,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Recipe Generator',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDeep,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Craft custom Sri Lankan meals fitted to your calories',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceMuted,
                      shape: const CircleBorder(),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                    onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.border),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Safety / Avoidance Badge
                    if (profile.allergies.isNotEmpty || profile.dietaryPref.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.mintSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.mint),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shield_rounded, size: 18, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                profile.allergies.isNotEmpty
                                    ? 'Respecting avoidances: ${profile.allergies}'
                                    : 'Tailored for ${profile.dietaryPref} diet',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDeep,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'AUTO-SYNCED',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Prompt Input Field
                    const Text(
                      'What would you like to eat?',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDeep,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: !_loading,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g., Spicy chicken kottu with less oil, or pol sambol with boiled manioc & eggs...',
                        hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surface,
                        suffixIcon: _controller.text.isNotEmpty && !_loading
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () => setState(() => _controller.clear()),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),

                    // Quick-Add Ingredients
                    const Row(
                      children: [
                        Icon(Icons.add_circle_outline_rounded, size: 16, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text(
                          'Tap to add ingredients on hand',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDeep,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          for (final ing in _quickIngredients)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                onTap: _loading ? null : () => _addIngredient(ing),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Text(
                                    ing,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Meal Type Selector
                    const Text(
                      'Meal Category',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDeep,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final m in _meals)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: InkWell(
                                onTap: _loading
                                    ? null
                                    : () {
                                        HapticFeedback.selectionClick();
                                        setState(() => _selectedMeal = m['name']!);
                                      },
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _selectedMeal == m['name']
                                        ? AppColors.primary
                                        : AppColors.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedMeal == m['name']
                                          ? AppColors.primary
                                          : AppColors.border,
                                      width: 1.2,
                                    ),
                                    boxShadow: _selectedMeal == m['name']
                                        ? [
                                            BoxShadow(
                                              color: AppColors.primary.withValues(alpha: 0.2),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        m['icon']!,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        m['name']!,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: _selectedMeal == m['name']
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Dietary / Target Vibe Selector
                    const Text(
                      'Dietary Focus & Vibe',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDeep,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final vibe in _vibes)
                          FilterChip(
                            label: Text(vibe),
                            selected: _selectedVibe == vibe,
                            selectedColor: AppColors.mintSoft,
                            checkmarkColor: AppColors.primary,
                            backgroundColor: AppColors.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: _selectedVibe == vibe ? AppColors.primary : AppColors.border,
                              ),
                            ),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _selectedVibe == vibe
                                  ? AppColors.primaryDeep
                                  : AppColors.textPrimary,
                            ),
                            onSelected: _loading ? null : (_) => _applyVibe(vibe),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Quick Inspiration Prompts Carousel/Cards
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Sri Lankan Cravings & Ideas',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDeep,
                          ),
                        ),
                        Text(
                          'Tap to use',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _inspirationCards.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final card = _inspirationCards[i];
                        return InkWell(
                          onTap: _loading
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  _controller.text = card['prompt']!;
                                  setState(() {
                                    _selectedMeal = card['meal']!;
                                  });
                                },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: AppColors.mintSoft,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    card['icon']!,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        card['title']!,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        card['subtitle']!,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                  color: AppColors.textMuted,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // Error Alert
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF991B1B), fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Dynamic Loading Indicator Card
                    if (_loading) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primaryDeep, AppColors.primary],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppShadows.card,
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.8,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.mint),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Synthesizing Recipe with AI',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: Text(
                                      _loadingMessages[_loadingStepIndex],
                                      key: ValueKey(_loadingStepIndex),
                                      style: TextStyle(
                                        color: AppColors.mint.withValues(alpha: 0.9),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Submit Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _loading ? null : () => _generate(_controller.text),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.auto_awesome_rounded, color: AppColors.mint, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _loading ? 'Generating Recipe...' : 'Invent Recipe with AI',
                              style: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
