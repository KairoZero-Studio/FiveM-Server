local blips={};local open=false;local cache={}
local function clear()for _,b in pairs(blips)do if DoesBlipExist(b)then RemoveBlip(b)end end;blips={}end
local function rebuild(rows)cache=type(rows)=='table'and rows or{};clear();for _,r in ipairs(cache)do if r.is_active==1 or r.is_active==true then local b=AddBlipForCoord((r.x or 0)+.0,(r.y or 0)+.0,(r.z or 0)+.0);SetBlipSprite(b,tonumber(r.sprite)or 280);SetBlipColour(b,tonumber(r.colour)or 3);SetBlipScale(b,(tonumber(r.scale)or .85)+.0);SetBlipAlpha(b,tonumber(r.alpha)or 255);SetBlipAsShortRange(b,r.short_range==1 or r.short_range==true);SetBlipDisplay(b,4);BeginTextCommandSetBlipName('STRING');AddTextComponentString(tostring(r.label or 'COOKIE'));EndTextCommandSetBlipName(b);blips[r.id]=b end end end
RegisterNetEvent('cookie_mapmarkers:client:set',function(rows)rebuild(rows);if open then SendNUIMessage({action='rows',rows=cache})end end)
local function showAdmin()
 if open then return end;local ok=lib.callback.await('cookie_mapmarkers:canAdmin',false);if not ok then return TriggerEvent('cookie_admin:client:notify','관리 업무 시작 후 사용할 수 있습니다.',true)end
 local d=lib.callback.await('cookie_mapmarkers:adminData',false);if not d or not d.ok then return end;open=true;SetNuiFocus(true,true);SendNUIMessage({action='open',rows=d.rows or{},presets=d.presets or{},ytdResource=d.ytdResource==true})
end
RegisterNetEvent('cookie_mapmarkers:client:openAdmin',showAdmin)
RegisterCommand(Config.AdminCommand or 'mapmarker',showAdmin,false)
RegisterNUICallback('close',function(_,cb)cb({ok=true});open=false;SetNuiFocus(false,false);SendNUIMessage({action='close'})end)
RegisterNUICallback('myPos',function(_,cb)local c=GetEntityCoords(PlayerPedId());cb({ok=true,x=c.x,y=c.y,z=c.z})end)
RegisterNUICallback('save',function(d,cb)cb({ok=true});TriggerServerEvent('cookie_mapmarkers:server:save',d)end)
RegisterNUICallback('delete',function(d,cb)cb({ok=true});TriggerServerEvent('cookie_mapmarkers:server:delete',d and d.id)end)
RegisterNUICallback('toggle',function(d,cb)cb({ok=true});TriggerServerEvent('cookie_mapmarkers:server:toggle',d and d.id,d and d.active==true)end)
CreateThread(function()Wait(1600);TriggerServerEvent('cookie_mapmarkers:server:request')end)
AddEventHandler('onClientResourceStop',function(r)if r==GetCurrentResourceName()then clear();SetNuiFocus(false,false)end end)
print('^2[cookie_mapmarkers]^7 native marker client ready · /mapmarker')
