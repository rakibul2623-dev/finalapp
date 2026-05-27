import 'package:flutter/material.dart';

/// Backports Color.withValues for toolchains that don't yet support it.
/// Only the `alpha` named parameter is honored; r/g/b are ignored.
extension ColorWithValuesCompat on Color {
  Color withValues({double? alpha, double? red, double? green, double? blue}) {
    final a = alpha ?? (this.alpha / 255.0);
    return withOpacity(a);
  }
}
