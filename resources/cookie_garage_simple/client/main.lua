local processing=false
local showing=false

local function toast(message,kind)
    lib.notify({title='🍪 COOKIE GARAGE',description=message,type=kind or 'inform',position='bottom-right'})
end
local function nearestGarage()
    local here=GetEntityCoords(PlayerPedId())
    local best,distance
    for key,cfg in pairs(Config.Garages) do
        local d=#(here-cfg.coords)
        if not distance or d<distance then best,distance=key,d end
    end
    return best,distance
end
local function nearbyVehicle()
    local ped=PlayerPedId()
    if IsPedInAnyVehicle(ped,false) then return GetVehiclePedIsIn(ped,false) end
    local coords=GetEntityCoords(ped)
    local entity,dist
    for _,veh in ipairs(GetGamePool('CVehicle')) do
        local d=#(GetEntityCoords(veh)-coords)
        if d<=7 and (not dist or d<dist) then entity,dist=veh,d end
    end
    return entity
end

local function spawnVehicle(key,id)
    if processing then return end
    processing=true
    local result=lib.callback.await('cookie_garage_simple:spawn',false,key,id)
    processing=false
    if not result or not result.ok then return toast(result and result.reason or '출고 응답이 없습니다.','error') end
    local deadline=GetGameTimer()+6000
    local vehicle
    repeat
        vehicle=NetToVeh(result.netId)
        if vehicle~=0 and DoesEntityExist(vehicle) then break end
        Wait(150)
    until GetGameTimer()>deadline
    if vehicle and vehicle~=0 and DoesEntityExist(vehicle) then
        local ped=PlayerPedId()
        if GetPedInVehicleSeat(vehicle,-1)~=ped then TaskWarpPedIntoVehicle(ped,vehicle,-1) end
        SetVehicleNeedsToBeHotwired(vehicle,false)
        SetVehicleHasBeenOwnedByPlayer(vehicle,true)
        SetVehicleIsStolen(vehicle,false)
        toast(result.recovered and '분실 출고 기록을 복구하여 차량을 생성했습니다.' or '차량 출고 완료!','success')
    else
        toast('차량은 서버에서 생성됐지만 화면에 표시되지 않았습니다. 잠시 기다린 뒤 중복 출고하지 마세요.','warning')
    end
end
local function storeVehicle(key)
    if processing then return end
    local veh=nearbyVehicle()
    if not veh then return toast('근처에 입고할 차량이 없습니다.','error') end
    local netId=VehToNet(veh)
    if not netId or netId==0 then return toast('차량 네트워크 정보가 없습니다.','error') end
    processing=true
    local props=lib.getVehicleProperties(veh)
    local result=lib.callback.await('cookie_garage_simple:store',false,key,netId,props)
    processing=false
    toast(result and (result.ok and '차고 입고 완료!' or result.reason) or '입고 서버 응답이 없습니다.',result and result.ok and 'success' or 'error')
end
local function openGarage(key)
    if processing then return end
    local cfg=Config.Garages[key]
    if not cfg then return end
    local data=lib.callback.await('cookie_garage_simple:list',false,key)
    if not data or not data.ok then return toast(data and data.reason or '차량 정보를 읽지 못했습니다.','error') end
    local options={{
        title='내 차량 입고',
        description='타고 있거나 근처에 세운 내 차량을 차고로 넣습니다.',
        icon='warehouse',onSelect=function() storeVehicle(key) end
    }}
    for _,car in ipairs(data.vehicles or {}) do
        local label,disabled
        if car.state==2 then label='압류 상태';disabled=true
        elseif car.exists then label='이미 월드에 있음';disabled=true
        elseif car.state==0 then label='출고 기록은 있으나 실제 차량 없음 → 복구 출고'
        else label='보관 중 → 바로 출고' end
        local id=car.id
        options[#options+1]={
            title=car.model..'  |  '..car.plate,
            description=label,
            icon=disabled and 'car-side' or 'car',
            disabled=disabled==true,
            onSelect=function() spawnVehicle(key,id) end
        }
    end
    if #options==1 then options[#options+1]={title='소유 차량이 없습니다.',disabled=true} end
    lib.registerContext({id='cookie_garage_simple_'..key,title='🍪 '..cfg.label,options=options})
    lib.showContext('cookie_garage_simple_'..key)
end

RegisterCommand('cookie_simple_garage',function()
    local key,d=nearestGarage()
    if key and d<=Config.OpenDistance then openGarage(key)
    else toast('차고 마커 근처에서 이용해 주세요.','error') end
end,false)
RegisterCommand('차고',function() ExecuteCommand('cookie_simple_garage') end,false)
exports('OpenGarage',openGarage)

CreateThread(function()
    for _,cfg in pairs(Config.Garages) do
        if cfg.blip then
            local b=AddBlipForCoord(cfg.coords.x,cfg.coords.y,cfg.coords.z)
            SetBlipSprite(b,357)
            SetBlipColour(b,47)
            SetBlipScale(b,0.65)
            SetBlipAsShortRange(b,true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(cfg.label)
            EndTextCommandSetBlipName(b)
        end
    end
    while true do
        local key,d=nearestGarage()
        if key and d<18 then
            Wait(0)
            local cfg=Config.Garages[key]
            DrawMarker(1,cfg.coords.x,cfg.coords.y,cfg.coords.z-1.0,
                0.,0.,0.,0.,0.,0., 1.3,1.3,0.28,255,191,80,120,false,true,2,false,nil,nil,false)
            if d<=Config.OpenDistance then
                if not showing then
                    lib.showTextUI('[E]  🍪 '..cfg.label,{position='left-center',icon='warehouse'})
                    showing=true
                end
                if IsControlJustReleased(0,38) and not IsPauseMenuActive() then openGarage(key) end
            elseif showing then lib.hideTextUI();showing=false end
        else
            Wait(700)
            if showing then lib.hideTextUI();showing=false end
        end
    end
end)
AddEventHandler('onResourceStop',function(resource)
    if resource==GetCurrentResourceName() and showing then lib.hideTextUI() end
end)
