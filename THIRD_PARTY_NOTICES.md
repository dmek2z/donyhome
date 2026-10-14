# 제3자 구성요소 고지

도니홈에 포함되었거나 코드를 참고한 외부 자원입니다. 각 라이선스 전문은 표의 경로에 있습니다.

| 구성요소 | 용도 | 라이선스 | 경로 |
|---|---|---|---|
| [Maccy](https://github.com/p0deje/Maccy) | 클립보드 캡처·검색·정렬 로직 참고·이식 | MIT | `Resources/Clipboard/Maccy-LICENSE.txt` |
| [fuse-swift](https://github.com/krisk/fuse-swift) 퍼지 검색 | 클립보드 유사 검색 | MIT | `Resources/Clipboard/Fuse-LICENSE.txt` |
| [battery](https://github.com/actuallymentor/battery) | 배터리 충전 제어 스크립트 | MIT | `Resources/Battery/LICENSE.battery` |
| [smcFanControl](https://github.com/hholtmann/smcFanControl) `smc` | 배터리 제어가 호출하는 별도 실행 파일. 저장소에는 소스만 있고 `scripts/build-app.sh`가 빌드 때 컴파일 | GPL-2.0 | `Resources/Battery/LICENSE.smc`, 소스 `Resources/Battery/smc-source/` |
| [Pretendard](https://github.com/orioncactus/pretendard) | 본문 글꼴 | SIL OFL 1.1 | `Resources/Fonts/OFL.txt` |
| [Fredoka](https://fonts.google.com/specimen/Fredoka) | 브랜드 글꼴 | SIL OFL 1.1 | `Resources/Fonts/Fredoka-OFL.txt` |
| [Phosphor Icons](https://github.com/phosphor-icons/core) | UI 아이콘 | MIT | `Resources/Icons/LICENSE` |
| 도구 아이콘 | 연동 도구 식별 | 각 소유자의 상표·저작물(식별 목적 사용) | `Resources/ToolIcons/SOURCES.md` |

## 참고

- `smc`는 GPL-2.0 소스로 만든 **별도 실행 파일**이며 앱이 프로세스로 호출합니다. 이 저장소는 소스만 담고 있고 사용자가 직접 빌드합니다. 도니홈 자체(MIT)와 `smc`(GPL-2.0)는 서로 다른 프로그램입니다. 빌드한 앱을 배포한다면 `smc` 소스와 라이선스 전문(위 경로)을 함께 제공해야 합니다.
- 도구 로고와 이름은 각 회사의 상표입니다. 도니홈은 해당 회사와 제휴·후원 관계가 없습니다.
