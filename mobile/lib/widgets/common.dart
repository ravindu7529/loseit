import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';

/// The white rounded container every screen builds its sections from.
///
/// Supports an optional [onTap] callback which renders an [InkWell] with a
/// subtle scale-down animation for tactile feedback.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = AppColors.surface,
    this.onTap,
    this.border,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final VoidCallback? onTap;
  final BoxBorder? border;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      lowerBound: 0.97,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  void _onTapDown(_) {
    if (widget.onTap != null) _scale.reverse();
  }

  void _onTapUp(_) => _scale.forward();
  void _onTapCancel() => _scale.forward();

  void _onTap() {
    if (widget.onTap == null) return;
    HapticFeedback.lightImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: widget.padding, child: widget.child);

    if (widget.onTap != null) {
      content = InkWell(
        onTap: _onTap,
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        borderRadius: AppRadius.card,
        child: content,
      );
    }

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.card,
        border: widget.border,
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: widget.color,
        borderRadius: AppRadius.card,
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );

    if (widget.onTap == null) return card;

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: card,
    );
  }
}

/// Small rounded label used for macros, dietary tags and AI badges.
class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.background = AppColors.mintSoft,
    this.foreground = AppColors.primaryDeep,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 11,
        vertical: dense ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 11 : 12.5,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.onTrailingTap,
  });

  final String title;
  final IconData? icon;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (trailing != null)
          TextButton(
            onPressed: onTrailingTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(trailing!),
          ),
      ],
    );
  }
}

/// Illustrated or photographic food image tile.
///
/// If an [imageUrl] is available, it displays the high-resolution food
/// photograph with smooth opacity fade-in. If offline or when loading fails,
/// it gracefully falls back to the deterministic gradient + glyph tile derived
/// from the recipe's food group and ID.
class RecipeThumbnail extends StatelessWidget {
  const RecipeThumbnail({
    super.key,
    required this.recipe,
    this.height = 160,
    this.borderRadius,
    this.showFoodGroup = true,
  });

  final Recipe recipe;
  final double height;
  final BorderRadius? borderRadius;
  final bool showFoodGroup;

  static const Map<String, List<Color>> _palettes = {
    'Rice & Curry': [Color(0xFF7A4B2A), Color(0xFFC98B54)],
    'Vegetables': [Color(0xFF2F6B4F), Color(0xFF7CB893)],
    'Leafy Greens': [Color(0xFF2C5F3A), Color(0xFF74A868)],
    'Sambol': [Color(0xFF9C3B22), Color(0xFFE08A5C)],
    'Bread & Hoppers': [Color(0xFF8A6A3A), Color(0xFFD9B77E)],
    'Short Eats': [Color(0xFF8F5220), Color(0xFFDBA061)],
    'Dessert': [Color(0xFF6E3B5C), Color(0xFFC98BB2)],
    'Beverage': [Color(0xFF2F5F6B), Color(0xFF84B8C4)],
    'Seafood': [Color(0xFF215A6B), Color(0xFF6FB0BE)],
    'Soup': [Color(0xFF8C4A28), Color(0xFFD48B55)],
    'One-Pot / Rice Dish': [Color(0xFF855A20), Color(0xFFD4A355)],
    'Condiment / Sambol': [Color(0xFF9C3B22), Color(0xFFE08A5C)],
    'Breakfast Porridge': [Color(0xFF336345), Color(0xFF76A884)],
  };

  static const List<Color> _fallback = [
    Color(0xFF3C5F4C),
    Color(0xFF8FB8A0),
  ];

  static const Map<String, IconData> _glyphs = {
    'Rice & Curry': Icons.rice_bowl_outlined,
    'Vegetables': Icons.eco_outlined,
    'Leafy Greens': Icons.spa_outlined,
    'Sambol': Icons.local_fire_department_outlined,
    'Condiment / Sambol': Icons.local_fire_department_outlined,
    'Bread & Hoppers': Icons.breakfast_dining_outlined,
    'Short Eats': Icons.bakery_dining_outlined,
    'Dessert': Icons.icecream_outlined,
    'Beverage': Icons.local_cafe_outlined,
    'Seafood': Icons.set_meal_outlined,
    'Soup': Icons.soup_kitchen_outlined,
    'One-Pot / Rice Dish': Icons.dinner_dining_outlined,
    'Breakfast Porridge': Icons.free_breakfast_outlined,
  };

  Widget _buildFallback(BuildContext context, {bool isPlaceholder = false}) {
    final colors = _palettes[recipe.foodGroup] ?? _fallback;
    final glyph = _glyphs[recipe.foodGroup] ?? Icons.restaurant_outlined;

    final seed = recipe.id.hashCode.abs() % 4;
    const alignments = [
      [Alignment.topLeft, Alignment.bottomRight],
      [Alignment.topRight, Alignment.bottomLeft],
      [Alignment.topCenter, Alignment.bottomCenter],
      [Alignment.centerLeft, Alignment.centerRight],
    ];

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: alignments[seed][0],
          end: alignments[seed][1],
          colors: colors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -14,
            bottom: -14,
            child: Icon(
              glyph,
              size: height * 0.78,
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          if (showFoodGroup && height >= 70 && recipe.foodGroup.isNotEmpty)
            Positioned(
              left: 14,
              bottom: 12,
              right: 14,
              child: Text(
                recipe.foodGroup.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ??
        const BorderRadius.vertical(top: Radius.circular(AppRadius.md));

    final url = recipe.imageUrl;
    Widget content;

    if (url != null && url.isNotEmpty) {
      content = Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return Stack(
              fit: StackFit.expand,
              children: [
                child,
                // Soft bottom gradient scrim to maintain readability of text & pills
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.5, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
                if (showFoodGroup && height >= 70 && recipe.foodGroup.isNotEmpty)
                  Positioned(
                    left: 14,
                    bottom: 12,
                    right: 14,
                    child: Text(
                      recipe.foodGroup.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Colors.white.withValues(alpha: 0.95),
                        shadows: const [
                          Shadow(
                            blurRadius: 4,
                            color: Colors.black45,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          }
          return _buildFallback(context, isPlaceholder: true);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallback(context);
        },
      );
    } else {
      content = _buildFallback(context);
    }

    return ClipRRect(
      borderRadius: effectiveRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: content,
      ),
    );
  }
}

/// Full-width empty/loading placeholder used by list screens.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.mintSoft, AppColors.mint],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(icon, size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Top bar used by the four main tabs: avatar, wordmark, bell.
class LoseItAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LoseItAppBar({
    super.key,
    required this.initials,
    this.onAvatarTap,
    this.actions,
  });

  final String initials;
  final VoidCallback? onAvatarTap;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 64,
      titleSpacing: 20,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.mint, AppColors.mintSoft],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 1.8),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.primaryDeep,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [AppColors.primaryDeep, AppColors.primary],
            ).createShader(bounds),
            child: const Text(
              'Spice & Scale',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white, // masked by shader
              ),
            ),
          ),
        ],
      ),
      actions: [
        ...?actions,
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded),
          tooltip: 'Notifications',
          onPressed: () {
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No new notifications')),
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Banner telling the user which scorer produced the current list.
class ModelSourceBanner extends StatelessWidget {
  const ModelSourceBanner({super.key, required this.source, this.onRetry});

  final ScoreSource source;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isTrained = source == ScoreSource.trainedModel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isTrained ? AppColors.mintSoft : const Color(0xFFFDEDE2),
        borderRadius: AppRadius.card,
      ),
      child: Row(
        children: [
          Icon(
            isTrained ? Icons.auto_awesome : Icons.cloud_off_rounded,
            size: 17,
            color: isTrained ? AppColors.primary : AppColors.accentDeep,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              source.description,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: isTrained ? AppColors.primaryDeep : AppColors.accentDeep,
              ),
            ),
          ),
          if (!isTrained && onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
