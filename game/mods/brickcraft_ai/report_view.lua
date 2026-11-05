-- Small, report-time scene used only to render the attached image. No whole-save copy.
local C=core
return function(player,location,dir)
  local id=os.date("%Y%m%d-%H%M%S").."-"..math.random(1000,9999)
  local view={id=id,location=location,entities={},time_of_day=C.get_timeofday(),
    image_kind="reconstructed report-time scene; not a screenshot from the reporting device"}
  local p=vector.round(player:get_pos())
  view.minp=vector.subtract(p,16); view.maxp=vector.add(p,16)
  C.mkdir(dir)
  local ok,err=pcall(function()
    C.create_schematic(view.minp,view.maxp,nil,dir.."/"..id..".view.mts")
    local f=assert(io.open(dir.."/"..id..".view.mts","rb"))
    local size=f:seek("end"); f:close()
    assert(size<=262144,"scene exceeds 256 KiB limit")
    for _,obj in ipairs(C.get_objects_in_area(view.minp,view.maxp)) do
      if obj~=player and #view.entities<48 then
        local props=obj:get_properties()
        -- Engine visual properties only; no inventories, chat, AI memory or staticdata.
        local visual={}
        for _,k in ipairs({"visual","visual_size","mesh","textures","colors","glow",
          "use_texture_alpha","backface_culling","is_visible","spritediv","initial_sprite_basepos"}) do
          visual[k]=props[k]
        end
        if #C.write_json(visual)<4096 then
          view.entities[#view.entities+1]={pos=obj:get_pos(),rotation=not obj:is_player() and obj:get_rotation() or nil,properties=visual}
        end
      end
    end
    local eyes=player:get_eye_offset()
    view.eye_offset=eyes
    view.eye_height=player:get_properties().eye_height
    assert(C.safe_file_write(dir.."/"..id..".view.json",C.write_json(view)),"cannot save view context")
  end)
  if not ok then
    view.error=tostring(err)
    C.safe_file_write(dir.."/"..id..".view.json",C.write_json(view))
    C.log("warning","Report view capture failed: "..view.error)
  end
  return view
end
