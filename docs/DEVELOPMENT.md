# BrickCraft 개발자 가이드

기준: 2026-10-31, 첫 프로토타입 커밋 `a2c7b92`와 저장된 검사 기록. 이 문서는 현재 구현을 설명하며, [TODO](../TODO.md)의 후속 기능을 구현 완료로 간주하지 않습니다.

## 1. 프로젝트 위치와 시작 문서

- 호스트: Mac Studio `jms.local`, 사용자 홈 `/Users/lifidea`.
- 요청 경로: `~/dev/BrickCraft` = `/Users/lifidea/dev/BrickCraft`.
- 실제 디스크 경로: `/Volumes/990PRO/lifidea/Projects/dev/BrickCraft`. `dev`가 심볼릭 링크이므로 별도 복사본이 아닙니다.
- [README](../README.md): 플레이와 검증 요약.
- [TODO](../TODO.md): 완료 범위, 우선순위, 승인 대기 사항.
- [출처와 라이선스](THIRD_PARTY.md), [Luanti 원본 고지](LUANTI-LICENSE.txt), [BrickCraft MIT 라이선스](../LICENSE).

## 2. 실행 환경과 공식 의존성

실제로 검증한 엔진은 **Luanti 5.17.0 macOS Apple Silicon**이며 `runtime/luanti.app`에 있습니다. 앱은 수정하지 않았습니다. [game.conf](../game/game.conf)의 `min_engine_version = 5.10`은 선언된 하한일 뿐, 5.10부터 모든 버전을 시험했다는 뜻은 아닙니다.

- [공식 다운로드](https://www.luanti.org/en/downloads/), [고정한 5.17.0 공식 아카이브](https://github.com/luanti-org/luanti/releases/download/5.17.0/luanti_5.17.0_macos12.3_arm64.zip).
- 아카이브 SHA-256: `0ba118b537d3cc6fd07cd2268fef25e515fc6d87c27ad69b476144a8e28dba3c`. 최초 준비 시 Homebrew cask 값과 대조했습니다.
- [해당 버전 엔진 소스](https://github.com/luanti-org/luanti/tree/5.17.0), [게임 구조 API](https://api.luanti.org/games/), [Lua API](https://api.luanti.org/).
- 게임/모드 외부 의존성은 없습니다. 자체 `brickcraft` 모드 하나가 Luanti 기본 API를 사용합니다. Minetest Game과 DevTest는 비교 후보였으며 설치된 게임 의존성이 아닙니다.
- 에셋 생성과 테스트 도구는 Python 3 표준 라이브러리만 사용합니다. Pillow, pip 패키지, 별도 Lua 설치가 필요하지 않습니다.
- 엔진은 LGPL-2.1-or-later이며 엔진 미디어는 별도 고지를 따릅니다. BrickCraft 원본 코드·생성 에셋은 MIT입니다.

`runtime/`은 Git에서 제외됩니다. 새 체크아웃에는 앱이 없을 수 있으므로 공식 고정 아카이브의 해시를 확인하고 `runtime/luanti.app` 구조로 준비해야 합니다. 임의 미러나 보안 설정 우회는 사용하지 않습니다.

## 3. 실제 폴더 구조

| 경로 | 역할 |
| --- | --- |
| [Launch BrickCraft.command](../Launch%20BrickCraft.command) | 프로젝트 경로 계산, 사용자 데이터 격리, 게임 링크·세계 초기화, 클라이언트 실행 |
| [brickcraft.conf](../brickcraft.conf) | 화면·맵 생성·사운드·OpenGL 등 실행 설정 |
| [game/game.conf](../game/game.conf), [game/minetest.conf](../game/minetest.conf) | 게임 메타데이터와 기본 설정 |
| [game/mods/brickcraft/init.lua](../game/mods/brickcraft/init.lua) | 노드·도구·맵 생성·플레이어·인벤토리·HUD·명령 |
| [game/mods/brickcraft/integration.lua](../game/mods/brickcraft/integration.lua) | 명시적으로 활성화할 때만 로드되는 2단계 통합 검사 |
| [tools/generate_assets.py](../tools/generate_assets.py) | 원본 PNG 12개와 블록 사람 OBJ 생성 |
| [tools/test_integration.py](../tools/test_integration.py) | 별도 세계에서 실제 GUI 클라이언트를 두 번 실행하는 검사 |
| `game/mods/brickcraft/textures/`, `models/` | Git에 보존된 생성 에셋 |
| `user/games/brickcraft` | 실행기가 만드는 `game/` 대상 심볼릭 링크 |
| `worlds/workshop/` | 사용자 실제 세계·플레이어·인벤토리 SQLite 저장 |
| `logs/client.log`, `user/` | 실행 로그와 프로젝트 전용 엔진 사용자 데이터 |
| `tests/run/session-*/` | 검사별 임시 세계·설정·사용자 데이터·로그 |
| [preview.png](preview.png), [test-phase1.log](test-phase1.log), [test-phase2.log](test-phase2.log) | 보존된 실제 화면과 통과 증거 |

현재 [.gitignore](../.gitignore)는 `runtime/`, `user/`, `worlds/`, `logs/`, `tests/run/`을 제외합니다. 코드 커밋만으로 개인 건축물까지 백업되는 것은 아닙니다.

## 4a. 멀티플레이 구조

- 실행기 세 개가 [tools/launcher-common.zsh](../tools/launcher-common.zsh)를 공유합니다: Luanti 위치(`runtime/` 또는 `/Applications`), 사용자 데이터 격리, 키 바인딩 복원, Control+클릭, 세계 생성, 접속 이름(`player_name`: `BRICKCRAFT_NAME` → `user/player_name` 파일 → Mac `LocalHostName`, 묻지 않음). 접속 이름은 컴퓨터만 구분하고, 누가 플레이하는지는 게임 안에서 고릅니다. 검사용으로 `BRICKCRAFT_WORLD`·`BRICKCRAFT_PORT`로 세계와 포트를 바꿀 수 있습니다.
- `Host BrickCraft.command`는 [server.conf](../server.conf)로 `luanti --server`를 백그라운드로 띄우고 `logs/server.log`에서 수신을 확인한 뒤 127.0.0.1로 접속합니다. 스크립트 종료 시 trap이 서버를 정상 종료해 저장합니다. `Join BrickCraft.command`는 서버 주소만 묻고 접속합니다.
- 플레이어(사람)는 `init.lua`의 `styles` 표(메시, 텍스처, 이름표 색, 견본 색)입니다. 매 접속마다 *Who's playing?* 폼(`brickcraft:style`)이 뜨고 `choose_player`가 현재 인벤토리를 모드 저장소 `bricks_<id>`에 저장한 뒤 고른 사람의 것을 불러옵니다(처음이면 기본 세트). 접속의 현재 사람은 메타 `brickcraft_profile`이며, 이전 세계의 접속은 고른 모습(`brickcraft_style`)의 사람으로 간주해 인벤토리를 옮깁니다. 퇴장·서버 종료 때도 저장하고, 다른 접속이 플레이 중인 사람은 고를 수 없습니다. 바꿀 때 되돌리기 기록은 지웁니다. 메시·텍스처는 `generate_assets.py`의 `styles`·`person()`이 만듭니다(텍스처 8행: 피부, 상의, 하의, 눈, 머리). 시작 자리는 `spots` 표와 메타 `brickcraft_spot`, `home_pos()`가 `/home`·리스폰·낙하 복귀에 쓰입니다.
- 검사: `python3 tools/test_multiplayer.py` (전용 서버 30010 + 클라이언트 2개, `brickcraft_multiplayer_test` 설정으로 `multiplayer_test.lua` 실행).

## 4. 실행과 개발 반복

```sh
cd ~/dev/BrickCraft
./"Launch BrickCraft.command"
```

Finder에서 실행 스크립트를 더블클릭해도 됩니다. 앱만 직접 열면 이 프로젝트의 게임·세계가 선택되지 않을 수 있습니다. 실행기는 `LUANTI_USER_PATH`를 프로젝트의 `user/`로 지정하고, `worlds/workshop/world.mt`가 없을 때만 생성합니다. 플레이어 이름은 `Builder`입니다. 같은 세계를 동시에 여러 인스턴스에서 열지 마세요.

1. 작업 전 `git status --short`로 기존 수정을 확인합니다.
2. Lua 로직이나 원본 에셋 생성기를 수정합니다. 기본 플레이 설정에서 `brickcraft_integration_test`를 켜지 않습니다.
3. 에셋을 변경했을 때만 다음 명령을 실행하고 생성 파일의 diff를 검토합니다. 이 명령은 현재 텍스처·메시를 다시 씁니다.

   ```sh
   python3 tools/generate_assets.py
   git diff --stat
   ```

4. 게임을 저장 종료한 뒤 실행 스크립트로 다시 엽니다. 현재 별도 핫 리로드 기능은 없습니다.
5. 변경한 동작을 직접 확인하고, 배치·회수·저장 경로를 변경했다면 아래 통합 검사도 실행합니다.

키 바인딩은 [brickcraft.conf](../brickcraft.conf)의 `keymap_*`에 있습니다. 방향키는 WASD와 `|`로 함께 묶었고, `?`/`/` 키(스캔코드 56)는 `keymap_zoom`으로 보내 `zoom_fov = 0`인 서버 쪽에서 도움말을 엽니다. U(스캔코드 24)는 쓰지 않는 sneak 컨트롤로 보내 마지막 건축 동작을 되돌립니다. 명령 채팅 키는 쓰지 않는 F13으로 옮겼습니다(빈 값은 쓰지 마세요). F 키도 배치(`keymap_place`)에 묶었습니다. 실행기가 시작 전 빠진 `keymap_*` 줄을 다시 추가하고, `SDL_MAC_CTRL_CLICK_EMULATE_RIGHT_CLICK=1`로 Control+클릭을 우클릭으로 바꿉니다(Luanti 5.17 내장 SDL 2.32). Cmd+클릭은 Luanti 키 설정이 수정키+마우스 조합을 지원하지 않아 넣지 않았습니다. **게임이 켜진 동안 이 파일을 고치지 마세요.** 클라이언트가 종료하며 시작 시점 설정으로 파일을 다시 써서 수정이 사라집니다. 조작 전체 목록은 게임 안 `?`·`/keys` 화면이며 `init.lua`의 `help_rows` 표 하나가 내용을 정합니다. 키를 바꾸면 이 표도 함께 고치세요. 조작: WASD 이동, 마우스 시점, Space 점프, 1 세퍼레이터/좌클릭 회수, 2–9 색 선택/우클릭 배치, U 되돌리기, I 인벤토리, C 카메라 전환. `/guide` 안내, `/home` 시작점 복귀. Esc만 눌러서는 세계가 닫히지 않으며, Exit to Menu 또는 Exit to OS로 저장 종료합니다.

## 5. 검사 방법과 확인된 범위

이번 문서 작성에서는 게임을 재실행하지 않고 기존 통과 로그와 현재 코드·설정을 대조했습니다. 원본 검사일은 2026-10-31입니다.

```sh
cd ~/dev/BrickCraft
python3 tools/test_integration.py
```

그래픽 클라이언트가 열리므로 데스크톱 환경에서 사용자 게임을 먼저 종료하고 실행합니다. 매 실행마다 `tests/run/session-*`를 새로 만들고 경로를 출력합니다. 마지막 출력의 일반적인 로그 안내보다 처음 출력되는 실제 세션 경로를 기준으로 `phase1.log`, `phase2.log`, `phase*-stdout.log`를 확인하세요. `--go` 실행은 설정 파일의 `port`를 무시하므로 검사 스크립트는 `--port 30009`를 명령줄로 넘깁니다. 로그상 `[::]:30009`에서 수신하므로 사용자 게임(30000)을 연 채로도 검사할 수 있습니다.

| 검사 | 근거와 범위 |
| --- | --- |
| 생성·배치·차감 | [Phase 1](test-phase1.log): 베이스플레이트 확인, 실제 `core.item_place` 콜백, coral 24→23 |
| 저장·재실행 | [Phase 2](test-phase2.log): 같은 검사 세계를 재실행해 브릭과 23개 인벤토리, 위치의 x 좌표 확인 |
| 회수·보호 | Phase 2: 실제 세퍼레이터 `on_use`로 노드 제거·23→24 복구, 베이스플레이트 유지 |
| 직접 GUI 검사 | README에 기록된 민트 브릭 클릭 회수 24→25와 우클릭 재배치 25→24, 이동·카메라·화면 확인 |

자동 검사는 GUI 엔진 안에서 콜백을 호출합니다. 모든 단계를 마우스로 수행하는 UI 자동화가 아닙니다. 현재 자동 검사는 인벤토리 포화, 세퍼레이터 없는 회수, 낙하 복귀, 모든 색, 전체 위치 벡터를 포괄하지 않습니다. 해당 동작을 바꾸면 필요한 사례를 추가해야 합니다. 장시간·다중 사용자·다른 OS는 미검증입니다.

`video_driver = opengl`은 Mac에서 동작한 OpenGL 2.1 경로를 선택합니다. 보존한 최종 검사 로그에는 초기 OpenGL3 컨텍스트 실패나 Lua 오류가 없고 일부 SDL 이벤트 지연 경고가 있습니다. 초기 실패 로그와 새 검사 결과는 `tests/run/` 안에서 구분하세요.

## 6. 저장과 기존 세계 보존

실제 저장은 `worlds/workshop/`의 `map.sqlite`(노드), `players.sqlite`(플레이어/인벤토리), `auth.sqlite`, `mod_storage.sqlite` 및 세계 메타 파일에 있습니다. 백업은 게임을 정상 종료한 뒤 **세계 폴더 전체**를 복사합니다. 개발 실험을 위해 이 폴더나 개별 DB를 삭제하지 마세요.

- `register_on_generated`는 새 맵블록에 베이스플레이트와 수집 더미를 생성합니다. 생성 코드를 수정해도 이미 저장된 지역이 자동으로 새 배치로 바뀌지는 않습니다.
- `brickcraft_started` 플레이어 메타가 처음 시작할 때만 도구와 각 색 24개를 지급하도록 합니다. 초기 지급 코드를 바꿔도 기존 플레이어에게 자동 지급되지 않습니다.
- `brickcraft:coral` 등 노드 이름은 저장 데이터의 식별자입니다. 단순 이름 변경 대신 기존 이름 호환·alias 또는 별도 마이그레이션을 설계하세요. 현재 명시적인 저장 스키마 버전/마이그레이션 기능은 없습니다.
- 자동 검사 세계는 사용자 workshop와 별개입니다. 기본 플레이 세계에서 검사 플래그를 켜면 테스트 코드가 실행될 수 있으므로 사용하지 않습니다.

## 7. 브릭·세퍼레이터·인벤토리 확장 지점

### 색 또는 형태 추가

`init.lua`의 `colors`·`labels`와 `generate_assets.py`의 색 정의를 함께 확인합니다. 노드는 `brickcraft:<color>`로 등록되며 `node_box`가 몸통과 돌기를 그립니다. 현재 모든 브릭의 충돌·선택 상자는 한 복셀 크기이고 `stack_max = 999`입니다. 크기 표시는 실제 부품 치수 인증이 아닙니다.

색을 늘릴 때 배열만 추가하면 끝나지 않습니다. 맵 생성의 `for i=1,8`, 수집 더미 간격, 핫바 9칸, 처음 지급 슬롯, 안내 문구가 현재 8색에 맞춰져 있습니다. 먼저 색 선택 UX를 정한 뒤 함께 수정해야 합니다.

형태는 `init.lua`의 `shapes` 표에 있습니다(`id`, 노드 이름 `suffix`, 실제 부품 `part`, 인벤토리 줄 `group`, `cost`, 2칸 부품 `long`, 노드박스 `boxes` 또는 메시 `mesh`, 충돌 상자). 경사·둥근 브릭은 노드박스로 그릴 수 없어 `generate_assets.py`의 `Mesh`가 OBJ를 만듭니다(바깥쪽 법선, 높은 쪽 +z). 새 부품은 실제 부품 번호와 돌기 배치를 확인해 표에 추가하고, `house_test.lua`에서 한 번 이상 쓰도록 하세요. 색마다 형태별 노드가 등록되지만 인벤토리 아이템은 `brickcraft:<color>` 하나이며, 그 `on_place`가 플레이어 메타 `brickcraft_shape`·`brickcraft_turn`을 읽어 해당 형태 노드를 놓습니다. 형태 노드의 `drop`은 색 아이템 × `cost`입니다.

몸통은 칸(-0.5..0.5)을 꽉 채우고 돌기는 0.5..0.64로 위 칸에 솟습니다. 위에 놓인 노드의 몸통이 돌기를 덮어 가리므로 쌓인 브릭 사이에 돌기가 보이지 않습니다. 충돌 상자는 칸 크기 그대로입니다. 2×4는 주 노드의 노드박스가 로컬 +z 방향으로 1.5까지 뻗고, `facedir_to_dir(param2)` 칸에 보이지 않는 `_2x4_tail` 노드를 둡니다. 끝 칸은 충돌·선택만 담당하며 회수·회전은 `primary_of`로 주 노드를 찾아 처리합니다. 주 노드의 `on_destruct`가 끝 칸을 지웁니다. 노드박스는 ±1.5를 넘을 수 없으므로 더 긴 부품은 같은 방식으로 끝 칸을 여러 개 두어야 합니다.

### 언덕과 나무

`init.lua`의 `build_landscape`가 서버 시작 후 `core.emerge_area`로 ±46 영역을 불러와 한 번만 씁니다. 모드 저장소의 `landscape_version`이 `LANDSCAPE_VERSION`보다 작을 때만 실행하므로 기존 세계에도 추가되며, 공기 칸만 채워 저장된 건축물을 보존합니다. 지형을 바꾸면 버전을 올리세요. 이미 쓰인 잔디·나무는 지우지 않고 빈 칸만 채웁니다. 기존 workshop 세계는 `mapgen_limit = 64`로 만들어져 블록이 약 -48..63에만 있으므로 지형 범위를 ±46으로 제한했습니다. 경치 노드(`grass`, `dirt`, `trunk`, `leaves`)는 `brick` 그룹이라 세퍼레이터로 수확하며, `drop`으로 일반 브릭(`green`·`tan`·`brown`·`green`) 1개를 줍니다. 언덕 전체를 그려도 가볍도록 노드 자체는 돌기 없는 정육면체로 두었고, 저장된 이름도 그대로라 마이그레이션이 필요 없습니다. 언덕 아래 y = -2에는 캘 수 없는 `brickcraft:baseplate` 바닥이 있습니다. `LANDSCAPE_VERSION` 2에서 추가했으며, v1 세계에는 바닥만 더하고 언덕·나무는 다시 채우지 않으므로 수확한 칸이 되살아나지 않습니다.

### 배치와 회수

배치는 색 아이템의 `on_place`(`place_brick`)가 형태·회전·끝 칸 공간을 확인한 뒤 `core.item_place_node`에 위임합니다. 통합 검사에서는 `core.item_place`가 아니라 아이템의 `on_place`를 호출해야 이 경로를 탑니다. 회수는 `brickcraft:separator`의 `on_use`가 `brick` 그룹의 노드를 찾아 해당 `on_dig`를 호출하고, 노드 쪽에서 도구와 인벤토리 공간을 확인한 뒤 `core.node_dig`에 위임합니다. 바닥은 `diggable = false`입니다.

새 브릭도 이 경로를 이용하려면 적절한 `brick` 그룹과 안전한 `on_dig`를 제공해야 합니다. 별도 제거 경로로 수량을 두 번 지급하거나, 회수 실패인데 노드만 지워지는 일이 없도록 합니다. 복합 브릭을 도입할 때는 한 번의 회수에서 전체 부품을 정확히 한 개 반환하는 규칙이 필요합니다.

### 인벤토리와 플레이어

`register_on_joinplayer`가 `main` 32칸, 핫바 12칸과 8×4 인벤토리 formspec을 설정합니다. 최초 지급은 1번 세퍼레이터, 2–9번 8색 브릭 각 24개(`STARTER_COLORS`)입니다. `colors`의 마지막 3색(green·brown·tan)은 지급하지 않고 경치 수확으로만 얻으며, 보통 10–12번 칸에 들어갑니다. 슬롯을 늘리거나 재배치할 때 formspec·핫바·초기 지급·기존 저장의 아이템 보존을 함께 확인하세요. 작은 크기로 줄이면 기존 슬롯의 아이템이 영향을 받을 수 있습니다.

현재 캐릭터는 원본 OBJ 정적 메시입니다. `visual_size = {x=10,y=10}`, 충돌 상자와 `eye_height`를 함께 사용하므로 메시 단위와 실제 이동 충돌을 혼동하지 마세요.

## 8. 현재 한계와 실제 부품 연결 방향

지금은 같은 복셀 크기의 2×2 시각 브릭을 놓는 게임입니다. 실제 stud/plate 단위, 부품 카탈로그 ID, 연결점·지지·구조 안정성, 실물 조립 순서 검증은 없습니다. 걷기 애니메이션·음향·제작·자원 재생성·한국어 UI·멀티플레이 UX도 후속 작업입니다.

실물 연결은 게임 내 부품 ID/회전/좌표 모델을 정한 다음 선택 영역의 형태·색·수량 내보내기, 카탈로그 매핑, 연결·충돌·지지 검증, 검증된 조립 단계와 설명서 순으로 진행할 계획입니다. 카탈로그 자료·도구 도입 시 라이선스와 단위를 먼저 확인해야 합니다. 현재 가능한 기능으로 홍보하거나 미검증 구조에 조립 가능 표시를 하지 않습니다.

## 9. native Local 세션과 승인 대기

조정용 cloud task에서 Mac Studio 파일을 작성한 사실은 native Local 세션 생성과 다릅니다. 지원 도구에 새 폴더의 프로젝트 등록 기능이 없었고 Codex 앱 `com.openai.codex` UI 접근도 안전 제한으로 거절돼 **native Local 세션은 생성되지 않았습니다. ID/링크도 없습니다.**

사용자가 Codex 데스크톱 앱에서 `~/dev/BrickCraft`를 프로젝트로 추가하고 해당 프로젝트의 **Local** 작업을 열어야 합니다. 이어서 “README, docs/DEVELOPMENT.md, TODO.md를 읽고 현재 저장 세계를 보존하며 다음 작업을 정하자”라고 시작할 수 있습니다.

`bind_address = 127.0.0.1` 변경은 자동 승인 검토에서 기존 “보안 변경 금지” 지침을 이유로 거절됐고 **미적용·사용자 명시적 승인 대기**입니다. 현재 설정에는 `server_announce = false`가 있으나 로그상 기본 내장 서버는 `[::]:30000`에서 수신했습니다. 이 문서 작성은 설정 변경 권한을 부여하지 않으며, 승인 전 재시도하거나 다른 경로로 적용하지 않습니다. 방화벽·보안 설정 변경이나 공개 배포도 수행하지 않았습니다.
