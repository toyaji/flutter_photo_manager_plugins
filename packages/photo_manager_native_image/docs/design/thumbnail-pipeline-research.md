# 리서치 — 메이저 갤러리와 Flutter 진영의 썸네일 처리

[← 본문](./thumbnail-pipeline.md)

## 비교

| 사례 | 썸네일 소스 | 픽셀 전달 | 크기 정책 | 프리페치 | 근거 |
|---|---|---|---|---|---|
| iOS 사진앱 / Apple 샘플 `AssetGridViewController` | `PHCachingImageManager.requestImage(targetSize=셀pt×scale, .aspectFill, options nil)` | UIImage 직접 | 셀 크기 1개 | 보이는 rect ±0.5화면, 1/3화면 이동마다 `start/stopCachingImages` 차분, 앨범 변경 시 `stopCachingImagesForAllAssets` | [Apple 샘플](https://developer.apple.com/library/archive/samplecode/UsingPhotosFramework/Listings/Shared_AssetGridViewController_swift.html) |
| Android (Google 권장) | `ContentResolver.loadThumbnail(uri, size)` = MediaStore 시스템 썸네일 저장소(API 29+) | Bitmap 직접 | 요청 크기 | Glide `RecyclerViewPreloader` | [Android 문서](https://developer.android.com/social-and-messaging/guides/media-thumbnails) |
| **Immich mobile** (Flutter, AGPL-3.0, 10만+ 자산) | iOS `PHImageManager.default().requestImage(.highQualityFormat, .fast, isSynchronous, isNetworkAccessAllowed)`를 `OperationQueue(코어×2)`에서. Android `loadThumbnail`(≤768) / `Thumbnails.getThumbnail`+Glide 폴백(<Q) / `ImageDecoder`(>768) | 네이티브 RGBA(`vImage`) → malloc 포인터(Int64)만 Pigeon으로 → Dart `Pointer.fromAddress` → `ImmutableBuffer` → `ImageDescriptor.raw` | **320 하나**(2~6열). 캐시 키는 `(id, checksum)` — size 제외 | 없음. sliver `cacheExtent`가 앞당기고, 캐시 리스너 식별 믹스인이 취소 | `mobile/ios/Runner/Images/LocalImagesImpl.swift`, `mobile/android/.../images/LocalImagesImpl.kt`, `mobile/lib/infrastructure/loaders/image_request.dart`, `mobile/lib/presentation/widgets/images/cache_aware_listener_tracker.mixin.dart`, `timeline/constants.dart:12` |
| photo_manager 3.12 (현재 Zelly) | `PHCachingImageManager.requestImage(.opportunistic, .fast)` 메인 큐 dispatch | UIImage → **JPEG 95 인코딩** → 채널 복사 → Dart **JPEG 디코딩** | 버킷 5종(128~512) | 자체 창 ±1.5화면 `startCachingImages`, 옵션 불일치로 `resizeMode None` | `PMManager.m:516-590, 3170-3202`, `PMImageUtil.m:24-35`, `gallery_thumbnail_service.dart:37-38` |

## 확인한 문서 사실

| 사실 | 출처 |
|---|---|
| `PHImageRequestOptionsResizeMode`: none "does not resize", fast "similar to, or slightly larger than", exact "match exactly" | Apple 문서 JSON |
| `startCachingImages`는 "later request와 같은 targetSize·contentMode·options"로 불러야 적중한다 | Apple `PHCachingImageManager` 문서 |
| `requestImage`를 백그라운드 스레드에서 부르면 `isSynchronous=true`로 블록해도 된다 | Apple `requestImage` 문서 |
| `ImmutableBuffer.fromUint8List`는 **복사**한다 → 이후 `malloc.free` 안전 | dart:ui 문서 |
| `ImageDescriptor.raw`도 `instantiateCodec(targetWidth:)` 리사이즈가 적용된다(Skia `ResizeRasterImage`, Impeller `DecompressTexture`) | Flutter 엔진 `image_decoder_skia.cc:78-101`, `image_decoder_impeller.cc:349-356` |
| `PaintingBinding.createImageCache()` 오버라이드 + 커스텀 바인딩은 프레임워크 공식 예시 | `image_cache.dart:60-73` dartdoc |
| `SentryWidgetsFlutterBinding`(9.22.0)은 상속 가능하고 `ensureInitialized`가 기존 인스턴스를 반환 | `binding_wrapper.dart:48-67` |
| Pigeon @async 응답은 정상 동작 중 반드시 도착. 유실은 엔진 detach뿐. 이중 응답은 Android 예외·iOS 무시 | `DartMessenger.java:412-433`, `FlutterJNI.java:1217-1256` |
| Android 26~28: `BitmapFactory`·`Thumbnails.getThumbnail`은 EXIF 미적용, 29+ `loadThumbnail`·`ImageDecoder`는 적용 | AOSP `ThumbnailUtils`, MediaStore API diff |
| Immich 이슈 #23658·#24312는 remote 경로 문제로 로컬 네이티브 경로의 반례가 아니다 | GitHub 이슈 |

## 기각한 대안

| 대안 | 이유 |
|---|---|
| PlatformView(UICollectionView/RecyclerView 그리드 임베드) | 래스터 스레드가 플랫폼 스레드에 합쳐져 그리드 위 Flutter 오버레이(머리글·비행 연출·시트)까지 느려지고 드래그 선택 히트테스트를 통째로 다시 써야 한다. Immich가 Flutter 그리드 + 네이티브 디코드만으로 감당한다 |
| 셀마다 `Texture` 위젯 | 핀치마다 등록/해제 수백 건. Impeller에서 `ImageDescriptor.raw`가 이미 GPU 텍스처로 직행한다 |
| 공유 메모리 zero-copy | `ImmutableBuffer`가 복사를 강제. 공개 API 없음 |
| `PHCachingImageManager` 재도입 | 이번 메모리 폭주의 원인 |
| `ResizeMode.exact` | 네이티브 CPU만 늘고 RGBA 상한은 Dart 디코드 크기가 정한다 |

라이선스: Immich는 AGPL-3.0. 방식은 따르되 코드는 옮기지 않는다.
