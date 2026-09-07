// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_image_channel.dart';
import 'native_image_exception.dart';
import 'native_image_metrics.dart';

/// Frees a buffer previously handed over by the platform.
typedef NativeBufferFree = void Function(Pointer<Uint8> pointer);

/// A `malloc` RGBA8888 buffer as described in the platform reply.
@immutable
class NativeImageBuffer {
  /// Creates a description of a native buffer.
  const NativeImageBuffer({
    required this.pointer,
    required this.width,
    required this.height,
    required this.rowBytes,
  });

  /// Parses the `{pointer, width, height, rowBytes}` reply.
  factory NativeImageBuffer.fromMap(Map<String, int> map) {
    return NativeImageBuffer(
      pointer: map['pointer']!,
      width: map['width']!,
      height: map['height']!,
      rowBytes: map['rowBytes']!,
    );
  }

  /// Address of the first byte.
  final int pointer;

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// Bytes per row, at least `width * 4`.
  final int rowBytes;

  /// Total bytes in the buffer.
  int get byteLength => rowBytes * height;
}

/// Target dimensions for the Dart-side safety net: scales the image down so
/// its shorter side is at most [size]. Returns `null` when no resize is needed.
({int width, int height})? resizeTargetFor(int width, int height, int size) {
  final int shorter = width < height ? width : height;
  if (shorter <= size) {
    return null;
  }
  final double scale = size / shorter;
  return (
    width: (width * scale).round().clamp(1, width),
    height: (height * scale).round().clamp(1, height),
  );
}

/// One native request from send to frame. Owns the buffer between the reply
/// and the copy into an [ui.ImmutableBuffer].
class NativeImageRequest {
  /// Creates a request; nothing is sent until [load] is called.
  NativeImageRequest({
    required this.channel,
    required this.assetId,
    required this.size,
    required this.isVideo,
    required this.allowNetwork,
    NativeBufferFree? free,
    NativeImageMetrics? metrics,
  })  : requestId = NativeImageChannel.allocateRequestId(),
        _free = free ?? malloc.free,
        _metrics = metrics ?? NativeImageMetrics.instance;

  /// The channel the request goes through.
  final NativeImageChannel channel;

  /// `AssetEntity.id`.
  final String assetId;

  /// Pixel length of the shorter side.
  final int size;

  /// Whether the asset is a video (Android picks the MediaStore table).
  final bool isVideo;

  /// iOS `isNetworkAccessAllowed`.
  final bool allowNetwork;

  /// Id shared with the platform for cancellation.
  final int requestId;

  final NativeBufferFree _free;
  final NativeImageMetrics _metrics;

  bool _sent = false;
  bool _cancelled = false;
  bool _settled = false;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Whether [load] has produced its single outcome.
  bool get isSettled => _settled;

  /// Sends the request and decodes the reply into a frame. Resolves to `null`
  /// when cancelled. Throws [NativeImageException] on failure.
  Future<ui.FrameInfo?> load() async {
    if (_sent) {
      throw StateError('load() may only be called once.');
    }
    _sent = true;
    if (_cancelled) {
      return _settle(() => null);
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    _metrics.markRequested();
    final Map<String, int>? reply;
    try {
      reply = await channel.requestImage(
        assetId: assetId,
        requestId: requestId,
        width: size,
        height: size,
        isVideo: isVideo,
        allowNetwork: allowNetwork,
      );
    } on PlatformException catch (exception) {
      _metrics.markAnswered();
      return _settle(() {
        _metrics.markFailed();
        throw NativeImageException.fromPlatform(exception);
      });
    }
    _metrics.markAnswered();
    if (reply == null) {
      return _settle(() => null);
    }

    // Past this point the platform has allocated: copy, then free on every
    // path, including a cancel that raced the reply.
    final NativeImageBuffer buffer = NativeImageBuffer.fromMap(reply);
    _metrics.markBufferReceived();
    final Pointer<Uint8> pointer = Pointer<Uint8>.fromAddress(buffer.pointer);
    final ui.ImmutableBuffer immutable;
    try {
      immutable = await ui.ImmutableBuffer.fromUint8List(
        pointer.asTypedList(buffer.byteLength),
      );
    } finally {
      _free(pointer);
      _metrics.markBufferFreed();
    }
    if (_cancelled) {
      immutable.dispose();
      return _settle(() => null);
    }

    final ui.ImageDescriptor descriptor;
    try {
      descriptor = ui.ImageDescriptor.raw(
        immutable,
        width: buffer.width,
        height: buffer.height,
        rowBytes: buffer.rowBytes,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
    } finally {
      immutable.dispose();
    }
    final ({int width, int height})? target =
        resizeTargetFor(buffer.width, buffer.height, size);
    // The codec reads through the descriptor, so both live until the frame
    // has been produced.
    final ui.FrameInfo frame;
    try {
      final ui.Codec codec = await descriptor.instantiateCodec(
        targetWidth: target?.width,
        targetHeight: target?.height,
      );
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
    if (_cancelled) {
      frame.image.dispose();
      return _settle(() => null);
    }
    return _settle(() {
      _metrics.markCompleted(stopwatch.elapsed);
      return frame;
    });
  }

  /// Asks the platform to drop the request if it has not allocated yet.
  /// Only the first call reaches the platform; a settled request ignores it.
  void cancel() {
    if (_cancelled || _settled) {
      return;
    }
    _cancelled = true;
    _metrics.markCancelled();
    if (_sent) {
      channel.cancelRequest(requestId).ignore();
    }
  }

  T _settle<T>(T Function() body) {
    if (_settled) {
      throw StateError('Request $requestId settled twice.');
    }
    _settled = true;
    return body();
  }
}
