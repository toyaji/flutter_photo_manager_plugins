# photo_manager_fast_image — 제안서 겸 1단계 패키지화 전환 계획 (검토 반영판, 2026-09-06)

> **문서 목적:** 확정된 썸네일 파이프라인 설계(`thumbnail-pipeline.md`, P1~P8)를 `zelly_flutter` 앱 내부에 직접 심는 대신, `photo_manager_video_player`의 선례를 따라 **photo_manager 컴패니언 패키지로 분리 개발**하기 위한 전환 제안서.
>
> 검토자 수정 표시: `[정정]` = 원안의 사실 오류, `[결정 필요]` = 사용자 판단 사항.

---

## 1. 한 문장 요약

**"네이티브 RGBA 디코드 → 포인터 직결"** 파이프라인(P2·P4·P5·P7)을 `photo_manager`의 `AssetEntity`와 호환되는 독립 패키지 **`photo_manager_fast_image`** 로 만들고, Zelly는 `path:` 의존성으로 붙인다. **해상도 정책·프리페치 제거·캐시 예산 같은 앱 정책은 앱에 남는다** (§3.4).

---

## 2. 왜 컴패니언 패키지인가 — 검토 결과

| 근거 | 검토 |
|---|---|
| 선례 `photo_manager_video_player`가 `path:`로 운영 중 | **확인.** `zelly_flutter/pubspec.yaml:73-74` → `../photo_manager_video_player/packages/photo_manager_video_player`. 패키지는 `darwin/` podspec + `Package.swift`, `android/build.gradle`(Kotlin), Pigeon 미사용 |
| 로컬 모노레포가 이미 있다 | **확인, 단 두 벌이다.** `~/projects/photo_manager_video_player`(독립 repo `toyaji/photo_manager_video_player`)와 `~/projects/flutter_photo_manager_plugins`(fork `toyaji/flutter_photo_manager_plugins`, 커밋 `ce8bfed`에 같은 패키지를 복사해 넣음). 두 곳의 `pubspec.yaml`은 동일. **[결정 필요]** 새 패키지의 정본 위치 — §5 |
| 앱 코드 순도 | 동의. 앱 `ios/Runner`·`android/app`에 C·JNI·Pigeon 생성물이 들어가지 않는다 |
| example 앱에서 격리 계측 | 동의. 단 **Zelly 게이트는 그대로 필요하다** — 그리드 위 오버레이·비행 연출·시트가 있는 실제 화면에서만 잡히는 프레임 드랍이 있다 |
| FlutterCandies 업스트림 기여 | 가능성이지 전제가 아니다. 수용 여부는 그쪽 판단이고, 이름·API 형태를 바꾸라고 할 수 있다. **패키지 설계를 업스트림 수용에 맞추느라 Zelly 요구를 깎지 않는다** |

`[정정]` "환경 구축 비용 0"은 아니다. 새 패키지는 podspec·`Package.swift`·Android CMake(JNI C)·Pigeon 설정·example 앱을 새로 만든다. 선례가 있어 **참고 비용이 0**인 것이다.

---

## 3. 패키지 경계와 API

### 3.1 입력 (photo_manager 호환) — 확인됨
- 입력은 `AssetEntity`. 패키지는 `photo_manager: ">=3.0.0 <4.0.0"`에만 의존하고 **`photo_manager_image_provider`에는 의존하지 않는다.**
- iOS `entity.id` = `PHAsset.localIdentifier` (`PMConvertUtils.m:90`), Android `entity.id` = MediaStore `_ID` (`ConvertUtils.kt:46`). 검토 F20·F21에서 확인.
- 캐시 키에 넣을 값은 `entity.id`, `entity.modifiedDateSecond`(null이면 `createDateSecond`), 요청 크기. 영상 여부는 `entity.type`.

### 3.2 공개 Dart API — `[정정]` 크기는 앱이 정한다

원안의 `FastThumbnailLayer.base/main/full = 128/320/1024`는 **Zelly의 정책 숫자**다. 패키지에 박으면 다른 앱은 못 쓰고, Zelly가 A/B로 320→384를 바꿀 때 패키지를 고쳐야 한다.

```dart
/// 픽셀 한 변(px)을 받는다. 어떤 크기를 몇 단계로 쓸지는 앱의 일이다.
FastAssetImageProvider(entity, size: 320, allowNetwork: false)

/// 편의 위젯 — Image 위에 errorBuilder·fit만 얹는다.
FastAssetImage(entity: entity, size: 320, fit: BoxFit.cover, errorBuilder: ...)

/// 에러는 문자열이 아니라 타입으로 (Zelly의 iCloud 전용 UI가 이것을 본다)
class FastAssetImageException { final FastAssetImageError code; } // notFound / icloudNotDownloaded / decodeFailed
```

- `allowNetwork`(iOS `isNetworkAccessAllowed`) 기본 false. iCloud 미다운로드는 `icloudNotDownloaded`로 돌아오고, **재요청 정책(저우선 큐, 1회)은 앱이 아니라 패키지가 갖는다** — 큐가 네이티브에 있으므로.
- Zelly는 앱 안에서 `ThumbnailLayer.base = 128`, `main = 320`, `full = 1024` 상수를 두고 이 API에 넘긴다.

### 3.3 메모리 안전 — `[정정]` NativeFinalizer는 이중 해제 위험

- 원칙 P5 그대로: 네이티브는 버퍼 할당 뒤 취소를 보지 않고 **정확히 1회** 응답, Dart가 `ImmutableBuffer.fromUint8List`(복사) 직후 **모든 경로**(정상·취소·예외)에서 `malloc.free`.
- `NativeFinalizer`를 "2중 안전망"으로 붙이려면 **수동 free 직후 반드시 `detach`** 해야 한다. 안 하면 GC 시점에 같은 포인터를 두 번 free한다. 붙일 거면 `Finalizable` 토큰 + `detach`를 짝으로 넣고, 아니면 붙이지 않는다. 응답이 유실되는 경우는 엔진 detach뿐이라(F36) 안 붙여도 누수 상한은 동시 요청 수 × ≤400KB다.
- Android 버퍼는 **JNI C `malloc`** 이어야 Dart `malloc.free`(libc)와 같은 힙이다. `ByteBuffer.allocateDirect` 금지 (F28).

### 3.4 `[정정]` 패키지에 들어갈 수 없는 것 — 앱에 남는 항목

| 항목 | 왜 앱인가 |
|---|---|
| **파티션 이미지 캐시** | Flutter는 `PaintingBinding.imageCache` 슬롯이 하나고 `createImageCache()`는 **앱 바인딩**이 오버라이드한다(확인 2). 패키지는 `PartitionedImageCache` 클래스를 **제공**할 수 있지만 **설치**는 Zelly의 `ZellyBinding`이 한다. 그리고 파티션 자체가 계측 뒤 3단계로 미뤄졌다 |
| 해상도 두 단계(128/320), 10열 dense 규칙 | `UploadGridLayout.thumbnailSizeFor` — 앱 정책 |
| 프리페치 삭제, `cacheExtent` 행 수, `GalleryThumbnailService` 제거 | 그리드 코드 |
| 셀 `Stack[base, main]`, compact UI, 에러 코드 → iCloud UI 매핑 | `media_widgets.dart` |
| 편집 자산 갱신(복귀 시 2튜플 비교) | `upload_view_model.dart` |
| 메모리 경고 시 `clear()`만 | `global_image_cache_layer.dart` |

패키지가 가져가는 것은 **프로바이더 + 취소 가능한 completer(캐시 리스너 식별 믹스인) + Pigeon 채널 + iOS/Android 네이티브 디코더 + iCloud 재요청 큐** 다.

### 3.5 빌드 제약 (Zelly 쪽) — 원안 누락
- Zelly는 **CocoaPods 전용**(SPM 비활성, `docs/guidelines.md`). 패키지는 선례처럼 `darwin/<name>.podspec` **필수**, `Package.swift`는 선택.
- Android JNI C는 플러그인 `build.gradle`에 `externalNativeBuild { cmake }` + NDK 설정. 플러그인 `minSdkVersion`은 Zelly(26)에 맞춰 **26**으로 두고, 26~28 폴백(`Thumbnails.getThumbnail` + EXIF 회전)은 패키지 안에 들어간다(F22·F60).
- Pigeon 생성물: `swiftOut → darwin/<name>/Sources/...`, `kotlinOut → android/src/main/kotlin/...`. `pigeon`은 패키지 dev_dependency, `ffi`는 패키지 dependency. **Zelly `pubspec.yaml`에는 둘 다 추가하지 않는다** (원안 §4 표에서 `zelly_flutter/pigeons/` 삭제 — 맞음).

---

## 4. 체크리스트 재배치 (`thumbnail-pipeline-checklist.md` 기준)

| 체크리스트 항목 | 위치 |
|---|---|
| 채널(Pigeon, 정확히 1회 응답, 취소 선행 집합, 에러 코드) | **패키지** |
| iOS `ThumbnailApiImpl.swift`(OperationQueue, NSCache, vImage, 저우선 네트워크 큐) | **패키지** `darwin/` |
| Android `ThumbnailApiImpl.kt` + `native_buffer.c` + 26~28 폴백·회전 | **패키지** `android/` |
| Dart 프로바이더·믹스인·free 규약·단위 테스트(오작동 3종, 이중 응답, 취소 후 free) | **패키지** `lib/`, `test/` |
| `pubspec`(pigeon·ffi) | **패키지** |
| 캐시 파티션(`ZellyBinding`, `main.dart:73-84`, T5 개정) | **앱**, 3단계 |
| 화면(`media_widgets`, `upload_page`, `upload_preview_page`, `upload_sheet`, `upload_status_page`, `upload_view_model`) | **앱** |
| `gallery_thumbnail_service.dart` 삭제 | **앱** |
| 게이트 1(핀치 왕복·assetsd·malloc 잔량·p50/p95·API 26 회전) | **example에서 1차, Zelly에서 최종** |

---

## 5. 정본 위치 `[결정 필요]`

| 선택지 | 장점 | 단점 |
|---|---|---|
| A. fork 모노레포 `~/projects/flutter_photo_manager_plugins/packages/photo_manager_fast_image` | melos 워크스페이스·LICENSE 복사 스크립트·업스트림 PR 경로가 그대로 | Zelly `path:`가 모노레포를 가리키게 됨(현재 video_player는 독립 repo를 가리킴 → 두 패키지의 경로 규칙이 달라짐) |
| B. 독립 repo `~/projects/photo_manager_fast_image` + 모노레포에 복사 | video_player와 같은 운영 방식 | 두 벌 동기화 수작업(지금 video_player가 그렇다) |

권장은 **A**. B의 "두 벌"은 이미 video_player에서 드리프트 위험을 만들고 있다.

---

## 6. 단계 `[정정]`

| 단계 | 내용 | 게이트 |
|---|---|---|
| 0 | **완료(2026-09-06).** 프리캐시 옵션 `.ios` 일치 + 동등성 테스트, 핀치 중 프리페치 제거·post-frame 1회, 줌아웃 로딩을 핀치 끝으로 + 반영, 서비스 단일 provider. (원안의 "clearLiveImages 제거"는 0단계에 포함되지 않았고, 화면이 하얗게 되는 원인도 아니다) | 실기기 핀치 왕복: 메모리 경고 0, assetsd 사망 0 — **통과** |
| 0.5 | **앱만:** 해상도 두 단계(128/320), 캐러셀·포스터 128. 패키지 없이 지금 파이프라인에서 2열 버벅임의 대부분(키 변경 재디코드)을 없앤다 | 4↔2 핀치에서 재요청 0 |
| 1-A | 패키지 구현 + example 계측 | example: 핀치 왕복 흰 칸 0, malloc 잔량 0, p50/p95 |
| 1-B | Zelly 연동: 프로바이더 교체, 프리페치·`GalleryThumbnailService` 삭제, 에러 코드 매핑, 편집 갱신 | Zelly DoD 1~3 |
| 2 | 디스크 128 캐시 — **[결정 필요]** 패키지(선택 기능) vs 앱 | 콜드 구간 계측 |
| 3 | A/B, 파티션 캐시 여부, 문서 개정, (선택) 업스트림 제안 | DoD 4 |

`[정정]` 원안의 "1~2시간", "120fps 검증"은 뺐다. 시간 추정은 근거가 없고, 판정 기준은 체크리스트의 "16ms 초과 프레임 수"다.

---

## 7. 결론

- P1~P8은 그대로. 바뀌는 것은 **P2·P4·P5·P7의 구현 위치**가 앱에서 패키지로 옮겨지는 것뿐이다.
- 패키지 API는 **크기를 숫자로 받고**, 해상도 단계·캐시 예산·프리페치 정책은 앱에 남긴다. 그래야 Zelly의 A/B와 다른 앱의 사용이 함께 성립한다.
- Immich는 AGPL-3.0 — 방식은 따르되 코드는 옮기지 않는다. 패키지 라이선스는 모노레포와 같게(MIT 계열) 둔다.
