import 'dart:async';
import 'package:flutter/material.dart';

/// A reusable fade-and-slide-in animation wrapper.
/// - duration: fade/slide duration
/// - delay: wait before starting
class FadeIn extends StatefulWidget {
  const FadeIn({super.key, required this.child, this.duration = const Duration(milliseconds: 800), this.delay = Duration.zero, this.offset = const Offset(0, 0.06)});

  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset offset; // slide from this offset to Offset.zero

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (widget.delay > Duration.zero) {
      _delayTimer = Timer(widget.delay, () => _controller.forward());
    } else {
      // microtask to avoid setState during build
      scheduleMicrotask(() => _controller.forward());
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
