import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// LinearLoadingWidget matching the exact HTML specification for the Initialization Screen:
/// - "Initializing..." heading (24px, font-display, text-on-surface-variant, tracking-tight).
/// - 128px wide by 4px high linear indeterminate progress bar (bg-surface-container-high & bg-primary).
class LinearLoadingWidget extends StatefulWidget {
  final String text;

  const LinearLoadingWidget({
    super.key,
    this.text = 'Initializing...',
  });

  @override
  State<LinearLoadingWidget> createState() => _LinearLoadingWidgetState();
}

class _LinearLoadingWidgetState extends State<LinearLoadingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final textColor = isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant;
    final barBgColor = isDark ? const Color(0xFF2A2A2A) : AppColors.lightSurfaceContainerHigh;
    final primaryColor = isDark ? const Color(0xFF1A73E8) : AppColors.lightPrimaryContainer;

    return Container(
      color: backgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Heading Text
            Text(
              widget.text,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 32),

            // Linear Progress Bar (w-32 / 128px wide, h-1 / 4px high)
            Container(
              width: 128,
              height: 4,
              decoration: BoxDecoration(
                color: barBgColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    final val = _animation.value;
                    final left = (val * 1.8 - 0.4).clamp(0.0, 1.0);
                    final right = (val * 1.8).clamp(0.0, 1.0);

                    return Stack(
                      children: [
                        Positioned(
                          left: left * 128,
                          width: (right - left) * 128,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Backwards compatibility alias
typedef WaveLoadingWidget = LinearLoadingWidget;
