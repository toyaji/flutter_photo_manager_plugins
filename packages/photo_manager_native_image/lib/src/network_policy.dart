// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

/// When a thumbnail request may download from iCloud (iOS only; Android
/// ignores it).
enum NetworkPolicy {
  /// Local only. An iCloud-only asset fails with `icloudNotDownloaded`.
  never,

  /// Local first. If the asset turns out to be iCloud-only, one more request
  /// is sent with network access on the low-priority queue. The default.
  fallback,

  /// Network from the start. Every request goes through the low-priority
  /// download queue (two slots), so use it for detail views, not grids.
  always,
}
