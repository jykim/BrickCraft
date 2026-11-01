-- Opt-in check for the AI builders (tools/test_ai_builder.py): jms, switched on for the test,
-- and Leona's own builder. Requests go through the real chat handler and builders place the
-- pieces on the real build loop.
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
    local jms=ai.get("jms")
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
    -- "next to Leona", "for Dad", "레오나 옆에" name who a build goes by and drop out of the request.
    local fake={{name="MPDad",id="dad",label="Dad"},{name="Kid1",id="daughter",label="Leona"}}
    local by,rest=ai.near_phrase("build a red tower next to Leona",fake)
    assert(by and by.label=="Leona" and rest=="build a red tower","near phrase: "..tostring(rest))
    by,rest=ai.near_phrase("write HI for daddy",fake)
    assert(by and by.label=="Dad" and rest=="write HI","nickname phrase: "..tostring(rest))
    by,rest=ai.near_phrase("레오나 옆에 빨간 탑 만들어줘",fake)
    assert(by and by.label=="Leona" and ai.parse_request(rest)=="tower","korean near phrase")
    assert(ai.near_phrase("build a red tower",fake)==nil,"no player named")
    -- Who's around: a connection that hasn't picked anyone isn't listed; once it plays Leona it is.
    assert(#ai.players()==0,"nobody picked yet")
    for _,handler in ipairs(C.registered_on_player_receive_fields) do
      if handler(player,"brickcraft:style",{style_daughter="x"}) then break end
    end
    assert(brickcraft.playing_as(player)=="daughter","playing Leona")
    local said={}
    local send=C.chat_send_all
    C.chat_send_all=function(msg) said[#said+1]=C.strip_colors(msg); return send(msg) end
    local function heard(pattern) for _,m in ipairs(said) do if m:find(pattern) then return m end end end
    local function players_part(done)
      local bp=jms.state().bot:get_pos()
      player:set_pos({x=bp.x,y=bp.y,z=bp.z+10}); player:set_look_horizontal(math.pi)
      local list=ai.players(bp)
      assert(#list==1 and list[1].label=="Leona" and list[1].name==name,"players list has Leona only")
      assert(math.abs(list[1].dist-10)<1.5 and list[1].dir=="north" and list[1].facing=="south",
        "Leona's distance and direction: "..list[1].dist.." "..list[1].dir.." facing "..list[1].facing)
      -- Bricks never go into a player's space: feet and head cells, and the cell beside a body.
      local pp=player:get_pos()
      local f={x=math.floor(pp.x+.5),y=math.floor(pp.y+.51),z=math.floor(pp.z+.5)}
      assert(ai.player_in(f) and ai.player_in(vector.offset(f,0,1,0)),"player's own cells")
      assert(not ai.player_in(vector.offset(f,0,2,0)) and not ai.player_in(vector.offset(f,2,0,0)),"cells clear of the player")
      ai.set_small_talk(false)
      chat(name,"jms, where is Leona?")
      wait(function() return heard("Leona is") or heard("You're") end,5,"jms says where Leona is",function()
        local m=heard("You're")
        assert(m and m:find("10 blocks north of me") and m:find("facing south"),"where: "..tostring(m))
        chat(name,"jms, who's here?")
        wait(function() return heard("just you and me") end,5,"jms says who's here",function()
          -- Leona walks over: jms says hi to her by name.
          ai.set_small_talk(true,1)
          player:set_pos({x=bp.x+2,y=bp.y,z=bp.z})
          local hi="<jms> [OoHh][hie,y ]+Leona!"
          wait(function() return heard(hi) end,30,"jms says hi",function()
            C.log("action","BRICKCRAFT AI small talk: "..heard(hi))
            ai.set_small_talk(false)
            done()
          end)
        end)
      end)
    end
    -- Maintenance: jms inspects what's there. A wall with a missing brick and a hole in the
    -- floor mosaic in front of Leona; "fill the holes here" patches both, in matching colors.
    local function maintenance_part(done)
      assert(ai.is_edit("fill the holes here") and ai.is_edit("please fix the roof") and ai.is_edit("레오나 집 고쳐줘"),"edit requests")
      assert(not ai.is_edit("build a red house") and not ai.is_edit("write HI"),"build requests aren't edits")
      for x=-10,-8 do for y=0,1 do C.set_node({x=x,y=y,z=-10},{name="brickcraft:coral"}) end end
      C.set_node({x=-9,y=0,z=-10},{name="air"})
      C.set_node({x=0,y=-1,z=-6},{name="air"})
      player:set_pos({x=-4,y=0,z=-15}); player:set_look_horizontal(0)
      local o={x=-12,y=0,z=-19} -- the 16 x 16 area in front of her
      local found={}
      for _,h in ipairs(ai.survey({x=o.x,y=-1,z=o.z},{x=o.x+15,y=8,z=o.z+15},true)) do found[h.x..","..h.y..","..h.z]=true end
      assert(found["-9,0,-10"] and found["0,-1,-6"],"survey finds the wall gap and the floor hole")
      -- Claude-style changes: replace a brick (collect it, put a gold one there); removing
      -- the baseplate or adding a floating piece is ignored.
      local list,down=ai.edit_jobs({lines={"2x2 gold 2 1 9","2x2 gold 9 6 9"},remove={"2 1 9","4 -1 4"}},o,"fix",name)
      assert(#list==1 and list[1].color=="gold" and down and #down.list==1 and
        vector.equals(down.list[1].pos,{x=-10,y=1,z=-10}),"edit jobs: "..#list.." to add")
      chat(name,"jms, fill the holes here")
      wait(function() local jj=jms.state().job; return jj and jj.title=="patch" end,5,"jms starts patching",function()
        wait(function() return jms.state().job==nil end,120,"jms patches",function()
          assert(C.get_node({x=-9,y=0,z=-10}).name=="brickcraft:coral","wall gap filled in coral")
          assert(C.get_node({x=0,y=-1,z=-6}).name~="air","floor hole filled")
          assert(heard("Filling 2 holes"),"jms says what he fills")
          -- A Claude-style answer to "make the top of the wall gold": he collects the old
          -- coral bricks with his separator, then puts gold ones in their place.
          jms.apply_edit({say="Gold it is!",title="gold wall top",lines={"2x2 gold 2 1 9","2x2 gold 3 1 9","2x2 gold 4 1 9"},
            remove={"2 1 9","3 1 9","4 1 9"}},o,name)
          assert(jms.state().job.kind=="collect","old pieces come out first")
          wait(function() return jms.state().job==nil end,120,"jms makes the wall top gold",function()
            for x=-10,-8 do
              assert(C.get_node({x=x,y=1,z=-10}).name=="brickcraft:gold","wall top is gold at "..x)
              assert(C.get_node({x=x,y=0,z=-10}).name=="brickcraft:coral","bottom row kept")
            end
            assert(jms.stats.inside==0,"no walking through blocks while fixing")
            done()
          end)
        end)
      end)
    end
    maintenance_part(function()
    players_part(function()
    -- A real request: jms builds a tower near the asker, through the chat handler. A wall
    -- 3 bricks high stands between his home and the asker, so he has to walk around it.
    for x=-15,15 do for y=0,2 do C.set_node({x=x,y=y,z=-1},{name="brickcraft:navy"}) end end
    player:set_pos({x=0,y=0,z=-12}); player:set_look_horizontal(0)
    local inv_ai=jms.inventory
    assert(inv_ai:get_stack("main",1):get_name()=="brickcraft:separator","jms has a player's inventory")
    local request=live and "jms, please build a small red lighthouse" or "jms, build a red tower next to Leona"
    chat(name,request)
    wait(function() return jms.state().job~=nil end,live and 300 or 5,"jms starts building",function()
      local j=jms.state().job
      local o=j.origin
      assert(live or j.title=="coral tower","the request without \"next to Leona\": "..j.title)
      C.log("action","BRICKCRAFT AI building "..j.title.." ("..#j.list.." pieces) at "..o.x..","..o.z)
      assert(jms.state().bot,"jms is in the world")
      assert(jms.state().bot:get_properties().nametag:find("jms"),"jms has a nametag")
      wait(function() return jms.state().job==nil end,300,"jms finishes",function()
        local last=jms.state().last
        local placed=#last.placed
        local st=jms.stats
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
          local jj=jms.state().job
          if jj and jj.kind=="collect" then down=true end
          return down and jj==nil
        end,300,"jms takes it down",function()
          assert(bricks("coral")>before,"collected bricks went back into his inventory")
          assert(jms.stats.inside==0,"no walking through blocks while taking down")
          for _,it in ipairs(last.placed) do
            assert(C.get_node(it.pos).name=="air","jms took the build down")
          end
          -- Left alone, jms first looks after the ground: he fills an old hole but leaves the
          -- one Leona just dug, then builds something on its own away from the start spots.
          C.set_node({x=2,y=-1,z=-6},{name="air"})
          local fresh={x=3,y=-1,z=-5}
          C.registered_tools["brickcraft:separator"].on_use(inv:get_stack("main",1),player,
            {type="node",under=fresh,above=vector.offset(fresh,0,1,0)})
          assert(C.get_node(fresh).name=="air","Leona dug a floor brick")
          ai.set_idle(.5)
          wait(function() return C.get_node({x=2,y=-1,z=-6}).name~="air" end,120,"jms looks after the ground",function()
          assert(heard("filling a hole in the ground"),"one hole: the old one")
          wait(function() local jj=jms.state().job; return jj and not jj.patch end,20,"jms builds alone",function()
          assert(C.get_node(fresh).name=="air","a fresh dig is left alone")
            local own=jms.state().job
            assert(own.by==nil,"own build")
            local ok,who=C.registered_chatcommands.who.func(name,"")
            assert(who:find("jms"),"/who lists jms")
            -- Leona's own builder: out since she picked Leona, named by her, and only she
            -- can stop it. "bot, ..." goes to it, and its plot never overlaps jms's build.
            local mine=ai.get("daughter")
            assert(mine.name=="Leona bot" and mine.state().bot,"Leona's builder is out as Leona bot")
            assert(who:find("Leona bot"),"/who lists Leona's builder")
            assert(ai.name_problem("Dad","daughter") and ai.name_problem("jms","daughter") and
              ai.name_problem("bot","daughter") and ai.name_problem("Lu:mi","daughter"),"names that are taken or odd")
            assert(not ai.name_problem("Lumi","daughter") and not ai.name_problem("루미","daughter"),"good names")
            local renamed,msg=C.registered_chatcommands.botname.func(name,"Lumi")
            assert(renamed and mine.name=="Lumi","/botname: "..tostring(msg))
            assert(mine.state().bot:get_properties().nametag=="Lumi (AI)","nametag follows the name")
            mine.handle("Visitor","stop")
            assert(heard("<Lumi> Only Leona can stop me"),"only the owner stops it")
            -- Who a chat line is for: a name at the start or the end; alone in a world,
            -- everything goes to her own builder, which answers questions in words.
            assert(ai.addressed(name,"make it bigger")==jms,"a follow-up goes to the builder she's talking with")
            ai.talking[name]=nil
            local r1,t1,h1=ai.addressed(name,"build a gold tower")
            assert(r1==mine and t1=="build a gold tower" and h1=="unnamed","alone, a request needs no name")
            local r2,t2,h2=ai.addressed(name,"are you there, Lumi?")
            assert(r2==mine and t2=="are you there" and h2=="named","name at the end: "..tostring(t2))
            assert(ai.addressed(name,"what doesn't look like a building")==mine,"alone, plain chat is for her builder")
            assert(ai.addressed(name,"jms, build a tree")==jms,"a named builder wins")
            assert(ai.addressed(name,"I like jms's flower")==nil,"naming another builder isn't talking to hers")
            mine.handle(name,"what doesn't look like a building","unnamed")
            assert(heard("<Lumi> I'm not sure, Leona") or heard("<Lumi> Hmm, I don't know, Leona"),
              "without its designer, a question gets a plain answer")
            assert(ai.is_edit("can we clean up all mess?"),"\"can we ...\" asks for work")
            assert(C.strip_colors(C.format_chat_message(name,"hi")):find("<Leona> hi",1,true),"chat shows who's playing")
            chat(name,"bot, build a gold tower")
            wait(function() return mine.state().job~=nil end,live and 300 or 5,"Lumi starts building",function()
              local mj=mine.state().job
              assert(live or mj.title=="gold tower","Lumi builds the request: "..mj.title)
              local function rect(jj) return jj.origin,vector.add(jj.origin,jj.size or {x=0,y=0,z=0}) end
              local a1,a2=rect(mj)
              local b1,b2=rect(own)
              assert(a2.x<b1.x or b2.x<a1.x or a2.z<b1.z or b2.z<a1.z,"Lumi's plot and jms's plot don't overlap")
              wait(function() return mine.state().job==nil end,300,"Lumi finishes",function()
                local ml=mine.state().last
                assert(#ml.placed>=#ml.list*.9,"Lumi placed "..#ml.placed.." of "..#ml.list)
                assert(mine.stats.inside==0 and mine.stats.max_reach<=7.01,"Lumi plays by the rules")
                assert(heard("<Lumi> Done! Here's your"),"Lumi says it's done")
                C.log("action","BRICKCRAFT AI PASS: "..#ai.order.." blueprints valid in 4 turns, requests parsed, "..
                  (live and "Claude Code designed" or "built-in").." '"..j.title.."' ("..placed.." pieces) built, "..
                  "collected, undone by his separator; walked "..
                  "around a wall, reach "..string.format("%.1f",st.max_reach)..", "..st.scaffold.." scaffold blocks, "..
                  st.skipped.." skipped; then on its own: ground patch, "..own.title.."; knows where Leona is and says hi; "..
                  "fills holes and gaps on request; Leona's builder renamed Lumi, built '"..mj.title.."' ("..#ml.placed..
                  " pieces) next to jms's build")
                C.request_shutdown("BrickCraft AI check passed",false,1)
              end)
            end)
          end)
          end)
        end)
      end)
    end)
    end)
    end)
  end)
end)
