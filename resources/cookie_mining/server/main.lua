local function cookieAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function()
            return exports.cookie_core:Allow(src, key, windowMs, maxCount)
        end)
        if ok then return allowed == true end
    end
    return true
end

local pending={}
local nodeCooldowns={}
local systemSettings={
    mineDurationMs=tonumber(Config.MineDurationMs) or 20000,
    rhythmSuccessMs=tonumber(Config.RhythmSuccessDurationMs) or 5000,
    rhythmRounds=tonumber(Config.RhythmRounds) or 4,
    nodeCount=tonumber(Config.NodeCount) or 9,
    respawnMs=tonumber(Config.NodeRespawnMs) or 45000,
    purityMinMultiplier=tonumber(Config.PurityPriceMinMultiplier) or 0.5,
    purityMaxMultiplier=tonumber(Config.PurityPriceMaxMultiplier) or 2.0,
    pickaxeSkilledMultiplier=tonumber(Config.Pickaxes and Config.Pickaxes.skilled and Config.Pickaxes.skilled.durationMultiplier) or 0.80,
    pickaxeExpertMultiplier=tonumber(Config.Pickaxes and Config.Pickaxes.expert and Config.Pickaxes.expert.durationMultiplier) or 0.60,
    pickaxeBasicPrice=tonumber(Config.Pickaxes and Config.Pickaxes.basic and Config.Pickaxes.basic.defaultPrice) or 50000,
    pickaxeSkilledPrice=tonumber(Config.Pickaxes and Config.Pickaxes.skilled and Config.Pickaxes.skilled.defaultPrice) or 150000,
    pickaxeExpertPrice=tonumber(Config.Pickaxes and Config.Pickaxes.expert and Config.Pickaxes.expert.defaultPrice) or 350000,
}

local function notify(src,msg,isErr) TriggerClientEvent('cookie_admin:client:notify',src,msg,isErr==true) end
local function comma(n) local s=tostring(math.floor(tonumber(n) or 0)); return s:reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,','') end
local function itemCount(src,item) local ok,n=pcall(function() return exports.ox_inventory:GetItemCount(src,item) end); return ok and (tonumber(n) or 0) or 0 end
local function pickaxeDef(key)
    local defs=Config.Pickaxes or {}
    return defs[key]
end
local function pickaxeMultiplier(key)
    if key=='skilled' then return math.max(0.10,tonumber(systemSettings.pickaxeSkilledMultiplier) or 0.80) end
    if key=='expert' then return math.max(0.10,tonumber(systemSettings.pickaxeExpertMultiplier) or 0.60) end
    return 1.0
end
local function bestPickaxe(src)
    for _,key in ipairs({'expert','skilled','basic'}) do
        local d=pickaxeDef(key)
        if d and d.item and itemCount(src,d.item)>0 then return key,d end
    end
    return nil,nil
end
local function equippedPickaxe(src,itemName)
    itemName=tostring(itemName or '')
    if itemName=='' then return nil,nil end
    for _,key in ipairs({'expert','skilled','basic'}) do
        local d=pickaxeDef(key)
        if d and d.item==itemName and itemCount(src,d.item)>0 then return key,d end
    end
    return nil,nil
end
local function playerCitizenId(src) local p=exports.qbx_core:GetPlayer(src); return p and p.PlayerData and p.PlayerData.citizenid or nil end
local function adminName(src) local n='-'; pcall(function() n=exports.cookie_admin:getAdminName(src) or '-' end); return n end
local function adminLevel(src,min) local ok,lv=pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end); return ok and (tonumber(lv) or 0)>=(min or 3) end
local function dbBool(v) return v==true or tonumber(v)==1 or tostring(v):lower()=='true' end
local function fract(x) return x-math.floor(x) end
local function seeded01(seed) return fract(math.sin(seed*12.9898+78.233)*43758.5453) end

local function pointInPoly2D(pos, pts)
    if type(pts) ~= 'table' or #pts < 3 then return false end
    local inside=false
    local j=#pts
    for i=1,#pts do
        local a,b=pts[i],pts[j]
        local ax,ay=tonumber(a.x or a[1]),tonumber(a.y or a[2])
        local bx,by=tonumber(b.x or b[1]),tonumber(b.y or b[2])
        if ax and ay and bx and by then
            local hit=((ay>pos.y) ~= (by>pos.y)) and (pos.x < (bx-ax)*(pos.y-ay)/((by-ay)+0.0000001)+ax)
            if hit then inside=not inside end
        end
        j=i
    end
    return inside
end

local function pointInZone(pos,z)
    if z.shape=='poly' then
        local hz=(tonumber(z.height) or 40)*0.5
        return math.abs(pos.z-(z.cz+0.0))<=hz and pointInPoly2D(pos,z.polyPoints)
    elseif z.shape=='sphere' then
        local dx,dy,dz=pos.x-(z.cx+0.0),pos.y-(z.cy+0.0),pos.z-(z.cz+0.0); local r=tonumber(z.radius) or 0
        return dx*dx+dy*dy+dz*dz<=r*r
    end
    local dx,dy=pos.x-(z.cx+0.0),pos.y-(z.cy+0.0); local rad=math.rad(-(tonumber(z.heading) or 0)); local cs,sn=math.cos(rad),math.sin(rad)
    local lx,ly=dx*cs-dy*sn,dx*sn+dy*cs; local hz=(tonumber(z.height) or 40)*0.5
    return math.abs(lx)<=((tonumber(z.length) or 0)*0.5) and math.abs(ly)<=((tonumber(z.width) or 0)*0.5) and math.abs(pos.z-(z.cz+0.0))<=hz
end

local function nodePosFor(zone,idx)
    -- IMPORTANT:
    -- 클라이언트가 실제로 생성한 바위 위치와 서버 검증 위치가 반드시 같아야 합니다.
    -- V1.7.6: client/main.lua 의 nodePosFor 계산식을 그대로 맞춥니다.
    local margin=tonumber(Config.NodeMargin) or 1.0
    local seed=(tonumber(zone.id) or 0)*100+idx
    local rx,ry=seeded01(seed+1),seeded01(seed+2)
    local pos

    local band=((idx-1)%3)+1
    local factor
    if band==1 then
        factor=0.18+0.22*seeded01(seed+20)
    elseif band==2 then
        factor=0.42+0.24*seeded01(seed+21)
    else
        factor=0.68+0.22*seeded01(seed+22)
    end

    if zone.shape=='sphere' then
        local maxR=math.max(2.0,(tonumber(zone.radius) or 10.0)-margin)
        local ang=seeded01(seed+3)*math.pi*2.0
        local dist=maxR*factor
        pos={
            x=(zone.cx+0.0)+math.cos(ang)*dist,
            y=(zone.cy+0.0)+math.sin(ang)*dist,
            z=zone.cz+0.0
        }
    elseif zone.shape=='poly' and type(zone.polyPoints)=='table' and #zone.polyPoints>=3 then
        local minX,maxX,minY,maxY=999999,-999999,999999,-999999
        for _,pt in ipairs(zone.polyPoints) do
            local x,y=tonumber(pt.x or pt[1]),tonumber(pt.y or pt[2])
            if x and y then
                minX=math.min(minX,x)
                maxX=math.max(maxX,x)
                minY=math.min(minY,y)
                maxY=math.max(maxY,y)
            end
        end

        local cx=tonumber(zone.cx) or ((minX+maxX)*0.5)
        local cy=tonumber(zone.cy) or ((minY+maxY)*0.5)

        for a=1,40 do
            local x=minX+(maxX-minX)*seeded01(seed+10+a*2)
            local y=minY+(maxY-minY)*seeded01(seed+11+a*2)
            x=cx+(x-cx)*factor
            y=cy+(y-cy)*factor

            local p={x=x,y=y,z=zone.cz+0.0}
            if pointInPoly2D(p,zone.polyPoints) then
                pos=p
                break
            end
        end

        if not pos then
            pos={x=cx,y=cy,z=zone.cz+0.0}
        end
    else
        local hl=math.max(2.0,((tonumber(zone.length) or 12.0)*0.5)-margin)
        local hw=math.max(2.0,((tonumber(zone.width) or 12.0)*0.5)-margin)
        local lx=(rx*2-1)*hl*factor
        local ly=(ry*2-1)*hw*factor
        local h=math.rad(tonumber(zone.heading) or 0.0)
        local cs,sn=math.cos(h),math.sin(h)

        pos={
            x=(zone.cx+0.0)+(lx*cs-ly*sn),
            y=(zone.cy+0.0)+(lx*sn+ly*cs),
            z=zone.cz+0.0
        }
    end

    return pos
end

local function miningZoneById(zoneId)
    zoneId=tonumber(zoneId); if not zoneId then return nil end
    local ok,rows=pcall(function() return exports.cookie_safezone:getZones() end); if not ok or type(rows)~='table' then return nil end
    for _,z in ipairs(rows) do if tonumber(z.id)==zoneId and z.type=='mining' then return z end end
end
local function currentMiningZone(src,id)
    local ped=GetPlayerPed(src); if not ped or ped==0 then return nil end; local z=miningZoneById(id); if z and pointInZone(GetEntityCoords(ped),z) then return z end
end
local function nodeNear(src,zone,idx)
    local p=GetEntityCoords(GetPlayerPed(src)); local n=nodePosFor(zone,idx); local dx,dy=p.x-n.x,p.y-n.y; local maxD=math.max(7.5,(tonumber(Config.InteractDistance) or 4.0)+3.0)
    return dx*dx+dy*dy<=maxD*maxD
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_mining_collection (citizenid VARCHAR(60) NOT NULL,mineral VARCHAR(40) NOT NULL,mined_count INT NOT NULL DEFAULT 0,best_purity INT NOT NULL DEFAULT 0,first_mined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,last_mined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,PRIMARY KEY(citizenid,mineral),INDEX idx_mining_citizen(citizenid)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_mining_zone_mineral (zone_id INT NOT NULL,mineral VARCHAR(40) NOT NULL,enabled TINYINT(1) NOT NULL DEFAULT 1,weight DECIMAL(10,3) NOT NULL DEFAULT 1,updated_by VARCHAR(60) NULL,updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,PRIMARY KEY(zone_id,mineral),INDEX idx_mining_zone(zone_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_mining_systemcfg (id TINYINT NOT NULL PRIMARY KEY DEFAULT 1,mine_duration_ms INT NOT NULL DEFAULT 20000,node_count INT NOT NULL DEFAULT 9,respawn_ms INT NOT NULL DEFAULT 45000,updated_by VARCHAR(60) NULL,updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    pcall(function() MySQL.query.await('ALTER TABLE cookie_mining_systemcfg ADD COLUMN rhythm_success_ms INT NOT NULL DEFAULT 5000') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_mining_systemcfg ADD COLUMN rhythm_rounds INT NOT NULL DEFAULT 4') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_mining_systemcfg ADD COLUMN purity_min_multiplier DECIMAL(8,3) NOT NULL DEFAULT 0.5') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_mining_systemcfg ADD COLUMN purity_max_multiplier DECIMAL(8,3) NOT NULL DEFAULT 2.0') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_mining_systemcfg ADD COLUMN pickaxe_skilled_multiplier DECIMAL(8,3) NOT NULL DEFAULT 0.8') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_mining_systemcfg ADD COLUMN pickaxe_expert_multiplier DECIMAL(8,3) NOT NULL DEFAULT 0.6') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_mining_systemcfg ADD COLUMN pickaxe_basic_price INT NOT NULL DEFAULT 50000') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_mining_systemcfg ADD COLUMN pickaxe_skilled_price INT NOT NULL DEFAULT 150000') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_mining_systemcfg ADD COLUMN pickaxe_expert_price INT NOT NULL DEFAULT 350000') end)
    MySQL.query.await('INSERT IGNORE INTO cookie_mining_systemcfg (id,mine_duration_ms,node_count,respawn_ms,rhythm_success_ms,rhythm_rounds,purity_min_multiplier,purity_max_multiplier) VALUES (1,?,?,?,?,?,?,?)',{systemSettings.mineDurationMs,systemSettings.nodeCount,systemSettings.respawnMs,systemSettings.rhythmSuccessMs,systemSettings.rhythmRounds,systemSettings.purityMinMultiplier,systemSettings.purityMaxMultiplier})
    local c=MySQL.single.await('SELECT * FROM cookie_mining_systemcfg WHERE id=1')
    if c and tonumber(c.mine_duration_ms)==6500 and (c.updated_by==nil or tostring(c.updated_by)=='') then
        MySQL.update.await('UPDATE cookie_mining_systemcfg SET mine_duration_ms=20000 WHERE id=1')
        c.mine_duration_ms=20000
    end
    if c then
        systemSettings.mineDurationMs=math.max(5000,tonumber(c.mine_duration_ms) or 20000); systemSettings.nodeCount=math.max(1,tonumber(c.node_count) or 9); systemSettings.respawnMs=math.max(5000,tonumber(c.respawn_ms) or 45000)
        systemSettings.rhythmSuccessMs=math.max(1000,tonumber(c.rhythm_success_ms) or 5000); systemSettings.rhythmRounds=math.max(1,tonumber(c.rhythm_rounds) or 4)
        systemSettings.purityMinMultiplier=tonumber(c.purity_min_multiplier) or 0.5; systemSettings.purityMaxMultiplier=tonumber(c.purity_max_multiplier) or 2.0
        systemSettings.pickaxeSkilledMultiplier=math.max(0.10,tonumber(c.pickaxe_skilled_multiplier) or systemSettings.pickaxeSkilledMultiplier)
        systemSettings.pickaxeExpertMultiplier=math.max(0.10,tonumber(c.pickaxe_expert_multiplier) or systemSettings.pickaxeExpertMultiplier)
        systemSettings.pickaxeBasicPrice=math.max(0,math.floor(tonumber(c.pickaxe_basic_price) or systemSettings.pickaxeBasicPrice))
        systemSettings.pickaxeSkilledPrice=math.max(0,math.floor(tonumber(c.pickaxe_skilled_price) or systemSettings.pickaxeSkilledPrice))
        systemSettings.pickaxeExpertPrice=math.max(0,math.floor(tonumber(c.pickaxe_expert_price) or systemSettings.pickaxeExpertPrice))
    end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_mining_npc_shop (npc_id INT NOT NULL,kind VARCHAR(20) NOT NULL,enabled TINYINT(1) NOT NULL DEFAULT 1,price INT NOT NULL DEFAULT 0,qty INT NOT NULL DEFAULT 1,updated_by VARCHAR(60) NULL,updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,PRIMARY KEY(npc_id,kind)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[INSERT IGNORE INTO cookie_mining_npc_shop (npc_id,kind,enabled,price,qty,updated_by) SELECT npc_id,'pickaxe_basic',enabled,price,qty,updated_by FROM cookie_mining_npc_shop WHERE kind='pickaxe']])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_mining_npc_mineral (npc_id INT NOT NULL,mineral VARCHAR(40) NOT NULL,enabled TINYINT(1) NOT NULL DEFAULT 1,base_price INT NULL,updated_by VARCHAR(60) NULL,updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,PRIMARY KEY(npc_id,mineral)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end)

local function settingsPayload()
    return {
        mineDurationMs=systemSettings.mineDurationMs,mineDurationSec=systemSettings.mineDurationMs/1000,
        rhythmSuccessMs=systemSettings.rhythmSuccessMs,rhythmSuccessSec=systemSettings.rhythmSuccessMs/1000,
        rhythmRounds=systemSettings.rhythmRounds,nodeCount=systemSettings.nodeCount,
        respawnMs=systemSettings.respawnMs,respawnSec=systemSettings.respawnMs/1000,
        purityMinMultiplier=systemSettings.purityMinMultiplier,purityMaxMultiplier=systemSettings.purityMaxMultiplier,
        pickaxeSkilledMultiplier=systemSettings.pickaxeSkilledMultiplier,
        pickaxeExpertMultiplier=systemSettings.pickaxeExpertMultiplier,
        pickaxeBasicPrice=systemSettings.pickaxeBasicPrice,
        pickaxeSkilledPrice=systemSettings.pickaxeSkilledPrice,
        pickaxeExpertPrice=systemSettings.pickaxeExpertPrice,
    }
end
local function saveSystemSettingsInternal(src,d)
    if src ~= 0 and not adminLevel(src,5) then return false,'권한이 없습니다' end
    d=d or {}
    local baseSec=tonumber(d.mineDurationSec) or 20
    local fast=tonumber(d.rhythmSuccessSec) or 5
    local rounds=math.floor(tonumber(d.rhythmRounds) or 4)
    local count=math.floor(tonumber(d.nodeCount) or 9)
    local resp=tonumber(d.respawnSec) or 45
    local pmin=tonumber(d.purityMinMultiplier) or 0.5
    local pmax=tonumber(d.purityMaxMultiplier) or 2.0
    local skilled=tonumber(d.pickaxeSkilledMultiplier) or systemSettings.pickaxeSkilledMultiplier or 0.80
    local expert=tonumber(d.pickaxeExpertMultiplier) or systemSettings.pickaxeExpertMultiplier or 0.60
    local basicPrice=math.max(0,math.floor(tonumber(d.pickaxeBasicPrice) or systemSettings.pickaxeBasicPrice or 50000))
    local skilledPrice=math.max(0,math.floor(tonumber(d.pickaxeSkilledPrice) or systemSettings.pickaxeSkilledPrice or 150000))
    local expertPrice=math.max(0,math.floor(tonumber(d.pickaxeExpertPrice) or systemSettings.pickaxeExpertPrice or 350000))
    if baseSec<5 or baseSec>120 then return false,'기본 채굴 시간은 5~120초' end
    if fast<1 or fast>baseSec then return false,'리듬 성공 시간은 1초 이상이며 기본 채굴 시간 이하여야 합니다' end
    if rounds<1 or rounds>10 then return false,'리듬 횟수는 1~10회' end
    if count<1 or count>40 then return false,'바위 개수는 1~40개' end
    if resp<5 or resp>3600 then return false,'재생 시간은 5~3600초' end
    if pmin<0 or pmax<pmin or pmax>10 then return false,'순도 가격 배율을 확인하세요' end
    if skilled<0.10 or skilled>2.0 or expert<0.10 or expert>2.0 then return false,'곡괭이 채굴시간 배율은 0.10~2.00 사이로 설정하세요' end
    if basicPrice>100000000 or skilledPrice>100000000 or expertPrice>100000000 then return false,'곡괭이 가격은 0~100,000,000원 사이로 설정하세요' end

    systemSettings.mineDurationMs=math.floor(baseSec*1000)
    systemSettings.rhythmSuccessMs=math.floor(fast*1000)
    systemSettings.rhythmRounds=rounds
    systemSettings.nodeCount=count
    systemSettings.respawnMs=math.floor(resp*1000)
    systemSettings.purityMinMultiplier=pmin
    systemSettings.purityMaxMultiplier=pmax
    systemSettings.pickaxeSkilledMultiplier=skilled
    systemSettings.pickaxeExpertMultiplier=expert
    systemSettings.pickaxeBasicPrice=basicPrice
    systemSettings.pickaxeSkilledPrice=skilledPrice
    systemSettings.pickaxeExpertPrice=expertPrice

    local ok,err=pcall(function()
        MySQL.query.await([[INSERT INTO cookie_mining_systemcfg (id,mine_duration_ms,node_count,respawn_ms,rhythm_success_ms,rhythm_rounds,purity_min_multiplier,purity_max_multiplier,pickaxe_skilled_multiplier,pickaxe_expert_multiplier,pickaxe_basic_price,pickaxe_skilled_price,pickaxe_expert_price,updated_by) VALUES (1,?,?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE mine_duration_ms=VALUES(mine_duration_ms),node_count=VALUES(node_count),respawn_ms=VALUES(respawn_ms),rhythm_success_ms=VALUES(rhythm_success_ms),rhythm_rounds=VALUES(rhythm_rounds),purity_min_multiplier=VALUES(purity_min_multiplier),purity_max_multiplier=VALUES(purity_max_multiplier),pickaxe_skilled_multiplier=VALUES(pickaxe_skilled_multiplier),pickaxe_expert_multiplier=VALUES(pickaxe_expert_multiplier),pickaxe_basic_price=VALUES(pickaxe_basic_price),pickaxe_skilled_price=VALUES(pickaxe_skilled_price),pickaxe_expert_price=VALUES(pickaxe_expert_price),updated_by=VALUES(updated_by)]],{systemSettings.mineDurationMs,systemSettings.nodeCount,systemSettings.respawnMs,systemSettings.rhythmSuccessMs,systemSettings.rhythmRounds,systemSettings.purityMinMultiplier,systemSettings.purityMaxMultiplier,systemSettings.pickaxeSkilledMultiplier,systemSettings.pickaxeExpertMultiplier,systemSettings.pickaxeBasicPrice,systemSettings.pickaxeSkilledPrice,systemSettings.pickaxeExpertPrice,src==0 and 'console' or adminName(src)})
    end)
    if not ok then return false,'DB 저장 실패: '..tostring(err) end
    local payload=settingsPayload()
    TriggerClientEvent('cookie_mining:client:systemSettings',-1,payload)
    return true,payload
end

exports('getSystemSettings',function(src)
    src=tonumber(src) or 0
    if src~=0 and not adminLevel(src,5) then return nil,'권한이 없습니다' end
    return settingsPayload()
end)
exports('saveSystemSettings',function(src,data) return saveSystemSettingsInternal(tonumber(src) or 0,data) end)

RegisterNetEvent('cookie_mining:server:systemAdminRequest',function()
    local src=source
    if not adminLevel(src,5) then return notify(src,'권한이 없습니다',true) end
    TriggerClientEvent('cookie_admin:client:miningSystemData',src,settingsPayload())
end)
RegisterNetEvent('cookie_mining:server:systemAdminSave',function(d)
    local src=source
    local ok,result=saveSystemSettingsInternal(src,d)
    if not ok then return notify(src,result or '저장에 실패했습니다',true) end
    TriggerClientEvent('cookie_admin:client:miningSystemData',src,result)
    notify(src,'광산 시스템 설정을 저장했습니다',false)
end)

local function nodeState(zoneId,idx) nodeCooldowns[zoneId]=nodeCooldowns[zoneId] or {};nodeCooldowns[zoneId][idx]=nodeCooldowns[zoneId][idx] or {cooldownUntil=0,busyBy=nil};return nodeCooldowns[zoneId][idx] end
local function broadcastNode(zoneId,idx)
    local s=nodeState(zoneId,idx);local remain=math.max(0,(tonumber(s.cooldownUntil) or 0)-GetGameTimer());TriggerClientEvent('cookie_mining:client:nodeState',-1,zoneId,idx,remain>0,remain,s.busyBy~=nil)
end
local function buildNodeStates(zone)
    local out={};local now=GetGameTimer();for i=1,systemSettings.nodeCount do local s=nodeState(zone.id,i);local rem=math.max(0,(s.cooldownUntil or 0)-now);out[i]={depleted=rem>0,remainingMs=rem,busy=s.busyBy~=nil} end;return out
end
RegisterNetEvent('cookie_mining:server:requestZoneNodes',function(zoneId) local src=source;local z=currentMiningZone(src,zoneId) or miningZoneById(zoneId);if z then TriggerClientEvent('cookie_mining:client:zoneNodesState',src,{zone=z,states=buildNodeStates(z),settings=settingsPayload()}) end end)

local function zoneMineralRows(zoneId)
    return MySQL.query.await('SELECT mineral,enabled,weight FROM cookie_mining_zone_mineral WHERE zone_id=?',{tonumber(zoneId)}) or {}
end

local function defaultMineralPool()
    local pool,total={},0
    for k,m in pairs(Config.Minerals or {}) do
        local w=math.max(0,tonumber(m.weight) or 0)
        if w>0 then pool[#pool+1]={key=k,m=m,w=w};total=total+w end
    end
    return pool,total
end

local function configuredMineralPool(rows)
    local pool,total={},0
    for _,r in ipairs(rows or {}) do
        local m=Config.Minerals[r.mineral]
        local w=math.max(0,tonumber(r.weight) or 0)
        if m and dbBool(r.enabled) and w>0 then
            pool[#pool+1]={key=r.mineral,m=m,w=w};total=total+w
        end
    end
    return pool,total
end

local function repairBrokenZoneMinerals(zoneId)
    -- 구버전 설정 저장 오류로 모든 광물이 OFF/0이 된 광산을 기본 출현표로 복구한다.
    for key,m in pairs(Config.Minerals or {}) do
        MySQL.query.await([[INSERT INTO cookie_mining_zone_mineral(zone_id,mineral,enabled,weight,updated_by)
            VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),weight=VALUES(weight),updated_by=VALUES(updated_by)]],
            {tonumber(zoneId),key,1,math.max(0,tonumber(m.weight) or 1),'auto_repair_v1.5.8'})
    end
    print(('[cookie_mining] repaired empty mineral table for zone=%s'):format(tostring(zoneId)))
end

local function rollMineral(zoneId)
    local rows=zoneMineralRows(zoneId)
    local pool,total
    if #rows>0 then
        pool,total=configuredMineralPool(rows)
        if total<=0 then
            repairBrokenZoneMinerals(zoneId)
            pool,total=defaultMineralPool()
        end
    else
        pool,total=defaultMineralPool()
    end
    if total<=0 or #pool==0 then return nil end
    local r=math.random()*total
    for _,e in ipairs(pool) do r=r-e.w;if r<=0 then return e.key,e.m end end
    local e=pool[#pool];return e.key,e.m
end
local function rollQuality() local total=0;for _,q in ipairs(Config.Quality or {}) do total=total+(tonumber(q.chance) or 0) end;local r=math.random()*math.max(total,1);local c=Config.Quality[1];for _,q in ipairs(Config.Quality or {}) do r=r-(tonumber(q.chance) or 0);if r<=0 then c=q;break end end;return math.random(tonumber(c.min) or 1,tonumber(c.max) or 1),c end
local function qualityForPurity(p) for _,q in ipairs(Config.Quality or {}) do if p>=(q.min or 0) and p<=(q.max or 100) then return q end end;return {key='normal',label='보통'} end


local function ensureMiningSeasonRankTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_mining_current (
            citizenid VARCHAR(64) NOT NULL,
            mineral VARCHAR(40) NOT NULL,
            best_purity INT NOT NULL DEFAULT 0,
            mined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(citizenid,mineral),
            INDEX idx_rank_mining_purity(best_purity)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
end

CreateThread(function()
    Wait(2200)
    pcall(ensureMiningSeasonRankTable)
end)

local function updateMiningSeasonRank(citizenid,mineral,purity)
    if not citizenid then return end
    ensureMiningSeasonRankTable()
    MySQL.query.await([[
        INSERT INTO cookie_ranking_mining_current(citizenid,mineral,best_purity,mined_at)
        VALUES (?,?,?,NOW())
        ON DUPLICATE KEY UPDATE
            mined_at=IF(VALUES(best_purity)>best_purity,NOW(),mined_at),
            best_purity=GREATEST(best_purity,VALUES(best_purity))
    ]],{citizenid,mineral,tonumber(purity) or 0})
end

RegisterNetEvent('cookie_mining:server:start',function(zoneId,idx,pickaxeItem)
    local src=source
    if not cookieAllowAction(src,'mining_start',700,1) then return end
    if pending[src] then return end
    local z=currentMiningZone(src,zoneId)
    idx=math.floor(tonumber(idx) or 0)
    if not z then return notify(src,'등록된 광산 범위가 아닙니다',true) end
    if idx<1 or idx>systemSettings.nodeCount then return notify(src,'올바른 바위를 찾을 수 없습니다',true) end
    if not nodeNear(src,z,idx) then return notify(src,'바위에 조금 더 가까이 가주세요',true) end

    local pickaxeKey,pickaxe=equippedPickaxe(src,pickaxeItem)
    if not pickaxe then return notify(src,'퀵슬롯에서 사용할 곡괭이를 먼저 들어주세요',true) end

    local st=nodeState(z.id,idx)
    if st.busyBy then return notify(src,'누군가 이미 채굴 중입니다',true) end
    if (st.cooldownUntil or 0)>GetGameTimer() then return notify(src,'이 바위는 아직 재생 중입니다',true) end

    st.busyBy=src
    pending[src]={zoneId=z.id,nodeIndex=idx,phase='rhythm',pickaxeKey=pickaxeKey,pickaxeItem=pickaxe.item,pickaxeLabel=pickaxe.label,activityStartedAt=GetGameTimer()}
    broadcastNode(z.id,idx)
    TriggerClientEvent('cookie_mining:client:rhythm',src,{nodeIndex=idx,rhythmRounds=systemSettings.rhythmRounds,pickaxeLabel=pickaxe.label})
end)
RegisterNetEvent('cookie_mining:server:rhythmResult',function(success)
    local src=source;if not cookieAllowAction(src,'mining_rhythm',300,1) then return end;local j=pending[src];if not j or j.phase~='rhythm' then return end
    j.rhythmSuccess=success==true
    local mult=pickaxeMultiplier(j.pickaxeKey)
    local raw=j.rhythmSuccess and systemSettings.rhythmSuccessMs or systemSettings.mineDurationMs
    j.durationMs=math.max(1000,math.floor(raw*mult))
    j.startedAt=GetGameTimer();j.phase='mining'
    TriggerClientEvent('cookie_mining:client:mineStart',src,{nodeIndex=j.nodeIndex,duration=j.durationMs,rhythmSuccess=j.rhythmSuccess,pickaxeLabel=j.pickaxeLabel})
end)
RegisterNetEvent('cookie_mining:server:finish',function(success)
    local src=source;if not cookieAllowAction(src,'mining_finish',800,1) then return end;local j=pending[src];pending[src]=nil;if not j then return end;local st=nodeState(j.zoneId,j.nodeIndex);if st.busyBy==src then st.busyBy=nil end
    local activeMs=GetGameTimer()-(tonumber(j.activityStartedAt) or GetGameTimer())
    local activeSec=math.max(1,math.min(180,math.floor(activeMs/1000)))
    TriggerEvent('cookie_admin:server:openActivityAccrueInternal',src,'mining',activeSec)
    if success~=true then broadcastNode(j.zoneId,j.nodeIndex);return end;local z=currentMiningZone(src,j.zoneId);if not z then broadcastNode(j.zoneId,j.nodeIndex);return notify(src,'광산 범위 밖으로 이동했습니다',true) end
    if not j.pickaxeItem or itemCount(src,j.pickaxeItem)<=0 then broadcastNode(j.zoneId,j.nodeIndex);return notify(src,'사용하던 곡괭이가 없습니다',true) end
    local elapsed=GetGameTimer()-(j.startedAt or 0);if elapsed<math.max(1000,(j.durationMs or 20000)-1000) then broadcastNode(j.zoneId,j.nodeIndex);return end
    local key,m=rollMineral(j.zoneId);if not key then broadcastNode(j.zoneId,j.nodeIndex);return notify(src,'이 광산에 출현하도록 설정된 광물이 없습니다',true) end;local purity,q=rollQuality();local rar=Config.Rarity[m.rarity] or {label=m.rarity}
    local meta={label=('%s (%d%%)'):format(m.label,purity),mineral=key,purity=purity,quality=q.key,qualityLabel=q.label,rarity=m.rarity,rarityLabel=rar.label,mineZoneId=z.id,mineZoneLabel=z.label}
    local added=false;pcall(function() added=exports.ox_inventory:AddItem(src,'mineral_'..key,1,meta) end);if not added then broadcastNode(j.zoneId,j.nodeIndex);return notify(src,'가방 공간이 부족합니다',true) end

    -- V13.4: 성공 채굴만 광질 숙련도에 누적합니다.
    pcall(function()
        exports.cookie_skill:addExp(
            src,
            tostring(Config.SkillKey or 'mining'),
            math.max(1, math.floor(tonumber(Config.SkillExpPerSuccess) or 1))
        )
    end)

    local cid=playerCitizenId(src);if cid then
        MySQL.query.await([[INSERT INTO cookie_mining_collection(citizenid,mineral,mined_count,best_purity) VALUES(?,?,1,?) ON DUPLICATE KEY UPDATE mined_count=mined_count+1,best_purity=GREATEST(best_purity,VALUES(best_purity)),last_mined_at=CURRENT_TIMESTAMP]],{cid,key,purity})
        updateMiningSeasonRank(cid,key,purity)
    end
    st.cooldownUntil=GetGameTimer()+systemSettings.respawnMs;broadcastNode(j.zoneId,j.nodeIndex);notify(src,('%s 획득 · %s / 순도 %d%%'):format(m.label,q.label,purity),false)
end)

-- 광물 관리인: 낚시 관리인과 동일한 NPC별 판매/매입 구조
local function validManagerNpc(id)
    id=math.floor(tonumber(id) or 0)
    if id<=0 then return nil end
    local row=MySQL.single.await([[
        SELECT id,label,job_key,x,y,z
        FROM cookie_npc
        WHERE id=? AND is_active=1
        LIMIT 1
    ]],{id})
    if not row then return nil end
    local job=tostring(row.job_key or ''):lower()
    if job~='mining' and job~='miner' and job~='mineral' then return nil end
    return row
end

local function managerNear(src,npc,maxDist)
    if not npc then return false end
    local ped=GetPlayerPed(src);if not ped or ped==0 then return false end
    local pos=GetEntityCoords(ped)
    return #(pos-vec3(tonumber(npc.x) or 0.0,tonumber(npc.y) or 0.0,tonumber(npc.z) or 0.0)) <= (tonumber(maxDist) or 5.0)
end

local function managerNpcRowsV162()
    return MySQL.query.await([[
        SELECT id,label,job_key,x,y,z
        FROM cookie_npc
        WHERE is_active=1
          AND LOWER(COALESCE(job_key,'')) IN ('mining','miner','mineral')
        ORDER BY id ASC
    ]]) or {}
end

RegisterNetEvent('cookie_mining:server:requestManagerNpcs',function()
    local src=source
    local rows=managerNpcRowsV162()
    print(('[cookie_mining] manager NPC sync -> src=%s count=%d'):format(src,#rows))
    TriggerClientEvent('cookie_mining:client:managerNpcList',src,rows)
end)

-- dbBool is defined near the top for zone/runtime use.
local function shopRows(npcId)
    local rows=MySQL.query.await('SELECT kind,enabled,price,qty FROM cookie_mining_npc_shop WHERE npc_id=?',{npcId}) or {}
    local map={};for _,r in ipairs(rows) do map[r.kind]=r end
    local out={}
    for _,key in ipairs(Config.PickaxeOrder or {'basic','skilled','expert'}) do
        local d=pickaxeDef(key)
        if d then
            local kind='pickaxe_'..key
            local r=map[kind]
            out[#out+1]={kind=kind,item=d.item,label=d.label,enabled=r==nil and true or dbBool(r.enabled),price=r and math.max(0,tonumber(r.price) or 0) or math.max(0,tonumber((key=='basic' and systemSettings.pickaxeBasicPrice) or (key=='skilled' and systemSettings.pickaxeSkilledPrice) or (key=='expert' and systemSettings.pickaxeExpertPrice) or d.defaultPrice) or 0),qty=r and math.max(1,tonumber(r.qty) or 1) or 1,tier=key,durationMultiplier=pickaxeMultiplier(key)}
        end
    end
    return out
end

local function mineralMap(npcId) local rows=MySQL.query.await('SELECT mineral,enabled,base_price FROM cookie_mining_npc_mineral WHERE npc_id=?',{npcId}) or {};local map={};for _,r in ipairs(rows) do map[r.mineral]=r end;return map end
local function mineralEnabled(key,map) local r=map[key];return r==nil or dbBool(r.enabled) end
local function mineralBasePrice(key,map) local r=map[key];if r and r.base_price~=nil then return math.max(0,math.floor(tonumber(r.base_price) or 0)) end;return math.max(0,math.floor(tonumber(Config.Minerals[key] and Config.Minerals[key].sell) or 0)) end
local function purityMult(purity) local p=math.max(0,math.min(100,tonumber(purity) or 0))/100;return systemSettings.purityMinMultiplier+(systemSettings.purityMaxMultiplier-systemSettings.purityMinMultiplier)*p end
local function mineralValue(key,purity,map) return math.floor(mineralBasePrice(key,map)*purityMult(purity)+0.5) end
local function managerAdminPayload(npcId,label)
    local map=mineralMap(npcId);local minerals={};for key,m in pairs(Config.Minerals) do minerals[#minerals+1]={key=key,label=m.label,rarity=m.rarity,rarityLabel=(Config.Rarity[m.rarity] and Config.Rarity[m.rarity].label) or m.rarity,enabled=mineralEnabled(key,map),basePrice=mineralBasePrice(key,map)} end
    table.sort(minerals,function(a,b) return a.label<b.label end);return {npcId=npcId,label=label,shop=shopRows(npcId),minerals=minerals,purityMinMultiplier=systemSettings.purityMinMultiplier,purityMaxMultiplier=systemSettings.purityMaxMultiplier}
end
local function inventoryMinerals(src,npcId)
    local map=mineralMap(npcId);local out,total,count={},0,0;for key,m in pairs(Config.Minerals) do if mineralEnabled(key,map) then local slots={};pcall(function() slots=exports.ox_inventory:Search(src,'slots','mineral_'..key) or {} end);for _,slot in ipairs(slots) do local c=math.max(1,tonumber(slot.count) or 1);local purity=slot.metadata and tonumber(slot.metadata.purity) or 30;local each=mineralValue(key,purity,map);local v=each*c;out[#out+1]={key=key,label=m.label,slot=slot.slot,count=c,purity=purity,priceEach=each,priceEachText=comma(each),value=v,valueText=comma(v)};total=total+v;count=count+c end end end;table.sort(out,function(a,b) return a.label<b.label end);return out,total,count
end
local function miningPurityLeaderboard(limit)
    limit=math.max(1,math.min(50,tonumber(limit) or 10))
    local db=MySQL.query.await([[
        SELECT c.citizenid,c.mineral,c.best_purity,p.license,u.gobun,u.nickname
        FROM cookie_mining_collection c
        LEFT JOIN players p ON p.citizenid=c.citizenid
        LEFT JOIN cookie_user u ON u.license COLLATE utf8mb4_general_ci=p.license COLLATE utf8mb4_general_ci
        WHERE c.best_purity>0
    ]]) or {}
    local rarityIndex={};for i,k in ipairs(Config.RarityOrder or {}) do rarityIndex[k]=i end
    local bestByCitizen={}
    for _,r in ipairs(db) do
        local m=Config.Minerals[tostring(r.mineral or '')]
        if m then
            local candidate={citizenid=r.citizenid,license=r.license,gobun=tonumber(r.gobun),nickname=r.nickname,mineral=r.mineral,mineralLabel=m.label,purity=tonumber(r.best_purity) or 0,rarity=m.rarity,rarityLabel=(Config.Rarity[m.rarity] and Config.Rarity[m.rarity].label) or m.rarity,rarityRank=rarityIndex[m.rarity] or 0}
            local old=bestByCitizen[r.citizenid]
            if not old or candidate.purity>old.purity or (candidate.purity==old.purity and candidate.rarityRank>old.rarityRank) then bestByCitizen[r.citizenid]=candidate end
        end
    end
    local out={};for _,v in pairs(bestByCitizen) do out[#out+1]=v end
    table.sort(out,function(a,b)
        if a.purity~=b.purity then return a.purity>b.purity end
        if a.rarityRank~=b.rarityRank then return a.rarityRank>b.rarityRank end
        return (tonumber(a.gobun) or 999999999)<(tonumber(b.gobun) or 999999999)
    end)
    local top={};for i=1,math.min(limit,#out) do out[i].rank=i;top[#top+1]=out[i] end
    return top
end

local function managerMiningRecords(src)
    local cid=playerCitizenId(src)
    if not cid then return {discovered=0,total=#(Config.RarityOrder or {}),totalMined=0,rows={}} end
    local db=MySQL.query.await('SELECT mineral,mined_count,best_purity FROM cookie_mining_collection WHERE citizenid=?',{cid}) or {}
    local map={};for _,r in ipairs(db) do map[r.mineral]=r end
    local rows,totalMined,discovered={},0,0
    for key,m in pairs(Config.Minerals) do
        local r=map[key];local cnt=r and (tonumber(r.mined_count) or 0) or 0;local purity=r and (tonumber(r.best_purity) or 0) or 0
        if r then discovered=discovered+1 end;totalMined=totalMined+cnt
        rows[#rows+1]={key=key,label=m.label,rarity=m.rarity,rarityLabel=(Config.Rarity[m.rarity] and Config.Rarity[m.rarity].label) or m.rarity,count=cnt,bestPurity=purity,discovered=r~=nil}
    end
    table.sort(rows,function(a,b) if a.discovered~=b.discovered then return a.discovered end;if a.bestPurity~=b.bestPurity then return a.bestPurity>b.bestPurity end;return a.label<b.label end)
    -- NPC 대화창은 서버 전체 순위 쿼리에 의존하지 않는다.
    -- 순위표는 ESC 전용으로 별도 조회하고, NPC는 개인 기록만 우선 표시한다.
    return {discovered=discovered,total=#rows,totalMined=totalMined,rows=rows,leaderboard={}}
end
local function sendManagerMenu(src,npcId)
    print(('[cookie_mining] manager menu request src=%s npc=%s'):format(src,tostring(npcId)))
    local npc=validManagerNpc(npcId)
    if not npc then
        print(('[cookie_mining] manager menu rejected: invalid npc=%s'):format(tostring(npcId)))
        TriggerClientEvent('cookie_mining:client:managerMenuError',src,'사용할 수 없는 광물 관리인입니다.')
        return notify(src,'사용할 수 없는 광물 관리인입니다',true)
    end
    local minerals,total,count=inventoryMinerals(src,npc.id)
    TriggerClientEvent('cookie_mining:client:managerMenu',src,{npcId=npc.id,label=npc.label,shop=shopRows(npc.id),minerals=minerals,totalValue=total,totalValueText=comma(total),totalCount=count,records=managerMiningRecords(src)})
end
RegisterNetEvent('cookie_mining:server:managerMenu',function(id) sendManagerMenu(source,id) end)
RegisterNetEvent('cookie_mining:server:managerAdminRequest',function(id) local src=source;if not adminLevel(src,3) then return notify(src,'권한이 없습니다',true) end;local n=validManagerNpc(id);if n then TriggerClientEvent('cookie_admin:client:miningAdminData',src,managerAdminPayload(n.id,n.label)) end end)
RegisterNetEvent('cookie_mining:server:managerShopSave',function(d)
    local src=source;if not adminLevel(src,3) then return end;local n=validManagerNpc(d and d.npcId);if not n then return end
    local kind=tostring(d and d.kind or '');local key=kind:match('^pickaxe_(.+)$');local def=key and pickaxeDef(key) or nil;if not def then return notify(src,'잘못된 곡괭이 종류입니다',true) end
    local en=(d.enabled==true or tonumber(d.enabled)==1) and 1 or 0;local price=math.max(0,math.floor(tonumber(d.price) or 0));local qty=math.max(1,math.floor(tonumber(d.qty) or 1))
    MySQL.query.await([[INSERT INTO cookie_mining_npc_shop(npc_id,kind,enabled,price,qty,updated_by) VALUES(?,?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),price=VALUES(price),qty=VALUES(qty),updated_by=VALUES(updated_by)]],{n.id,kind,en,price,qty,adminName(src)})
    TriggerClientEvent('cookie_admin:client:miningAdminData',src,managerAdminPayload(n.id,n.label));notify(src,def.label..' 판매 설정 저장',false)
end)
RegisterNetEvent('cookie_mining:server:managerMineralSave',function(d) local src=source;if not adminLevel(src,3) then return end;local n=validManagerNpc(d and d.npcId);local key=tostring(d and d.key or '');if not n or not Config.Minerals[key] then return end;local en=(d.enabled==true or tonumber(d.enabled)==1) and 1 or 0;local price=math.max(0,math.floor(tonumber(d.basePrice) or 0));MySQL.query.await([[INSERT INTO cookie_mining_npc_mineral(npc_id,mineral,enabled,base_price,updated_by) VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),base_price=VALUES(base_price),updated_by=VALUES(updated_by)]],{n.id,key,en,price,adminName(src)});TriggerClientEvent('cookie_admin:client:miningAdminData',src,managerAdminPayload(n.id,n.label));notify(src,Config.Minerals[key].label..' 매입 설정 저장',false) end)
RegisterNetEvent('cookie_mining:server:buy',function(kind,npcId)
    local src=source;if not cookieAllowAction(src,'mining_buy',700,1) then return end;kind=tostring(kind or '');local key=kind:match('^pickaxe_(.+)$');local def=key and pickaxeDef(key) or nil;if not def then return end
    local n=validManagerNpc(npcId);if not n or not managerNear(src,n,6.0) then return notify(src,'광물 관리인 근처에서만 이용할 수 있습니다',true) end;local selected=nil;for _,row in ipairs(shopRows(n.id)) do if row.kind==kind then selected=row break end end
    if not selected or not selected.enabled then return notify(src,'이 관리인은 해당 곡괭이를 판매하지 않습니다',true) end
    local p=exports.qbx_core:GetPlayer(src);if not p then return end
    local can=true;pcall(function() can=exports.ox_inventory:CanCarryItem(src,selected.item,selected.qty) end);if not can then return notify(src,'가방 공간이 부족합니다',true) end
    local paid=p.Functions.RemoveMoney('cash',selected.price,'곡괭이 구매');if not paid then return notify(src,'현금이 부족합니다',true) end
    local ok=false;pcall(function() ok=exports.ox_inventory:AddItem(src,selected.item,selected.qty) end);if not ok then p.Functions.AddMoney('cash',selected.price,'곡괭이 구매 환불');return notify(src,'지급 실패로 환불했습니다',true) end
    notify(src,('%s %d개 구매 · %s원'):format(selected.label,selected.qty,comma(selected.price)),false);sendManagerMenu(src,n.id)
end)
RegisterNetEvent('cookie_mining:server:sellOne',function(npcId,key,slotId)
    local src=source;if not cookieAllowAction(src,'mining_sell_one',500,1) then return end
    local n=validManagerNpc(npcId);key=tostring(key or '');slotId=tonumber(slotId)
    if not n or not managerNear(src,n,6.0) or not Config.Minerals[key] or not slotId then return end
    local map=mineralMap(n.id);if not mineralEnabled(key,map) then return notify(src,'이 관리인은 해당 광물을 매입하지 않습니다',true) end
    local slots=exports.ox_inventory:Search(src,'slots','mineral_'..key) or {};local target=nil
    for _,slot in ipairs(slots) do if tonumber(slot.slot)==slotId then target=slot;break end end
    if not target then return end
    local c=tonumber(target.count) or 1;local purity=target.metadata and tonumber(target.metadata.purity) or 30
    local value=mineralValue(key,purity,map)*c
    local ok=exports.ox_inventory:RemoveItem(src,'mineral_'..key,c,nil,slotId);if not ok then return end
    local p=exports.qbx_core:GetPlayer(src);if not p then pcall(function() exports.ox_inventory:AddItem(src,'mineral_'..key,c,target.metadata) end);return end
    local okPay,paid=pcall(function() return p.Functions.AddMoney('cash',value,'광물 판매') end)
    if not okPay or paid==false then
        pcall(function() exports.ox_inventory:AddItem(src,'mineral_'..key,c,target.metadata) end)
        return notify(src,'판매금 지급에 실패해 광물을 돌려드렸습니다',true)
    end
    notify(src,('%s 순도 %d%% 판매 · %s원'):format(Config.Minerals[key].label,purity,comma(value)),false);sendManagerMenu(src,n.id)
end)
RegisterNetEvent('cookie_mining:server:sellAll',function(npcId)
    local src=source;if not cookieAllowAction(src,'mining_sell_all',1200,1) then return end
    local n=validManagerNpc(npcId);if not n or not managerNear(src,n,6.0) then return notify(src,'광물 관리인 근처에서만 이용할 수 있습니다',true) end
    local map=mineralMap(n.id);local total,count=0,0;local removed={}
    for key,_ in pairs(Config.Minerals) do
        if mineralEnabled(key,map) then
            local slots=exports.ox_inventory:Search(src,'slots','mineral_'..key) or {}
            for _,slot in ipairs(slots) do
                local c=tonumber(slot.count) or 1;local purity=slot.metadata and tonumber(slot.metadata.purity) or 30
                local value=mineralValue(key,purity,map)*c
                local ok=exports.ox_inventory:RemoveItem(src,'mineral_'..key,c,nil,slot.slot)
                if ok then removed[#removed+1]={item='mineral_'..key,count=c,metadata=slot.metadata};total=total+value;count=count+c end
            end
        end
    end
    if count<=0 then return notify(src,'판매할 광물이 없습니다',true) end
    local p=exports.qbx_core:GetPlayer(src);local okPay,paid=false,false
    if p then okPay,paid=pcall(function() return p.Functions.AddMoney('cash',total,'광물 판매') end) end
    if not okPay or paid==false then
        for _,r in ipairs(removed) do pcall(function() exports.ox_inventory:AddItem(src,r.item,r.count,r.metadata) end) end
        return notify(src,'판매금 지급에 실패해 판매한 광물을 복구했습니다',true)
    end
    notify(src,('광물 %d개 판매 · %s원'):format(count,comma(total)),false);sendManagerMenu(src,n.id)
end)

-- F3 광산별 출현 광물 설정
local function zoneSettingsPayload(zoneId)
    local z=miningZoneById(zoneId);if not z then return nil end
    local db=zoneMineralRows(z.id)
    if #db>0 then
        local _,total=configuredMineralPool(db)
        if total<=0 then
            repairBrokenZoneMinerals(z.id)
            db=zoneMineralRows(z.id)
        end
    end
    local map={};for _,r in ipairs(db) do map[r.mineral]=r end
    local ri={};for i,k in ipairs(Config.RarityOrder or {}) do ri[k]=i end;local out={}
    for key,m in pairs(Config.Minerals) do local r=map[key];out[#out+1]={key=key,label=m.label,rarity=m.rarity,rarityLabel=(Config.Rarity[m.rarity] and Config.Rarity[m.rarity].label) or m.rarity,rarityColor=(Config.Rarity[m.rarity] and Config.Rarity[m.rarity].color) or '#999',enabled=r==nil and true or dbBool(r.enabled),weight=r and tonumber(r.weight) or tonumber(m.weight) or 1,defaultWeight=tonumber(m.weight) or 1} end
    table.sort(out,function(a,b)local ai,bi=ri[a.rarity] or 999,ri[b.rarity] or 999;if ai==bi then return a.label<b.label end;return ai<bi end)
    return {zoneId=z.id,label=z.label,minerals=out,rarityOrder=Config.RarityOrder}
end

RegisterNetEvent('cookie_mining:server:zoneSettingsRequest',function(id)
    local src=source;id=tonumber(id)
    if not adminLevel(src,5) then TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.');return end
    if not id then TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'광산 ID가 올바르지 않습니다.');return end
    local d=zoneSettingsPayload(id)
    if not d then TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'광산 범위를 찾을 수 없습니다.');return end
    print(('[cookie_mining] zone settings -> src=%s zone=%s minerals=%s'):format(src,id,#(d.minerals or {})))
    TriggerClientEvent('cookie_admin:client:miningZoneSettingsData',src,d)
end)

RegisterNetEvent('cookie_mining:server:zoneSettingsSave',function(d)
    local src=source
    if not adminLevel(src,5) then TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.');return end
    local id=tonumber(d and d.zoneId)
    if not miningZoneById(id) then TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'광산 범위를 찾을 수 없습니다.');return end
    if type(d and d.minerals)~='table' or #d.minerals==0 then TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'저장할 광물 설정이 없습니다.');return end
    local inc={};local any=false
    for _,r in ipairs(d.minerals or {}) do
        local key=tostring(r.key or '')
        if Config.Minerals[key] then
            local enabled=(r.enabled==true or tonumber(r.enabled)==1) and 1 or 0
            local weight=math.max(0,tonumber(r.weight) or 0)
            inc[key]={enabled=enabled,weight=weight}
            if enabled==1 and weight>0 then any=true end
        end
    end
    if not any then TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'최소 1종 이상의 광물을 ON으로 설정하고 가중치를 0보다 크게 입력하세요.');return end
    for key,_ in pairs(Config.Minerals) do
        local r=inc[key]
        if r then
            MySQL.query.await([[INSERT INTO cookie_mining_zone_mineral(zone_id,mineral,enabled,weight,updated_by) VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),weight=VALUES(weight),updated_by=VALUES(updated_by)]],{id,key,r.enabled,r.weight,adminName(src)})
        end
    end
    local payload=zoneSettingsPayload(id)
    print(('[cookie_mining] zone settings saved -> src=%s zone=%s'):format(src,id))
    TriggerClientEvent('cookie_admin:client:miningZoneSettingsData',src,payload)
    notify(src,'광산 출현 광물 설정 저장',false)
end)

exports('getZoneSettings',function(src,zoneId)
    src=tonumber(src) or 0
    if src~=0 and not adminLevel(src,5) then return nil,'권한이 없습니다' end
    local res=zoneSettingsPayload(zoneId)
    if not res then return nil,'광산 범위를 찾을 수 없습니다' end
    return res
end)
exports('saveZoneSettings',function(src,d)
    src=tonumber(src) or 0
    if src~=0 and not adminLevel(src,5) then return false,'권한이 없습니다' end
    d=d or {};local id=tonumber(d.zoneId);if not miningZoneById(id) then return false,'광산 범위를 찾을 수 없습니다' end
    if type(d.minerals)~='table' or #d.minerals==0 then return false,'저장할 광물 설정이 없습니다' end
    local inc={};for _,r in ipairs(d.minerals) do local key=tostring(r.key or '');if Config.Minerals[key] then inc[key]={enabled=(r.enabled==true or tonumber(r.enabled)==1) and 1 or 0,weight=math.max(0,tonumber(r.weight) or 0)} end end
    for key,m in pairs(Config.Minerals) do local r=inc[key];if r then MySQL.query.await([[INSERT INTO cookie_mining_zone_mineral(zone_id,mineral,enabled,weight,updated_by) VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),weight=VALUES(weight),updated_by=VALUES(updated_by)]],{id,key,r.enabled,r.weight,src==0 and 'console' or adminName(src)}) end end
    return true,zoneSettingsPayload(id)
end)

local function buildCollectionPayload(src)
    local cid=playerCitizenId(src);local rows=cid and (MySQL.query.await('SELECT mineral,mined_count,best_purity,first_mined_at,last_mined_at FROM cookie_mining_collection WHERE citizenid=?',{cid}) or {}) or {};local mine,total,disc={},0,0;local best=nil
    for _,r in ipairs(rows) do mine[r.mineral]=r;local c=tonumber(r.mined_count) or 0;local p=tonumber(r.best_purity) or 0;total=total+c;disc=disc+1;if not best or p>best.purity then local m=Config.Minerals[r.mineral];best={key=r.mineral,label=m and m.label or r.mineral,purity=p,qualityLabel=qualityForPurity(p).label} end end
    local ri={};for i,k in ipairs(Config.RarityOrder or {}) do ri[k]=i end;local out={};for key,m in pairs(Config.Minerals) do local r=mine[key];local bp=r and tonumber(r.best_purity) or 0;local rr=Config.Rarity[m.rarity] or {};out[#out+1]={key=key,label=m.label,rarity=m.rarity,rarityLabel=rr.label,rarityColor=rr.color,discovered=r~=nil,minedCount=r and tonumber(r.mined_count) or 0,bestPurity=bp,bestQualityLabel=bp>0 and qualityForPurity(bp).label or nil,firstMinedAt=r and r.first_mined_at,lastMinedAt=r and r.last_mined_at} end;table.sort(out,function(a,b)local ai,bi=ri[a.rarity] or 999,ri[b.rarity] or 999;if ai==bi then return a.label<b.label end;return ai<bi end);return {minerals=out,rarityOrder=Config.RarityOrder,summary={discovered=disc,total=#out,totalMined=total,personalBest=best},quality=Config.Quality}
end
RegisterNetEvent('cookie_mining:server:collectionRequest',function() TriggerClientEvent('cookie_admin:client:miningCollectionData',source,buildCollectionPayload(source)) end)
exports('getCollectionData',function(src) return buildCollectionPayload(tonumber(src) or 0) end)
exports('getPurityLeaderboard',function(limit) return miningPurityLeaderboard(limit) end)

AddEventHandler('playerDropped',function() local src=source;local j=pending[src];pending[src]=nil;if j then local s=nodeState(j.zoneId,j.nodeIndex);if s.busyBy==src then s.busyBy=nil;broadcastNode(j.zoneId,j.nodeIndex) end end end)

print('[cookie_mining] ROCK INTERACTION HARD FIX V1.5.9 active')


-- ============================================================
-- ESC 상시 순위표용: 광물 최고 순도 TOP
-- 순도 DESC -> 희귀도 DESC -> 고번 ASC
-- 이벤트 집계와 무관하며 cookie_mining_collection의 영구 기록을 사용한다.
-- ============================================================
local ESC_MINERAL_RARITY_RANK_V160={common=1,uncommon=2,rare=3,epic=4,legendary=5}
local ESC_MINERAL_RARITY_LABEL_V160={common='일반',uncommon='고급',rare='희귀',epic='영웅',legendary='전설'}

local function escMineralPurityRankingV160(limit)
    limit=math.max(1,math.min(50,math.floor(tonumber(limit) or 10)))
    local rows=MySQL.query.await([[
        SELECT c.citizenid,c.mineral,c.best_purity,p.license,u.gobun,u.nickname
        FROM cookie_mining_collection c
        LEFT JOIN players p ON p.citizenid=c.citizenid
        LEFT JOIN cookie_user u ON u.license COLLATE utf8mb4_general_ci=p.license COLLATE utf8mb4_general_ci
        WHERE c.best_purity>0
    ]]) or {}

    local best={}
    for _,r in ipairs(rows) do
        local cfg=Config.Minerals[tostring(r.mineral or '')]
        if cfg then
            local rarity=tostring(cfg.rarity or 'common')
            local cand={
                citizenid=r.citizenid, license=r.license,
                gobun=tonumber(r.gobun), nickname=r.nickname,
                mineral=tostring(r.mineral), mineralLabel=cfg.label or tostring(r.mineral),
                rarity=rarity, rarityLabel=ESC_MINERAL_RARITY_LABEL_V160[rarity] or rarity,
                rarityRank=ESC_MINERAL_RARITY_RANK_V160[rarity] or 0,
                purity=tonumber(r.best_purity) or 0,
            }
            local old=best[tostring(r.citizenid)]
            if not old or cand.purity>old.purity or (cand.purity==old.purity and cand.rarityRank>old.rarityRank) then
                best[tostring(r.citizenid)]=cand
            end
        end
    end

    local all={}
    for _,v in pairs(best) do all[#all+1]=v end
    table.sort(all,function(a,b)
        if a.purity~=b.purity then return a.purity>b.purity end
        if a.rarityRank~=b.rarityRank then return a.rarityRank>b.rarityRank end
        return (tonumber(a.gobun) or 999999999)<(tonumber(b.gobun) or 999999999)
    end)
    local out={}
    for i=1,math.min(limit,#all) do
        local v=all[i];v.rank=i;out[#out+1]=v
    end
    return out
end

exports('getPurityRanking',function(limit)
    return escMineralPurityRankingV160(limit)
end)

RegisterNetEvent('cookie_mining:server:requestPurityRanking',function(limit)
    local src=source
    TriggerClientEvent('cookie_mining:client:purityRanking',src,escMineralPurityRankingV160(limit))
end)

print('[cookie_mining] ESC MINERAL PURITY RANK V1.6.0 ready')

print('[cookie_mining] MANAGER NPC SERVER FIX V1.6.2 ready')

print('[cookie_mining] NPC DIALOG SERVER HOTFIX V1.6.7 ready')

print('[cookie_mining] ESC SEASON RANK V1.7.1 active')

print('[cookie_mining] QUICK SLOT PICKAXE EQUIP V1.7.5 ready')
print('^2[cookie_mining]^7 ROCK SERVER POSITION SYNC V1.7.6 active')
print('^2[cookie_mining]^7 F3 MINING SKILL EXP V13.4 active')
