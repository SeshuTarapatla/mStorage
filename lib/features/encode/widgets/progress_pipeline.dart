import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../encode_notifier.dart';

class ProgressPipeline extends StatelessWidget {
  final EncodeStep currentStep;
  final Color accentColor;
  final double compressProgress;
  final double combineProgress;

  const ProgressPipeline({
    super.key,
    required this.currentStep,
    required this.accentColor,
    this.compressProgress = 0.0,
    this.combineProgress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final steps = [
      (EncodeStep.generatingMask, Icons.movie_creation_outlined, 'Mask Video', null),
      (EncodeStep.compressing, Icons.compress_rounded, 'Packaging',
          currentStep == EncodeStep.compressing ? compressProgress : null),
      (EncodeStep.combining, Icons.merge_rounded, 'Combining',
          currentStep == EncodeStep.combining ? combineProgress : null),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          _StepDot(
            icon: steps[i].$2,
            label: steps[i].$3,
            state: _stepState(steps[i].$1),
            accentColor: accentColor,
            progress: steps[i].$4,
          ),
          if (i < steps.length - 1)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 19),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: 2,
                  color: _stepState(steps[i].$1) == _StepState.done
                      ? accentColor
                      : kBorderColor,
                ),
              ),
            ),
        ],
      ],
    );
  }

  _StepState _stepState(EncodeStep step) {
    final order = [
      EncodeStep.generatingMask,
      EncodeStep.compressing,
      EncodeStep.combining,
      EncodeStep.done,
    ];
    final currentIdx = order.indexOf(currentStep);
    final stepIdx = order.indexOf(step);
    if (currentIdx < 0) return _StepState.idle;
    if (stepIdx < currentIdx) return _StepState.done;
    if (stepIdx == currentIdx) return _StepState.active;
    return _StepState.idle;
  }
}

enum _StepState { idle, active, done }

class _StepDot extends StatelessWidget {
  final IconData icon;
  final String label;
  final _StepState state;
  final Color accentColor;
  final double? progress; // null → indeterminate, 0.0–1.0 → determinate ring

  const _StepDot({
    required this.icon,
    required this.label,
    required this.state,
    required this.accentColor,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = state == _StepState.active;
    final isDone = state == _StepState.done;
    final color = isDone || isActive ? accentColor : kTextMuted;

    Widget? innerChild;
    if (isDone) {
      innerChild = Icon(Icons.check_rounded, color: accentColor, size: 18);
    } else if (isActive) {
      if (progress != null) {
        innerChild = TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: progress!),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (_, val, _) => SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: accentColor,
              value: val,
            ),
          ),
        );
      } else {
        innerChild = SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: accentColor,
          ),
        );
      }
    } else {
      innerChild = Icon(icon, color: kTextMuted, size: 18);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone || isActive
                ? accentColor.withValues(alpha: 0.15)
                : kSurface2Color,
            border: Border.all(color: color, width: isActive ? 2 : 1),
            boxShadow: isActive
                ? [BoxShadow(color: accentColor.withValues(alpha: 0.4), blurRadius: 12)]
                : [],
          ),
          child: Center(child: innerChild),
        ),
        const SizedBox(height: 6),
        // Always show label; show percentage as a secondary line when available
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        if (isActive && progress != null)
          Text(
            '${(progress! * 100).round()}%',
            style: TextStyle(fontSize: 10, color: accentColor),
          ),
      ],
    );
  }
}
