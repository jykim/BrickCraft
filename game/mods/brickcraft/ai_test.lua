-- Opt-in check for jms, the AI builder (tools/test_ai_builder.py). Requests go through the
-- real chat handler and jms places the pieces on the real build loop.
local C=core
local ai=brickcraft.ai
local live=C.settings:get_bool("brickcraft_ai_llm",false)
local function chat(name,msg)
  for _,f in ipairs(C.registered_on_chat_messages) do if f(name,msg) then return end end
end
local function wait(cond,secs,label,next_step)
  local t=0
  local function poll()
    if cond() then return next_step() end
    t=t+.25
    assert(t<secs,"timed out: "..label)
    C.after(.25,poll)
  end
  poll()
end

C.register_on_joinplayer(function(player)
  C.after(2,function()
    local name=player:get_player_name()
    -- Every built-in blueprint makes a valid plan: known pieces, no overlaps, on the ground.
    local o={size=2,color="coral",accent="navy",text="HI LEONA"}
    for _,id in ipairs(ai.order) do
      for turns=0,3 do
        local list=ai.blueprint(id,o,turns)
        assert(#list>0,id.." is empty")
        local seen,miny={},99
        for _,it in ipairs(list) do
          assert(brickcraft.shapes[it.piece] and C.registered_nodes["brickcraft:"..it.color],id.." piece")
          for _,c in ipairs(ai.cells_of(it)) do
            local k=c.x..","..c.y..","..c.z
            assert(not seen[k],id.." overlaps at "..k); seen[k]=true
            assert(c.x>=0 and c.z>=0,id.." starts at 0"); miny=math.min(miny,c.y)
          end
        end
        assert(miny==0,id.." stands on the ground")
      end
    end
    -- Requests in plain words (and Korean) pick blueprints, colors and sizes.
    local id,r=ai.parse_request("build a big red house with a blue roof")
    assert(id=="house" and r.color=="coral" and r.accent=="sky" and r.size==3,"house request")
    id,r=ai.parse_request("빨간 탑 만들어줘")
    assert(id=="tower" and r.color=="coral","korean tower request")
    id,r=ai.parse_request("write LEONA in pink")
    assert(id=="word" and r.text=="LEONA" and r.color=="rose","word request "..tostring(r and r.text))
    assert(ai.parse_request("build a dragon")==nil,"unknown request")
    -- Claude-style plans: boxes, hollow walls, carved doors, long pieces, junk lines skipped.
    local plan=ai.parse_plan({"walls coral 0 0 0 4 2 3","clear 2 0 0 2 1 0","2x4 gold 0 3 0 1",
      "slope_2x2 navy 0 4 0 0","nonsense","2x2 plaid 1 1 1","box sky 9 9 9 99 99 99"},0)
    local n,long=0,false
    for _,it in ipairs(plan) do n=n+1; if it.piece=="2x4" then long=true end end
    assert(n==14*3-2+2 and long,"parsed plan has "..n.." pieces")
    -- A real request: jms builds a tower near the asker, through the chat handler. A wall
    -- 3 bricks high stands between his home and the asker, so he has to walk around it.
    for x=-15,15 do for y=0,2 do C.set_node({x=x,y=y,z=-1},{name="brickcraft:navy"}) end end
    player:set_pos({x=0,y=0,z=-12}); player:set_look_horizontal(0)
    local inv_ai=ai.inventory
    assert(inv_ai:get_stack("main",1):get_name()=="brickcraft:separator","jms has a player's inventory")
    local request=live and "jms, please build a small red lighthouse" or "jms, build a red tower"
    chat(name,request)
    wait(function() return ai.state().job~=nil end,live and 300 or 5,"jms starts building",function()
      local j=ai.state().job
      local o=j.origin
      C.log("action","BRICKCRAFT AI building "..j.title.." ("..#j.list.." pieces) at "..o.x..","..o.z)
      assert(ai.state().bot,"jms is in the world")
      assert(ai.state().bot:get_properties().nametag:find("jms"),"jms has a nametag")
      wait(function() return ai.state().job==nil end,300,"jms finishes",function()
        local last=ai.state().last
        local placed=#last.placed
        local st=ai.stats
        assert(placed>=#last.list*.9,"placed "..placed.." of "..#last.list)
        -- The rules: never inside a block, never beyond reach, scaffold dug back down.
        assert(st.inside==0,"jms walked through blocks "..st.inside.." times")
        assert(st.max_reach<=7.01,"reach "..st.max_reach)
        local o2=last.origin
        assert(#C.find_nodes_in_area(vector.offset(o2,-6,0,-6),vector.offset(o2,24,10,24),{"brickcraft:tan"})==0,
          "no scaffold left behind")
        for _,it in ipairs(last.placed) do
          assert(C.get_node(it.pos).name==it.name,"pieces are in the world")
        end
        -- Anyone can collect jms's bricks with the separator.
        local first=last.placed[1].pos
        local inv=player:get_inventory()
        C.registered_tools["brickcraft:separator"].on_use(inv:get_stack("main",1),player,
          {type="node",under=first,above=vector.offset(first,0,1,0)})
        assert(C.get_node(first).name=="air","a player collected one of jms's bricks")
        -- "Undo": jms collects the rest of his build back into his inventory.
        local function bricks(color)
          local n=0
          for _,stack in ipairs(inv_ai:get_list("main")) do
            if stack:get_name()=="brickcraft:"..color then n=n+stack:get_count() end
          end
          return n
        end
        local before=bricks("coral")
        chat(name,"jms, undo")
        local down
        wait(function()
          local jj=ai.state().job
          if jj and jj.kind=="collect" then down=true end
          return down and jj==nil
        end,300,"jms takes it down",function()
          assert(bricks("coral")>before,"collected bricks went back into his inventory")
          assert(ai.stats.inside==0,"no walking through blocks while taking down")
          for _,it in ipairs(last.placed) do
            assert(C.get_node(it.pos).name=="air","jms took the build down")
          end
          -- Left alone, jms builds something on its own away from the start spots.
          ai.set_idle(.5)
          wait(function() return ai.state().job~=nil end,10,"jms builds alone",function()
            local own=ai.state().job
            assert(own.by==nil,"own build")
            local ok,who=C.registered_chatcommands.who.func(name,"")
            assert(who:find("jms"),"/who lists jms")
            C.log("action","BRICKCRAFT AI PASS: "..#ai.order.." blueprints valid in 4 turns, requests parsed, "..
              (live and "Claude Code designed" or "built-in").." '"..j.title.."' ("..placed.." pieces) built, "..
              "collected, undone by his separator; walked "..
              "around a wall, reach "..string.format("%.1f",st.max_reach)..", "..st.scaffold.." scaffold blocks, "..
              st.skipped.." skipped; then on its own: "..own.title)
            C.request_shutdown("BrickCraft AI check passed",false,1)
          end)
        end)
      end)
    end)
  end)
end)
