

local T = Config.Fishing

-- 낚시 장비 3단계 체계
-- 기존 fishingrod / fishingrod_pro / fishingbait / fishingbait_pro ID는 그대로 유지한다.
local FISH_GEAR = {
    rods = {
        beginner = { kind='rod',    item=(T.Items and T.Items.rod) or 'fishingrod',         label='초급 낚싯대', biteScale=1.00, gameScale=1.00 },
        middle   = { kind='rodMid', item=(T.Items and T.Items.rodMid) or 'fishingrod_mid',  label='중급 낚싯대', biteScale=0.85, gameScale=1.10 },
        advanced = { kind='rodPro', item=(T.Items and T.Items.rodPro) or 'fishingrod_pro',  label='고급 낚싯대', biteScale=0.70, gameScale=1.20 },
    },
    baits = {
        beginner = { kind='bait',    item=(T.Items and T.Items.bait) or 'fishingbait',         label='초급 미끼', rareBoost=1.00 },
        middle   = { kind='baitMid', item=(T.Items and T.Items.baitMid) or 'fishingbait_mid',  label='중급 미끼', rareBoost=1.15 },
        advanced = { kind='baitPro', item=(T.Items and T.Items.baitPro) or 'fishingbait_pro',  label='고급 미끼', rareBoost=1.35 },
    },
}
local function shopNum(key)
    return math.max(0, math.floor(tonumber((T.Shop or {})[key]) or 0))
end
local function midPrice(a,b)
    a,b=shopNum(a),shopNum(b)
    if a>0 and b>0 then return math.floor((a+b)/2) end
    return math.max(a,b)
end

local function flog(...) if Config.Fishing.Debug then  end end
local function notify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

local adminPrice  = {}
local adminWeight = {}
local gradeWeights = {
    shore = {},
    boat = {},
}


-- ─────────────────────────────────────────────────────────────
-- V2 취미 낚시: 관리자 생성 낚시 포인트 + 서식지별 어종 + 무게 희귀도
-- 낚시는 cookie_safezone의 type='fishing' 포인트 안에서만 가능하다.
-- 포인트 생성 시 fishingRegion을 직접 지정한다.
-- ─────────────────────────────────────────────────────────────
local FISHING_REGION_LABELS = {
    freshwater = '알라모해 · 내륙 수역',
    coast = '일반 연안',
    north = '북부 연안',
    west = '서부 연안',
    south = '남부 연안',
    east = '동부 연안',
    city = '로스 산토스 연안',
    offshore = '외해 · 심해',
}

local FRESHWATER = {
    ['붕어']=true, ['잉어']=true, ['미꾸라지']=true, ['메기']=true, ['블루길']=true,
    ['빙어']=true, ['배스']=true, ['은어']=true, ['연어']=true, ['장어']=true, ['철갑상어']=true,
}
local DEEP_ONLY = {
    ['실러캔스']=true, ['개복치']=true, ['산갈치']=true, ['만타가오리']=true,
    ['백상아리']=true, ['청상아리']=true, ['귀상어']=true,
    ['범고래']=true, ['대왕고래']=true, ['향유고래']=true, ['일각고래']=true, ['밍크고래']=true,
    ['크라켄']=true, ['레비아탄']=true, ['메갈로돈']=true,
}

local REGION_PREFERRED = {
    north = { ['빙어']=true,['연어']=true,['대구']=true,['방어']=true,['삼치']=true,['고등어']=true,['노래미']=true,['우럭']=true,['광어']=true,['청상아리']=true,['밍크고래']=true,['일각고래']=true },
    west  = { ['우럭']=true,['광어']=true,['감성돔']=true,['도미']=true,['참돔']=true,['돌돔']=true,['다금바리']=true,['참치']=true,['청새치']=true,['황새치']=true,['만새기']=true,['백상아리']=true,['만타가오리']=true },
    south = { ['쭈꾸미']=true,['문어']=true,['오징어']=true,['갈치']=true,['병어']=true,['전어']=true,['학꽁치']=true,['고등어']=true,['민어']=true,['참치']=true,['개복치']=true },
    east  = { ['숭어']=true,['농어']=true,['가시복어']=true,['쥐치']=true,['도미']=true,['참돔']=true,['달고기']=true,['돗돔']=true,['붉바리']=true,['실러캔스']=true },
    city  = { ['불가사리']=true,['해파리']=true,['쥐치']=true,['병어']=true,['갈치']=true,['숭어']=true,['전어']=true,['고등어']=true,['농어']=true },
    offshore = { ['참치']=true,['청새치']=true,['황새치']=true,['만새기']=true,['실러캔스']=true,['개복치']=true,['산갈치']=true,['만타가오리']=true,['백상아리']=true,['청상아리']=true,['귀상어']=true,['범고래']=true,['대왕고래']=true,['향유고래']=true,['일각고래']=true,['밍크고래']=true,['크라켄']=true,['레비아탄']=true,['메갈로돈']=true },
}

local function speciesRegionMultiplier(label, regionKey)
    regionKey = tostring(regionKey or 'coast')
    if regionKey == 'freshwater' then return FRESHWATER[label] and 3.5 or 0.0 end
    if FRESHWATER[label] then return 0.0 end
    if DEEP_ONLY[label] and regionKey ~= 'offshore' then return 0.0 end
    if regionKey == 'coast' then return 1.0 end
    local pref = REGION_PREFERRED[regionKey]
    return (pref and pref[label]) and 3.25 or 1.0
end

local function speciesRegions(label)
    if FRESHWATER[label] then return { FISHING_REGION_LABELS.freshwater } end
    if DEEP_ONLY[label] then return { FISHING_REGION_LABELS.offshore } end
    local out = { FISHING_REGION_LABELS.coast }
    for _, key in ipairs({ 'north','west','south','east','city','offshore' }) do
        if REGION_PREFERRED[key] and REGION_PREFERRED[key][label] then out[#out+1] = FISHING_REGION_LABELS[key] end
    end
    return out
end

local function gradeWeightOf(kind, grade)
    local custom = gradeWeights[kind] and gradeWeights[kind][grade]
    if custom ~= nil then return tonumber(custom) or 0 end
    return tonumber((T.ZoneWeights[kind] or {})[grade]) or 0
end

local function ppkOf(key)
    if adminPrice[key] ~= nil then return adminPrice[key] end
    local f = T.Fish[key]; return f and f.ppk or 0
end
local function weightOf(key)
    if adminWeight[key] ~= nil then return adminWeight[key] end
    local f = T.Fish[key]; return f and f.w or 1
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_fishing_hof (
                id         INT PRIMARY KEY DEFAULT 1,
                citizenid  VARCHAR(60)  NULL,
                gobun      VARCHAR(20)  NULL,
                nickname   VARCHAR(60)  NULL,
                species    VARCHAR(40)  NULL,   -- 물고기 key
                label      VARCHAR(40)  NULL,   -- 표시명
                kg         DOUBLE       NOT NULL DEFAULT 0,
                caught_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])

        MySQL.query.await('INSERT IGNORE INTO cookie_fishing_hof (id, kg) VALUES (1, 0)')
    end)
    if ok then
    else  end
end)

CreateThread(function()
    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_fishing_collection (
                citizenid       VARCHAR(60) NOT NULL,
                species         VARCHAR(40) NOT NULL,
                caught_count    INT NOT NULL DEFAULT 0,
                best_kg         DOUBLE NOT NULL DEFAULT 0,
                first_region    VARCHAR(32) NULL,
                last_region     VARCHAR(32) NULL,
                first_caught_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                last_caught_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (citizenid, species)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_fishing_species_record (
                species    VARCHAR(40) PRIMARY KEY,
                citizenid  VARCHAR(60) NULL,
                gobun      VARCHAR(20) NULL,
                nickname   VARCHAR(60) NULL,
                best_kg    DOUBLE NOT NULL DEFAULT 0,
                region_key VARCHAR(32) NULL,
                caught_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)
end)

CreateThread(function()
    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_fishing_zone_fish (
                zone_id      INT NOT NULL,
                species      VARCHAR(40) NOT NULL,
                enabled      TINYINT(1) NOT NULL DEFAULT 1,
                weight       DECIMAL(10,3) NOT NULL DEFAULT 1,
                updated_by   VARCHAR(60) NULL,
                updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (zone_id, species),
                INDEX idx_fishing_zone (zone_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)
end)

local pending = {}

local function cookieAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function() return exports.cookie_core:Allow(src, key, windowMs, maxCount) end)
        if ok then return allowed == true end
    end
    return true
end

local function fitem(key) return 'fish_' .. key end

local function itemCount(src, item)
    local ok, n = pcall(function() return exports.ox_inventory:GetItemCount(src, item) end)
    return (ok and tonumber(n)) or 0
end

local function bestRod(src)
    for _,tier in ipairs({'advanced','middle','beginner'}) do
        local d=FISH_GEAR.rods[tier]
        if d and itemCount(src,d.item)>0 then return tier,d end
    end
    return nil,nil
end
local function rodByItem(src,itemName)
    itemName=tostring(itemName or '')
    if itemName=='' then return nil,nil end
    for _,tier in ipairs({'advanced','middle','beginner'}) do
        local d=FISH_GEAR.rods[tier]
        if d and d.item==itemName and itemCount(src,d.item)>0 then return tier,d end
    end
    return nil,nil
end
local function bestBait(src)
    for _,tier in ipairs({'advanced','middle','beginner'}) do
        local d=FISH_GEAR.baits[tier]
        if d and itemCount(src,d.item)>0 then return tier,d end
    end
    return nil,nil
end
local function hasRodAny(src) local _,d=bestRod(src); return d~=nil end
local function hasBaitAny(src) local _,d=bestBait(src); return d~=nil end
local function baitGradeMultiplier(grade,baitTier)
    if baitTier=='beginner' or not baitTier then return 1.0 end
    local rank=1
    for i,g in ipairs(T.GradeOrder or {}) do if g==grade then rank=i break end end
    -- basic/intermediate/advanced는 큰 변화 없이, 희귀 이상부터 단계적으로 보너스를 준다.
    if rank<=3 then return 1.0 end
    local base=(baitTier=='advanced') and 0.12 or 0.06
    return 1.0 + base * (rank-3)
end

local function pointInPoly2D(px,py,points)
    if type(points)~='table' or #points<3 then return false end
    local inside=false
    local j=#points
    for i=1,#points do
        local a,b=points[i],points[j]
        local ax,ay=tonumber(a.x),tonumber(a.y)
        local bx,by=tonumber(b.x),tonumber(b.y)
        if ax and ay and bx and by then
            local cross=((ay>py)~=(by>py)) and (px < (bx-ax)*(py-ay)/((by-ay)==0 and 0.000001 or (by-ay))+ax)
            if cross then inside=not inside end
        end
        j=i
    end
    return inside
end

local function pointInFishingZone(pos, z)
    if z.shape == 'sphere' then
        local dx,dy,dz=pos.x-(tonumber(z.cx) or 0),pos.y-(tonumber(z.cy) or 0),pos.z-(tonumber(z.cz) or 0)
        local r=tonumber(z.radius) or 0.0
        return (dx*dx+dy*dy+dz*dz)<=(r*r)
    end

    if z.shape == 'poly' then
        local pts=z.polyPoints
        if type(pts)~='table' or #pts<3 then return false end
        local baseZ=tonumber(z.cz) or tonumber(pts[1] and pts[1].z) or pos.z
        local hz=(tonumber(z.height) or 40.0)*0.5
        if math.abs(pos.z-baseZ)>hz then return false end
        return pointInPoly2D(pos.x,pos.y,pts)
    end

    -- box
    local dx,dy=pos.x-(tonumber(z.cx) or 0),pos.y-(tonumber(z.cy) or 0)
    local rad=math.rad(-(tonumber(z.heading) or 0.0))
    local cs,sn=math.cos(rad),math.sin(rad)
    local lx=dx*cs-dy*sn
    local ly=dx*sn+dy*cs
    local hz=(tonumber(z.height) or 40.0)*0.5
    return math.abs(lx)<=((tonumber(z.length) or 0.0)*0.5)
       and math.abs(ly)<=((tonumber(z.width) or 0.0)*0.5)
       and math.abs(pos.z-(tonumber(z.cz) or 0))<=hz
end

local function currentZone(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local pos = GetEntityCoords(ped)

    local ok, rows = pcall(function()
        return exports.cookie_safezone:getZones()
    end)
    if ok and type(rows) == 'table' then
        for _, z in ipairs(rows) do
            if z.type == 'fishing' and pointInFishingZone(pos, z) then
                local kind = (z.fishingType == 'boat') and 'boat' or 'shore'
                local regionKey = tostring(z.fishingRegion or ((kind == 'boat') and 'offshore' or 'coast'))
                return {
                    kind = kind,
                    label = z.label,
                    id = z.id,
                    regionKey = regionKey,
                    regionLabel = FISHING_REGION_LABELS[regionKey] or '일반 연안',
                    x = pos.x, y = pos.y,
                }
            end
        end
    end

    return nil
end

local function fishingZoneById(zoneId)
    zoneId = tonumber(zoneId)
    if not zoneId then return nil end
    local ok, rows = pcall(function() return exports.cookie_safezone:getZones() end)
    if not ok or type(rows) ~= 'table' then return nil end
    for _, z in ipairs(rows) do
        if tonumber(z.id) == zoneId and z.type == 'fishing' then return z end
    end
    return nil
end

local function zoneFishRows(zoneId)
    return MySQL.query.await('SELECT species, enabled, weight FROM cookie_fishing_zone_fish WHERE zone_id = ?', { tonumber(zoneId) }) or {}
end

local function zoneHasCustomFish(zoneId)
    local row = MySQL.single.await('SELECT zone_id FROM cookie_fishing_zone_fish WHERE zone_id = ? LIMIT 1', { tonumber(zoneId) })
    return row ~= nil
end

local function rollConfiguredSpecies(src, zone, baitTier)
    local rows = zoneFishRows(zone.id)
    if #rows == 0 then return nil, nil, false end
    local lvl = 1
    pcall(function() lvl = tonumber(exports.cookie_skill:level(src, T.SkillKey)) or 1 end)
    local pool, total = {}, 0.0
    for _, r in ipairs(rows) do
        local f = T.Fish[r.species]
        local w = tonumber(r.weight) or 0
        if f and (r.enabled==true or tonumber(r.enabled)==1) and w > 0 then
            local def = T.Grades[f.g] or {}
            w = w * (1.0 + lvl * (def.boost or 0)) * baitGradeMultiplier(f.g,baitTier)
            pool[#pool+1] = { key=r.species, f=f, w=w }
            total = total + w
        end
    end
    if total <= 0 or #pool == 0 then return nil, nil, true end
    local r = math.random() * total
    for _, e in ipairs(pool) do
        r = r - e.w
        if r <= 0 then return e.key, e.f, true end
    end
    local e=pool[#pool]; return e.key,e.f,true
end

local function inBoat(src)
    local ped = GetPlayerPed(src)
    local veh = ped and GetVehiclePedIsIn(ped, false) or 0
    if not veh or veh == 0 then return false end
    local ok, class = pcall(GetVehicleClass, veh)
    return ok and class == 14
end

local function regionHasGrade(regionKey, grade)
    for _, f in pairs(T.Fish) do
        if f.g == grade and speciesRegionMultiplier(f.label, regionKey) > 0 then return true end
    end
    return false
end

local function rollGrade(src, zone, baitTier)
    local lvl = 1
    pcall(function() lvl = tonumber(exports.cookie_skill:level(src, T.SkillKey)) or 1 end)

    -- 현재 버전은 고급 낚싯대/고급 미끼를 등급 해금 조건으로 사용하지 않는다.
    -- 모든 등급은 낚시 방식/관리자 확률/숙련도/포인트 서식지로만 결정한다.
    local base = T.ZoneWeights[zone.kind] or {}

    local weights, total = {}, 0.0
    for _, g in ipairs(T.GradeOrder) do
        local w = gradeWeightOf(zone.kind, g)
        local def = T.Grades[g]

        if not regionHasGrade(zone.regionKey, g) then w = 0 end

        if w > 0 then w = w * (1.0 + lvl * (def.boost or 0)) * baitGradeMultiplier(g,baitTier) end
        weights[g] = w
        total = total + w
    end
    if total <= 0 then return 'basic' end

    local r = math.random() * total
    for _, g in ipairs(T.GradeOrder) do
        r = r - (weights[g] or 0)
        if r <= 0 then return g end
    end
    return 'basic'
end

local function rollSpecies(grade, regionKey)
    local pool, total = {}, 0.0
    for key, f in pairs(T.Fish) do
        if f.g == grade then
            local mult = speciesRegionMultiplier(f.label, regionKey)
            local w = weightOf(key) * mult
            if w > 0 then
                pool[#pool + 1] = { key = key, f = f, w = w }
                total = total + w
            end
        end
    end
    if #pool == 0 or total <= 0 then return nil end
    local r = math.random() * total
    for _, e in ipairs(pool) do
        r = r - e.w
        if r <= 0 then return e.key, e.f end
    end
    local e = pool[#pool]; return e.key, e.f
end

local function rollWeight(f)
    local minKg, maxKg = tonumber(f.min) or 0, tonumber(f.max) or 0
    if maxKg < minKg then minKg, maxKg = maxKg, minKg end
    local span = math.max(0, maxKg - minKg)
    local r = math.random()
    local lo, hi, tier, label
    if r < 0.70 then
        lo, hi, tier, label = 0.00, 0.55, 'normal', '일반'
    elseif r < 0.92 then
        lo, hi, tier, label = 0.55, 0.80, 'large', '대형'
    elseif r < 0.99 then
        lo, hi, tier, label = 0.80, 0.95, 'trophy', '대물'
    else
        lo, hi, tier, label = 0.95, 1.00, 'record', '기록급'
    end
    local frac = lo + math.random() * (hi - lo)
    local kg = minKg + span * frac
    kg = math.floor(kg * 100 + 0.5) / 100
    return kg, tier, label
end

local CLASSIC_KEYS_WASD={ 'w','a','s','d' }
local CLASSIC_KEYS_WASDQE={ 'w','a','s','d','q','e' }
local function makeSequence(grade)
    local def=T.Grades[grade] or {keys={2,3},mode='wasd'}
    local lo=math.max(2,math.floor(tonumber(def.keys and def.keys[1]) or 2))
    local hi=math.max(lo,math.floor(tonumber(def.keys and def.keys[2]) or lo))
    local n=math.random(lo,hi)
    local mode=tostring(def.mode or 'wasd')
    local pool=(mode=='wasdqe') and CLASSIC_KEYS_WASDQE or CLASSIC_KEYS_WASD
    local seq={}
    for i=1,n do seq[i]=pool[math.random(#pool)] end
    return seq
end

local function refundPendingBait(src,job)
    if not job or job.baitRefunded then return end
    job.baitRefunded=true
    local item=job.baitItem
    if item and item~='' and GetPlayerName(src) then
        pcall(function() exports.ox_inventory:AddItem(src,item,1) end)
    end
end

local function clearPendingFishing(src,refund,reason)
    local job=pending[src]
    if not job then return end
    pending[src]=nil
    if refund then refundPendingBait(src,job) end
    if reason and GetPlayerName(src) then
        TriggerClientEvent('cookie_fishing:client:cancelPending',src,reason)
    end
end

local function rejectFishingStart(src,msg)
    notify(src,msg,true)
    TriggerClientEvent('cookie_fishing:client:startRejected',src)
end

RegisterNetEvent('cookie_fishing:server:start', function(rodItem)
    local src=source
    if not cookieAllowAction(src, 'fishing_start', 1500, 1) then return rejectFishingStart(src,'요청이 너무 빠릅니다') end
    if pending[src] then return rejectFishingStart(src,'이미 낚시를 진행 중입니다') end

    local rodTier,rod=rodByItem(src,rodItem)
    local baitTier,bait=bestBait(src)
    if not rod then return rejectFishingStart(src,'퀵슬롯에서 사용할 낚싯대를 먼저 들어주세요.') end
    if not bait then return rejectFishingStart(src,'미끼가 없습니다') end

    local zone=currentZone(src)
    if not zone then return rejectFishingStart(src,'등록된 낚시 포인트가 아닙니다') end
    if zone.kind=='boat' and not inBoat(src) then
        return rejectFishingStart(src,'선상 낚시 포인트는 보트를 타고 와야 합니다')
    end

    local key,f,hasCustom=rollConfiguredSpecies(src,zone,baitTier)
    local grade
    if hasCustom then
        if not key then return rejectFishingStart(src,'이 낚시 포인트에 출현하도록 설정된 물고기가 없습니다') end
        grade=f.g
    else
        grade=rollGrade(src,zone,baitTier)
        key,f=rollSpecies(grade,zone.regionKey)
        if not key then return rejectFishingStart(src,'이 지역에는 해당 물고기가 없습니다') end
    end

    local removed=false
    pcall(function() removed=exports.ox_inventory:RemoveItem(src,bait.item,1) end)
    if not removed then return rejectFishingStart(src,'미끼 소모에 실패했습니다') end

    local kg,sizeTier,sizeLabel=rollWeight(f)
    local biteMin=math.max(250,math.floor((tonumber(T.BiteWait.min) or 1000)*(rod.biteScale or 1.0)))
    local biteMax=math.max(biteMin,math.floor((tonumber(T.BiteWait.max) or biteMin)*(rod.biteScale or 1.0)))
    local seq=makeSequence(grade)
    local baseGameMs=math.max(1800,math.floor((tonumber(T.MinigameMs) or 5000)*(rod.gameScale or 1.0)))
    local perKeyMs=(grade=='transcendent') and 760 or ((grade=='mythic') and 700 or 620)
    local gameMs=math.max(baseGameMs,#seq*perKeyMs)
    local token=('%s:%s:%s'):format(src,GetGameTimer(),math.random(100000,999999))

    pending[src]={
        token=token,grade=grade,key=key,fish=f,kg=kg,
        sizeTier=sizeTier,sizeLabel=sizeLabel,
        regionKey=zone.regionKey,regionLabel=zone.label or zone.regionLabel,zoneId=zone.id,
        rodTier=rodTier,rodItem=rod.item,rodLabel=rod.label,
        baitTier=baitTier,baitLabel=bait.label,baitItem=bait.item,baitRefunded=false,
        activityStartedAt=GetGameTimer(),
        earliestSuccessAt=GetGameTimer()+biteMin+math.max(900, math.floor(gameMs*0.20)),
    }

    TriggerClientEvent('cookie_fishing:client:bite',src,{
        token=token,biteMin=biteMin,biteMax=biteMax,gameMs=gameMs,
        grade=grade,gradeLabel=T.Grades[grade].label,gradeColor=T.Grades[grade].color,
        seq=seq,rodLabel=rod.label,baitLabel=bait.label,
    })

    local maxLife=biteMax+gameMs+15000
    SetTimeout(maxLife,function()
        local job=pending[src]
        if job and job.token==token then
            print(('[cookie_fishing] pending timeout src=%s token=%s'):format(src,token))
            clearPendingFishing(src,true,'낚시 진행이 시간 초과되어 취소되었습니다. 미끼를 돌려드렸습니다.')
        end
    end)
end)


local function fishingIdentity(src)
    local p = exports.qbx_core:GetPlayer(src)
    if not p or not p.PlayerData then return nil end
    local cid = p.PlayerData.citizenid
    if not cid then return nil end
    local head = Player(src).state.ckHead or {}
    return {
        citizenid = cid,
        gobun = head.gobun and tostring(head.gobun) or '-',
        nickname = head.nick or GetPlayerName(src) or '무명',
    }
end


local function ensureFishingSeasonRankTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_fishing_current (
            citizenid VARCHAR(64) NOT NULL PRIMARY KEY,
            gobun VARCHAR(20) NULL,
            nickname VARCHAR(80) NULL,
            species VARCHAR(40) NULL,
            label VARCHAR(80) NULL,
            kg DOUBLE NOT NULL DEFAULT 0,
            caught_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_rank_fishing_kg(kg)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
end

CreateThread(function()
    Wait(2200)
    pcall(ensureFishingSeasonRankTable)
end)

local function updateFishingSeasonRank(ident, job)
    ensureFishingSeasonRankTable()
    MySQL.query.await([[
        INSERT INTO cookie_ranking_fishing_current(citizenid,gobun,nickname,species,label,kg,caught_at)
        VALUES (?,?,?,?,?,?,NOW())
        ON DUPLICATE KEY UPDATE
            gobun=IF(VALUES(kg)>kg,VALUES(gobun),gobun),
            nickname=IF(VALUES(kg)>kg,VALUES(nickname),nickname),
            species=IF(VALUES(kg)>kg,VALUES(species),species),
            label=IF(VALUES(kg)>kg,VALUES(label),label),
            caught_at=IF(VALUES(kg)>kg,NOW(),caught_at),
            kg=GREATEST(kg,VALUES(kg))
    ]],{ident.citizenid,ident.gobun,ident.nickname,job.key,job.fish and job.fish.label or job.key,tonumber(job.kg) or 0})
end

local function updateCollectionAndSpeciesRecord(src, job)
    local ident = fishingIdentity(src)
    if not ident then return end
    local regionKey = job.regionKey or 'unknown'
    MySQL.query.await([[
        INSERT INTO cookie_fishing_collection
            (citizenid, species, caught_count, best_kg, first_region, last_region)
        VALUES (?, ?, 1, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            caught_count = caught_count + 1,
            best_kg = GREATEST(best_kg, VALUES(best_kg)),
            last_region = VALUES(last_region),
            last_caught_at = CURRENT_TIMESTAMP
    ]], { ident.citizenid, job.key, job.kg, regionKey, regionKey })

    updateFishingSeasonRank(ident,job)

    local old = MySQL.single.await('SELECT best_kg FROM cookie_fishing_species_record WHERE species = ?', { job.key })
    local oldKg = old and tonumber(old.best_kg) or 0
    if job.kg > oldKg then
        MySQL.query.await([[
            INSERT INTO cookie_fishing_species_record
                (species, citizenid, gobun, nickname, best_kg, region_key, caught_at)
            VALUES (?, ?, ?, ?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE
                citizenid=VALUES(citizenid), gobun=VALUES(gobun), nickname=VALUES(nickname),
                best_kg=VALUES(best_kg), region_key=VALUES(region_key), caught_at=NOW()
        ]], { job.key, ident.citizenid, ident.gobun, ident.nickname, job.kg, regionKey })

        TriggerClientEvent('cookie_admin:client:notifyBottom', -1,
            ('어종 신기록! %s님이 %s %.2fkg (%s)'):format(ident.nickname, job.fish.label, job.kg, job.sizeLabel or '기록'), false)
    end
end

local function fishingKing(records)
    local by = {}
    for _, r in ipairs(records or {}) do
        if r.citizenid and (tonumber(r.best_kg) or 0) > 0 then
            local e = by[r.citizenid]
            if not e then
                e = { citizenid=r.citizenid, nickname=r.nickname or '무명', gobun=r.gobun or '-', recordCount=0, score=0 }
                by[r.citizenid] = e
            end
            e.recordCount = e.recordCount + 1
            local f = T.Fish[r.species]
            local maxKg = f and tonumber(f.max) or 0
            if maxKg > 0 then e.score = e.score + math.min(1.0, (tonumber(r.best_kg) or 0) / maxKg) end
        end
    end
    local best = nil
    for _, e in pairs(by) do
        if (not best) or e.recordCount > best.recordCount or (e.recordCount == best.recordCount and e.score > best.score) then best = e end
    end
    return best
end

local function buildCollectionPayload(src)
    local ident = fishingIdentity(src)
    if not ident then return { fish={}, summary={discovered=0,total=0,totalCaught=0}, gradeOrder=T.GradeOrder or {} } end

    local mineRows = MySQL.query.await('SELECT species, caught_count, best_kg, first_region, last_region, first_caught_at, last_caught_at FROM cookie_fishing_collection WHERE citizenid = ?', { ident.citizenid }) or {}
    local recRows = MySQL.query.await('SELECT species, citizenid, gobun, nickname, best_kg, region_key, caught_at FROM cookie_fishing_species_record') or {}
    local mine, rec = {}, {}
    local totalCaught, discovered = 0, 0
    local personalBest = nil
    for _, r in ipairs(mineRows) do
        mine[r.species] = r
        local c = tonumber(r.caught_count) or 0
        totalCaught = totalCaught + c
        discovered = discovered + 1
        local kg = tonumber(r.best_kg) or 0
        local f = T.Fish[r.species]
        if kg > 0 and ((not personalBest) or kg > personalBest.kg) then personalBest = { key=r.species, label=f and f.label or r.species, kg=kg } end
    end
    for _, r in ipairs(recRows) do rec[r.species] = r end

    local gradeIndex = {}
    for i, g in ipairs(T.GradeOrder or {}) do gradeIndex[g] = i end

    -- 도감의 출현 위치 힌트도 실제 관리자 포인트 설정을 기준으로 표시한다.
    local allZoneRows = MySQL.query.await('SELECT zone_id, species, enabled FROM cookie_fishing_zone_fish') or {}
    local customZone, enabledAt = {}, {}
    for _, zr in ipairs(allZoneRows) do
        local zid = tonumber(zr.zone_id)
        customZone[zid] = true
        if tonumber(zr.enabled) == 1 then
            enabledAt[zr.species] = enabledAt[zr.species] or {}
            enabledAt[zr.species][zid] = true
        end
    end
    local safeZones = {}
    pcall(function() safeZones = exports.cookie_safezone:getZones() or {} end)
    local function actualPointLabels(key, f)
        local labels = {}
        for _, z in ipairs(safeZones) do
            if z.type == 'fishing' then
                local zid = tonumber(z.id)
                local show
                if customZone[zid] then
                    show = enabledAt[key] and enabledAt[key][zid]
                else
                    local region = z.fishingRegion or ((z.fishingType == 'boat') and 'offshore' or 'coast')
                    show = speciesRegionMultiplier(f.label, region) > 0
                end
                if show then labels[#labels+1] = z.label or ('낚시 포인트 #'..tostring(zid)) end
            end
        end
        if #labels == 0 then return speciesRegions(f.label) end
        return labels
    end

    local fish = {}
    for key, f in pairs(T.Fish or {}) do
        local m, sr = mine[key], rec[key]
        fish[#fish+1] = {
            key=key, label=f.label, grade=f.g,
            gradeLabel=(T.Grades[f.g] and T.Grades[f.g].label) or f.g,
            gradeColor=(T.Grades[f.g] and T.Grades[f.g].color) or '#9aa4b2',
            min=tonumber(f.min) or 0, max=tonumber(f.max) or 0, img=f.img,
            regions=actualPointLabels(key, f), discovered=m ~= nil,
            caughtCount=m and (tonumber(m.caught_count) or 0) or 0,
            personalBest=m and (tonumber(m.best_kg) or 0) or 0,
            firstCaughtAt=m and m.first_caught_at or nil,
            lastCaughtAt=m and m.last_caught_at or nil,
            serverRecord=sr and { kg=tonumber(sr.best_kg) or 0, nickname=sr.nickname or '무명', gobun=sr.gobun or '-', caughtAt=sr.caught_at } or nil,
        }
    end
    table.sort(fish, function(a,b)
        local ai, bi = gradeIndex[a.grade] or 999, gradeIndex[b.grade] or 999
        if ai == bi then return tostring(a.label) < tostring(b.label) end
        return ai < bi
    end)
    return {
        fish=fish, gradeOrder=T.GradeOrder or {},
        summary={ discovered=discovered, total=#fish, totalCaught=totalCaught, personalBest=personalBest },
        king=fishingKing(recRows),
        sizeChances={ normal=70, large=22, trophy=7, record=1 },
    }
end

local function fishingAdminOk(src)
    local ok, lv = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    return ok and (tonumber(lv) or 0) >= 5
end

local function defaultZoneFishWeight(zone, key, f)
    local kind = (zone.fishingType == 'boat') and 'boat' or 'shore'
    local gradeBase = math.max(0, tonumber(gradeWeightOf(kind, f.g)) or 0)
    local denom = 0.0
    for k2, f2 in pairs(T.Fish or {}) do
        if f2.g == f.g then denom = denom + math.max(0, tonumber(weightOf(k2)) or 0) end
    end
    local own = math.max(0, tonumber(weightOf(key)) or 0)
    local w = denom > 0 and (gradeBase * own / denom) or own
    local mult = speciesRegionMultiplier(f.label, zone.fishingRegion or ((zone.fishingType=='boat') and 'offshore' or 'coast'))
    if mult > 1 then w = w * mult end
    if w <= 0 then w = math.max(0.01, own) end
    return math.floor(w * 1000 + 0.5) / 1000
end

local function fishingZoneSettingsPayload(zoneId)
    local zone = fishingZoneById(zoneId)
    if not zone then return nil end
    local rows = zoneFishRows(zone.id)
    local map = {}
    for _, r in ipairs(rows) do map[r.species] = r end
    local gradeIndex = {}
    for i,g in ipairs(T.GradeOrder or {}) do gradeIndex[g]=i end
    local fish = {}
    for key,f in pairs(T.Fish or {}) do
        local r=map[key]
        local defaultEnabled = speciesRegionMultiplier(f.label, zone.fishingRegion or ((zone.fishingType=='boat') and 'offshore' or 'coast')) > 0
        fish[#fish+1] = {
            key=key,label=f.label,grade=f.g,
            gradeLabel=(T.Grades[f.g] and T.Grades[f.g].label) or f.g,
            gradeColor=(T.Grades[f.g] and T.Grades[f.g].color) or '#9aa4b2',
            enabled=r==nil and defaultEnabled or (r.enabled==true or tonumber(r.enabled)==1),
            weight=r and (tonumber(r.weight) or 0) or defaultZoneFishWeight(zone,key,f),
            defaultWeight=defaultZoneFishWeight(zone,key,f),
        }
    end
    table.sort(fish,function(a,b)
        local ai,bi=gradeIndex[a.grade] or 999,gradeIndex[b.grade] or 999
        if ai==bi then return a.label<b.label end
        return ai<bi
    end)
    return {
        zoneId=zone.id,label=zone.label,
        fishingType=zone.fishingType or 'normal',
        fishingRegion=zone.fishingRegion or ((zone.fishingType=='boat') and 'offshore' or 'coast'),
        custom=#rows>0, fish=fish, gradeOrder=T.GradeOrder or {}
    }
end

RegisterNetEvent('cookie_fishing:server:zoneSettingsRequest', function(zoneId)
    local src=source
    zoneId=tonumber(zoneId)
    if not fishingAdminOk(src) then
        TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.')
        return
    end
    if not zoneId then
        TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'낚시 포인트 ID가 올바르지 않습니다.')
        return
    end
    local data=fishingZoneSettingsPayload(zoneId)
    if not data then
        TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,('낚시 포인트 #%s를 찾을 수 없습니다.'):format(tostring(zoneId)))
        return
    end
    print(('[cookie_fishing] zone settings -> src=%s zone=%s fish=%s'):format(src,zoneId,#(data.fish or {})))
    TriggerClientEvent('cookie_admin:client:fishingZoneSettingsData',src,data)
end)

RegisterNetEvent('cookie_fishing:server:zoneSettingsSave', function(data)
    local src=source
    if not fishingAdminOk(src) then
        TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.')
        return
    end
    local zoneId=tonumber(data and data.zoneId)
    if not fishingZoneById(zoneId) then
        TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'낚시 포인트를 찾을 수 없습니다.')
        return
    end
    if type(data and data.fish)~='table' or #data.fish==0 then
        TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'저장할 어종 설정이 없습니다.')
        return
    end
    local incoming={}
    for _,r in ipairs((data and data.fish) or {}) do
        local key=tostring(r.key or '')
        if T.Fish[key] then
            incoming[key]={enabled=(r.enabled==true or tonumber(r.enabled)==1) and 1 or 0,weight=math.max(0,math.min(100000,tonumber(r.weight) or 0))}
        end
    end
    local anyEnabled=false
    for _,r in pairs(incoming) do
        if r.enabled==1 and (tonumber(r.weight) or 0)>0 then anyEnabled=true break end
    end
    if not anyEnabled then
        TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'최소 1종 이상의 물고기를 ON으로 설정하고 가중치를 0보다 크게 입력하세요.')
        return
    end
    local by='-'
    pcall(function() by=exports.cookie_admin:getAdminName(src) or '-' end)
    for key,f in pairs(T.Fish or {}) do
        local r=incoming[key] or {enabled=0,weight=defaultZoneFishWeight(fishingZoneById(zoneId),key,f)}
        MySQL.query.await([[
            INSERT INTO cookie_fishing_zone_fish (zone_id,species,enabled,weight,updated_by)
            VALUES (?,?,?,?,?)
            ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),weight=VALUES(weight),updated_by=VALUES(updated_by)
        ]],{zoneId,key,r.enabled,r.weight,by})
    end
    local payload=fishingZoneSettingsPayload(zoneId)
    print(('[cookie_fishing] zone settings saved -> src=%s zone=%s enabled=%s'):format(src,zoneId,tostring(anyEnabled)))
    notify(src,'낚시 포인트 출현 어종 설정을 저장했습니다',false)
    TriggerClientEvent('cookie_admin:client:fishingZoneSettingsData',src,payload)
end)

exports('getZoneSettings', function(src, zoneId)
    src=tonumber(src) or 0
    if src~=0 and not fishingAdminOk(src) then return nil,'권한이 없습니다' end
    local res=fishingZoneSettingsPayload(zoneId)
    if not res then return nil,'낚시 포인트를 찾을 수 없습니다' end
    return res
end)

exports('saveZoneSettings', function(src,data)
    src=tonumber(src) or 0
    if src~=0 and not fishingAdminOk(src) then return false,'권한이 없습니다' end
    data=data or {};local zoneId=tonumber(data.zoneId)
    local zone=fishingZoneById(zoneId);if not zone then return false,'낚시 포인트를 찾을 수 없습니다' end
    if type(data.fish)~='table' or #data.fish==0 then return false,'저장할 어종 설정이 없습니다' end
    local incoming={}
    for _,r in ipairs(data.fish) do local key=tostring(r.key or '');if T.Fish[key] then incoming[key]={enabled=(r.enabled==true or tonumber(r.enabled)==1) and 1 or 0,weight=math.max(0,math.min(100000,tonumber(r.weight) or 0))} end end
    local by=src==0 and 'console' or '-';if src~=0 then pcall(function() by=exports.cookie_admin:getAdminName(src) or '-' end) end
    for key,_ in pairs(T.Fish or {}) do local r=incoming[key];if r then MySQL.query.await([[INSERT INTO cookie_fishing_zone_fish (zone_id,species,enabled,weight,updated_by) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),weight=VALUES(weight),updated_by=VALUES(updated_by)]],{zoneId,key,r.enabled,r.weight,by}) end end
    return true,fishingZoneSettingsPayload(zoneId)
end)

RegisterNetEvent('cookie_fishing:server:collectionRequest', function()
    local src = source
    TriggerClientEvent('cookie_admin:client:fishingCollectionData', src, buildCollectionPayload(src))
end)

exports('getCollectionData', function(src) return buildCollectionPayload(tonumber(src) or 0) end)

RegisterNetEvent('cookie_fishing:server:cancel',function(token)
    local src=source
    local job=pending[src]
    if not job then return end
    if token and tostring(token)~='' and tostring(token)~=tostring(job.token or '') then return end
    clearPendingFishing(src,true,nil)
end)

RegisterNetEvent('cookie_fishing:server:finish', function(success,token,reason)
    local src=source
    if not cookieAllowAction(src, 'fishing_finish', 1200, 2) then return end
    local job=pending[src]
    if not job then return end
    if tostring(token or '')~=tostring(job.token or '') then
        print(('[cookie_fishing] rejected finish token src=%s'):format(src))
        return
    end
    if success then
        local now = GetGameTimer()
        if now < (tonumber(job.earliestSuccessAt) or 0) then
            print(('[cookie_fishing] rejected too-fast finish src=%s'):format(src))
            return clearPendingFishing(src, false, '비정상적으로 빠른 낚시 완료가 감지되어 취소되었습니다.')
        end
        local zone = currentZone(src)
        if not zone or tonumber(zone.id) ~= tonumber(job.zoneId) then
            return clearPendingFishing(src, false, '낚시 포인트를 벗어나 낚시가 취소되었습니다.')
        end
        local rodTier, rod = rodByItem(src, job.rodItem)
        if not rod then
            return clearPendingFishing(src, false, '낚싯대를 확인할 수 없어 낚시가 취소되었습니다.')
        end
    end
    pending[src]=nil

    -- 오픈 낚시왕: 실제 한 번의 낚시 시도에 소비한 시간을 누적한다.
    local activeMs=GetGameTimer()-(tonumber(job.activityStartedAt) or GetGameTimer())
    local activeSec=math.max(1,math.min(180,math.floor(activeMs/1000)))
    TriggerEvent('cookie_admin:server:openActivityAccrueInternal',src,'fishing',activeSec)

    if not success then
        notify(src, ('%s이(가) 도망쳤습니다'):format(job.fish.label), true)
        return
    end

    local given = false
    pcall(function()
        given = exports.ox_inventory:AddItem(src, fitem(job.key), 1, {
            label = ('%s (%.2fkg)'):format(job.fish.label, job.kg),
            weightKg = job.kg,
            grade = job.grade,
            sizeTier = job.sizeTier,
            sizeLabel = job.sizeLabel,
            regionKey = job.regionKey,
            regionLabel = job.regionLabel,
        })
    end)
    if not given then
        notify(src, '가방이 가득 차 물고기를 놓쳤습니다', true)
        return
    end

    local exp = (T.ExpPerCatch or {})[job.grade] or 1
    pcall(function() exports.cookie_skill:addExp(src, T.SkillKey, exp) end)

    updateCollectionAndSpeciesRecord(src, job)
    updateHOF(src, job) -- 구버전 호환용 전체 최대무게 기록은 유지

    TriggerClientEvent('cookie_fishing:client:caught', src, {
        label = job.fish.label, kg = job.kg,
        grade = job.grade, gradeLabel = T.Grades[job.grade].label,
        gradeColor = T.Grades[job.grade].color,
        sizeTier = job.sizeTier, sizeLabel = job.sizeLabel,
        regionKey = job.regionKey, regionLabel = job.regionLabel,
    })

end)


AddEventHandler('playerDropped',function()
    pending[source]=nil
end)

function updateHOF(src, job)
    if not (T.HOF and T.HOF.enabled) then return end

    local p = exports.qbx_core:GetPlayer(src)
    local cid = p and p.PlayerData and p.PlayerData.citizenid
    local head = Player(src).state.ckHead or {}
    local gobun = head.gobun and tostring(head.gobun) or '-'
    local nick = head.nick or '무명'

    CreateThread(function()
        local row = MySQL.single.await('SELECT kg FROM cookie_fishing_hof WHERE id = 1')
        local best = (row and tonumber(row.kg)) or 0
        if job.kg <= best then return end

        MySQL.update.await([[
            UPDATE cookie_fishing_hof
            SET citizenid=?, gobun=?, nickname=?, species=?, label=?, kg=?, caught_at=NOW()
            WHERE id = 1
        ]], { cid, gobun, nick, job.key, job.fish.label, job.kg })

        TriggerClientEvent('cookie_admin:client:notifyBottom', -1,
            ('전체 최대어 갱신! %s님이 %s %.2fkg 를 낚았습니다'):format(nick, job.fish.label, job.kg), false)
    end)
end

function CookieFishingHOF()
    local row = MySQL.single.await('SELECT * FROM cookie_fishing_hof WHERE id = 1')
    if not row or (tonumber(row.kg) or 0) <= 0 then return nil end
    return {
        gobun = row.gobun, nickname = row.nickname,
        species = row.species, label = row.label, kg = tonumber(row.kg),
        caughtAt = row.caught_at,
    }
end
exports('getHOF', function() return CookieFishingHOF() end)

RegisterNetEvent('cookie_fishing:server:requestHOF', function()
    TriggerClientEvent('cookie_fishing:client:hof', source, CookieFishingHOF())
end)

local function priceOf(key, kg)
    return math.floor((tonumber(kg) or 0) * ppkOf(key) + 0.5)
end


-- ─────────────────────────────────────────────────────────────
-- F3 낚시 관리인: NPC별 판매/매입 설정
-- ─────────────────────────────────────────────────────────────
local MANAGER_SHOP = {
    rod     = { item=FISH_GEAR.rods.beginner.item, label='초급 낚싯대', defaultPrice=function() return shopNum('rod') end, defaultQty=function() return 1 end },
    rodMid  = { item=FISH_GEAR.rods.middle.item,   label='중급 낚싯대', defaultPrice=function() return shopNum('rodMid')>0 and shopNum('rodMid') or midPrice('rod','rodPro') end, defaultQty=function() return 1 end },
    rodPro  = { item=FISH_GEAR.rods.advanced.item, label='고급 낚싯대', defaultPrice=function() return shopNum('rodPro') end, defaultQty=function() return 1 end },
    bait    = { item=FISH_GEAR.baits.beginner.item,label='초급 미끼', defaultPrice=function() return shopNum('bait') end, defaultQty=function() return (T.Shop or {}).baitPack or 10 end },
    baitMid = { item=FISH_GEAR.baits.middle.item,  label='중급 미끼', defaultPrice=function() return shopNum('baitMid')>0 and shopNum('baitMid') or midPrice('bait','baitPro') end, defaultQty=function() return (T.Shop or {}).baitPack or 10 end },
    baitPro = { item=FISH_GEAR.baits.advanced.item,label='고급 미끼', defaultPrice=function() return shopNum('baitPro') end, defaultQty=function() return (T.Shop or {}).baitPack or 10 end },
}
local MANAGER_SHOP_ORDER = { 'rod', 'rodMid', 'rodPro', 'bait', 'baitMid', 'baitPro' }


CreateThread(function()
    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_fishing_npc_shop (
                npc_id      INT NOT NULL,
                kind        VARCHAR(20) NOT NULL,
                enabled     TINYINT(1) NOT NULL DEFAULT 1,
                price       INT NOT NULL DEFAULT 0,
                qty         INT NOT NULL DEFAULT 1,
                updated_by  VARCHAR(60) NULL,
                updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (npc_id, kind)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_fishing_npc_fish (
                npc_id      INT NOT NULL,
                species     VARCHAR(40) NOT NULL,
                enabled     TINYINT(1) NOT NULL DEFAULT 1,
                ppk         INT NULL,
                updated_by  VARCHAR(60) NULL,
                updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (npc_id, species)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)
end)

local function validManagerNpc(npcId)
    npcId = math.floor(tonumber(npcId) or 0)
    if npcId <= 0 then return nil end
    local row = MySQL.single.await(
        "SELECT id, label FROM cookie_npc WHERE id = ? AND is_active = 1 AND job_key IN ('fishing','fisher','fisherman')",
        { npcId })
    return row
end

local function dbBool(v)
    if v == true then return true end
    if v == false or v == nil then return false end
    local n = tonumber(v)
    if n ~= nil then return n == 1 end
    local s = tostring(v):lower()
    return s == 'true' or s == '1'
end

local function managerShopRows(npcId)
    local db = MySQL.query.await('SELECT kind, enabled, price, qty FROM cookie_fishing_npc_shop WHERE npc_id = ?', { npcId }) or {}
    local by = {}
    for _, r in ipairs(db) do by[r.kind] = r end
    local out = {}
    for _, kind in ipairs(MANAGER_SHOP_ORDER) do
        local def, r = MANAGER_SHOP[kind], by[kind]
        out[#out + 1] = {
            kind = kind, item = def.item, label = def.label,
            enabled = r == nil and true or dbBool(r.enabled),
            price = r and math.max(0, math.floor(tonumber(r.price) or 0)) or def.defaultPrice(),
            qty = r and math.max(1, math.floor(tonumber(r.qty) or 1)) or def.defaultQty(),
        }
    end
    return out
end

local function managerFishMap(npcId)
    local rows = MySQL.query.await('SELECT species, enabled, ppk FROM cookie_fishing_npc_fish WHERE npc_id = ?', { npcId }) or {}
    local map = {}
    for _, r in ipairs(rows) do map[r.species] = r end
    return map
end

local function managerFishEnabled(npcId, key, map)
    map = map or managerFishMap(npcId)
    local r = map[key]
    return r == nil or dbBool(r.enabled)
end

local function managerFishPrice(npcId, key, map)
    map = map or managerFishMap(npcId)
    local r = map[key]
    if r and r.ppk ~= nil then return math.max(0, math.floor(tonumber(r.ppk) or 0)) end
    return ppkOf(key)
end

local function managerAdminPayload(npcId, label)
    local fmap = managerFishMap(npcId)
    local fish = {}
    for key, f in pairs(T.Fish) do
        fish[#fish + 1] = {
            key = key, label = f.label, grade = f.g,
            gradeLabel = (T.Grades[f.g] and T.Grades[f.g].label) or f.g,
            min = f.min, max = f.max, img = f.img,
            enabled = managerFishEnabled(npcId, key, fmap),
            ppk = managerFishPrice(npcId, key, fmap),
        }
    end
    table.sort(fish, function(a, b)
        local ai, bi = 999, 999
        for i, g in ipairs(T.GradeOrder or {}) do
            if g == a.grade then ai = i end
            if g == b.grade then bi = i end
        end
        if ai == bi then return a.label < b.label end
        return ai < bi
    end)
    return { npcId = npcId, label = label, shop = managerShopRows(npcId), fish = fish, gradeOrder = T.GradeOrder }
end

local function managerInventoryFish(src, npcId, fmap)
    local out = {}
    local totalValue, totalCount = 0, 0
    for key, f in pairs(T.Fish) do
        if managerFishEnabled(npcId, key, fmap) then
            local slots = {}
            pcall(function() slots = exports.ox_inventory:Search(src, 'slots', fitem(key)) or {} end)
            for _, slot in ipairs(slots) do
                local count = math.max(1, math.floor(tonumber(slot.count) or 1))
                local kg = (slot.metadata and tonumber(slot.metadata.weightKg)) or f.min
                local ppk = managerFishPrice(npcId, key, fmap)
                local priceEach = math.floor((tonumber(kg) or 0) * ppk + 0.5)
                local value = priceEach * count
                out[#out + 1] = {
                    key = key, label = f.label, grade = f.g,
                    gradeLabel = (T.Grades[f.g] and T.Grades[f.g].label) or f.g,
                    gradeColor = (T.Grades[f.g] and T.Grades[f.g].color) or '#ffffff',
                    img = f.img, slot = slot.slot, count = count, kg = kg,
                    ppk = ppk, priceEach = priceEach, value = value,
                }
                totalValue = totalValue + value
                totalCount = totalCount + count
            end
        end
    end
    table.sort(out, function(a, b)
        if a.grade == b.grade then return a.label < b.label end
        local ai, bi = 999, 999
        for i, g in ipairs(T.GradeOrder or {}) do
            if g == a.grade then ai = i end
            if g == b.grade then bi = i end
        end
        return ai < bi
    end)
    return out, totalValue, totalCount
end

local function sendManagerMenu(src, npcId)
    local npc = validManagerNpc(npcId)
    if not npc then return notify(src, '사용할 수 없는 낚시 관리인입니다', true) end
    local fmap = managerFishMap(npc.id)
    local fish, totalValue, totalCount = managerInventoryFish(src, npc.id, fmap)
    TriggerClientEvent('cookie_fishing:client:managerMenu', src, {
        npcId = npc.id, label = npc.label, hof = CookieFishingHOF(),
        shop = managerShopRows(npc.id), fish = fish,
        totalValue = totalValue, totalCount = totalCount,
        collection = buildCollectionPayload(src),
    })
end

RegisterNetEvent('cookie_fishing:server:managerMenu', function(npcId)
    sendManagerMenu(source, npcId)
end)

RegisterNetEvent('cookie_fishing:server:managerAdminRequest', function(npcId)
    local src = source
    local okLv, lv = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    if not (okLv and (tonumber(lv) or 0) >= 3) then return notify(src, '권한이 없습니다', true) end
    local npc = validManagerNpc(npcId)
    if not npc then return notify(src, '낚시 관리인 NPC를 찾을 수 없습니다', true) end
    TriggerClientEvent('cookie_admin:client:fishingAdminData', src, managerAdminPayload(npc.id, npc.label))
end)

RegisterNetEvent('cookie_fishing:server:managerShopSave', function(data)
    local src = source
    local okLv, lv = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    if not (okLv and (tonumber(lv) or 0) >= 3) then return notify(src, '권한이 없습니다', true) end
    local npc = validManagerNpc(data and data.npcId)
    local kind = data and tostring(data.kind or '') or ''
    local def = MANAGER_SHOP[kind]
    if not npc or not def then return end
    local enabled = (data.enabled == true or tonumber(data.enabled) == 1) and 1 or 0
    local price = math.max(0, math.floor(tonumber(data.price) or 0))
    local qty = math.max(1, math.floor(tonumber(data.qty) or 1))
    local by = '-'; pcall(function() by = exports.cookie_admin:getAdminName(src) or '-' end)
    MySQL.query.await([[
        INSERT INTO cookie_fishing_npc_shop (npc_id, kind, enabled, price, qty, updated_by)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE enabled=VALUES(enabled), price=VALUES(price), qty=VALUES(qty), updated_by=VALUES(updated_by)
    ]], { npc.id, kind, enabled, price, qty, by })
    notify(src, ('%s 판매 설정을 저장했습니다'):format(def.label), false)
    TriggerClientEvent('cookie_admin:client:fishingAdminData', src, managerAdminPayload(npc.id, npc.label))
end)

RegisterNetEvent('cookie_fishing:server:managerFishSave', function(data)
    local src = source
    local okLv, lv = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    if not (okLv and (tonumber(lv) or 0) >= 3) then return notify(src, '권한이 없습니다', true) end
    local npc = validManagerNpc(data and data.npcId)
    local key = data and tostring(data.key or '') or ''
    if not npc or not T.Fish[key] then return end
    local enabled = (data.enabled == true or tonumber(data.enabled) == 1) and 1 or 0
    local ppk = math.max(0, math.floor(tonumber(data.ppk) or 0))
    local by = '-'; pcall(function() by = exports.cookie_admin:getAdminName(src) or '-' end)
    MySQL.query.await([[
        INSERT INTO cookie_fishing_npc_fish (npc_id, species, enabled, ppk, updated_by)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE enabled=VALUES(enabled), ppk=VALUES(ppk), updated_by=VALUES(updated_by)
    ]], { npc.id, key, enabled, ppk, by })
    notify(src, ('%s 매입 설정을 저장했습니다'):format(T.Fish[key].label), false)
    TriggerClientEvent('cookie_admin:client:fishingAdminData', src, managerAdminPayload(npc.id, npc.label))
end)

RegisterNetEvent('cookie_fishing:server:sellOne', function(npcId, key, slotId)
    local src = source
    local manager = validManagerNpc(npcId)
    key = tostring(key or '')
    slotId = math.floor(tonumber(slotId) or 0)
    local f = T.Fish[key]
    if not manager or not f or slotId <= 0 then return end

    local fmap = managerFishMap(manager.id)
    if not managerFishEnabled(manager.id, key, fmap) then
        return notify(src, '이 관리인은 해당 물고기를 매입하지 않습니다', true)
    end

    local slots = {}
    pcall(function() slots = exports.ox_inventory:Search(src, 'slots', fitem(key)) or {} end)
    local target = nil
    for _, slot in ipairs(slots) do
        if tonumber(slot.slot) == slotId then target = slot break end
    end
    if not target then return notify(src, '판매할 물고기를 찾을 수 없습니다', true) end

    local count = math.max(1, math.floor(tonumber(target.count) or 1))
    local kg = (target.metadata and tonumber(target.metadata.weightKg)) or f.min
    local ppk = managerFishPrice(manager.id, key, fmap)
    local price = math.floor((tonumber(kg) or 0) * ppk + 0.5) * count

    local removed = false
    pcall(function() removed = exports.ox_inventory:RemoveItem(src, fitem(key), count, nil, slotId) end)
    if not removed then return notify(src, '물고기 판매에 실패했습니다', true) end

    local p = exports.qbx_core:GetPlayer(src)
    if not p then return end
    p.Functions.AddMoney('cash', price, '물고기 판매')
    notify(src, ('%s %.2fkg 판매 (%s원)'):format(f.label, kg, comma(price)), false)
    sendManagerMenu(src, manager.id)
end)

RegisterNetEvent('cookie_fishing:server:sellAll', function(npcId)
    local src = source
    local manager = nil
    local fmap = nil
    if npcId ~= nil then
        manager = validManagerNpc(npcId)
        if not manager then return notify(src, '사용할 수 없는 낚시 관리인입니다', true) end
        fmap = managerFishMap(manager.id)
    end
    local p = exports.qbx_core:GetPlayer(src)
    if not p then return end

    local total, count = 0, 0

    for key, f in pairs(T.Fish) do
        if (not manager) or managerFishEnabled(manager.id, key, fmap) then
        local items = {}
        pcall(function() items = exports.ox_inventory:Search(src, 'slots', fitem(key)) or {} end)
        for _, slot in ipairs(items) do
            local kg = (slot.metadata and tonumber(slot.metadata.weightKg)) or f.min
            local unit = manager and managerFishPrice(manager.id, key, fmap) or ppkOf(key)
            local price = math.floor((tonumber(kg) or 0) * unit + 0.5) * (slot.count or 1)
            local ok = false
            pcall(function() ok = exports.ox_inventory:RemoveItem(src, fitem(key), slot.count or 1, nil, slot.slot) end)
            if ok then total = total + price; count = count + (slot.count or 1) end
        end
        end
    end

    if count == 0 then return notify(src, '팔 물고기가 없습니다', true) end
    p.Functions.AddMoney('cash', total, '물고기 판매')
    notify(src, ('물고기 %d마리를 %s원에 팔았습니다'):format(count, comma(total)), false)
    if manager then sendManagerMenu(src, manager.id) end

end)

RegisterNetEvent('cookie_fishing:server:buy', function(kind, npcId)
    local src = source
    local o = nil
    for _, row in ipairs(managerShopRows(npcId and tonumber(npcId) or -1)) do
        if row.kind == kind then o = { item=row.item, qty=row.qty, price=row.price, label=row.label, enabled=row.enabled }; break end
    end
    if not o then
        local def=MANAGER_SHOP[kind]
        if def then o={item=def.item,qty=def.defaultQty(),price=def.defaultPrice(),label=def.label,enabled=true} end
    end
    if not o or not o.price then return end

    if npcId ~= nil then
        local manager = validManagerNpc(npcId)
        if not manager then return notify(src, '사용할 수 없는 낚시 관리인입니다', true) end
        local selected = nil
        for _, s in ipairs(managerShopRows(manager.id)) do if s.kind == kind then selected = s break end end
        if not selected or not selected.enabled then return notify(src, '이 관리인은 해당 용품을 판매하지 않습니다', true) end
        o.price = selected.price
        o.qty = selected.qty
    end

    local p = exports.qbx_core:GetPlayer(src)
    if not p then return end

    local can = true
    pcall(function() can = exports.ox_inventory:CanCarryItem(src, o.item, o.qty) end)
    if not can then return notify(src, '가방에 공간이 부족합니다', true) end

    local paid = p.Functions.RemoveMoney('cash', o.price, '낚시 용품 구매')
    if not paid then
        return notify(src, ('현금이 부족합니다 (%s원)'):format(comma(o.price)), true)
    end

    local ok = false
    pcall(function() ok = exports.ox_inventory:AddItem(src, o.item, o.qty) end)
    if not ok then
        p.Functions.AddMoney('cash', o.price, '낚시 용품 환불')
        return notify(src, '지급 실패, 환불되었습니다', true)
    end

    notify(src, ('%s %d개 구매 (%s원)'):format(o.label, o.qty, comma(o.price)), false)
    if npcId ~= nil then sendManagerMenu(src, npcId) end

end)

function comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

RegisterCommand('fishdiag', function(src)
    if src ~= 0 then return end
    CreateThread(function()
        local hof = CookieFishingHOF()

    end)
end, true)

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_fishing_fishcfg (
                species    VARCHAR(40) PRIMARY KEY,
                ppk        INT NULL,               -- KG당 가격(원). NULL이면 config 기본가
                weight     INT NULL,               -- 등급 내 확률 가중치. NULL이면 config w
                updated_by VARCHAR(60) NULL,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)
    if ok then

        local rows = MySQL.query.await('SELECT species, ppk, weight FROM cookie_fishing_fishcfg') or {}
        for _, r in ipairs(rows) do
            if r.ppk ~= nil then adminPrice[r.species] = math.floor(tonumber(r.ppk) or 0) end
            if r.weight ~= nil then adminWeight[r.species] = math.max(0, math.floor(tonumber(r.weight) or 0)) end
        end

    else

    end
end)


local adminOk

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_fishing_gradecfg (
            zone_kind  VARCHAR(16) NOT NULL,
            grade_key  VARCHAR(32) NOT NULL,
            chance     DECIMAL(7,3) NOT NULL DEFAULT 0,
            updated_by VARCHAR(60) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (zone_kind, grade_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    local rows = MySQL.query.await('SELECT zone_kind, grade_key, chance FROM cookie_fishing_gradecfg') or {}
    for _, r in ipairs(rows) do
        if gradeWeights[r.zone_kind] and T.Grades[r.grade_key] then
            gradeWeights[r.zone_kind][r.grade_key] = tonumber(r.chance) or 0
        end
    end
end)

local function gradeSettingsPayload()
    local grades = {}
    for _, g in ipairs(T.GradeOrder) do
        grades[#grades + 1] = {
            key = g,
            label = (T.Grades[g] and T.Grades[g].label) or g,
        }
    end
    local weights = { shore = {}, boat = {} }
    for _, kind in ipairs({ 'shore', 'boat' }) do
        for _, g in ipairs(T.GradeOrder) do
            weights[kind][g] = gradeWeightOf(kind, g)
        end
    end
    return { grades = grades, weights = weights }
end

exports('getGradeSettings', function()
    return gradeSettingsPayload()
end)

exports('saveGradeSettings', function(src, data)
    src = tonumber(src) or 0
    if src ~= 0 and not adminOk(src) then return false, '권한이 없습니다' end
    if type(data) ~= 'table' then return false, '잘못된 데이터입니다' end

    local incoming = data.weights or data
    local clean = { shore = {}, boat = {} }

    for _, kind in ipairs({ 'shore', 'boat' }) do
        local total = 0.0
        for _, g in ipairs(T.GradeOrder) do
            local v = tonumber(incoming[kind] and incoming[kind][g]) or 0
            if v < 0 or v > 100 then return false, '확률은 0~100 사이여야 합니다' end
            clean[kind][g] = math.floor(v * 1000 + 0.5) / 1000
            total = total + clean[kind][g]
        end
        if math.abs(total - 100.0) > 0.01 then
            return false, (kind == 'shore' and '일반 낚시' or '선상 낚시') .. ' 확률 합계가 100%여야 합니다'
        end
    end

    local by = '-'
    pcall(function()
        local a = exports.cookie_admin:getAdminName(src)
        if a and a ~= '' then by = a end
    end)

    for _, kind in ipairs({ 'shore', 'boat' }) do
        for _, g in ipairs(T.GradeOrder) do
            local v = clean[kind][g]
            gradeWeights[kind][g] = v
            MySQL.query.await([[
                INSERT INTO cookie_fishing_gradecfg (zone_kind, grade_key, chance, updated_by)
                VALUES (?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE chance = VALUES(chance), updated_by = VALUES(updated_by)
            ]], { kind, g, v, by })
        end
    end
    return true
end)

local function _adminOkImpl(src)
    if src == 0 then return true end
    local ok, lv = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    return ok and (tonumber(lv) or 0) >= 3
end
adminOk = _adminOkImpl

RegisterNetEvent('cookie_fishing:server:adminRequest', function()
    local src = source
    if not adminOk(src) then return notify(src, '권한이 없습니다', true) end

    local list = {}
    for key, f in pairs(T.Fish) do
        list[#list + 1] = {
            key = key, label = f.label, grade = f.g,
            gradeLabel = (T.Grades[f.g] and T.Grades[f.g].label) or f.g,
            min = f.min, max = f.max, img = f.img,
            ppk = ppkOf(key), w = weightOf(key),
            ppkDefault = f.ppk, wDefault = f.w,
            custom = (adminPrice[key] ~= nil) or (adminWeight[key] ~= nil),
        }
    end
    TriggerClientEvent('cookie_fishing:client:adminData', src, {
        fish = list,
        gradeOrder = T.GradeOrder,
    })
end)

RegisterNetEvent('cookie_fishing:server:adminSave', function(data)
    local src = source
    if not adminOk(src) then return notify(src, '권한이 없습니다', true) end
    local key = data and data.key
    if not key or not T.Fish[key] then return end

    local ppk = math.max(0, math.floor(tonumber(data.ppk) or 0))
    local w   = math.max(0, math.floor(tonumber(data.w) or 0))

    adminPrice[key]  = ppk
    adminWeight[key] = w

    local by = '-'
    pcall(function() local a = exports.cookie_admin:getAdminName(src); if a and a ~= '' then by = a end end)

    MySQL.query.await([[
        INSERT INTO cookie_fishing_fishcfg (species, ppk, weight, updated_by) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE ppk = VALUES(ppk), weight = VALUES(weight), updated_by = VALUES(updated_by)
    ]], { key, ppk, w, by })

    notify(src, ('%s 저장 (KG당 %s원, 확률 %d)'):format(T.Fish[key].label, comma(ppk), w), false)

end)

print('^2[cookie_fishing]^7 ESC SEASON RANK V1.7.1 active')

print('[cookie_fishing] TOOL EQUIP + CONTINUOUS CLASSIC KEYS V1.7.5 ready')
