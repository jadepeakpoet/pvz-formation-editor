import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Pointer targets must use the final route layout, including popup clipping.
Future<void> settleFrames() async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
  for (var i = 0; i < 60 &&
      SchedulerBinding.instance.transientCallbackCount > 0; i++) {
    await WidgetsBinding.instance.endOfFrame;
  }
}
