## 0.1.0

- `NativeImageProvider`, `NativeAssetImage`, `NativeImageException`: load a
  `photo_manager` `AssetEntity` thumbnail as native RGBA pixels handed to
  Flutter through `dart:ffi` and `ImageDescriptor.raw`, with no JPEG round
  trip.
- iOS: `PHImageManager.requestImage` on a worker queue, `vImage` downscale,
  XPC reconnect retry, `icloud_not_downloaded` classification, low-priority
  queue for network-allowed requests.
- Android: `ContentResolver.loadThumbnail` / `ImageDecoder` on API 29+,
  `MediaStore.*.Thumbnails` and `BitmapFactory` with orientation correction on
  API 26–28, JNI `malloc` buffers.
- Cancellation that recognises the `ImageCache` listener, so scrolled-away
  cells stop their native work without false cancels on `imageCache.clear()`.
