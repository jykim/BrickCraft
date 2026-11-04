-- Durable, per-reporter delivery. External status polling writes only small JSON sidecars.
local C=core
return function(dir,storage)
  local key="player_report_notifications"
  local pending=C.deserialize(storage:get_string(key)) or {}
  local function save() storage:set_string(key,C.serialize(pending)) end
  local function target(recipient)
    for _,p in ipairs(C.get_connected_players()) do
      if (recipient.style and brickcraft.playing_as(p)==recipient.style) or
        (not recipient.style and p:get_player_name()==recipient.name) then return p:get_player_name() end
    end
  end
  local function read(path)
    local f=io.open(path,"r"); if not f then return end
    local s=f:read("*a"); f:close(); return s
  end
  local function deliver(id,r)
    local name=target(r.recipient)
    if not name then return false end
    local changed=false
    local function tell(state,message)
      if r.seen[state] then return end
      C.chat_send_player(name,"[Report "..id.."] "..message)
      r.seen[state]=true; changed=true
    end
    tell("received","Report received. I wrote it down for the game's makers: \""..r.title.."\".")
    local url=read(dir.."/sent/"..id..".url")
    url=url and url:match("[^\r\n]+")
    if url then tell("posted","Your report is on GitHub now: "..url) end
    local raw=read(dir.."/sent/"..id..".status.json")
    local status=raw and C.parse_json(raw)
    local messages={
      working="Work has started on your report.",
      review="A fix is ready for review.",
      merged="The fix was merged. It may still need a server update before you see it.",
      failed="The worker could not finish this attempt; your report is still saved.",
      needs_details="Your report needs more details or a developer's review.",
      closed="Your report was closed.",
    }
    if type(status)=="table" and type(status.events)=="table" then
      for _,event in ipairs(status.events) do
        local msg=messages[event.state]
        if msg then tell(event.state,msg..(event.url and " "..event.url or "")) end
      end
    end
    if r.seen.merged or r.seen.closed then r.complete=true end
    return changed
  end
  local api={}
  function api.track(id,title,recipient)
    pending[id]={title=title,recipient=recipient,seen={}}
    C.safe_file_write(dir.."/"..id..".recipient.json",C.write_json({title=title,recipient=recipient}))
    deliver(id,pending[id]); save()
  end
  function api.poll()
    local changed=false
    for _,folder in ipairs({dir,dir.."/sent"}) do
      for _,file in ipairs(C.get_dir_list(folder,false) or {}) do
        local id=file:match("^([%w%-]+)%.recipient%.json$")
        if id and not pending[id] then
          local raw=read(folder.."/"..file)
          local receipt=raw and C.parse_json(raw)
          if type(receipt)=="table" and type(receipt.recipient)=="table" and type(receipt.title)=="string" then
            pending[id]={title=receipt.title,recipient=receipt.recipient,seen={}}
            changed=true
          end
        end
      end
    end
    for id,r in pairs(pending) do
      if not r.complete and deliver(id,r) then changed=true end
    end
    if changed then save() end
  end
  local timer=0
  C.register_globalstep(function(dt)
    timer=timer+dt
    if timer<3 then return end
    timer=0; api.poll()
  end)
  return api
end
