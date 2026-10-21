local required={'qbx_core','oxmysql','ox_inventory','cookie_core','cookie_admin','cookie_garage','cookie_safezone'}
local function isAdmin(src)
 if src==0 then return true end
 if IsPlayerAceAllowed(src,'cookie.health') then return true end
 if GetResourceState('cookie_admin')=='started' then local ok,v=pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end); if ok and tonumber(v or 0)>=4 then return true end end
 return false
end
local function run(src)
 local okc,warn,fail=0,0,0; local lines={'[COOKIE HEALTH]'}
 for _,r in ipairs(required) do local st=GetResourceState(r); if st=='started' then okc=okc+1; lines[#lines+1]='✅ '..r else fail=fail+1; lines[#lines+1]='❌ '..r..' ('..st..')' end end
 local checks={{'player_vehicles','SELECT COUNT(*) FROM player_vehicles'},{'cookie_user','SELECT COUNT(*) FROM cookie_user'}}
 for _,c in ipairs(checks) do local ok=pcall(function() MySQL.scalar.await(c[2]) end); if ok then okc=okc+1; lines[#lines+1]='✅ DB '..c[1] else warn=warn+1; lines[#lines+1]='⚠ DB '..c[1] end end
 lines[#lines+1]=('결과: %d 정상 / %d 경고 / %d 오류'):format(okc,warn,fail)
 for _,l in ipairs(lines) do if src==0 then print(l) else TriggerClientEvent('chat:addMessage',src,{args={'COOKIE',l}}) end end
end
RegisterCommand('cookiehealth',function(src) if not isAdmin(src) then return end run(src) end,false)
CreateThread(function() Wait(5000); run(0) end)
