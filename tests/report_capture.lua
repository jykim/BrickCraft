local C=core
C.after(0,function()
 C.emerge_area({x=-16,y=-16,z=-16},{x=16,y=16,z=16},function(_,_,remaining)
  if remaining~=0 then return end
  C.set_node({x=0,y=0,z=4},{name="brickcraft:coral"})
  C.set_node({x=1,y=0,z=4},{name="brickcraft:gold"})
  local p={get_pos=function() return {x=0,y=0,z=0} end,
   get_look_horizontal=function() return 0 end,get_look_vertical=function() return 0 end,
   get_eye_offset=function() return {x=0,y=0,z=0} end,
   get_properties=function() return {eye_height=1.625} end}
  local location=brickcraft.reports.location(p)
  assert(location.world_id==0 and location.world_name=="Workshop" and location.save=="world")
  assert(#C.write_json(location)<1024)
  local worlds=brickcraft.worlds()
  worlds[#worlds+1]={id=999,name="Report Test",x=128,z=0,built=true}
  local original_pos=p.get_pos
  p.get_pos=function() return {x=130.25,y=12.75,z=3.5} end
  local moved=brickcraft.reports.location(p)
  assert(moved.world_id==999 and moved.world_name=="Report Test" and moved.position.x==130.25)
  assert(location.world_id==0 and location.position.x==0,"captured location doesn't move with the player")
  p.get_pos=original_pos
  local view=brickcraft.reports.capture_view(p,location,brickcraft.reports.dir)
  assert(not view.error,view.error)
  local id=brickcraft.reports.queue("Test report","World pointer: "..C.write_json(location),"bug",function() end,view)
  assert(id==view.id)
  C.safe_file_write(C.get_worldpath().."/test-id",id)
  -- Reporter-only status delivery survives an engine restart and a changed connection name.
  local connect,send,playing=C.get_connected_players,C.chat_send_player,brickcraft.playing_as
  local online,messages={},{}
  C.get_connected_players=function() return online end
  C.chat_send_player=function(name,msg) messages[#messages+1]={name=name,msg=msg} end
  brickcraft.playing_as=function(p) return p.style end
  local data=""
  local store={get_string=function() return data end,set_string=function(_,_,value) data=value end}
  local factory=dofile(C.get_modpath("brickcraft_ai").."/report_notifications.lua")
  local notifications=factory(brickcraft.reports.dir,store)
  online={{style="dad",get_player_name=function() return "OldMac" end}}
  notifications.track("notify-test","Test report",{style="dad",name="OldMac"})
  assert(#messages==1 and messages[1].msg:find("Report received",1,true))
  online={}
  C.mkdir(brickcraft.reports.dir.."/sent")
  C.safe_file_write(brickcraft.reports.dir.."/sent/notify-test.url","https://example.test/issues/1")
  C.safe_file_write(brickcraft.reports.dir.."/sent/notify-test.status.json",
    C.write_json({events={{state="working",url="https://example.test/issues/1"}}}))
  notifications.poll(); assert(#messages==1,"offline updates wait")
  notifications=factory(brickcraft.reports.dir,store)
  online={{style="dad",get_player_name=function() return "NewMac" end},
    {style="daughter",get_player_name=function() return "OtherMac" end}}
  notifications.poll()
  assert(#messages==3 and messages[2].name=="NewMac" and messages[3].name=="NewMac")
  assert(messages[3].msg:find("Work has started",1,true))
  notifications.poll(); assert(#messages==3,"status acknowledgments are not repeated")
  C.get_connected_players,C.chat_send_player,brickcraft.playing_as=connect,send,playing
  C.log("action","REPORT CAPTURE PASS")
  C.request_shutdown("Report capture passed",false,0)
 end)
end)
