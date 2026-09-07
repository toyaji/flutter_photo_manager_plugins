// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

/// Load `photo_manager` thumbnails as native RGBA pixels, with no JPEG round
/// trip and cancellation that follows the Flutter image cache.
library;

export 'src/cache_aware_listener_tracker.dart';
export 'src/native_asset_image.dart';
export 'src/native_image_channel.dart';
export 'src/native_image_exception.dart';
export 'src/native_image_metrics.dart';
export 'src/native_image_provider.dart';
export 'src/native_image_request.dart' show NativeImageBuffer, resizeTargetFor;
export 'src/native_image_stream_completer.dart';
