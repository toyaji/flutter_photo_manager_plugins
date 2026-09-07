// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';

import 'native_image_provider.dart';
import 'network_policy.dart';

/// [Image] over a [NativeImageProvider].
class NativeAssetImage extends StatelessWidget {
  /// Shows [entity] at [size] pixels on its shorter side.
  const NativeAssetImage(
    this.entity, {
    required this.size,
    super.key,
    this.network = NetworkPolicy.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.gaplessPlayback = true,
    this.width,
    this.height,
    this.errorBuilder,
    this.frameBuilder,
  });

  /// The asset to show.
  final AssetEntity entity;

  /// Pixel length of the shorter side of the decoded image.
  final int size;

  /// See [NativeImageProvider.network].
  final NetworkPolicy network;

  /// See [Image.fit].
  final BoxFit fit;

  /// See [Image.alignment].
  final AlignmentGeometry alignment;

  /// See [Image.filterQuality].
  final FilterQuality filterQuality;

  /// See [Image.gaplessPlayback].
  final bool gaplessPlayback;

  /// See [Image.width].
  final double? width;

  /// See [Image.height].
  final double? height;

  /// See [Image.errorBuilder]; the error is a `NativeImageException`.
  final ImageErrorWidgetBuilder? errorBuilder;

  /// See [Image.frameBuilder].
  final ImageFrameBuilder? frameBuilder;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: NativeImageProvider(entity, size: size, network: network),
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      gaplessPlayback: gaplessPlayback,
      width: width,
      height: height,
      errorBuilder: errorBuilder,
      frameBuilder: frameBuilder,
    );
  }
}
