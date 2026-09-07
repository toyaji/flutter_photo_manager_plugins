// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:photo_manager/photo_manager.dart';

import 'native_image_channel.dart';
import 'native_image_request.dart';
import 'native_image_stream_completer.dart';

/// Loads an [AssetEntity] thumbnail decoded natively to RGBA.
///
/// [size] is the pixel length of the shorter side (aspect fill); which sizes an
/// app uses, and how many, is the app's policy. The cache key is
/// `(entity.id, modified date, size, isVideo)`, so an edited asset reloads and
/// [allowNetwork] does not split the cache.
class NativeImageProvider extends ImageProvider<NativeImageProvider> {
  /// Creates a provider for [entity] at [size] pixels.
  NativeImageProvider(
    this.entity, {
    required this.size,
    this.allowNetwork = false,
    this.scale = 1.0,
    NativeImageChannel? channel,
    NativeBufferFree? debugFree,
  })  : assert(size > 0),
        _channel = channel,
        _debugFree = debugFree;

  /// The asset to load.
  final AssetEntity entity;

  /// Pixel length of the shorter side of the decoded image.
  final int size;

  /// iOS: allow PhotoKit to download an iCloud original. Such requests run on
  /// a low-priority queue so they never block on-screen thumbnails.
  final bool allowNetwork;

  /// Scale reported in the resulting [ImageInfo].
  final double scale;

  final NativeImageChannel? _channel;
  final NativeBufferFree? _debugFree;

  /// The date part of the cache key.
  int get modifiedDateSecond =>
      entity.modifiedDateSecond ?? entity.createDateSecond ?? 0;

  /// Whether the asset is a video.
  bool get isVideo => entity.type == AssetType.video;

  @override
  Future<NativeImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<NativeImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    NativeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final NativeImageRequest request = NativeImageRequest(
      channel: _channel ?? NativeImageChannel.instance,
      assetId: entity.id,
      size: size,
      isVideo: isVideo,
      allowNetwork: allowNetwork,
      free: _debugFree,
    );
    return NativeImageStreamCompleter(
      load: request.load,
      onCancel: () {
        request.cancel();
        PaintingBinding.instance.imageCache.evict(key);
      },
      // Like NetworkImage: a failed key must not be served from the pending
      // cache, so an `allowNetwork: true` retry can start a new load.
      onFailure: () => PaintingBinding.instance.imageCache.evict(key),
      scale: scale,
      debugLabel: '${entity.id}@$size',
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is NativeImageProvider &&
        other.entity.id == entity.id &&
        other.modifiedDateSecond == modifiedDateSecond &&
        other.size == size &&
        other.isVideo == isVideo;
  }

  @override
  int get hashCode => Object.hash(entity.id, modifiedDateSecond, size, isVideo);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'NativeImageProvider')}(${entity.id}, size: $size)';
}
