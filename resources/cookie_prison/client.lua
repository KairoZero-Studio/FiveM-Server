local carrying=false
local box=0
local dropIndex=1

local function notify(msg,bad)
    TriggerEvent('cookie_admin:client:notify',tostring(msg or ''),bad==true)
end

local function detained()
    return LocalPlayer.state.cookieDetained == true
end

local function loadModel(model)
    local h=joaat(model)
    RequestModel(h)
    local untilAt=GetGameTimer()+4000
    while not HasModelLoaded(h) and GetGameTimer()<untilAt do Wait(0) end
    return HasModelLoaded(h) and h or nil
end

local function cleanup()
    carrying=false
    ClearPedTasks(PlayerPedId())
    if box~=0 and DoesEntityExist(box) then DeleteEntity(box) end
    box=0
end

local function draw3d(p,text)
    local ok,x,y=World3dToScreen2d(p.x,p.y,p.z+0.55)
    if not ok then return end
    SetTextScale(.31,.31);SetTextFont(0);SetTextCentre(true);SetTextColour(255,255,255,230);SetTextOutline()
    BeginTextCommandDisplayText('STRING');AddTextComponentSubstringPlayerName(text);EndTextCommandDisplayText(x,y)
end

local function beginCarry(index)
    if carrying then return end
    local h=loadModel(Config.BoxModel or 'prop_cs_cardbox_01')
    if not h then return notify('박스 모델을 불러오지 못했습니다.',true) end
    local ped=PlayerPedId()
    RequestAnimDict('anim@heists@box_carry@')
    while not HasAnimDictLoaded('anim@heists@box_carry@') do Wait(0) end
    box=CreateObject(h,0,0,0,true,true,false)
    AttachEntityToEntity(box,ped,GetPedBoneIndex(ped,60309),0.025,0.08,0.255,-145.0,290.0,0.0,true,true,false,true,1,true)
    TaskPlayAnim(ped,'anim@heists@box_carry@','idle',8.0,-8.0,-1,49,0,false,false,false)
    carrying=true
    dropIndex=math.max(1,math.floor(tonumber(index) or 1))
    SetModelAsNoLongerNeeded(h)
    notify('박스를 지정된 적재 위치로 옮기세요.',false)
end

exports('useReleaseTicket',function(data)
    if GetResourceState('ox_inventory')~='started' then return notify('ox_inventory가 실행 중이 아닙니다.',true) end
    exports.ox_inventory:useItem(data,function(used)
        if not used then return end
        TriggerServerEvent('cookie_prison:server:useReleaseTicket')
    end)
end)

CreateThread(function()
    while true do
        if not detained() then
            if carrying then
                cleanup()
                TriggerServerEvent('cookie_prison:server:cancelWork')
            end
            Wait(700)
        else
            local ped=PlayerPedId()
            local pc=GetEntityCoords(ped)
            local sleep=500

            if not carrying then
                for _,p in ipairs(Config.PickupPoints or {}) do
                    local d=#(pc-p)
                    if d<14.0 then
                        sleep=0
                        DrawMarker(1,p.x,p.y,p.z-1.0,0,0,0,0,0,0,0.9,0.9,0.18,240,190,55,115,false,false,2,false)
                        if d<1.6 then
                            draw3d(p,'[E] 박스 운반 시작')
                            if IsControlJustReleased(0,38) then
                                local r=lib.callback.await('cookie_prison:startWork',false)
                                if r and r.ok then beginCarry(r.dropIndex)
                                else notify((r and r.message) or '노역을 시작할 수 없습니다.',true) end
                            end
                        end
                    end
                end
            else
                sleep=0
                if not IsEntityPlayingAnim(ped,'anim@heists@box_carry@','idle',3) then
                    TaskPlayAnim(ped,'anim@heists@box_carry@','idle',8.0,-8.0,-1,49,0,false,false,false)
                end
                local target=Config.DropPoints[dropIndex]
                if target then
                    local d=#(pc-target)
                    DrawMarker(1,target.x,target.y,target.z-1.0,0,0,0,0,0,0,1.0,1.0,0.2,90,220,120,130,false,false,2,false)
                    if d<1.8 then
                        draw3d(target,'[E] 박스 내려놓기')
                        if IsControlJustReleased(0,38) then
                            cleanup()
                            TriggerServerEvent('cookie_prison:server:completeWork',dropIndex)
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end
end)

AddEventHandler('onResourceStop',function(r) if r==GetCurrentResourceName() then cleanup() end end)
