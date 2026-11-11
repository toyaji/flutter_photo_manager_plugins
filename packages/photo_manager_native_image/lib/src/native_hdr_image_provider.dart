// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:photo_manager/photo_manager.dart';

import 'native_image_channel.dart';
import 'native_image_request.dart';
import 'native_image_stream_completer.dart';

/// Loads the HDR rendition of an [AssetEntity] photo as float pixels.
///
/// The image is in extended sRGB: 1.0 is SDR white and highlights exceed it,
/// up to [maxHeadroom] times SDR white. It only looks brighter than SDR on a
/// surface that can show values above 1.0.
///
/// The load fails with [NativeImageErrorCode.notHdr] for an asset without HDR
/// content, [NativeImageErrorCode.icloudNotDownloaded] when the original is
/// not on the device (the network is never used), and
/// [NativeImageErrorCode.unsupported] where HDR pixels cannot be produced.
/// A caller typically keeps showing its SDR image in those cases.
class NativeHdrImageProvider extends ImageProvider<NativeHdrImageProvider> {
  /// Creates a provider for [entity] at [size] pixels.
  NativeHdrImageProvider(
    this.entity, {
    required this.size,
    this.maxHeadroom = 1.6,
  })  : assert(size > 0),
        assert(maxHeadroom >= 1);

  /// The asset to load.
  final AssetEntity entity;

  /// Pixel length of the shorter side of the decoded image.
  final int size;

  /// Brightest value kept, as a multiple of SDR white in linear light.
  final double maxHeadroom;

  int get _modifiedDateSecond =>
      entity.modifiedDateSecond ?? entity.createDateSecond ?? 0;

  @override
  Future<NativeHdrImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<NativeHdrImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    NativeHdrImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final NativeImageRequest request = NativeImageRequest(
      channel: NativeImageChannel.instance,
      assetId: entity.id,
      size: size,
      isVideo: false,
      hdrMaxHeadroom: maxHeadroom,
    );
    return NativeImageStreamCompleter(
      load: request.load,
      onCancel: () {
        request.cancel();
        PaintingBinding.instance.imageCache.evict(key);
      },
      onFailure: () => PaintingBinding.instance.imageCache.evict(key),
      debugLabel: '${entity.id}@$size hdr',
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is NativeHdrImageProvider &&
        other.entity.id == entity.id &&
        other._modifiedDateSecond == _modifiedDateSecond &&
        other.size == size &&
        other.maxHeadroom == maxHeadroom;
  }

  @override
  int get hashCode =>
      Object.hash(entity.id, _modifiedDateSecond, size, maxHeadroom);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'NativeHdrImageProvider')}(${entity.id}, size: $size)';
}
