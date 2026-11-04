"""Render a compact report-time scene in an isolated Luanti world (macOS GUI required)."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
MAX_IMAGE_BYTES = 200 * 1024
PREVIEW_MOD = r'''
local C=core
local f=assert(io.open(C.get_worldpath().."/view.json","r"))
local view=C.parse_json(f:read("*a")); f:close()
C.register_entity(":report_preview:frozen",{
  initial_properties={physical=false,pointable=false,static_save=false},
})
C.register_on_joinplayer(function(player)
  C.emerge_area(view.minp,view.maxp,function(_,_,remaining)
    if remaining~=0 then return end
    C.place_schematic(view.minp,C.get_worldpath().."/view.mts","0",nil,true)
    for _,e in ipairs(view.entities or {}) do
      local obj=C.add_entity(e.pos,"report_preview:frozen")
      if obj then
        obj:set_properties(e.properties)
        if e.rotation then obj:set_rotation(e.rotation) end
      end
    end
    C.set_timeofday(view.time_of_day or .5)
    player:set_physics_override({speed=0,jump=0,gravity=0})
    player:set_pos(view.location.position)
    player:set_look_horizontal(view.location.look.yaw)
    player:set_look_vertical(view.location.look.pitch)
    if view.eye_offset then player:set_eye_offset(view.eye_offset) end
    if view.eye_height then player:set_properties({eye_height=view.eye_height}) end
    player:set_camera({mode="first"})
    player:hud_set_flags({hotbar=false,healthbar=false,breathbar=false,minimap=false,wielditem=false,basic_debug=false,chat=false})
    for i=1,12 do C.after(i*.5,function()
      C.close_formspec(player:get_player_name(),"")
      for id in pairs(player:hud_get_all()) do player:hud_remove(id) end
    end) end
    C.log("action","REPORT VIEW READY")
  end)
end)
'''


def render(queue, report_id, output):
    if output.exists() and 0 < output.stat().st_size <= MAX_IMAGE_BYTES:
        return output
    context = queue / (report_id + '.view.json')
    scene = queue / (report_id + '.view.mts')
    data = json.loads(context.read_text())
    if data.get("error"):
        raise RuntimeError("Report-time scene capture failed: "+data["error"])
    assert scene.stat().st_size <= 262144, 'Scene exceeds 256 KiB limit'
    with tempfile.TemporaryDirectory(prefix='brickcraft-report-view-') as tmp:
        tmp = Path(tmp)
        world, user = tmp / 'world', tmp / 'user'
        mod = world / 'worldmods/report_preview'
        mod.mkdir(parents=True)
        (user / 'games').mkdir(parents=True)
        (user / 'games/brickcraft').symlink_to(ROOT / 'game')
        (world / 'world.mt').write_text('gameid = brickcraft\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n')
        shutil.copy2(context, world / 'view.json')
        shutil.copy2(scene, world / 'view.mts')
        (mod / 'mod.conf').write_text('name = report_preview\ndepends = brickcraft_ai\n')
        (mod / 'init.lua').write_text(PREVIEW_MOD)
        conf = tmp / 'preview.conf'
        conf.write_text((ROOT / 'brickcraft.conf').read_text() + '''
brickcraft_integration_test = true
brickcraft_ai_builder = true
brickcraft_ai_llm = false
brickcraft_ai_jms = false
screen_w = 960
screen_h = 540
window_maximized = false
enable_sound = false
show_debug = false
show_chat = false
keymap_screenshot = KEY_F12
'''+f'\nscreenshot_path = {user}/screenshots\n')
        (user / 'screenshots').mkdir()
        log = tmp / 'preview.log'
        proc = subprocess.Popen([str(ROOT / 'runtime/luanti.app/Contents/MacOS/luanti'),
            '--go', '--gameid', 'brickcraft', '--world', str(world), '--config', str(conf),
            '--name', 'ReportPreview', '--port', '30179', '--logfile', str(log)],
            env={**os.environ, 'LUANTI_USER_PATH': str(user)}, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                text = log.read_text() if log.exists() else ''
                if 'REPORT VIEW READY' in text:
                    break
                if proc.poll() is not None or 'ServerError' in text or 'ModError' in text:
                    raise RuntimeError(text[-2000:])
                time.sleep(.25)
            else:
                raise RuntimeError('Screenshot renderer did not become ready; GUI session required')
            time.sleep(6)  # meshes arrive, forms close, camera settles
            result = subprocess.run(['osascript', '-e', 'tell application "System Events"',
                '-e', f'set frontmost of (first process whose unix id is {proc.pid}) to true',
                '-e', 'delay 0.5', '-e', 'key code 111', '-e', 'end tell'],
                text=True, capture_output=True, timeout=10)
            if result.returncode:
                raise RuntimeError('Screenshot input permission unavailable: '+result.stderr.strip())
            deadline = time.monotonic() + 5
            pictures = []
            while time.monotonic() < deadline:
                pictures = list((user / 'screenshots').glob('*.png'))
                if pictures:
                    break
                time.sleep(.25)
            if not pictures:
                raise RuntimeError('Luanti did not save a screenshot')
            for quality in (70, 50, 30):
                subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', str(quality),
                    '-Z', '960', str(pictures[-1]), '--out', str(output)], check=True,
                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                if output.stat().st_size <= MAX_IMAGE_BYTES:
                    return output
            output.unlink(missing_ok=True)
            raise RuntimeError('Screenshot exceeds 200 KiB cap')
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=8)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('queue', type=Path)
    parser.add_argument('report_id')
    args = parser.parse_args()
    assert args.report_id and all(c.isalnum() or c == '-' for c in args.report_id)
    output = args.queue / (args.report_id + '.jpg')
    print(render(args.queue, args.report_id, output))
