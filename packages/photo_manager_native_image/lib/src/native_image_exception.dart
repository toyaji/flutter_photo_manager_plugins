// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/services.dart';

/// Why a native thumbnail request failed.
enum NativeImageErrorCode {
  /// The asset no longer exists in the photo library.
  notFound('not_found'),

  /// iOS only: the original is in iCloud and the request had
  /// `allowNetwork: false`. Retry with `allowNetwork: true` to download it.
  icloudNotDownloaded('icloud_not_downloaded'),

  /// The platform could not produce pixels for the asset.
  decodeFailed('decode_failed');

  const NativeImageErrorCode(this.wireCode);

  /// The code string sent by the platform side.
  final String wireCode;

  /// Maps a platform code to a [NativeImageErrorCode]; unknown codes are
  /// reported as [decodeFailed].
  static NativeImageErrorCode fromWire(String? code) {
    for (final NativeImageErrorCode value in values) {
      if (value.wireCode == code) {
        return value;
      }
    }
    return decodeFailed;
  }
}

/// Thrown into the [ImageStream] (and so into `Image.errorBuilder`) when a
/// thumbnail cannot be loaded.
class NativeImageException implements Exception {
  /// Creates an exception with a typed [code].
  const NativeImageException(this.code, {this.message});

  /// Builds the exception for a [PlatformException] raised by the channel.
  factory NativeImageException.fromPlatform(PlatformException exception) {
    return NativeImageException(
      NativeImageErrorCode.fromWire(exception.code),
      message: exception.message,
    );
  }

  /// The typed failure reason.
  final NativeImageErrorCode code;

  /// Optional detail from the platform.
  final String? message;

  @override
  String toString() =>
      'NativeImageException(${code.wireCode}${message == null ? '' : ': $message'})';
}
