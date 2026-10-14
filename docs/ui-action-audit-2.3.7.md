# 2.3.7 버튼·메뉴 점검 기록

2026-10-14. 단독 작업. 기준 소스: `codex/development-tool-care`.

## 조사 범위

배포 소스 32개 파일의 **205개 행동 참조 행**을 조사했다. 중첩 메뉴와 반복 행의 동적 버튼을 포함하며, 205개의 서로 다른 버튼을 모두 물리적으로 눌렀다는 뜻은 아니다. 각 행의 원문·위치는 [전체 목록](ui-action-inventory-2.3.7.json)에 남겼다. 연결된 AppModel·ClipboardController·AgentTaskController·BatteryController와 관련 서비스의 조건, 부작용, 오류 처리도 따라갔다.

## 확인한 문제와 수정

| 문제 | 수정 |
|---|---|
| SwiftUI Button → ConfirmationDialog → NSApp.runModal이 원래 SwiftUI 업데이트를 붙잡음 | continuation 기반 비동기 확인창. 원래 버튼은 즉시 반환하고, 실행·취소 버튼은 별도 이벤트로 동작 |
| 동일 확인 방식이 정리·프로세스·유지보수·배터리에 반복 | 공통 구현과 13개 확인 진입점을 함께 전환 |
| 검사 폴더·프로젝트 연결·클립보드 제외 앱 선택이 runModal 사용 | NSOpenPanel.begin 완료 콜백을 기다리도록 3곳 전환 |
| 확인 대기 중 중복 요청·백그라운드 검사 가능 | 모델의 대기 상태와 공통 열린 확인창을 busy에 포함. 한 번의 요청만 유지 |
| 비동기 확인 뒤 설정/검사 결과 변경 가능 | busy·검사 epoch·보관 기간·프로젝트 선택/범위·도구 검사 상태 재확인. 파일/프로세스의 실행 직전 보호 검증 유지 |
| 선택 앱 종료의 확인을 취소해도 선택이 사라짐 | 클릭 시 즉시 선택을 비우는 코드 제거 |
| 검사 중 종료 버튼/강제 종료 메뉴/전체 검사 명령이 활성 상태 | 같은 busy 기준으로 비활성화 |

종료·삭제 확인은 유지한다. 파괴적 행동의 Enter는 취소, Escape와 창 닫기는 취소다. 클립보드 전체 지우기만 사용자의 기존 요청대로 확인 없이 한 번에 비운다.

## 실제 실행 검증

- 설치된 2.3.6 프로세스의 sample에서 SwiftUICore Update.dispatchActions → ButtonAction → AppModel.moveToTrash → NSApp.runModalForWindow 스택을 확인했다. 기존 UI 동기 모달 검사도 실패했다.
- `ConfirmationDialogTests`: 렌더링된 NSHostingView에 실제 NSEvent mouseDown/mouseUp을 전달했다. 파란 버튼 가운데와 배경 가장자리, 취소, Enter/Escape, 창 닫기, Task 취소, 중복 요청, 원래 SwiftUI 버튼에서 열리는 sheet를 검사했다. completion 콜백을 직접 호출해서 클릭 결과를 대신하지 않았다.
- 실제 AppModel/TrashService/HistoryStore로 테스트가 생성한 **78개 파일**을 정리했다. 취소하면 78개와 기록 0건 유지, 실행하면 78개 실제 이동·기록 저장·정리 결과 78건을 확인했다. 테스트가 생성한 파일만 기록된 목적지에서 원위치로 복원하고 제거했다. 사용자의 휴지통 목록을 순회하거나 비우지 않았다.
- DEBUG 전용 `ActionUIFixture`는 프로덕션 RootView와 실제 화면을 사용한다. 별도 bundle ID, 임시 HistoryStore, 전용 NSPasteboard, 전용 defaults로 사용자의 기록과 복사 내용을 분리했다. 네이티브 접근성 클릭으로 전체 선택 → 취소 → 다시 실행 → 78개 이동 완료를 확인했고 기록 파일도 확인했다. fixture 파일은 복원했다.
- 같은 fixture에서 사이드바 **13개 화면**, 파일 검사 **5개 탭**, 개발 **5개 탭**, 클립보드 설정 **6개 탭**을 실제 클릭했다.
- 본창 설정 → 보관 기간 설정 → + → 완료 → 15일 반영, 중첩 클립보드 설정 열기/완료, 앱 정보 열기/완료를 확인했다.
- 폴더 선택은 취소와 완료를 모두 눌러 본화면 복귀·검사 결과 초기화를 확인했다. 폴더 용량 검사 버튼으로 fixture의 **81개 항목·35 KB** 측정 결과를 확인했다. 클립보드 제외 앱 선택창 열기/취소도 확인했다.
- 클립보드 더보기 메뉴의 고정과 텍스트 편집 → 저장을 실행하고 JSON의 고정 상태/편집 결과를 확인했다. 빠른 창 설정 → 완료, 전체 지우기 한 번 → 0개·빈 기록·비활성 버튼을 확인했다.
- DNS 초기화·Spotlight 재색인·배터리 설치 검토 버튼은 실제 확인창 열기와 취소를 검증했다. 관리자 인증과 시스템 변경은 실행하지 않았다.

네이티브 fixture의 표시는 2.3.6 리소스와 변경 중인 DEBUG 바이너리를 사용했다. 최종 2.3.7/build 25 배포 앱을 `/Users/dhkim/Applications/DonyHome.app`에 교체 설치하고 실행 경로·버전·서명을 별도로 확인했다. 이 설치 앱에서 설정 열기/완료와 DNS 확인창 열기/취소를 실제 클릭하고 확인창을 캡처했다. 개인 보관 기간은 기존 14일로 유지됨을 확인했다. fixture는 배포 바이너리에 포함하지 않는다.

## 자동 검사

- 전체 Swift 검사: DonyCore **191개 / 34 suites**, DonyClean **25개 / 2 suites**, 합계 **216개 통과**.
- 디자인 규칙 및 규칙 회귀 검사 5개 통과.
- UI 행동 검사: 배포 UI 코드의 runModal/runModalSession/stopModal 금지. GitHub Actions에도 추가.
- 릴리스 빌드 및 strict codesign 확인.

테스트 번들에는 제품 폰트 리소스가 없어서 폰트 descriptor 로그가 발생한다. CLT의 기존 경로/SDK deprecation 경고도 남아 있다. 빌드와 테스트 실패는 없으며 실제 앱은 포함된 폰트로 렌더링했다.

## 검증의 한계

205개 참조 행은 소스 전수 조사 범위다. 실제 UI 클릭 검증 범위는 위에 명시한 화면·흐름이다. 사용자 앱 종료, 실행 중 개발 작업 정지, 관리자 DNS/색인/스냅샷 삭제, 배터리 SMC 제어, 사용자 파일 영구 삭제, 권한 승인은 이 조사에서 실행하지 않았다. 이 경로들은 공통 확인창과 서비스/정책 테스트로 검증했으며, 다른 물리 Mac과 다른 macOS 버전의 실제 실행까지 확인한 것은 아니다.

## 파일별 행동 참조 행

| 소스 파일 | 참조 행 |
|---|---:|
| AIProjectsView.swift | 16 |
| AboutView.swift | 1 |
| ApplicationsView.swift | 3 |
| AutomaticCleanupView.swift | 1 |
| BatteryManagementView.swift | 13 |
| CleanupView.swift | 6 |
| ClipboardView.swift | 38 |
| ConfirmationDialog.swift | 4 |
| DeveloperTasksView.swift | 5 |
| DeveloperView.swift | 2 |
| DeviceCareModel.swift | 3 |
| DonyCleanApp.swift | 21 |
| DonyProfileView.swift | 1 |
| FilesView.swift | 5 |
| HistoryView.swift | 4 |
| LeftoversView.swift | 2 |
| OnboardingView.swift | 10 |
| OverviewView.swift | 6 |
| PerformanceView.swift | 5 |
| PermissionsView.swift | 5 |
| ProjectCapacityView.swift | 1 |
| RetentionSettings.swift | 4 |
| ScanResultsView.swift | 3 |
| SimilarPhotosView.swift | 3 |
| SmartCareView.swift | 4 |
| SpaceView.swift | 6 |
| Theme.swift | 3 |
| ToolCareView.swift | 11 |
| ToolSelectionView.swift | 1 |
| ToolsView.swift | 4 |
| DonyControls.swift | 11 |
| TrashView.swift | 3 |
