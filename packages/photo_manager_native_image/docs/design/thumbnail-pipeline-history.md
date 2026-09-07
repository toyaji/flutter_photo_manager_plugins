# 변경 이력 — 폐기한 안과 이유

[← 본문](./thumbnail-pipeline.md)

| 버전 | 폐기한 안 | 이유 |
|---|---|---|
| v1 | 버킷 5종 유지 + 프리페치 창 120장 상한 + 버킷 전환 시 네이티브 캐시 해제 | photo_manager에 자산별 `stopCachingImages` API가 없어 전역 해제뿐. 근본 원인(옵션 불일치·타이밍)을 놓친 채 상한만 두는 땜빵 |
| v1 | `ResizeMode.exact` | RGBA 상한은 Dart 디코드 크기가 정한다. 네이티브 CPU만 늘어난다 |
| v1 | 게이트 "메모리 경고 0회" | OS 전체 압박에도 오므로 재현 불가. `assetsd` 재연결 0으로 교체 |
| v2 | 점진 개선(S1~S12)만으로 종료 | 사용자 기준 변경: 성능 최우선, 네이티브 경로 포함 |
| v3 | "`onLastListenerRemoved`로 취소" 직결 | Immich가 세 오작동을 문서화하고 믹스인으로 감싼 지점 |
| v3 | "네이티브 캐시 0, 총량 = 살아 있는 셀" | Flutter 캐시 100MB와 자기모순 |
| v3 | Android `loadThumbnail`만 | minSdk 26. 26~28 폴백 필수 |
| v4 | "분리 캐시 2개 설치" | `PaintingBinding`은 캐시 슬롯이 하나. 파사드 1개 + 커스텀 바인딩으로 |
| v4 | R3 "JPEG 0회" 전면 | 디스크 캐시(JPEG q70)와 충돌. PhotoKit/MediaStore 경로 한정으로 |
| v4 | `imageCache.evict(this)`(completer) | 키는 프로바이더. completer로는 no-op |
| v4 | E의 근거 "photo_manager 표시 경로가 남으면 `PHCachingImageManager` 캐시가 되살아난다" | 그 캐시는 `startCachingImages` 등록분만 쥔다. E(전부 새 경로)는 JPEG 왕복 제거·키 통일로 정당화 |
| v5 | 편집 자산 갱신을 키(`modifiedDateSecond`)만으로 | 복귀 동기화가 개수만 비교해 편집을 못 잡는다 → 2튜플 비교 |
| v5 | 26~28 full 경로 `BitmapFactory`만 | EXIF 미적용. base/main 폴백도 같은 결함 → 회전 보정 |
| v6 | `getAssetListRange`에 `OrderByItem` | 그 API에 order 인자가 없고 `OrderByItem`은 다른 필터 계통. 앨범 필터가 이미 `updateDate desc`라 불필요 |
| 전체 | PlatformView 그리드 / 셀별 `Texture` / 공유 메모리 / `PHCachingImageManager` 재도입 | 리서치 문서 "기각한 대안" |
