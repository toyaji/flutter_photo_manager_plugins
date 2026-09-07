# photo_manager_native_image

Load `photo_manager` thumbnails as **native RGBA pixels**. No JPEG is encoded
or decoded between the photo library and the screen: the platform decodes to
RGBA, hands Flutter a `malloc` pointer, and Flutter uploads it straight through
`ImageDescriptor.raw`.

```dart
// Any pixel size — which sizes an app uses is the app's policy.
Image(image: NativeImageProvider(asset, size: 320), fit: BoxFit.cover);

// Or the convenience widget.
NativeAssetImage(asset, size: 320, errorBuilder: (context, error, _) {
  if (error is NativeImageException &&
      error.code == NativeImageErrorCode.icloudNotDownloaded) {
    return const Icon(Icons.cloud_download);
  }
  return const Icon(Icons.broken_image);
});
```

| | Android | iOS |
|---|---|---|
| Source | `ContentResolver.loadThumbnail` (≤768 px), `ImageDecoder` above; `MediaStore.*.Thumbnails` + `BitmapFactory` with orientation fix on API 26–28 | `PHImageManager.requestImage(.aspectFill, .highQualityFormat, .fast)` on a worker queue, `vImage` downscale |
| Pixels handed over | `ARGB_8888` → JNI `malloc` | RGBA8888 → `malloc` |
| JPEG round trips | **0** | **0** |
| Cancellation | before allocation | before allocation |
| Extra framework | none | `Photos`, `Accelerate` |

## Why

`AssetEntityImageProvider` asks the platform for a JPEG, copies it across the
channel, and decodes it again in Dart. In a grid that is two decodes and two
copies per cell. This package does one native decode, one copy into Flutter's
immutable buffer, and lets the engine upload the texture.

## Behaviour

- **Size** is the pixel length of the shorter side (aspect fill). The Dart side
  never upscales; if the platform returns something larger it is scaled down
  once through `instantiateCodec`.
- **Cache key** is `(id, modifiedDateSecond ?? createDateSecond, size, isVideo)`.
  Edited assets reload; `allowNetwork` does not split the cache.
- **Cancellation** follows the image cache. When the only remaining listener is
  the cache's own, the native request is dropped (if it has not allocated yet)
  and the key is evicted, so a later request starts fresh. `imageCache.clear()`
  under memory pressure does not cancel images that are still on screen.
- **Buffers are owned by Dart.** Once the platform has allocated it always
  replies, and Dart frees the pointer on every path (normal, cancelled, error).
- **iCloud** (`iOS`): `allowNetwork: false` (default) reports
  `icloudNotDownloaded` instead of blocking a worker on a download. Retry with
  `allowNetwork: true`; such requests run on a low-priority queue with two
  slots.
- **Photo daemon reconnect** (`iOS`): an XPC interruption evicts the cached
  `PHAsset` and retries once, so a hot restart does not leave blank cells.

Errors reach `errorBuilder` as `NativeImageException` with a typed
`NativeImageErrorCode` (`notFound`, `icloudNotDownloaded`, `decodeFailed`).

`NativeImageMetrics.instance` exposes request/complete/cancel counts, latency
samples and the number of live native buffers for instrumentation; the example
app shows them in a panel.

## Requirements

Android `minSdkVersion 26`, iOS 13. Request photo permission through
`PhotoManager.requestPermissionExtend()` before loading.

## Not in scope

Disk caching, prefetching, cache partitioning, and resolution policy. Those
belong to the app.

## License

Apache-2.0.
