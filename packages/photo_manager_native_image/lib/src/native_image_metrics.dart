// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/foundation.dart';

/// Counters for the native pipeline, meant for the example app and for
/// checking a device run (live buffers must return to zero).
class NativeImageMetrics extends ChangeNotifier {
  NativeImageMetrics._();

  /// The process-wide instance.
  static final NativeImageMetrics instance = NativeImageMetrics._();

  /// Requests sent to the platform.
  int requested = 0;

  /// Requests that produced a frame.
  int completed = 0;

  /// Requests cancelled from Dart.
  int cancelled = 0;

  /// Requests that ended with an error.
  int failed = 0;

  /// Requests sent but not yet answered.
  int inFlight = 0;

  /// The highest [inFlight] seen since [reset].
  int maxInFlight = 0;

  /// Native buffers received and not yet freed. Must be zero at rest.
  int liveBuffers = 0;

  /// Request-to-frame latencies in milliseconds since [reset].
  final List<int> latenciesMs = <int>[];

  /// Clears every counter.
  void reset() {
    requested = 0;
    completed = 0;
    cancelled = 0;
    failed = 0;
    inFlight = 0;
    maxInFlight = 0;
    liveBuffers = 0;
    latenciesMs.clear();
    notifyListeners();
  }

  /// Latency percentile in milliseconds, or `null` before any completion.
  int? percentile(double p) {
    if (latenciesMs.isEmpty) {
      return null;
    }
    final List<int> sorted = List<int>.of(latenciesMs)..sort();
    final int index = ((sorted.length - 1) * p).round();
    return sorted[index];
  }

  void _onRequested() {
    requested++;
    inFlight++;
    if (inFlight > maxInFlight) {
      maxInFlight = inFlight;
    }
    notifyListeners();
  }

  void _onAnswered() {
    inFlight--;
  }

  void _onBufferReceived() {
    liveBuffers++;
  }

  void _onBufferFreed() {
    liveBuffers--;
    notifyListeners();
  }

  void _onCompleted(Duration latency) {
    completed++;
    latenciesMs.add(latency.inMilliseconds);
    notifyListeners();
  }

  void _onCancelled() {
    cancelled++;
    notifyListeners();
  }

  void _onFailed() {
    failed++;
    notifyListeners();
  }
}

/// Package-internal hooks kept off the public surface.
extension NativeImageMetricsInternal on NativeImageMetrics {
  /// A request was sent.
  void markRequested() => _onRequested();

  /// The platform replied (result, null, or error).
  void markAnswered() => _onAnswered();

  /// A malloc buffer arrived from the platform.
  void markBufferReceived() => _onBufferReceived();

  /// A malloc buffer was freed.
  void markBufferFreed() => _onBufferFreed();

  /// A frame was produced.
  void markCompleted(Duration latency) => _onCompleted(latency);

  /// A request was cancelled from Dart.
  void markCancelled() => _onCancelled();

  /// A request failed.
  void markFailed() => _onFailed();
}
