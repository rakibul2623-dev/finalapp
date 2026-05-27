import 'package:flutter/material.dart';
import '../theme.dart';

class HajjCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const HajjCard({
    super.key, 
    required this.child,
    this.padding = const EdgeInsets.all(24.0),
    this.onTap,
  });

  @override
  State<HajjCard> createState() => _HajjCardState();
}

class _HajjCardState extends State<HajjCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      transform: _isHovered ? (Matrix4.identity()..translate(0.0, -4.0)..scale(1.02)) : Matrix4.identity(),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color.fromRGBO(21, 40, 33, 0.08),
            offset: _isHovered ? const Offset(0, 8) : const Offset(0, 4),
            blurRadius: _isHovered ? 24 : 16,
          ),
        ],
      ),
      child: Padding(
        padding: widget.padding,
        child: widget.child,
      ),
    );

    if (widget.onTap != null) {
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: card,
        ),
      );
    }

    return card;
  }
}
