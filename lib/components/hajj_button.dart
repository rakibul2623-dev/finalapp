import 'package:flutter/material.dart';
import '../theme.dart';

enum HajjButtonSize { small, medium, large }

class HajjButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final HajjButtonSize size;
  final bool isSecondary;

  const HajjButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.size = HajjButtonSize.medium,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    double height = 52.0;
    if (size == HajjButtonSize.small) height = 44.0;
    if (size == HajjButtonSize.large) height = 60.0;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSecondary ? AppColors.surface : AppColors.primary,
          foregroundColor: isSecondary ? AppColors.primary : AppColors.primaryForeground,
          side: isSecondary ? const BorderSide(color: AppColors.primary, width: 1) : BorderSide.none,
          elevation: 0,
        ),
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }
}
