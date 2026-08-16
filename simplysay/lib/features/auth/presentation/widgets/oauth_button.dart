import 'package:flutter/material.dart';

class OAuthButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onPressed;

  const OAuthButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        side: BorderSide(
          color: const Color(0xFFC1C6D6).withValues(alpha: 0.5),
          width: 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
        ),
        backgroundColor: isDark ? const Color(0xFF0E0E0E) : Colors.white,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 24 / 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
