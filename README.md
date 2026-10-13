# DonyClean · 도니클린

Dony의 Mac에서만 사용하는 저장 공간 정리·성능 관리 앱. macOS 14 이상, SwiftUI/AppKit. 서버·계정·외부 API·추가 런타임 없이 실행합니다.

## 실행

```sh
./scripts/build-app.sh
open build/DonyClean.app
```

Finder에서 `build/DonyClean.app`을 `~/Applications`로 옮겨 사용할 수 있습니다. 로그인 시 실행을 사용할 경우 이동한 앱을 실행한 뒤 앱 설정에서 켜세요. 현재 빌드는 개인 로컬 사용을 위한 ad-hoc 서명입니다.

## 기능

- 한눈에 보기: 실제 CPU·메모리·압박·스왑·디스크 상태. 스마트 점검 한 번으로 캐시·로그·개발 캐시, 큰 파일·중복·오래된 파일·설치 파일·유사 사진·용량 지도, 설치 앱·잔여물을 모아서 확인합니다.
- 스마트 정리: 오래된 캐시·로그와 동일한 파일 사본을 자동으로 추리고, 추천 정리 실행으로 일괄 휴지통 이동. 추천 종류 제외·상세 검토, 실행 직전 재검증, 원본 보관, 항목별 실패 기록을 제공합니다. 자세한 범위와 미지원 기능은 [CleanMyMac 비교 리뷰](docs/cleanmymac-review.md)를 참고하세요.
- 저장 공간 정리: `~/Library/Caches`, `~/Library/Logs`의 개별 항목 확인과 선택한 항목의 휴지통 이동. 실행 앱 ID와 정확히 일치하는 폴더는 건너뜁니다.
- 개발 캐시: Xcode Build/Index/noindex 생성물, npm/pip/Homebrew/Yarn 다운로드 캐시. 실행 도구와 최근 변경을 확인하고 7일 이상 지난 항목을 추천. Archives와 패키지 저장소는 유지합니다.
- 용량 지도: 크기순 폴더 지도·하위 탐색·직접 선택 정리. 논리 크기 기준이며 링크·하드 링크·미다운로드 iCloud 파일을 구분합니다.
- 유사 사진: macOS Vision의 로컬 CPU 비교, 미리보기, 보관 사진 교체와 수동 정리. 최대 200장, 거리 기준 0.35. 보관 사진은 자동 추천에서도 보호합니다.
- 오래된 파일·설치 파일: 180일 이상 미변경 파일, dmg/pkg/iso를 분류해서 직접 검토.
- 큰 파일: 선택한 폴더의 100 MB 이상 파일. 중복 파일: 크기 → 스트리밍 SHA-256 → 실제 바이트 비교. 그룹마다 원본 한 개를 보관합니다.
- CPU·메모리: 프로세스별 실시간 CPU 변화량, 앱과 도우미 프로세스 합산 사용량. CPU 50% 이상 또는 앱 합산 메모리 1 GB 이상인 앱을 추려 선택할 수 있습니다. 선택한 GUI 앱에 일반 종료를 일괄 요청하고 필요할 때 별도로 강제 종료합니다. 종료 요청 전후 시스템 수치를 관측합니다.
- 앱 관리: `/Applications`, `~/Applications`의 사용자 설치 앱. 앱 ID가 정확히 일치하는 캐시·로그·환경 설정·Application Support·컨테이너를 확인합니다. 앱 이름을 쓰거나 여러 앱이 공유하는 지원 폴더는 자동 추정하지 않습니다.
- 앱 잔여물 후보: 설치/등록/실행 앱 ID 확인 후 Preferences·지원 파일·Containers·캐시 등의 미등록 후보를 표시. 실제 제거 여부는 직접 판단하며 이동 직전 상태를 다시 확인합니다.
- 유지보수: DNS 초기화·Spotlight 재색인 요청·Time Machine 로컬 스냅샷 목록 및 선택 제거. 확인 후 OS 관리자 인증으로 고정 명령을 실행합니다. 스냅샷 제거는 영구 삭제이며 실제 개인 백업을 테스트로 제거하지 않았습니다.
- 메뉴 막대: 실시간 CPU·메모리·배터리·네트워크 수신률. 개요에서 송수신률도 표시합니다. 설정에서 지속적인 과부하 알림과 로그인 실행을 켤 수 있습니다.
- 정리 기록: 최근 500건의 실제 결과와 실패 이유를 `~/Library/Application Support/DonyClean/history.json`에 저장합니다.

## 파일과 앱 보호

직접 선택한 항목 또는 검토한 추천 목록을 native 확인 창에 전체 경로를 표시하고 이동합니다. 검사 후 파일·디렉터리 내용·부모 경로가 변경되면 작업을 거부합니다. 중복 사본은 원본이 그대로 남아 있을 때만 이동합니다. 휴지통 이동은 즉시 디스크 공간 확보로 계산하지 않습니다. 휴지통 비우기와 복원은 Finder에서 합니다.

앱 종료는 현재 사용자 소유의 일반 GUI 앱만 가능합니다. PID, 시작 시각, UID를 다시 확인하고 시스템 프로세스와 도니클린 자체를 보호합니다. CPU·메모리 정리는 선택한 앱 종료를 통해 자원을 회수합니다. `purge`, 스왑 파일 삭제, 메모리 강제 할당 같은 동작을 수행하지 않습니다.

검사 중단·읽기 권한 부족·변경된 파일은 결과에 표시됩니다. macOS가 접근을 제한하는 폴더는 앱에서 권한을 우회하지 않습니다. 원하면 시스템 설정에서 접근 권한을 직접 관리할 수 있습니다.

악성코드 검사와 타사 앱 자동 업데이트는 이번 버전에 포함하지 않습니다. 앱별 합산 메모리에는 공유 메모리가 중복될 수 있고, CPU는 코어당 100%라 앱 수치가 100%를 넘을 수 있습니다. 클라우드 검사는 iCloud의 다운로드 상태를 확인하며 모든 타사 클라우드 공급자를 보장하지 않습니다.

## 디자인

Dony Dony 스타일 토큰·사이드바·버튼·탭·체크박스를 SwiftUI로 적용했습니다. 회색 배경, 흰 카드, 파란 기본 행동, Pretendard. 아이콘은 원격 사이드바와 같은 Phosphor의 채움 벡터, 보조 동작은 같은 계열의 선형 아이콘입니다. 로고는 Dony의 원본 favicon입니다. [자산 출처](Resources/ASSETS.md).

## 개발·검증

```sh
./scripts/test.sh
./scripts/build-app.sh
build/DonyClean.app/Contents/MacOS/DonyClean --diagnostics
build/DonyClean.app/Contents/MacOS/DonyClean --smart-plan
build/DonyClean.app/Contents/MacOS/DonyClean --snapshots
build/DonyClean.app/Contents/MacOS/DonyClean --scan "$HOME/Downloads"
```

`--diagnostics`, `--smart-plan`, `--snapshots`, `--scan`은 읽기 전용입니다. `--smart-plan --folder /경로`로 파일 범위를 지정할 수 있습니다. 파일 작업 테스트는 매 실행마다 만든 임시 파일만 사용하고, 테스트 파일의 휴지통 이동 후 복원·정리합니다.

이 Mac의 Command Line Tools에는 XCTest가 없어 Swift Testing을 사용합니다. 테스트 스크립트는 해당 프레임워크와 매크로 플러그인을 명시적으로 연결합니다. 설치된 macOS 27 SDK의 SwiftUI 플러그인 누락을 피하기 위해 macOS 26.5 SDK가 있으면 이를 사용합니다. `DONY_SDK_PATH`로 빌드 SDK를 지정할 수 있습니다.
