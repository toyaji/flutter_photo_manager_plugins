# 작업 체크리스트 — 썸네일 파이프라인

[← 본문](./thumbnail-pipeline.md) · 원칙 P1~P8 위반 시 그 작업은 폐기.

## 0단계 — 결함 수정 (설계와 독립)

- [ ] `gallery_thumbnail_service.dart:37-38` `optionFor` → `ThumbnailOption.ios(size:, quality:)` — 프리캐시가 `resizeMode None`(리사이즈 없음)으로 나가던 원인. `toMap()` 동등성 단위 테스트로 고정
- [ ] `upload_page.dart:618-630` `_onColumnsChanged`의 `_prefetchWindow` 호출 삭제(핀치 중에만 불리므로 무의미), `_onPinchEnd`는 `addPostFrameCallback`으로 — `_thumbnailSize`·`_itemWidth`가 빌드 뒤에야 갱신된다
- [ ] `_onColumnsChanged`의 `loadMoreImageInShort` → `_onPinchEnd`(줌아웃일 때만) + 완료 시 `setState` — 현재는 notify가 없어 화면에 반영되지 않는다
- [ ] `GalleryThumbnailService`를 provider 1개로 공유(`upload_page.dart:529`, `upload_preview_page.dart:350`) — 뷰어의 `cancel()`이 전역 stop이라 그리드 캐시를 지운다
- [ ] 게이트: 핀치 왕복 중 `assetsd` 사망 0, `didHaveMemoryPressure` 횟수 기록

## 1단계 — 네이티브 픽셀 경로

### 채널
- [ ] `pubspec.yaml`: `pigeon`(dev), `ffi` 직접 의존 승격
- [ ] `pigeons/thumbnail_api.dart`: `request(id, requestId, size, isVideo, allowNetwork, orientationHint) → Map<String,int>?`, `cancel(requestId)`
- [ ] 응답 규약: 요청 객체 `done` 플래그로 **정확히 1회**. 워커 스레드에서 바로 응답. "취소가 먼저 온 requestId" 집합
- [ ] 에러 코드: `not_found` / `icloud_not_downloaded` / `decode_failed`, 취소는 nil

### iOS `ios/Runner/Thumbnails/ThumbnailApiImpl.swift`
- [ ] `OperationQueue(userInitiated, 코어×2)`, `PHAsset` `NSCache(countLimit 10000)`
- [ ] **연결 끊김 회복:** `requestImage`가 XPC 무효화 오류(`NSCocoaErrorDomain 4097/4099`, `PHPhotosErrorDomain`)로 실패하면 그 `PHAsset`을 NSCache에서 버리고 다시 fetch해 **1회 재시도**. photo_manager는 `PMCacheContainer`에 죽은 객체를 영구 보관해 사진 데몬이 죽으면 프로세스 재시작 전까지 회복하지 못했다(2026-09-06, 핫리스타트 흰 화면의 원인). 앱 시작 시 `PhotoManager.releaseCache()`는 임시 조치
- [ ] `PHImageManager.default().requestImage(targetSize, .aspectFill, .highQualityFormat, .fast, isSynchronous, version .current, isNetworkAccessAllowed: allowNetwork)`
- [ ] `.fast` 결과 > size면 `vImageScale`, RGBA8888 변환 → `malloc` 버퍼. **할당 뒤 취소 검사 금지**(Dart가 free)
- [ ] `PHImageResultIsInCloudKey`/`PHImageErrorKey` → `icloud_not_downloaded`
- [ ] 저우선 큐(동시 2) `allowNetwork: true` 재요청 경로
- [ ] `PetSegmentationChannel.swift`와 같은 등록 방식

### Android `android/.../thumbnails/ThumbnailApiImpl.kt` + `src/main/cpp/native_buffer.c`
- [ ] JNI `NativeBuffer.allocate/free`(C malloc) — `ByteBuffer.allocateDirect` 금지(Dart `malloc.free`와 힙 불일치)
- [ ] 29+: `loadThumbnail(uri, Size)`(≤768), full(1024)은 `ImageDecoder.setTargetSize`
- [ ] 26~28: base/main `Images/Video.Thumbnails.getThumbnail(MINI_KIND)`+스케일, full `BitmapFactory` 경계 디코드 + `inSampleSize`. **회전 보정**: 이미지 `Images.ImageColumns.ORIENTATION`(29+ `MediaColumns.ORIENTATION`은 컴파일 불가), 영상 `MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION`, `Matrix.postRotate`. photo_manager가 pre-Q에 싣는 `AssetEntity.orientation`을 힌트로 넘기면 재조회 1회 절약
- [ ] `ARGB_8888` 강제 → `copyPixelsToBuffer`. 풀 = 코어/2+1

### Dart `lib/service/thumbnail_service.dart`
- [ ] `ZellyThumbnailProvider(id, modifiedDateSecond ?? createDateSecond, layer∈{base, main, full})`. `==`/`hashCode`에 size 없음
- [ ] `Pointer.fromAddress` → `asTypedList` → `ImmutableBuffer.fromUint8List` → **await 전후 취소 분기 포함 모든 경로에서 `malloc.free`** → `ImageDescriptor.raw` → `instantiateCodec(targetWidth: size)` 안전망
- [ ] 취소 가능한 `ImageStreamCompleter` + 캐시 리스너 식별 믹스인(첫 리스너 = 캐시로 잠금, `hadInitialImage`면 첫 동기 제거 무시, 캐시 리스너만 남고 미도착일 때만 취소). 취소 시 `imageCache.evict(key)` — key는 `loadImage(key, decode)`의 프로바이더
- [ ] 단위 테스트: 오작동 3종(메모리 경고 clear 중 취소 안 됨 / `putIfAbsent` 동기 detach 거짓 취소 없음 / 리스너 오인 없음), 이중 응답 무시, 취소 후 free

### 캐시 파티션 `lib/main.dart`
- [ ] `ZellyBinding extends SentryWidgetsFlutterBinding` + `createImageCache()` → `ImageCache` 상속 파사드(base / main+full 2개 위임). 외부 키(`NetworkImage`·`AssetImage`)는 main/full
- [ ] `main.dart:69-70` → `ZellyBinding(); final binding = WidgetsBinding.instance;`로 `FlutterNativeSplash.preserve`
- [ ] `main.dart:73-84` 주석 10줄 + 전역 `maximumSizeBytes/maximumSize` 삭제. 예산은 파사드 생성자(base 64MB/1000, main+full 100MB/250)
- [ ] `clear()` = main/full만, `clearAll()` 별도. `GlobalImageCacheLayer.onMemoryPressure`는 `clear()`만, `clearLiveImages()` 제거
- [ ] `gallery-performance.md` T5(1200장/100MB) 개정 동반

### 화면
- [ ] `media_widgets.dart`: `ZellyGridThumbnail` = `Stack[Image(base) 항상, if (!dense) Image(main)]`, `errorBuilder`는 에러 코드로 분기(`icloud_not_downloaded` → 전용 UI + `onICloudFailure`), `compact`(10열: 재생 아이콘 숨김, 체크 중앙)
- [ ] `upload_page.dart`: 버킷 5종 → base/main, `_prefetchWindow` 삭제, `cacheExtent` 앞뒤 6행, `GalleryThumbnailService` 참조 4곳(`:14 import, :390, :529, :534`) 제거. **유지:** 셀 GlobalKey(`_cellKey`), 핀치 중 `_isPinching` 단계 동결 후 손 뗀 뒤 1회 전환 — 6↔10 레이어 전환 시점의 계약
- [ ] `upload_preview_page.dart`: 캐러셀·영상 포스터 base, 본판 full(1024), `_prefetchAround` 삭제. `GalleryThumbnailService` 참조 5곳(`:18 import, :350, :418, :477, :611`) + `AssetEntityImageProvider` 2곳(`:607, :816`) 정리
- [ ] `upload_sheet.dart:13,226`, `upload_status_page.dart:704`, `upload_view_model.dart:866`(`_imageCache`/`getCachedImage` 제거) 정리
- [ ] `gallery_thumbnail_service.dart` 삭제. `AssetEntityImageProvider`·`PhotoCachingManager` 사용처 0 확인(grep)
- [ ] 편집 자산 갱신: `syncCurrentAlbumOnResume`을 (개수, `getAssetListRange(0,1)`의 `modifiedDateSecond`) 2튜플 비교로 — 앨범 필터가 이미 `updateDate desc`라 별도 정렬 옵션 불필요. 빈 앨범(null) 가드
- [ ] 권한: 채널은 `requestPermissionExtend` 이후에만. iOS limited·Android 26~28 `READ_EXTERNAL_STORAGE` 전제 명시

### 게이트 1
- [ ] 10↔2 핀치 왕복 10회: 흰 칸 0, 셀 Element 재생성 0(`upload_grid_section_test.dart:521` 통과 유지), `assetsd` 재연결 0, 취소율, `malloc` 잔량 0, 요청→프레임 지연 p50/p95, 큐 대기 길이 최대치, 16ms 초과 프레임, iCloud 다운로드 횟수
- [ ] 픽셀 패스 코드 검사: ≤ 4회(변환·스케일·`ImmutableBuffer` 복사·Dart 안전망), API 26~28은 회전 포함 ≤ 5회
- [ ] API 26 에뮬레이터: 그리드 표시, 세로 사진 정립

## 2단계 — 디스크 썸네일 캐시
- [ ] base 128 JPEG q70을 앱 캐시 디렉터리에 `id_modifiedDateSecond_128`로. 읽기: Flutter 캐시 → 디스크(네이티브 디코드 → RGBA) → PhotoKit/MediaStore(후 기록)
- [ ] 200MB LRU, 삭제 자산 지연 정리
- [ ] 게이트: 첫 진입·앨범 전환 콜드 구간 계측 전후 비교

## 3단계 — A/B·문서
- [ ] main 320 vs 256 vs 384, base 프리워밍(진행 방향 1화면) 유무
- [ ] `gallery-performance.md` T1~T6 전면 개정
