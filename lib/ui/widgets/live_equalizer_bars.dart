import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class LiveEqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final int barCount;

  const LiveEqualizerBars({
    super.key,
    required this.isPlaying,
    this.barCount = 24,
  });

  @override
  State<LiveEqualizerBars> createState() => _LiveEqualizerBarsState();
}

class _LiveEqualizerBarsState extends State<LiveEqualizerBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (index) {
            double height = 4.0;
            if (widget.isPlaying) {
              final phase = _controller.value * 2 * pi + (index * 0.4);
              final wave = (sin(phase) + 1.0) / 2.0;
              height = 4.0 + (wave * 18.0);
            }
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3.5,
              height: height,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }
}
