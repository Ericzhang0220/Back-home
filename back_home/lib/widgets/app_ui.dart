import 'package:flutter/material.dart';

class AppColors {
  static const Color cream = Color(0xFFFCF7F1);
  static const Color card = Color(0xFFF8EFE4);
  static const Color blush = Color(0xFFF4D7C5);
  static const Color peach = Color(0xFFF2C6A8);
  static const Color clay = Color(0xFFB36A49);
  static const Color sage = Color(0xFF7E9A84);
  static const Color gold = Color(0xFFDAA75D);
  static const Color ink = Color(0xFF3D2A24);
  static const Color muted = Color(0xFF806A60);
  static const Color stroke = Color(0xFFE8D8C8);

  const AppColors._();
}

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    this.showTopGlow = true,
    this.showSideGlow = true,
  });

  final bool showTopGlow;
  final bool showSideGlow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFBF6),
            Color.fromARGB(255, 255, 237, 224),
            Color.fromARGB(255, 255, 221, 198),
          ],
        ),
      ),
      child: Stack(
        children: [
          if (showTopGlow)
            const _GlowOrb(
              alignment: Alignment.topRight,
              color: Color(0x55FFFFFF),
              size: 240,
              offset: Offset(60, -40),
            ),
          if (showSideGlow)
            const _GlowOrb(
              alignment: Alignment.centerLeft,
              color: Color(0x40F4D7C5),
              size: 220,
              offset: Offset(-90, -20),
            ),
        ],
      ),
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 140),
  });

  final String? eyebrow;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null)
            Text(
              eyebrow!.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.clay,
                letterSpacing: 1.6,
              ),
            ),
          if (eyebrow != null) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 0, 0, 0),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: const Color.fromARGB(255, 0, 0, 0),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          ),
          const SizedBox(height: 28),
          ...children,
        ],
      ),
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
    this.color,
    this.radius = 28,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.card.withValues(alpha: 0.92),
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.stroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.titleSize = 20,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final double titleSize;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: titleSize,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tint = AppColors.blush,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.clay),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text(value, style: theme.textTheme.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.ink),
                ),
                const Spacer(),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(subtitle, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.icon,
    this.highlight = false,
  });

  final String label;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? AppColors.ink : Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight ? AppColors.ink : AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: highlight ? Colors.white : AppColors.clay,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              color: highlight ? Colors.white : AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class MoodBarChart extends StatelessWidget {
  const MoodBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.emoji,
  }) : assert(values.length == labels.length);

  final List<double> values;
  final List<String> labels;
  final List<String>? emoji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(values.length, (index) {
        final clamped = values[index].clamp(0.0, 1.0);
        final height = 28 + (clamped * 54);

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (emoji != null) ...[
                  Text(emoji![index], style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                ],
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [AppColors.clay, AppColors.peach],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                const SizedBox(height: 10),
                Text(labels[index], style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.alignment,
    required this.color,
    required this.size,
    required this.offset,
  });

  final Alignment alignment;
  final Color color;
  final double size;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: offset,
        child: Container(
          height: size,
          width: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, Colors.transparent]),
          ),
        ),
      ),
    );
  }
}
