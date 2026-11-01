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

- 실행기(Admin·Play·Launch)가 [tools/launcher-common.zsh](../tools/launcher-common.zsh)를 공유합니다: Luanti 위치(`runtime/` 또는 `/Applications`), 사용자 데이터 격리, 키 바인딩 복원, Control+클릭, 세계 생성, 접속 이름(`player_name`: `BRICKCRAFT_NAME` → `user/player_name` 파일 → Mac `LocalHostName`, 묻지 않음). 접속 이름은 컴퓨터만 구분하고, 누가 플레이하는지는 게임 안에서 고릅니다. 검사용으로 `BRICKCRAFT_WORLD`·`BRICKCRAFT_PORT`로 세계와 포트를 바꿀 수 있습니다.
- `Admin BrickCraft.command`는 [server.conf](../server.conf)로 `luanti --server`를 백그라운드로 띄우고 `logs/server.log`에서 수신을 확인한 뒤 127.0.0.1로 접속합니다. 스크립트 종료 시 trap이 서버를 정상 종료해 저장합니다. `Play BrickCraft.command`는 경로를 차례로 시도합니다: 지정 주소(`BRICKCRAFT_SERVER` → `user/server_address`), Tailscale `jms`, 로컬 `jms.local`. jms는 두 네트워크(en0 192.168.4.x, en1 192.168.0.x)와 Tailscale에 동시에 있어 이름 하나가 여러 주소가 되고, 닿는 주소라고 서버가 떠 있다는 보장도 없습니다. 그래서 각 IPv4(`ping`, `.local`은 `dns-sd -G v4`)에 Luanti 저수준 패킷(프로토콜 ID `4f457403`, peer 0, reliable seq 65500, ORIGINAL)을 `nc -u`로 보내 서버 응답(`OEt…`)이 온 첫 주소로 접속합니다. 서버 로그에는 남지 않습니다. 시도 결과는 `logs/play.log`, 응답이 없으면 게임을 열지 않고 종료합니다. 게임은 `exec`하지 않고 기다렸다가, 실행 전 `logs/client.log` 줄 수 이후(이번 세션)에 `Connected to`가 없으면 `timed out`·`denied`·`ERROR` 줄이나 "접속 전 종료"를 이유로 출력하고 다른 경로(`jms` ↔ `jms.local`)를 제안합니다(이슈 #2). 둘 다 먼저 [tools/update.zsh](../tools/update.zsh)를 실행합니다: 묻지 않고 `git pull --ff-only --autostash`(`BRICKCRAFT_UPDATE=0`·`--no-update`면 건너뜀), 실패하면 경고 후 계속, 새 커밋을 받았으면 `LAUNCHER`를 한 번 다시 `exec`. 갱신이 스크립트를 다시 쓸 수 있어 본문을 `{ ... }`로 감싸 zsh가 끝까지 읽은 뒤 실행하게 했고, Luanti 검사(`launcher-common.zsh`)보다 먼저 갱신합니다. `brickcraft.conf`는 Luanti가 종료 때 다시 써서 늘 수정 상태이므로 autostash로 보존합니다.
- 플레이어(사람)는 `init.lua`의 `styles` 표(메시, 텍스처, 이름표 색, 견본 색)입니다. 매 접속마다 *Who's playing?* 폼(`brickcraft:style`)이 뜨고 `choose_player`가 현재 인벤토리를 모드 저장소 `bricks_<id>`에 저장한 뒤 고른 사람의 것을 불러옵니다(처음이면 기본 세트). 접속의 현재 사람은 메타 `brickcraft_profile`이며, 이전 세계의 접속은 고른 모습(`brickcraft_style`)의 사람으로 간주해 인벤토리를 옮깁니다. 퇴장·서버 종료 때도 저장하고, 다른 접속이 플레이 중인 사람은 고를 수 없습니다. 바꿀 때 되돌리기 기록은 지웁니다. 메시·텍스처는 `generate_assets.py`의 `styles`·`person()`이 만듭니다(텍스처 8행: 피부, 상의, 하의, 눈, 머리). 시작 자리는 `spots` 표와 메타 `brickcraft_spot`, `home_pos()`가 `/home`·리스폰·낙하 복귀에 쓰입니다.
- 검사: `python3 tools/test_multiplayer.py` (전용 서버 30010 + 클라이언트 2개, `brickcraft_multiplayer_test` 설정으로 `multiplayer_test.lua` 실행).

## 4b. AI 빌더(플레이어별, jms)

- [ai_builder.lua](../game/mods/brickcraft/ai_builder.lua)는 `brickcraft_ai_builder = true`(server.conf)일 때만 로드되어 공유 서버에만 빌더가 있습니다. 빌더는 `new_worker(owner)`가 만드는 객체이고 owner는 플레이어 id(`builder`·`dad`·`daughter`·`explorer`, 접속 이름이 아님) 또는 `"jms"`입니다. 몸·인벤토리(`brickcraft_ai_<owner>`)·작업·대기열·저장(`ai_state_<owner>`, `ai_bricks_<owner>`, `ai_pos_<owner>`, 이름 `ai_name_<owner>`)이 따로이며, jms는 예전 키(`brickcraft_ai`, `ai_state` 등)를 그대로 씁니다. 전역 스텝이 지금 플레이하는 사람의 빌더만 `tick`하고(`brickcraft_ai_bots`), 주인이 없으면 `despawn`(저장 후 제거)합니다. jms는 `brickcraft_ai_jms = true`일 때만 나옵니다. 작업은 위치로 세계가 정해지고(`world_at`) 빌더는 주인 세계의 작업만 하며 나머지는 대기열에 둡니다. `find_plot`·`survey`·시작 자리는 그 세계 중심 기준이고, `find_plot`은 모든 빌더의 진행·대기 건물 자리와 몸 칸을 막힌 칸으로 봅니다. LuaJIT은 함수 하나에 업밸류 60개까지라 `new_worker`는 위쪽 도우미를 `lib` 표 하나로 받아 지역 변수로 풉니다(실행 중 바뀌는 `quiet`·`IDLE`·잡담 설정만 업밸류). 채팅은 `addressed`가 가장 긴 빌더 이름(또는 `bot`/`my bot` → 말한 사람의 빌더)으로 보냅니다. Claude 요청은 동시 `brickcraft_ai_parallel`(2)개. Luanti는 HTTP를 `init.lua` 최상위에서만 주므로 `init.lua`가 `C.request_http_api()`를 `brickcraft.http`에 넣고 모듈을 불러옵니다(`secure.http_mods = brickcraft`).
- jms는 플레이어와 같은 규칙으로 짓습니다(브릭만 공짜). 저장하지 않는 물리 엔티티(`static_save = false`, 충돌·중력, 게임의 `movement_speed_walk`·점프·중력 값. 클라이언트가 플레이어에게 중력을 2배로 적용하므로 빌더도 2×`movement_gravity`로 떨어져 같은 점프 높이를 냅니다)이며 `core.find_path`로 장애물을 돌아 걷습니다. 손이 닿는 거리 7, 보이는 면을 가리켜야 하며(`aim_place`가 raycast로 첫 번째로 맞는 면이 놓을 칸 옆 면인지 확인), 이미 있는 조각이나 바닥에 붙여서만 놓습니다. 높은 곳은 기둥 쌓기(점프 중 발밑에 tan 브릭)로 올라가 짓고 내려올 때 그 비계를 세퍼레이터로 회수합니다. 막히면 플레이어처럼 `/home`. 놓기·회수는 가짜 플레이어 `hands`로 브릭 아이템 `on_place`(`place_brick`)와 세퍼레이터 `on_use`(`collect`→`core.node_dig`)를 그대로 부르며, jms의 인벤토리는 플레이어와 같은 32칸 `main`(분리 인벤토리 `brickcraft_ai`, 저장소 `ai_bricks`, 우클릭으로 보기)입니다. 색이 모자라면 99개로 채웁니다. 가짜 플레이어 이름은 `<빌더 이름> (AI)`라 실제 접속과 기록이 섞이지 않습니다(파낸 자리 기록도 이 접미사로 빌더를 뺍니다). 진행 중 작업·대기열·마지막 건물은 `ai_state`에 남습니다.
- 계획은 지역 좌표 조각 목록 `{piece,color,x,y,z,turn}`입니다. 정면은 -z이고, `finish`가 요청자를 향하도록 90° 단위로 돌린 뒤 0,0,0에 맞춥니다. `find_plot`이 베이스플레이트(±24)에서 y 0..30이 비어 있고 둘레 1칸이 빈 자리 중 목표에 가장 가까운 곳을 고릅니다.
- 요청은 Local AI API의 OpenAI 형식 `POST /claude/v1/chat/completions`(`brickcraft_ai_url`, `brickcraft_ai_model = opus`)로 보내고, 응답 JSON의 `lines`(`<piece> <color> x y z [turn]`, `box`, `walls`, `clear`)를 `parse_plan`이 검증·제한(18×18×24, 500조각)합니다. 새 부품은 `shapes` 표에서 프롬프트에 자동으로 추가됩니다. 실패하면 `parse_request`가 단어로 내장 설계도를 고릅니다.
- 설정: `brickcraft_ai_jms`(기본 false), `brickcraft_ai_bots`(기본 true), `brickcraft_ai_bot_auto`(기본 false), `brickcraft_ai_parallel`, `brickcraft_ai_name`(jms 이름), `brickcraft_ai_idle`(혼자 짓기까지 초), `brickcraft_ai_auto_max`, `brickcraft_ai_auto`, `brickcraft_ai_llm`(false면 내장만).
- 검사: `python3 tools/test_ai_builder.py`(내장, 30012, jms를 켜고 Leona 빌더도 확인: 이름 규칙·`/botname`·주인만 멈추기·겹치지 않는 자리), `--claude`(실제 설계 1회).

## 4c. 선로와 수레(trains.lua)

- 기차 부품은 `shapes`의 `train=` 항목(Trains 줄)입니다. `place_brick`이 `brickcraft.trains.place`로 넘기고, 수레에 대한 우클릭(엔티티의 `on_rightclick`)이 모터·배터리 박스 부품을 붙이거나 세퍼레이터로 스위치를 움직입니다. 타기는 수레의 `people`이 갑판에 내려앉은 플레이어를 붙이고(점프로 내린 뒤 1초는 다시 붙지 않음), 지면에서 수레 쪽으로 걷는 플레이어의 속도를 선로 방향으로 받아 밉니다.
- 선로 조각은 색마다 노드(`brickcraft:<색>_track`/`_track_curve`, facedir, 정의에 `brickcraft_track`·`brickcraft_color`)이고 `ends_of`가 형태·회전에서 두 끝 방향을 냅니다(직선 r: r, r+2 / 곡선 r: r, r+1). `brick` 그룹이라 세퍼레이터 회수·돌리기와 `remember`(되돌리기)를 브릭과 같이 씁니다. 놓을 때 `lay`가 이웃을 점수로 고릅니다: 이미 이쪽을 향한 끝(4) > 한쪽만 이어진 이웃(1, 돌려 맞춤) > 일직선(+1).
- 수레는 엔진 물리를 쓰지 않는 엔티티입니다(minetest_game carts와 advtrains 방식). 상태는 칸(`_cell`), 들어온 끝(`_from`), 조각 안 거리(`_s`), 속도(`_v`), 운전자 없이 유지할 속도(`_cruise`)이며 staticdata에 저장됩니다. 매 단계 `centerline`(직선, 또는 모서리 중심 반지름 0.5의 사분원)으로 목표 위치를 구해 속도 = 접선×v + (목표−현재)×4로 움직여 클라이언트 보간이 부드럽습니다. 0.6칸 넘게 벗어나면 `set_pos`로 맞춥니다.
- 모터·배터리 박스는 수레의 `_motor`·`_battery`이고 모습은 붙어 다니는 `brickcraft:cart_part` 엔티티(저장 안 함, 수레가 켜질 때 다시 붙임)입니다. 배터리 박스 부품의 우클릭이 스위치(`_power` 1/0/−1)입니다. `_flip`은 수레의 앞이 진행 방향 반대인지이며 진행 방향을 뒤집을 때마다 바뀌어, 모터의 "앞으로"와 모습의 방향이 기관차 기준으로 유지됩니다.
- 연결: 따라가는 수레는 `_leader`(앞 수레 `_id`, `carts` 표로 찾음)와의 선로 거리 `gap`을 1칸으로 맞춥니다. 속도 = 앞 수레의 선로 속도(서로의 `gap` 부호로 방향 판단) + 3×(거리−1). 세계 속도를 접선에 투영하면 곡선에서 0에 가까워져 한 칸 가까이 처지므로 쓰지 않습니다. 기관차는 따라가지 않고, 연결할 수 없는 두 차가 닿으면 움직이던 쪽이 멈춥니다.
- 탄 사람의 키는 수레가 읽고, `init.lua`의 키 동작(U 되돌리기, Tab, ?)은 붙어 있는 동안 건너뜁니다.
- 메시는 `tools/generate_assets.py`가 만듭니다. Luanti OBJ 로더는 x를 뒤집고(`COBJMeshFileLoader`의 `vec.X = -...`) 재질을 `usemtl`이 아니라 `g` 그룹으로 나누므로, 선로·수레는 `flip_x=True`로 미리 뒤집고 재질마다 `g`를 씁니다(타일 순서 = 그룹 순서). 대칭이 아닌 기존 메시(경사 2×1, 둥근 1×1)는 이 보정을 받지 않았습니다.

## 4d. 버그 보고 → GitHub 이슈

- 빌더의 `report`가 `brickcraft.reports.queue`로 `<world>/issues/<id>.md`·`.label`·`.title`(마지막에 씀)을 남깁니다. Luanti 모드는 셸을 못 쓰므로 Admin 실행기가 서버를 띄운 동안 15초마다 `tools/post_issues.zsh <world>`를 돌려 `gh issue create`로 올리고 `issues/sent/<id>.url`을 남깁니다. 빌더는 3초마다 그 파일을 보고 링크를 말합니다. `BRICKCRAFT_ISSUES_DRY=1`이면 올리지 않고 출력만 하며, AI 검사가 이것으로 확인합니다.

## 4e. 전쟁 모드(war.lua)

- 켜기·끄기는 `start`/`stop`(`/war`, 인벤토리 `war` 버튼). 켜면 `main`을 `war_stash` 목록으로 옮기고 `main`에 도구 4개를 넣습니다. `init.lua`의 `save_bricks`는 `war_stash`가 있으면 그것을 저장하고, `choose_player`는 바꾸기 전에 `brickcraft.war.stop`을 부릅니다. 접속 시 `war_stash`가 남아 있으면(서버 종료 등) 브릭을 되돌립니다. 켤 때 되돌리기 기록(`brickcraft.forget`)을 지워 브릭이 도구 칸으로 가지 않게 합니다.
- 하트는 모드 자체 값(`war[name].hp`, 반 칸 단위 10)과 statbar HUD입니다. `enable_damage = false`는 그대로입니다. `hit(target, attacker, move, dir)`가 모든 공격의 한 경로이며 `MOVES` 표가 피해·밀림·쿨다운을 정합니다. 플레이어 밀림은 `add_velocity`라 클라이언트가 움직이고, 땅 마찰이 커서 값이 큽니다(칼 7 → 약 1칸).
- 대포알은 엔진 물리 없이 매 단계 지난 구간을 `core.raycast`로 확인하고, 단단한 노드나 사람·기사에 닿으면 둘레 `BLAST`(1.6) 안의 대상을 맞힙니다. 쏜 사람은 맞지 않습니다. 대포·기사·대포알은 `static_save = false`이며 주인이 전쟁을 끝내면 지웁니다.
- War Lab은 Train Yard처럼 `make_world`로 한 번 만들며(`lab`, `lab_built`), 기사는 저장되지 않으므로 누군가 그 세계에 있을 때 다시 세웁니다(`_lab`). 검사 세계에서는 `brickcraft_war_test`일 때만 만듭니다.
- 검사: `python3 tools/test_war.py`(전용 서버 30014 + 클라이언트 2개): 평화(전쟁 아닌 사람은 안 맞음), 칼·발차기·밀기의 실제 클라이언트 밀림, 대포, 녹아웃·보호, 기사, 브릭 복원, War Lab.

## 4e. 테크닉 기계(technic.lua)

- 부품은 `shapes`의 `technic=` 항목과, 바닥에 놓은 `train=motor/battery`입니다. 축·기어는 모델의 y축이 회전축이고 facedir의 축 방향(param2 ÷ 4)으로 눕힙니다. 테크닉 브릭·모터·배터리 박스는 param2 % 4로 돕니다.
- 회전 계산(`solve`): 켜진 모터마다 출력 칸에서 시작해 같은 축의 축·기어·테크닉 브릭으로 같은 빠르기를, 옆 칸의 평행한 기어로 −잇수비를 전달합니다. 한 칸에 다른 값이 오면 걸림(그 기계 전체 0). 부품을 놓기·회수·돌리기·스위치할 때와 2초마다, 플레이어 80칸 안의 모터만 계산합니다(모터 위치는 mod storage `technic_motors`).
- 도는 부품은 보이지 않는 짝 노드(`_spin`, 그룹 `technic_spin`)로 바꾸고 그 자리에 `brickcraft:spinner` 엔티티를 둡니다. 엔티티는 `vector.dir_to_rotation`으로 모델 y축을 회전축에 맞추고 `automatic_rotate`(초당 회전 × 2π)로 클라이언트에서 돌아 네트워크 부담이 없습니다. 저장하지 않으며, 블록을 다시 읽을 때 LBM이 짝 노드를 원래대로 돌려놓고 다음 계산이 다시 돌립니다.
- Technic Lab 세계는 `init.lua`가 만들고(Train Yard와 같은 방식) `technic.lua`의 `build_lab`이 기계를 놓습니다.

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

키 바인딩은 [brickcraft.conf](../brickcraft.conf)의 `keymap_*`에 있습니다. 방향키는 WASD와 `|`로 함께 묶었고, `?`/`/` 키(스캔코드 56)는 `keymap_zoom`으로 보내 `zoom_fov = 0`인 서버 쪽에서 도움말을 엽니다. U(스캔코드 24)는 쓰지 않는 sneak 컨트롤로 보내 마지막 건축 동작을 되돌립니다. 명령 채팅 키는 쓰지 않는 F13으로 옮겼습니다(빈 값은 쓰지 마세요). F 키도 배치(`keymap_place`)에 묶었습니다. 실행기가 시작 전 빠진 `keymap_*` 줄을 다시 추가하고, `SDL_MAC_CTRL_CLICK_EMULATE_RIGHT_CLICK=1`로 Control+클릭을 우클릭으로 바꿉니다(Luanti 5.17 내장 SDL 2.32). Cmd+클릭은 Luanti 키 설정이 수정키+마우스 조합을 지원하지 않아 넣지 않았습니다. **게임이 켜진 동안 이 파일을 고치지 마세요.** 클라이언트가 종료하며 시작 시점 설정으로 파일을 다시 써서 수정이 사라집니다. 조작 전체 목록은 게임 안 `?`·`/keys` 화면이며 `init.lua`의 `help_rows` 표 하나가 내용을 정합니다. 키를 바꾸면 이 표도 함께 고치세요. 조작: WASD 이동, 마우스 시점, Space 점프(`game/minetest.conf`의 `movement_speed_jump = 9.3`, 높이 = 점프²/(4×중력) ≈ 2.2칸이라 2칸 벽에 오름), 1 세퍼레이터/좌클릭 회수, 2–9 색 선택/우클릭 배치, U 되돌리기, I 인벤토리, C 카메라 전환. `/guide` 안내, `/home` 시작점 복귀. Esc만 눌러서는 세계가 닫히지 않으며, Exit to Menu 또는 Exit to OS로 저장 종료합니다.

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

`init.lua`의 `build_landscape`가 서버 시작 후 `core.emerge_area`로 ±46 영역을 불러와 한 번만 씁니다. 모드 저장소의 `landscape_version`이 `LANDSCAPE_VERSION`보다 작을 때만 실행하므로 기존 세계에도 추가되며, 공기 칸만 채워 저장된 건축물을 보존합니다. 지형을 바꾸면 버전을 올리세요. 이미 쓰인 잔디·나무는 지우지 않고 빈 칸만 채웁니다. 기존 workshop 세계는 `mapgen_limit = 64`로 만들어져 블록이 약 -48..63에만 있으므로 지형 범위를 ±46으로 제한했습니다. 플레이어가 만드는 세계 때문에 실행기(`init_world`)가 그런 세계의 `map_meta.txt`를 `mapgen_limit = 1024`로 올리고, `brickcraft.conf`도 1024입니다.

**세계(Which world?):** 서버에는 Luanti 세계가 하나뿐이므로, 플레이어가 만드는 세계는 같은 지도에서 원점의 Workshop 둘레 고리 모양 자리(`SPACING` = 128칸 간격, ±`EDGE` 언덕이 겹치지 않음)에 놓인 작업장 복사본입니다. 모드 저장소 `worlds`에 `{id, name, owner, x, z, built}`로 저장합니다. `make_world`가 `emerge_area` 후 `build_landscape(0, 중심, true)`로 베이스플레이트·수집 더미·아치·모자이크(`workshop_node`)와 바닥·언덕·나무를 공기 칸에만 씁니다. 짓다가 종료되면 다음 시작에 마저 짓습니다(`built=false`). 지금 있는 세계는 위치로 정합니다(`world_at`: 그 128칸 칸을 쓰는 세계, 없으면 Workshop). `home_pos`·`/home`·추락 복귀·리스폰은 그 세계의 중심 + 시작 자리입니다. 사람별 마지막 세계는 `world_<id>`에 저장해 목록에서 미리 고릅니다. 플레이어 빌더(`ai_builder.lua`)는 주인이 있는 세계의 중심 기준으로 짓고, jms는 Workshop에만 있습니다. `tools/test_multiplayer.py`가 *Make new world*·목록 선택·더블 클릭 경로를 확인합니다. 경치 노드(`grass`, `dirt`, `trunk`, `leaves`)는 `brick` 그룹이라 세퍼레이터로 수확하며, `drop`으로 일반 브릭(`green`·`tan`·`brown`·`green`) 1개를 줍니다. 언덕 전체를 그려도 가볍도록 노드 자체는 돌기 없는 정육면체로 두었고, 저장된 이름도 그대로라 마이그레이션이 필요 없습니다. 언덕 아래 y = -2에는 캘 수 없는 `brickcraft:baseplate` 바닥이 있습니다. `LANDSCAPE_VERSION` 2에서 추가했으며, v1 세계에는 바닥만 더하고 언덕·나무는 다시 채우지 않으므로 수확한 칸이 되살아나지 않습니다.

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
