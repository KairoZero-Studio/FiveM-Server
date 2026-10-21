

local TICK_IN  = 60
local TICK_OUT = 400

local shown = false
local hudHidden = false
local last = { speed = -1, fuel = -1, belt = nil, gear = -1, engine = -1, rpm = -1 }

local function getFuel(veh)
    local st = Entity(veh).state.fuel
    if type(st) == 'number' then return st end
    return GetVehicleFuelLevel(veh) or 0.0
end

local function getBelt()
    return LocalPlayer.state.seatbelt == true
end

local function hide()
    if not shown then return end
    shown = false
    last.speed, last.fuel, last.gear, last.engine, last.belt, last.rpm = -1, -1, -1, -1, nil, -1
    SendNUIMessage({ action = 'vehHide' })
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if hudHidden then
            Wait(300)
        elseif veh ~= 0 and DoesEntityExist(veh) then
            local speed  = math.floor(GetEntitySpeed(veh) * 3.6 + 0.5)
            local fuel   = math.floor(getFuel(veh) + 0.5)
            local belt   = getBelt()
            local gear   = GetVehicleCurrentGear(veh)
            local engine = math.floor((GetVehicleEngineHealth(veh) / 1000.0) * 100.0)
            if engine < 0 then engine = 0 elseif engine > 100 then engine = 100 end

            local rpm = math.floor((GetVehicleCurrentRpm(veh) or 0.0) * 100.0 + 0.5)
            if rpm < 0 then rpm = 0 elseif rpm > 100 then rpm = 100 end

            if not shown then
                shown = true
                SendNUIMessage({ action = 'vehShow' })
            end

            if speed ~= last.speed or fuel ~= last.fuel or belt ~= last.belt
                or gear ~= last.gear or engine ~= last.engine or rpm ~= last.rpm then
                SendNUIMessage({
                    action = 'vehUpdate',
                    speed  = speed,
                    fuel   = fuel,
                    belt   = belt,
                    gear   = gear,
                    engine = engine,
                    rpm    = rpm,
                })
                last.speed, last.fuel, last.belt, last.gear, last.engine, last.rpm =
                    speed, fuel, belt, gear, engine, rpm
            end

            Wait(TICK_IN)
        else
            hide()
            Wait(TICK_OUT)
        end
    end
end)

AddEventHandler('cookie_hud:client:hudVisible', function(visible)
    hudHidden = not visible
    SendNUIMessage({ action = 'hudVisible', visible = visible and true or false })
    if hudHidden then
        hide()
        last.speed = -1
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    hide()
end)
