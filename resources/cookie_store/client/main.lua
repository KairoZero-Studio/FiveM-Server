local open=false
local function display(data)
    open=true
    SetNuiFocus(true,true)
    SendNUIMessage({type='open',data=data})
end
RegisterNetEvent('cookie_store:client:open',display)
RegisterNetEvent('cookie_store:client:notify',function(msg,bad)
    lib.notify({title='COOKIE STORE',description=msg,type=bad and 'error' or 'success'})
end)
RegisterNUICallback('close',function(_,cb) open=false;SetNuiFocus(false,false);SendNUIMessage({type='close'});cb({ok=true}) end)
RegisterNUICallback('openWeb',function(_,cb) SetNuiFocus(false,false);open=false;SendNUIMessage({type='close'}); TriggerEvent('chat:addMessage',{args={'COOKIE','Tebex 상점: https://cookie-server.tebex.store'}}); cb({ok=true}) end)
RegisterNUICallback('buy',function(d,cb) TriggerServerEvent('cookie_store:server:buy',d.id,d.method);cb({ok=true}) end)
RegisterNUICallback('redeem',function(d,cb) TriggerServerEvent('cookie_store:server:redeem',d.code);cb({ok=true}) end)
RegisterNUICallback('save',function(d,cb) TriggerServerEvent('cookie_store:server:adminSave',d);cb({ok=true}) end)
RegisterNUICallback('points',function(d,cb) TriggerServerEvent('cookie_store:server:adminPoints',d.target,d.delta);cb({ok=true}) end)
RegisterCommand('cookie_store_close',function() if open then open=false;SetNuiFocus(false,false);SendNUIMessage({type='close'}) end end)
RegisterKeyMapping('cookie_store_close','쿠키 상점 닫기','keyboard','ESCAPE')
-- F3 integration through optional patch; also accessible by /쿠키상점관리.
RegisterNetEvent('cookie_store:client:launchAdmin',function() TriggerServerEvent('cookie_store:server:open',true) end)
