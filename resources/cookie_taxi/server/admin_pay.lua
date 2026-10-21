local T = Config.Taxi

local DEFAULT = {
    base_fare = tonumber(T.BaseFare) or 5500,
    free_dist = tonumber(T.FreeDist) or 1000,
    step_dist = tonumber(T.StepDist) or 500,
    step_fare = tonumber(T.StepFare) or 200,
    intercity_fee = tonumber(T.IntercityFee) or 2000,
    max_fare = tonumber(T.MaxFare) or 200000,
}

local function isAdmin(src)
    local ok, lv = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    return ok and (tonumber(lv) or 0) >= 3
end

local function notify(src,msg,err)
    TriggerClientEvent('cookie_admin:client:notify',src,msg,err==true)
end

local function apply(r)
    if not r then return end
    T.BaseFare = tonumber(r.base_fare) or DEFAULT.base_fare
    T.FreeDist = tonumber(r.free_dist) or DEFAULT.free_dist
    T.StepDist = tonumber(r.step_dist) or DEFAULT.step_dist
    T.StepFare = tonumber(r.step_fare) or DEFAULT.step_fare
    T.IntercityFee = tonumber(r.intercity_fee) or DEFAULT.intercity_fee
    T.MaxFare = tonumber(r.max_fare) or DEFAULT.max_fare
end

local function row()
    return MySQL.single.await('SELECT base_fare,free_dist,step_dist,step_fare,intercity_fee,max_fare FROM cookie_taxi_paycfg WHERE id=1') or DEFAULT
end

local function syncClients(target)
    local p = row()
    apply(p)
    TriggerClientEvent('cookie_taxi:client:pricing',target or -1,p)
    return p
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_taxi_paycfg (
            id TINYINT NOT NULL PRIMARY KEY DEFAULT 1,
            base_fare INT NOT NULL DEFAULT 5500,
            free_dist DOUBLE NOT NULL DEFAULT 1000,
            step_dist DOUBLE NOT NULL DEFAULT 500,
            step_fare INT NOT NULL DEFAULT 200,
            intercity_fee INT NOT NULL DEFAULT 2000,
            max_fare INT NOT NULL DEFAULT 200000,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.insert.await([[
        INSERT IGNORE INTO cookie_taxi_paycfg(id,base_fare,free_dist,step_dist,step_fare,intercity_fee,max_fare)
        VALUES(1,?,?,?,?,?,?)
    ]],{DEFAULT.base_fare,DEFAULT.free_dist,DEFAULT.step_dist,DEFAULT.step_fare,DEFAULT.intercity_fee,DEFAULT.max_fare})
    syncClients(-1)
end)

RegisterNetEvent('cookie_taxi:server:adminPayGet',function()
    local src=source
    if not isAdmin(src) then return end
    TriggerClientEvent('cookie_taxi:client:adminPay',src,row())
end)

RegisterNetEvent('cookie_taxi:server:adminPaySave',function(d)
    local src=source
    if not isAdmin(src) or type(d)~='table' then return end
    local v={
        math.max(0,math.floor(tonumber(d.baseFare) or DEFAULT.base_fare)),
        math.max(0,tonumber(d.freeDist) or DEFAULT.free_dist),
        math.max(1,tonumber(d.stepDist) or DEFAULT.step_dist),
        math.max(0,math.floor(tonumber(d.stepFare) or DEFAULT.step_fare)),
        math.max(0,math.floor(tonumber(d.intercityFee) or DEFAULT.intercity_fee)),
        math.max(0,math.floor(tonumber(d.maxFare) or DEFAULT.max_fare)),
    }
    MySQL.update.await([[UPDATE cookie_taxi_paycfg SET base_fare=?,free_dist=?,step_dist=?,step_fare=?,intercity_fee=?,max_fare=? WHERE id=1]],v)
    syncClients(-1)
    notify(src,'택시 요금 설정을 저장했습니다.',false)
    TriggerClientEvent('cookie_taxi:client:adminPay',src,row())
end)

AddEventHandler('playerJoining',function()
    local src=source
    SetTimeout(1500,function() if GetPlayerPing(src)>0 then syncClients(src) end end)
end)

exports('getPricing',function() return row() end)
