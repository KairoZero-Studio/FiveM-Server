local sessions = {}
local openTokens = {}
local cachedLocations = {}
local cachedRecipes = {}

local function getPlayer(src)
    if not src or src <= 0 then return nil end
    return exports.qbx_core:GetPlayer(src)
end

local function citizenId(src)
    local p = getPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function getFaction(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil end
    local ok, data = pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    return ok and data or nil
end

local function isCrime(src)
    local f = getFaction(src)
    if not f then return false, nil end
    local t = tostring(f.type or f.faction_type or ''):lower()
    return t == 'crime', f
end

local function isAdmin(src)
    if src == 0 then return true end
    if Config.AdminAce and IsPlayerAceAllowed(src, Config.AdminAce) then return true end
    if IsPlayerAceAllowed(src, 'command') then return true end
    if GetResourceState('cookie_admin') == 'started' then
        local ok, level = pcall(function() return exports.cookie_admin:GetAdminLevel(src) end)
        if ok and tonumber(level or 0) >= (Config.AdminMinLevel or 3) then return true end
        local ok2, level2 = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
        if ok2 and tonumber(level2 or 0) >= (Config.AdminMinLevel or 3) then return true end
    end
    return false
end

local function clampInt(v, minv, maxv)
    v = math.floor(tonumber(v) or 0)
    if v < minv then v = minv end
    if maxv and v > maxv then v = maxv end
    return v
end

local function clean(v, max)
    v = tostring(v or ''):gsub('[%c\r\n]', ' '):gsub('%s+', ' ')
    if max and #v > max then v = v:sub(1, max) end
    return v
end

local function ensureSchema()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_drugcraft_locations (
        id INT NOT NULL AUTO_INCREMENT,label VARCHAR(100) NOT NULL DEFAULT '조직 제조',
        x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,radius DOUBLE NOT NULL DEFAULT 3.0,
        enabled TINYINT(1) NOT NULL DEFAULT 1,created_by VARCHAR(80) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_drugcraft_recipes (
        code VARCHAR(32) NOT NULL,label VARCHAR(80) NOT NULL,raw_item VARCHAR(80) NOT NULL,
        output_item VARCHAR(80) NOT NULL,raw_per_batch INT NOT NULL DEFAULT 5,
        output_per_batch INT NOT NULL DEFAULT 1,base_seconds INT NOT NULL DEFAULT 15,
        boost_seconds INT NOT NULL DEFAULT 5,minigame VARCHAR(32) NOT NULL,
        enabled TINYINT(1) NOT NULL DEFAULT 1,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (code)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_drugcraft_refunds (
        citizenid VARCHAR(64) NOT NULL,item VARCHAR(80) NOT NULL,amount INT NOT NULL DEFAULT 0,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (citizenid,item)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_drugcraft_reservations (
        citizenid VARCHAR(64) NOT NULL,recipe_code VARCHAR(32) NOT NULL,
        raw_item VARCHAR(80) NOT NULL,remaining_raw INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY (citizenid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_drugcraft_history (
        id BIGINT NOT NULL AUTO_INCREMENT,citizenid VARCHAR(64) NOT NULL,faction_id INT NULL,
        recipe_code VARCHAR(32) NOT NULL,reserved_raw INT NOT NULL DEFAULT 0,
        produced INT NOT NULL DEFAULT 0,boosted TINYINT(1) NOT NULL DEFAULT 0,
        status VARCHAR(32) NOT NULL DEFAULT 'running',
        started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,ended_at TIMESTAMP NULL DEFAULT NULL,
        PRIMARY KEY (id),KEY idx_drugcraft_citizen (citizenid),KEY idx_drugcraft_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end

local function seedRecipes()
    for code, r in pairs(Config.Recipes or {}) do
        MySQL.query.await([[INSERT IGNORE INTO cookie_drugcraft_recipes
            (code,label,raw_item,output_item,raw_per_batch,output_per_batch,base_seconds,boost_seconds,minigame,enabled)
            VALUES (?,?,?,?,?,?,?,?,?,1)]],
            {code,r.label,r.rawItem,r.outputItem,r.rawPerBatch or 5,r.outputPerBatch or 1,
             Config.OrganizationBaseSeconds or 15,Config.OrganizationBoostSeconds or 5,r.minigame or code})
    end
end

local function recoverStaleReservations()
    local rows = MySQL.query.await('SELECT citizenid,raw_item,remaining_raw FROM cookie_drugcraft_reservations WHERE remaining_raw>0', {}) or {}
    for _, row in ipairs(rows) do
        MySQL.query.await([[INSERT INTO cookie_drugcraft_refunds (citizenid,item,amount)
            VALUES (?,?,?) ON DUPLICATE KEY UPDATE amount=amount+VALUES(amount)]],
            {row.citizenid,row.raw_item,tonumber(row.remaining_raw) or 0})
    end
    MySQL.query.await('DELETE FROM cookie_drugcraft_reservations', {})
    MySQL.update.await("UPDATE cookie_drugcraft_history SET status='restart_refund',ended_at=NOW() WHERE status='running'", {})
end

local function refreshCache(push)
    cachedLocations = MySQL.query.await('SELECT id,label,x,y,z,radius,enabled FROM cookie_drugcraft_locations ORDER BY id ASC', {}) or {}
    cachedRecipes = MySQL.query.await([[SELECT code,label,raw_item,output_item,raw_per_batch,output_per_batch,
        base_seconds,boost_seconds,minigame,enabled FROM cookie_drugcraft_recipes ORDER BY code ASC]], {}) or {}
    if push then TriggerClientEvent('cookie_drugcraft:client:locations', -1, cachedLocations) end
end

local function findLocation(id)
    id = tonumber(id)
    for _, loc in ipairs(cachedLocations) do if tonumber(loc.id) == id then return loc end end
end

local function findRecipe(code)
    code = tostring(code or '')
    for _, r in ipairs(cachedRecipes) do if tostring(r.code) == code then return r end end
end

local function nearLocation(src, loc, extra)
    if not loc then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local c = GetEntityCoords(ped)
    local max = (tonumber(loc.radius) or 3.0) + (extra or 0.0)
    return #(c - vector3(loc.x+0.0,loc.y+0.0,loc.z+0.0)) <= max
end

local function addRefund(cid,item,amount)
    amount=clampInt(amount,0)
    if not cid or amount<=0 then return end
    MySQL.query.await([[INSERT INTO cookie_drugcraft_refunds (citizenid,item,amount)
        VALUES (?,?,?) ON DUPLICATE KEY UPDATE amount=amount+VALUES(amount)]],{cid,item,amount})
end

local function giveOrQueueRefund(src,cid,item,amount)
    amount=clampInt(amount,0)
    if amount<=0 then return 0 end
    if src and GetPlayerName(src) then
        local ok,result=pcall(function() return exports.ox_inventory:AddItem(src,item,amount) end)
        if ok and result then return amount end
    end
    addRefund(cid,item,amount)
    return amount
end

local function stopSession(src,status,disconnected)
    local s=sessions[src]
    if not s then return end
    sessions[src]=nil
    local remaining=math.max(0,tonumber(s.remainingRaw) or 0)
    if remaining>0 then
        if disconnected then addRefund(s.citizenid,s.rawItem,remaining)
        else giveOrQueueRefund(src,s.citizenid,s.rawItem,remaining) end
    end
    MySQL.query.await('DELETE FROM cookie_drugcraft_reservations WHERE citizenid=?',{s.citizenid})
    MySQL.update.await('UPDATE cookie_drugcraft_history SET status=?,produced=?,ended_at=NOW() WHERE id=?',
        {status or 'canceled',s.produced or 0,s.historyId})
    if not disconnected and GetPlayerName(src) then
        TriggerClientEvent('cookie_drugcraft:client:canceled',src,{refunded=remaining,produced=s.produced or 0,reason=status})
    end
end

local function adminPayload()
    return {locations=cachedLocations,recipes=cachedRecipes,defaults={
        orgBase=Config.OrganizationBaseSeconds or 15,orgBoost=Config.OrganizationBoostSeconds or 5,
        normalBase=Config.DefaultBaseSeconds or 20,normalBoost=Config.DefaultBoostSeconds or 8}}
end

CreateThread(function()
    Wait(500)
    ensureSchema()
    seedRecipes()
    recoverStaleReservations()
    refreshCache(true)
    print('^2[cookie_drugcraft] V1.0.0 loaded · organization 15s / minigame 5s^7')
end)

RegisterNetEvent('cookie_drugcraft:server:requestLocations',function()
    TriggerClientEvent('cookie_drugcraft:client:locations',source,cachedLocations)
end)

RegisterNetEvent('cookie_drugcraft:server:claimRefund',function()
    local src=source
    local cid=citizenId(src)
    if not cid then return end
    local rows=MySQL.query.await('SELECT item,amount FROM cookie_drugcraft_refunds WHERE citizenid=? AND amount>0',{cid}) or {}
    local total=0
    for _,row in ipairs(rows) do
        local amount=clampInt(row.amount,0)
        if amount>0 then
            local ok,result=pcall(function() return exports.ox_inventory:AddItem(src,row.item,amount) end)
            if ok and result then
                total=total+amount
                MySQL.query.await('DELETE FROM cookie_drugcraft_refunds WHERE citizenid=? AND item=?',{cid,row.item})
            end
        end
    end
    TriggerClientEvent('cookie_drugcraft:client:refundClaimed',src,total)
end)

RegisterNetEvent('cookie_drugcraft:server:open',function(locationId)
    local src=source
    if sessions[src] then return TriggerClientEvent('cookie_drugcraft:client:denied',src,'이미 제조가 진행 중입니다.') end
    local loc=findLocation(locationId)
    if not loc or tonumber(loc.enabled)~=1 then return TriggerClientEvent('cookie_drugcraft:client:denied',src,'사용할 수 없는 제조소입니다.') end
    if not nearLocation(src,loc,2.5) then return TriggerClientEvent('cookie_drugcraft:client:denied',src,'제조소에서 너무 멉니다.') end
    local crime,faction=isCrime(src)
    if Config.RequireCrimeFaction and not crime then return TriggerClientEvent('cookie_drugcraft:client:denied',src,'조직원만 사용할 수 있습니다.') end
    local recipes={}
    for _,r in ipairs(cachedRecipes) do
        if tonumber(r.enabled)==1 then
            local count=exports.ox_inventory:Search(src,'count',r.raw_item) or 0
            recipes[#recipes+1]={
                code=r.code,label=r.label,rawItem=r.raw_item,outputItem=r.output_item,
                rawPerBatch=tonumber(r.raw_per_batch) or 5,outputPerBatch=tonumber(r.output_per_batch) or 1,
                baseSeconds=crime and (tonumber(r.base_seconds) or Config.OrganizationBaseSeconds or 15) or (Config.DefaultBaseSeconds or 20),
                boostSeconds=crime and (tonumber(r.boost_seconds) or Config.OrganizationBoostSeconds or 5) or (Config.DefaultBoostSeconds or 8),
                minigame=r.minigame,rawCount=tonumber(count) or 0}
        end
    end
    local token=('%d:%d:%d:%d'):format(src,tonumber(locationId) or 0,os.time(),math.random(100000,999999))
    openTokens[src]={token=token,locationId=tonumber(locationId),expires=os.time()+90}
    TriggerClientEvent('cookie_drugcraft:client:open',src,{
        token=token,locationId=tonumber(locationId),locationLabel=loc.label,
        factionName=faction and (faction.name or faction.label) or '조직',recipes=recipes})
end)

RegisterNetEvent('cookie_drugcraft:server:start',function(data)
    local src=source
    if sessions[src] then return TriggerClientEvent('cookie_drugcraft:client:denied',src,'이미 제조가 진행 중입니다.') end
    local token=openTokens[src];openTokens[src]=nil
    if not token or token.expires<os.time() or tostring(data and data.token or '')~=tostring(token.token) then
        return TriggerClientEvent('cookie_drugcraft:client:denied',src,'제조 요청이 만료되었습니다.')
    end
    local loc=findLocation(token.locationId)
    if not loc or tonumber(loc.enabled)~=1 or not nearLocation(src,loc,2.5) then
        return TriggerClientEvent('cookie_drugcraft:client:denied',src,'제조소에서 너무 멉니다.')
    end
    local crime,faction=isCrime(src)
    if Config.RequireCrimeFaction and not crime then return TriggerClientEvent('cookie_drugcraft:client:denied',src,'조직원만 사용할 수 있습니다.') end
    local recipe=findRecipe(data and data.recipe)
    if not recipe or tonumber(recipe.enabled)~=1 then return TriggerClientEvent('cookie_drugcraft:client:denied',src,'사용할 수 없는 제조법입니다.') end
    local rawPer=math.max(1,tonumber(recipe.raw_per_batch) or 5)
    local outPer=math.max(1,tonumber(recipe.output_per_batch) or 1)
    local requested=clampInt(data and data.rawAmount,1,100000000)
    local have=tonumber(exports.ox_inventory:Search(src,'count',recipe.raw_item) or 0) or 0
    local usable=math.min(requested,have)
    local batches=math.floor(usable/rawPer)
    if batches<=0 then return TriggerClientEvent('cookie_drugcraft:client:denied',src,('원재료가 부족합니다. 최소 %d개 필요합니다.'):format(rawPer)) end
    local reservedRaw=batches*rawPer
    local removed=exports.ox_inventory:RemoveItem(src,recipe.raw_item,reservedRaw)
    if not removed then return TriggerClientEvent('cookie_drugcraft:client:denied',src,'원재료 예약에 실패했습니다.') end
    local cid=citizenId(src)
    if not cid then
        exports.ox_inventory:AddItem(src,recipe.raw_item,reservedRaw)
        return TriggerClientEvent('cookie_drugcraft:client:denied',src,'캐릭터 정보를 확인할 수 없습니다.')
    end
    local boosted=data and data.boosted==true
    local cycleSeconds
    if crime then
        cycleSeconds=boosted and (tonumber(recipe.boost_seconds) or Config.OrganizationBoostSeconds or 5)
            or (tonumber(recipe.base_seconds) or Config.OrganizationBaseSeconds or 15)
    else
        cycleSeconds=boosted and (Config.DefaultBoostSeconds or 8) or (Config.DefaultBaseSeconds or 20)
    end
    cycleSeconds=clampInt(cycleSeconds,1,3600)
    local historyId=MySQL.insert.await([[INSERT INTO cookie_drugcraft_history
        (citizenid,faction_id,recipe_code,reserved_raw,produced,boosted,status)
        VALUES (?,?,?,?,?,?, 'running')]],{cid,faction and tonumber(faction.id) or nil,recipe.code,reservedRaw,0,boosted and 1 or 0})
    MySQL.query.await([[INSERT INTO cookie_drugcraft_reservations (citizenid,recipe_code,raw_item,remaining_raw)
        VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE recipe_code=VALUES(recipe_code),raw_item=VALUES(raw_item),
        remaining_raw=VALUES(remaining_raw),created_at=CURRENT_TIMESTAMP]],{cid,recipe.code,recipe.raw_item,reservedRaw})
    sessions[src]={
        citizenid=cid,locationId=tonumber(loc.id),recipeCode=recipe.code,label=recipe.label,
        rawItem=recipe.raw_item,outputItem=recipe.output_item,rawPerBatch=rawPer,outputPerBatch=outPer,
        totalBatches=batches,completed=0,produced=0,remainingRaw=reservedRaw,cycleSeconds=cycleSeconds,
        boosted=boosted,historyId=historyId}
    TriggerClientEvent('cookie_drugcraft:client:started',src,{
        label=recipe.label,totalBatches=batches,reservedRaw=reservedRaw,expectedOutput=batches*outPer,
        cycleSeconds=cycleSeconds,boosted=boosted})
    CreateThread(function()
        while sessions[src] do
            local s=sessions[src]
            if not s or s.completed>=s.totalBatches then break end
            local currentLoc=findLocation(s.locationId)
            if not currentLoc or not nearLocation(src,currentLoc,Config.CancelDistance or 18.0) then stopSession(src,'distance',false) return end
            TriggerClientEvent('cookie_drugcraft:client:cycle',src,{
                completed=s.completed,total=s.totalBatches,produced=s.produced,cycleSeconds=s.cycleSeconds,label=s.label,phase='start'})
            Wait(s.cycleSeconds*1000)
            s=sessions[src]
            if not s then return end
            currentLoc=findLocation(s.locationId)
            if not currentLoc or not nearLocation(src,currentLoc,Config.CancelDistance or 18.0) then stopSession(src,'distance',false) return end
            if not exports.ox_inventory:CanCarryItem(src,s.outputItem,s.outputPerBatch) then
                stopSession(src,'inventory_full',false)
                TriggerClientEvent('cookie_drugcraft:client:denied',src,'인벤토리 공간이 부족해 제조를 중단했습니다.')
                return
            end
            local added=exports.ox_inventory:AddItem(src,s.outputItem,s.outputPerBatch)
            if not added then stopSession(src,'output_failed',false) return end
            s.completed=s.completed+1;s.produced=s.produced+s.outputPerBatch
            s.remainingRaw=math.max(0,s.remainingRaw-s.rawPerBatch)
            MySQL.update.await('UPDATE cookie_drugcraft_reservations SET remaining_raw=? WHERE citizenid=?',{s.remainingRaw,s.citizenid})
            TriggerClientEvent('cookie_drugcraft:client:cycle',src,{
                completed=s.completed,total=s.totalBatches,produced=s.produced,cycleSeconds=s.cycleSeconds,label=s.label,phase='complete'})
        end
        local s=sessions[src]
        if not s then return end
        sessions[src]=nil
        MySQL.query.await('DELETE FROM cookie_drugcraft_reservations WHERE citizenid=?',{s.citizenid})
        MySQL.update.await("UPDATE cookie_drugcraft_history SET status='done',produced=?,ended_at=NOW() WHERE id=?",{s.produced,s.historyId})
        TriggerClientEvent('cookie_drugcraft:client:finished',src,{label=s.label,produced=s.produced,batches=s.completed})
    end)
end)

RegisterNetEvent('cookie_drugcraft:server:cancel',function() stopSession(source,'manual_cancel',false) end)
AddEventHandler('playerDropped',function() stopSession(source,'disconnect',true);openTokens[source]=nil end)

RegisterNetEvent('cookie_drugcraft:server:adminRequest',function()
    local src=source
    if not isAdmin(src) then return TriggerClientEvent('cookie_drugcraft:client:denied',src,'관리 권한이 없습니다.') end
    TriggerClientEvent('cookie_drugcraft:client:adminOpen',src,adminPayload())
end)

RegisterNetEvent('cookie_drugcraft:server:adminAddLocation',function(data)
    local src=source;if not isAdmin(src) then return end
    local ped=GetPlayerPed(src);if not ped or ped==0 then return end
    local c=GetEntityCoords(ped);local label=clean(data and data.label or '조직 제조',100)
    if label=='' then label='조직 제조' end
    local radius=math.max(1.0,math.min(20.0,tonumber(data and data.radius) or 3.0))
    MySQL.insert.await('INSERT INTO cookie_drugcraft_locations (label,x,y,z,radius,enabled,created_by) VALUES (?,?,?,?,?,1,?)',
        {label,c.x,c.y,c.z,radius,citizenId(src)})
    refreshCache(true);TriggerClientEvent('cookie_drugcraft:client:adminRefresh',src,adminPayload())
end)

RegisterNetEvent('cookie_drugcraft:server:adminUpdateLocation',function(data)
    local src=source;if not isAdmin(src) then return end
    local id=tonumber(data and data.id);if not id then return end
    local label=clean(data.label or '조직 제조',100)
    local radius=math.max(1.0,math.min(20.0,tonumber(data.radius) or 3.0))
    MySQL.update.await('UPDATE cookie_drugcraft_locations SET label=?,radius=?,enabled=? WHERE id=?',
        {label,radius,data.enabled==true and 1 or 0,id})
    refreshCache(true);TriggerClientEvent('cookie_drugcraft:client:adminRefresh',src,adminPayload())
end)

RegisterNetEvent('cookie_drugcraft:server:adminDeleteLocation',function(data)
    local src=source;if not isAdmin(src) then return end
    local id=tonumber(data and data.id);if not id then return end
    MySQL.query.await('DELETE FROM cookie_drugcraft_locations WHERE id=?',{id})
    refreshCache(true);TriggerClientEvent('cookie_drugcraft:client:adminRefresh',src,adminPayload())
end)

RegisterNetEvent('cookie_drugcraft:server:adminUpdateRecipe',function(data)
    local src=source;if not isAdmin(src) then return end
    local code=clean(data and data.code or '',32);if not findRecipe(code) then return end
    MySQL.update.await([[UPDATE cookie_drugcraft_recipes SET raw_per_batch=?,output_per_batch=?,
        base_seconds=?,boost_seconds=?,enabled=? WHERE code=?]],{
        clampInt(data.rawPerBatch,1,100000),clampInt(data.outputPerBatch,1,100000),
        clampInt(data.baseSeconds,1,3600),clampInt(data.boostSeconds,1,3600),
        data.enabled==true and 1 or 0,code})
    refreshCache(false);TriggerClientEvent('cookie_drugcraft:client:adminRefresh',src,adminPayload())
end)
