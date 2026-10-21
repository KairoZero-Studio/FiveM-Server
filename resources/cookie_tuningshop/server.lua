local sessions={}

local function clean(v,maxLen)
    local s=tostring(v or ''):gsub('[%z\1-\31]',' '):gsub('^%s+',''):gsub('%s+$','')
    if maxLen and #s>maxLen then s=s:sub(1,maxLen) end
    return s
end

local function clampInt(v,lo,hi,def)
    v=math.floor(tonumber(v) or tonumber(def) or lo)
    if v<lo then v=lo elseif v>hi then v=hi end
    return v
end

local function toBool(v)
    return v==true or v==1 or v=='1'
end

local function plateNorm(v)
    return clean(v,24):upper()
end

local function player(src)
    return exports.qbx_core:GetPlayer(src)
end

local function citizenid(src)
    local p=player(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function rgb(v,fallback)
    fallback=fallback or {255,255,255}
    if type(v)~='table' then return {fallback[1],fallback[2],fallback[3]} end
    return {
        clampInt(v[1] or v.r,0,255,fallback[1]),
        clampInt(v[2] or v.g,0,255,fallback[2]),
        clampInt(v[3] or v.b,0,255,fallback[3]),
    }
end

local specialMap={}
for _,v in ipairs(Config.SpecialPaints or {}) do specialMap[tostring(v.key)]=true end

local wheelColorMap={}
for _,v in ipairs(Config.WheelColors or {}) do wheelColorMap[tonumber(v.id)]=true end

local tintMap={}
for _,v in ipairs(Config.WindowTints or {}) do tintMap[tonumber(v.id)]=true end

local xenonMap={}
for _,v in ipairs(Config.XenonColors or {}) do xenonMap[tonumber(v.id)]=true end

local plateMap={}
for _,v in ipairs(Config.PlateStyles or {}) do plateMap[tonumber(v.id)]=true end

local wheelTypeMap={}
for _,v in ipairs(Config.WheelTypes or {}) do wheelTypeMap[tonumber(v.id)]=true end

local interiorMap={}
for _,v in ipairs(Config.InteriorColors or {}) do interiorMap[tonumber(v.id)]=true end

local audioMap={}
for _,v in ipairs(Config.EngineAudios or {}) do audioMap[tostring(v.key)]=true end

local function sanitizeExtras(v)
    local out={}
    if type(v)~='table' then return out end
    for k,val in pairs(v) do
        local id=tonumber(k)
        if id and id>=0 and id<=20 then
            out[tostring(math.floor(id))]=toBool(val)
        end
    end
    return out
end

local function sanitizeSides(v)
    v=type(v)=='table' and v or {}
    return {
        left=toBool(v.left),
        right=toBool(v.right),
        front=toBool(v.front),
        back=toBool(v.back),
    }
end

local function sanitizeTune(raw)
    raw=type(raw)=='table' and raw or {}

    local special=clean(raw.specialKey,40)
    if not specialMap[special] then special='none' end

    local wc=tonumber(raw.wheelColor)
    if not wc or not wheelColorMap[wc] then wc=0 end

    local wt=tonumber(raw.windowTint)
    if not wt or not tintMap[wt] then wt=4 end

    local xc=tonumber(raw.xenonColor)
    if not xc or not xenonMap[xc] then xc=0 end

    local ps=tonumber(raw.plateStyle)
    if not ps or not plateMap[ps] then ps=0 end

    local wtype=tonumber(raw.wheelType)
    if not wtype or not wheelTypeMap[wtype] then wtype=0 end

    local ic=tonumber(raw.interiorColor)
    if not ic or not interiorMap[ic] then ic=0 end

    local audio=clean(raw.engineAudio,40)
    if not audioMap[audio] then audio='stock' end

    return {
        primary=rgb(raw.primary,{255,255,255}),
        secondary=rgb(raw.secondary,{255,255,255}),
        primaryCustom=toBool(raw.primaryCustom),
        secondaryCustom=toBool(raw.secondaryCustom),
        primaryIndex=clampInt(raw.primaryIndex,0,255,0),
        secondaryIndex=clampInt(raw.secondaryIndex,0,255,0),
        specialKey=special,

        wheelColor=math.floor(wc),
        windowTint=math.floor(wt),
        interiorColor=math.floor(ic),

        engineLevel=clampInt(raw.engineLevel,0,Config.MaxEngineLevel or 5,0),
        speedLevel=clampInt(raw.speedLevel,0,Config.MaxSpeedLevel or 5,0),
        durabilityLevel=clampInt(raw.durabilityLevel,0,Config.MaxDurabilityLevel or 5,0),
        brakeLevel=clampInt(raw.brakeLevel,0,Config.MaxBrakeLevel or 5,0),
        suspensionLevel=clampInt(raw.suspensionLevel,0,Config.MaxSuspensionLevel or 5,0),
        transmissionLevel=clampInt(raw.transmissionLevel,0,Config.MaxTransmissionLevel or 5,0),
        turbo=toBool(raw.turbo),

        bulletproofTyres=toBool(raw.bulletproofTyres),
        tyreSmoke=rgb(raw.tyreSmoke,{255,255,255}),
        tyreSmokeEnabled=toBool(raw.tyreSmokeEnabled),

        hornIndex=clampInt(raw.hornIndex,-1,255,-1),

        xenonEnabled=toBool(raw.xenonEnabled),
        xenonColor=math.floor(xc),

        engineAudio=audio,
        extras=sanitizeExtras(raw.extras),

        plateStyle=math.floor(ps),

        neonEnabled=toBool(raw.neonEnabled),
        neonColor=rgb(raw.neonColor,{255,255,255}),
        neonSides=sanitizeSides(raw.neonSides),

        wheelType=math.floor(wtype),
        wheelIndex=clampInt(raw.wheelIndex,-1,255,-1),

        frontBumper=clampInt(raw.frontBumper,-1,255,-1),
        rearBumper=clampInt(raw.rearBumper,-1,255,-1),
        roofIndex=clampInt(raw.roofIndex,-1,255,-1),
        exhaustIndex=clampInt(raw.exhaustIndex,-1,255,-1),
    }
end

local function mergeTune(base,overlay)
    local out={}
    for k,v in pairs(type(base)=='table' and base or {}) do out[k]=v end
    for k,v in pairs(type(overlay)=='table' and overlay or {}) do
        if v~=nil then out[k]=v end
    end
    return sanitizeTune(out)
end

local function getOwned(src,plate)
    local cid=citizenid(src)
    if not cid then return nil,'시민 정보를 찾을 수 없습니다.' end

    plate=plateNorm(plate)
    if plate=='' then return nil,'번호판을 확인할 수 없습니다.' end

    local r=MySQL.single.await([[
        SELECT id,citizenid,vehicle,plate
        FROM player_vehicles
        WHERE citizenid=?
          AND UPPER(TRIM(plate))=?
        LIMIT 1
    ]],{cid,plate})

    if not r then return nil,'본인 소유 차량만 튜닝할 수 있습니다.' end
    return r
end

local function getStored(vehicleId)
    return MySQL.single.await([[
        SELECT *
        FROM cookie_vehicle_tuning
        WHERE vehicle_id=?
        LIMIT 1
    ]],{vehicleId})
end

local function legacyTune(r)
    if not r then return nil end
    return {
        primary={r.primary_r or 255,r.primary_g or 255,r.primary_b or 255},
        secondary={r.secondary_r or 255,r.secondary_g or 255,r.secondary_b or 255},
        primaryCustom=tonumber(r.primary_custom or 0)==1,
        secondaryCustom=tonumber(r.secondary_custom or 0)==1,
        specialKey=r.special_key or 'none',
        wheelColor=r.wheel_color or 0,
        tyreSmoke={r.tyre_smoke_r or 255,r.tyre_smoke_g or 255,r.tyre_smoke_b or 255},
        tyreSmokeEnabled=true,
        windowTint=r.window_tint or 4,
        engineLevel=r.engine_level or 0,
        speedLevel=r.speed_level or 0,
        brakeLevel=r.brake_level or 0,
        durabilityLevel=r.durability_level or 0,
        turbo=tonumber(r.turbo or 0)==1,
        bulletproofTyres=tonumber(r.bulletproof_tyres or 0)==1,
    }
end

local function decodeStored(r,base)
    if not r then return sanitizeTune(base) end

    local decoded=nil
    if r.tuning_json and tostring(r.tuning_json)~='' then
        local ok,val=pcall(json.decode,r.tuning_json)
        if ok and type(val)=='table' then decoded=val end
    end

    if decoded then return mergeTune(base,decoded) end
    return mergeTune(base,legacyTune(r))
end

local function sameRgb(a,b)
    return tonumber(a and a[1])==tonumber(b and b[1])
       and tonumber(a and a[2])==tonumber(b and b[2])
       and tonumber(a and a[3])==tonumber(b and b[3])
end

local function sameSides(a,b)
    a=a or {}; b=b or {}
    return toBool(a.left)==toBool(b.left)
       and toBool(a.right)==toBool(b.right)
       and toBool(a.front)==toBool(b.front)
       and toBool(a.back)==toBool(b.back)
end

local function changedExtras(a,b)
    a=a or {}; b=b or {}
    local ids={}
    for k in pairs(a) do ids[k]=true end
    for k in pairs(b) do ids[k]=true end
    local n=0
    for k in pairs(ids) do
        if toBool(a[k])~=toBool(b[k]) then n=n+1 end
    end
    return n
end

local function levelPrice(oldV,newV,unit)
    local diff=math.abs((tonumber(newV) or 0)-(tonumber(oldV) or 0))
    return diff*(tonumber(unit) or 0)
end

local function priceFor(old,new)
    local p=Config.Prices or {}
    local total=0
    local lines={}

    local function add(label,amount)
        amount=math.max(0,math.floor(tonumber(amount) or 0))
        if amount<=0 then return end
        total=total+amount
        lines[#lines+1]={label=label,price=amount}
    end

    if not sameRgb(old.primary,new.primary)
       or old.primaryCustom~=new.primaryCustom
       or tonumber(old.primaryIndex)~=tonumber(new.primaryIndex) then
        add('1차 색상',p.primaryColor)
    end

    if not sameRgb(old.secondary,new.secondary)
       or old.secondaryCustom~=new.secondaryCustom
       or tonumber(old.secondaryIndex)~=tonumber(new.secondaryIndex) then
        add('2차 색상',p.secondaryColor)
    end

    if tostring(old.specialKey)~=tostring(new.specialKey) then
        add('특수 페인트',p.specialPaint)
    end

    if tonumber(old.wheelColor)~=tonumber(new.wheelColor) then add('휠 색상',p.wheelColor) end
    if tonumber(old.windowTint)~=tonumber(new.windowTint) then add('유리 썬팅',p.windowTint) end
    if tonumber(old.interiorColor)~=tonumber(new.interiorColor) then add('내부 색상',p.interiorColor) end

    add('엔진',levelPrice(old.engineLevel,new.engineLevel,p.enginePerLevel))
    add('속도',levelPrice(old.speedLevel,new.speedLevel,p.speedPerLevel))
    add('내구도',levelPrice(old.durabilityLevel,new.durabilityLevel,p.durabilityPerLevel))
    add('브레이크',levelPrice(old.brakeLevel,new.brakeLevel,p.brakePerLevel))
    add('서스펜션',levelPrice(old.suspensionLevel,new.suspensionLevel,p.suspensionPerLevel))
    add('미션',levelPrice(old.transmissionLevel,new.transmissionLevel,p.transmissionPerLevel))

    if old.turbo~=new.turbo then add('터보',p.turbo) end
    if old.bulletproofTyres~=new.bulletproofTyres then add('타이어',p.bulletproofTyres) end
    if tonumber(old.hornIndex)~=tonumber(new.hornIndex) then add('경적',p.horn) end

    if old.xenonEnabled~=new.xenonEnabled
       or tonumber(old.xenonColor)~=tonumber(new.xenonColor) then
        add('헤드라이트',p.xenon)
    end

    if tostring(old.engineAudio)~=tostring(new.engineAudio) then add('배기음',p.engineAudio) end

    local extraCount=changedExtras(old.extras,new.extras)
    if extraCount>0 then add(('차량 엑스트라 ×%d'):format(extraCount),extraCount*(p.extrasEach or 0)) end

    if tonumber(old.plateStyle)~=tonumber(new.plateStyle) then add('번호판 색상',p.plateStyle) end

    if old.neonEnabled~=new.neonEnabled
       or not sameRgb(old.neonColor,new.neonColor)
       or not sameSides(old.neonSides,new.neonSides) then
        add('네온',p.neon)
    end

    if tonumber(old.wheelType)~=tonumber(new.wheelType)
       or tonumber(old.wheelIndex)~=tonumber(new.wheelIndex) then
        add('휠',p.wheelModel)
    end

    if not sameRgb(old.tyreSmoke,new.tyreSmoke)
       or old.tyreSmokeEnabled~=new.tyreSmokeEnabled then
        add('타이어 연기',p.tyreSmokeColor)
    end

    if tonumber(old.frontBumper)~=tonumber(new.frontBumper) then add('앞범퍼',p.frontBumper) end
    if tonumber(old.rearBumper)~=tonumber(new.rearBumper) then add('뒷범퍼',p.rearBumper) end
    if tonumber(old.roofIndex)~=tonumber(new.roofIndex) then add('루프',p.roof) end
    if tonumber(old.exhaustIndex)~=tonumber(new.exhaustIndex) then add('배기구 외형',p.exhaust) end

    return total,lines
end

local function moneySnapshot(p)
    local m=p and p.PlayerData and p.PlayerData.money or {}
    return {
        bank=math.max(0,math.floor(tonumber(m.bank) or 0)),
        cash=math.max(0,math.floor(tonumber(m.cash) or 0)),
    }
end

local function charge(src,amount,reason)
    amount=math.max(0,math.floor(tonumber(amount) or 0))
    if amount<=0 then return true,'free' end

    local p=player(src)
    if not p then return false,'플레이어 정보를 찾을 수 없습니다.' end
    local snap=moneySnapshot(p)

    for _,account in ipairs(Config.PaymentOrder or {'bank','cash'}) do
        if (tonumber(snap[account]) or 0)>=amount then
            local ok=p.Functions.RemoveMoney(account,amount,reason or 'COOKIE 튜닝샵')
            if ok~=false then return true,account end
        end
    end

    return false,'잔액이 부족합니다.'
end

local function refund(src,account,amount)
    if account=='free' or not account or (tonumber(amount) or 0)<=0 then return end
    local p=player(src)
    if p then p.Functions.AddMoney(account,amount,'COOKIE 튜닝 저장 실패 환불') end
end

local function saveTune(owned,t)
    local encoded=json.encode(t)

    MySQL.query.await([[
        INSERT INTO cookie_vehicle_tuning (
            vehicle_id,citizenid,plate,model,
            primary_r,primary_g,primary_b,primary_custom,
            secondary_r,secondary_g,secondary_b,secondary_custom,
            special_key,wheel_color,
            tyre_smoke_r,tyre_smoke_g,tyre_smoke_b,
            window_tint,
            engine_level,speed_level,brake_level,durability_level,
            turbo,bulletproof_tyres,
            tuning_json
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE
            citizenid=VALUES(citizenid),
            plate=VALUES(plate),
            model=VALUES(model),
            primary_r=VALUES(primary_r),primary_g=VALUES(primary_g),primary_b=VALUES(primary_b),
            primary_custom=VALUES(primary_custom),
            secondary_r=VALUES(secondary_r),secondary_g=VALUES(secondary_g),secondary_b=VALUES(secondary_b),
            secondary_custom=VALUES(secondary_custom),
            special_key=VALUES(special_key),
            wheel_color=VALUES(wheel_color),
            tyre_smoke_r=VALUES(tyre_smoke_r),tyre_smoke_g=VALUES(tyre_smoke_g),tyre_smoke_b=VALUES(tyre_smoke_b),
            window_tint=VALUES(window_tint),
            engine_level=VALUES(engine_level),
            speed_level=VALUES(speed_level),
            brake_level=VALUES(brake_level),
            durability_level=VALUES(durability_level),
            turbo=VALUES(turbo),
            bulletproof_tyres=VALUES(bulletproof_tyres),
            tuning_json=VALUES(tuning_json),
            updated_at=CURRENT_TIMESTAMP
    ]],{
        owned.id,owned.citizenid,plateNorm(owned.plate),clean(owned.vehicle,64),
        t.primary[1],t.primary[2],t.primary[3],t.primaryCustom and 1 or 0,
        t.secondary[1],t.secondary[2],t.secondary[3],t.secondaryCustom and 1 or 0,
        t.specialKey,t.wheelColor,
        t.tyreSmoke[1],t.tyreSmoke[2],t.tyreSmoke[3],
        t.windowTint,
        t.engineLevel,t.speedLevel,t.brakeLevel,t.durabilityLevel,
        t.turbo and 1 or 0,t.bulletproofTyres and 1 or 0,
        encoded
    })
end

local function sessionFor(src,owned)
    local s=sessions[src]
    if not s then return nil end
    if os.time()>(tonumber(s.expiresAt) or 0) then
        sessions[src]=nil
        return nil
    end
    if tonumber(s.vehicleId)~=tonumber(owned.id) or s.plate~=plateNorm(owned.plate) then return nil end
    return s
end

lib.callback.register('cookie_tuningshop:server:open',function(src,payload)
    payload=type(payload)=='table' and payload or {}

    local owned,msg=getOwned(src,payload.plate)
    if not owned then return {ok=false,message=msg} end

    local base=sanitizeTune(payload.baseTuning)
    local storedRow=getStored(owned.id)
    local current=decodeStored(storedRow,base)

    -- V1 데이터가 있으면 V2 JSON으로 자동 승격.
    if storedRow and (not storedRow.tuning_json or tostring(storedRow.tuning_json)=='') then
        pcall(function() saveTune(owned,current) end)
    end

    local repairRequired=payload.damageRequired==true
    sessions[src]={
        vehicleId=tonumber(owned.id),
        plate=plateNorm(owned.plate),
        repairRequired=repairRequired,
        repaired=not repairRequired,
        expiresAt=os.time()+(Config.SessionSeconds or 600),
        baseTuning=base,
    }

    return {
        ok=true,
        vehicleId=tonumber(owned.id),
        model=tostring(owned.vehicle or ''),
        plate=plateNorm(owned.plate),
        tuning=current,
        money=moneySnapshot(player(src)),
        repairRequired=repairRequired,
        repairPrice=Config.FullRepairPrice or 300000,

        prices=Config.Prices,
        specialPaints=Config.SpecialPaints,
        wheelColors=Config.WheelColors,
        windowTints=Config.WindowTints,
        xenonColors=Config.XenonColors,
        plateStyles=Config.PlateStyles,
        wheelTypes=Config.WheelTypes,
        interiorColors=Config.InteriorColors,
        engineAudios=Config.EngineAudios,

        maxLevels={
            engine=Config.MaxEngineLevel or 5,
            speed=Config.MaxSpeedLevel or 5,
            durability=Config.MaxDurabilityLevel or 5,
            brake=Config.MaxBrakeLevel or 5,
            suspension=Config.MaxSuspensionLevel or 5,
            transmission=Config.MaxTransmissionLevel or 5,
        }
    }
end)

lib.callback.register('cookie_tuningshop:server:repair',function(src,plate)
    local owned,msg=getOwned(src,plate)
    if not owned then return {ok=false,message=msg} end

    local s=sessionFor(src,owned)
    if not s then return {ok=false,message='튜닝 세션이 만료되었습니다. 다시 열어주세요.'} end
    if s.repaired then
        return {ok=true,message='이미 수리가 완료된 차량입니다.',money=moneySnapshot(player(src))}
    end

    local price=math.max(0,math.floor(tonumber(Config.FullRepairPrice) or 300000))
    local ok,payment=charge(src,price,'COOKIE 튜닝샵 전체 수리')
    if not ok then return {ok=false,message=payment} end

    s.repaired=true
    s.repairRequired=false

    return {
        ok=true,
        message=('전체 수리 완료 · %s원'):format(price),
        price=price,
        payment=payment,
        money=moneySnapshot(player(src))
    }
end)

lib.callback.register('cookie_tuningshop:server:getByPlate',function(src,plate)
    local owned=getOwned(src,plate)
    if not owned then return nil end

    local r=getStored(owned.id)
    if not r then return nil end
    return decodeStored(r,{})
end)

lib.callback.register('cookie_tuningshop:server:purchase',function(src,payload)
    payload=type(payload)=='table' and payload or {}

    local owned,msg=getOwned(src,payload.plate)
    if not owned then return {ok=false,message=msg} end

    local s=sessionFor(src,owned)
    if not s then return {ok=false,message='튜닝 세션이 만료되었습니다. 다시 열어주세요.'} end
    if s.repairRequired and not s.repaired then
        return {ok=false,message='차량이 손상되어 있습니다. 전체 수리를 먼저 진행해주세요.'}
    end

    local stored=getStored(owned.id)
    local old=decodeStored(stored,s.baseTuning or payload.baseTuning or {})
    local new=sanitizeTune(payload.tuning)

    local total,lines=priceFor(old,new)
    local ok,payment=charge(src,total,'COOKIE 차량 튜닝')
    if not ok then return {ok=false,message=payment,total=total} end

    local success,err=pcall(function()
        saveTune(owned,new)
        MySQL.insert.await([[
            INSERT INTO cookie_vehicle_tuning_history
              (vehicle_id,citizenid,plate,model,total_price,payment_type,detail_json)
            VALUES (?,?,?,?,?,?,?)
        ]],{
            owned.id,owned.citizenid,plateNorm(owned.plate),clean(owned.vehicle,64),
            total,payment,json.encode(lines)
        })
    end)

    if not success then
        refund(src,payment,total)
        print('[cookie_tuningshop] save error: '..tostring(err))
        return {ok=false,message='튜닝 저장에 실패했습니다. 결제금액은 환불되었습니다.'}
    end

    return {
        ok=true,
        message=('튜닝 적용 완료 · %s원'):format(total),
        total=total,
        payment=payment,
        tuning=new,
        money=moneySnapshot(player(src))
    }
end)

RegisterNetEvent('cookie_tuningshop:server:closeSession',function()
    sessions[source]=nil
end)

AddEventHandler('playerDropped',function()
    sessions[source]=nil
end)

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_vehicle_tuning (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            vehicle_id BIGINT UNSIGNED NOT NULL,
            citizenid VARCHAR(64) NOT NULL,
            plate VARCHAR(24) NOT NULL,
            model VARCHAR(64) NOT NULL,

            primary_r SMALLINT NOT NULL DEFAULT 255,
            primary_g SMALLINT NOT NULL DEFAULT 255,
            primary_b SMALLINT NOT NULL DEFAULT 255,
            primary_custom TINYINT(1) NOT NULL DEFAULT 0,

            secondary_r SMALLINT NOT NULL DEFAULT 255,
            secondary_g SMALLINT NOT NULL DEFAULT 255,
            secondary_b SMALLINT NOT NULL DEFAULT 255,
            secondary_custom TINYINT(1) NOT NULL DEFAULT 0,

            special_key VARCHAR(40) NOT NULL DEFAULT 'none',
            wheel_color INT NOT NULL DEFAULT 0,

            tyre_smoke_r SMALLINT NOT NULL DEFAULT 255,
            tyre_smoke_g SMALLINT NOT NULL DEFAULT 255,
            tyre_smoke_b SMALLINT NOT NULL DEFAULT 255,

            window_tint TINYINT NOT NULL DEFAULT 4,

            engine_level TINYINT UNSIGNED NOT NULL DEFAULT 0,
            speed_level TINYINT UNSIGNED NOT NULL DEFAULT 0,
            brake_level TINYINT UNSIGNED NOT NULL DEFAULT 0,
            durability_level TINYINT UNSIGNED NOT NULL DEFAULT 0,

            turbo TINYINT(1) NOT NULL DEFAULT 0,
            bulletproof_tyres TINYINT(1) NOT NULL DEFAULT 0,

            tuning_json LONGTEXT NULL,

            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

            PRIMARY KEY(id),
            UNIQUE KEY uq_cookie_tuning_vehicle(vehicle_id),
            KEY idx_cookie_tuning_plate(plate),
            KEY idx_cookie_tuning_citizen(citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    local function ensureColumn(name,ddl)
        local n=MySQL.scalar.await([[
            SELECT COUNT(*)
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA=DATABASE()
              AND TABLE_NAME='cookie_vehicle_tuning'
              AND COLUMN_NAME=?
        ]],{name})
        if tonumber(n or 0)==0 then
            MySQL.query.await(('ALTER TABLE cookie_vehicle_tuning ADD COLUMN %s'):format(ddl))
        end
    end

    ensureColumn('window_tint',"window_tint TINYINT NOT NULL DEFAULT 4 AFTER tyre_smoke_b")
    ensureColumn('tuning_json',"tuning_json LONGTEXT NULL AFTER bulletproof_tyres")

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_vehicle_tuning_history (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            vehicle_id BIGINT UNSIGNED NOT NULL,
            citizenid VARCHAR(64) NOT NULL,
            plate VARCHAR(24) NOT NULL,
            model VARCHAR(64) NOT NULL,
            total_price BIGINT NOT NULL DEFAULT 0,
            payment_type VARCHAR(20) NULL,
            detail_json LONGTEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(id),
            KEY idx_cookie_tuning_history_vehicle(vehicle_id,created_at),
            KEY idx_cookie_tuning_history_citizen(citizenid,created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    print('^2[cookie_tuningshop]^7 V2 ready · repair + full tuning')
end)
