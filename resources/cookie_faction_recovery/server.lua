local crimeCuffed={}
local crimeEscorts={}

local function player(src)
    local ok,p=pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if ok then return p end
end

local function citizenid(src)
    local p=player(src)
    return p and p.PlayerData and tostring(p.PlayerData.citizenid or '') or ''
end

local function normalize(m)
    if not m then return nil end
    local t=tostring(m.type or m.faction_type or m.factionType or '')
    local name=tostring(m.name or m.faction_name or m.label or '')
    return {
        id=tonumber(m.id or m.faction_id),
        name=name,
        type=t,
        grade=tonumber(m.grade) or 0,
        duty=m.duty==true or tonumber(m.duty)==1,
        isOfficer=m.isOfficer==true or tonumber(m.isOfficer)==1 or tonumber(m.is_officer)==1,
        isLeader=m.isLeader==true or tonumber(m.isLeader)==1 or tonumber(m.is_leader)==1,
        isTow=(t=='tow') or (name:find('렉카',1,true)~=nil)
    }
end

local function dbMember(src)
    local cid=citizenid(src)
    if cid=='' then return nil end
    local row=MySQL.single.await([[
        SELECT f.id,f.name,f.faction_type AS type,fm.grade,fm.duty,
               COALESCE(fr.is_officer,0) AS is_officer,
               COALESCE(fr.is_leader,0) AS is_leader
        FROM cookie_faction_member fm
        JOIN cookie_faction f ON f.id=fm.faction_id
        LEFT JOIN cookie_faction_rank fr ON fr.faction_id=fm.faction_id AND fr.grade=fm.grade
        WHERE fm.citizenid=? AND fm.status='active' AND f.is_active=1
        ORDER BY f.id DESC LIMIT 1
    ]],{cid})
    return normalize(row)
end

local function member(src)
    if GetResourceState('cookie_admin')=='started' then
        local ok,m=pcall(function() return exports.cookie_admin:getFactionOf(src) end)
        if ok and m then
            local n=normalize(m)
            if n and n.id then
                if n.name=='' or n.type=='' then
                    local row=MySQL.single.await('SELECT name,faction_type FROM cookie_faction WHERE id=? LIMIT 1',{n.id})
                    if row then
                        if n.name=='' then n.name=tostring(row.name or '') end
                        if n.type=='' then n.type=tostring(row.faction_type or '') end
                        n.isTow=n.type=='tow' or n.name:find('렉카',1,true)~=nil
                    end
                end
                return n
            end
        end
    end
    return dbMember(src)
end

local function ret(ok,msg,extra)
    local r=extra or {}
    r.ok=ok==true
    r.message=msg
    return r
end

local function budget(fid)
    return tonumber(MySQL.scalar.await('SELECT budget FROM cookie_faction WHERE id=? LIMIT 1',{fid}) or 0) or 0
end

local function budgetLog(fid,delta,category,reason,cid)
    local b=budget(fid)
    MySQL.insert.await([[
        INSERT INTO cookie_faction_budget_log
        (faction_id,delta,balance_after,category,reason,actor_citizenid)
        VALUES (?,?,?,?,?,?)
    ]],{fid,delta,b,category,reason,cid})
    return b
end

lib.callback.register('cookie_faction_recovery:profile',function(src)
    local m=member(src)
    if not m then return {allowed=false,reason='소속 팩션을 찾지 못했습니다.'} end
    return {
        allowed=true,id=m.id,name=m.name,type=m.type,grade=m.grade,duty=m.duty,
        isOfficer=m.isOfficer,isLeader=m.isLeader,isTow=m.isTow
    }
end)

lib.callback.register('cookie_faction_recovery:accountOverview',function(src)
    local m=member(src)
    if not m then return ret(false,'소속 팩션이 없습니다.') end
    local p=player(src)
    if not p then return ret(false,'플레이어 정보를 찾지 못했습니다.') end
    local logs=MySQL.query.await([[
        SELECT delta,balance_after,category,reason,created_at
        FROM cookie_faction_budget_log
        WHERE faction_id=? ORDER BY id DESC LIMIT 15
    ]],{m.id}) or {}
    return {
        ok=true,balance=budget(m.id),
        bank=tonumber(p.PlayerData.money and p.PlayerData.money.bank or 0) or 0,
        canWithdraw=m.isOfficer or m.isLeader,
        logs=logs
    }
end)

lib.callback.register('cookie_faction_recovery:deposit',function(src,data)
    local m=member(src)
    if not m then return ret(false,'소속 팩션이 없습니다.') end
    local amount=math.floor(tonumber(data and data.amount) or 0)
    if amount<=0 then return ret(false,'입금 금액이 올바르지 않습니다.') end
    local p=player(src)
    if not p then return ret(false,'플레이어 정보를 찾지 못했습니다.') end
    if not p.Functions.RemoveMoney('bank',amount,'팩션 공동계좌 수동 입금') then
        return ret(false,'은행 잔액이 부족합니다.')
    end
    local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=? AND is_active=1',{amount,m.id})
    if not changed or changed<1 then
        p.Functions.AddMoney('bank',amount,'공동계좌 입금 실패 환불')
        return ret(false,'입금 실패로 환불했습니다.')
    end
    local reason=tostring(data and data.reason or '')
    if reason=='' then reason='수동 입금' end
    local b=budgetLog(m.id,amount,'field_deposit',reason,citizenid(src))
    return ret(true,('%d원 입금 완료 · 공계 %d원'):format(amount,b))
end)

lib.callback.register('cookie_faction_recovery:withdraw',function(src,data)
    local m=member(src)
    if not m then return ret(false,'소속 팩션이 없습니다.') end
    if not (m.isOfficer or m.isLeader) then return ret(false,'간부/대표 권한이 필요합니다.') end
    local amount=math.floor(tonumber(data and data.amount) or 0)
    if amount<=0 then return ret(false,'출금 금액이 올바르지 않습니다.') end
    local reason=tostring(data and data.reason or '')
    if reason=='' then return ret(false,'출금 사유를 입력하세요.') end
    local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget-? WHERE id=? AND is_active=1 AND budget>=?',{amount,m.id,amount})
    if not changed or changed<1 then return ret(false,'공동계좌 잔액이 부족합니다.') end
    local p=player(src)
    if not p or not p.Functions.AddMoney('bank',amount,'팩션 공동계좌 수동 출금') then
        MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=?',{amount,m.id})
        return ret(false,'출금 실패로 잔액을 복구했습니다.')
    end
    local b=budgetLog(m.id,-amount,'field_withdraw',reason,citizenid(src))
    return ret(true,('%d원 출금 완료 · 공계 %d원'):format(amount,b))
end)

local function normPlate(v)
    return tostring(v or ''):upper():gsub('%s+','')
end

local function towMember(src)
    local m=member(src)
    if not m or not m.isTow then return nil,'렉카 팩션만 사용할 수 있습니다.' end
    return m
end

local function rowByPlate(plate)
    return MySQL.single.await([[
        SELECT id,citizenid,vehicle,plate,garage,state
        FROM player_vehicles
        WHERE REPLACE(UPPER(plate),' ','')=?
        LIMIT 1
    ]],{normPlate(plate)})
end

local function nearbyEntity(src,netId,plate)
    local ped=GetPlayerPed(src)
    if ped==0 then return nil,'플레이어 위치를 확인할 수 없습니다.' end
    local ent=NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if ent==0 or not DoesEntityExist(ent) then return nil,'대상 차량이 존재하지 않습니다.' end
    if #(GetEntityCoords(ped)-GetEntityCoords(ent))>8.0 then return nil,'대상 차량이 너무 멉니다.' end
    local real=normPlate(GetVehicleNumberPlateText(ent))
    if real=='' or real~=normPlate(plate) then return nil,'번호판 검증에 실패했습니다.' end
    return ent
end

local function protected(row)
    if not row then return true,'차량 정보 없음' end
    local owner=tostring(row.citizenid or '')
    if owner:sub(1,8)=='FACTION_' or owner=='LSPD_FLEET' then return true,'팩션 차량은 처리할 수 없습니다.' end
    local limited=false
    pcall(function()
        limited=tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM cookie_limited_vehicles WHERE LOWER(model)=LOWER(?) AND active=1',
            {tostring(row.vehicle or '')}
        ) or 0)>0
    end)
    if limited then return true,'한정/특수 차량은 폐차할 수 없습니다.' end
    return false
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_tow_impound_recovery (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            vehicle_id INT NOT NULL,
            faction_id INT NOT NULL,
            plate VARCHAR(24) NOT NULL,
            vehicle VARCHAR(80) NOT NULL,
            owner_citizenid VARCHAR(60) NOT NULL,
            old_garage VARCHAR(80) NULL,
            reason VARCHAR(180) NULL,
            fee BIGINT NOT NULL DEFAULT 0,
            actor_citizenid VARCHAR(60) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_tow_vehicle (vehicle_id),
            KEY idx_tow_faction (faction_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_tow_scrap_recovery (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            faction_id INT NOT NULL,
            vehicle_id INT NULL,
            plate VARCHAR(24) NOT NULL,
            vehicle VARCHAR(80) NOT NULL,
            owner_citizenid VARCHAR(60) NULL,
            actor_citizenid VARCHAR(60) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            KEY idx_scrap_faction (faction_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    print('^2[cookie_faction_recovery]^7 DB ready')
end)

lib.callback.register('cookie_faction_recovery:towImpound',function(src,data)
    local m,err=towMember(src)
    if not m then return ret(false,err) end
    local ent,verr=nearbyEntity(src,data and data.netId,data and data.plate)
    if not ent then return ret(false,verr) end
    local row=rowByPlate(data and data.plate)
    if not row then return ret(false,'DB에 등록된 개인 차량만 압류할 수 있습니다.') end
    local owner=tostring(row.citizenid or '')
    if owner:sub(1,8)=='FACTION_' or owner=='LSPD_FLEET' then return ret(false,'팩션 차량은 압류할 수 없습니다.') end
    local reason=tostring(data and data.reason or '')
    if reason=='' then return ret(false,'압류 사유를 입력하세요.') end
    local fee=math.max(0,math.floor(tonumber(data and data.fee) or 0))

    MySQL.query.await([[
        INSERT INTO cookie_tow_impound_recovery
        (vehicle_id,faction_id,plate,vehicle,owner_citizenid,old_garage,reason,fee,actor_citizenid)
        VALUES (?,?,?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE
          faction_id=VALUES(faction_id),plate=VALUES(plate),vehicle=VALUES(vehicle),
          owner_citizenid=VALUES(owner_citizenid),old_garage=VALUES(old_garage),
          reason=VALUES(reason),fee=VALUES(fee),actor_citizenid=VALUES(actor_citizenid),
          created_at=CURRENT_TIMESTAMP
    ]],{row.id,m.id,tostring(row.plate or ''),tostring(row.vehicle or ''),owner,tostring(row.garage or ''),reason,fee,citizenid(src)})
    MySQL.update.await('UPDATE player_vehicles SET state=2 WHERE id=?',{row.id})
    pcall(function() DeleteEntity(ent) end)
    return ret(true,('차량 %s 압류 완료'):format(tostring(row.plate or '')))
end)

lib.callback.register('cookie_faction_recovery:towImpounds',function(src)
    local m=towMember(src)
    if not m then return nil end
    return MySQL.query.await([[
        SELECT id,vehicle_id,plate,vehicle,owner_citizenid,old_garage,reason,fee,created_at
        FROM cookie_tow_impound_recovery
        WHERE faction_id=? ORDER BY id DESC LIMIT 100
    ]],{m.id}) or {}
end)

lib.callback.register('cookie_faction_recovery:towRelease',function(src,id)
    local m,err=towMember(src)
    if not m then return ret(false,err) end
    local row=MySQL.single.await('SELECT * FROM cookie_tow_impound_recovery WHERE id=? AND faction_id=? LIMIT 1',{tonumber(id),m.id})
    if not row then return ret(false,'압류 기록을 찾지 못했습니다.') end
    local garage=tostring(row.old_garage or '')
    if garage=='' then garage='cookie_personal_v2' end
    MySQL.update.await('UPDATE player_vehicles SET state=1,garage=? WHERE id=?',{garage,row.vehicle_id})
    MySQL.query.await('DELETE FROM cookie_tow_impound_recovery WHERE id=?',{row.id})
    return ret(true,('%s 차량을 차고로 반환했습니다.'):format(tostring(row.plate or '')))
end)

lib.callback.register('cookie_faction_recovery:towScrap',function(src,data)
    local m,err=towMember(src)
    if not m then return ret(false,err) end
    local ent,verr=nearbyEntity(src,data and data.netId,data and data.plate)
    if not ent then return ret(false,verr) end
    local row=rowByPlate(data and data.plate)
    if not row then return ret(false,'DB에 등록된 개인 차량만 폐차할 수 있습니다.') end
    local yes,why=protected(row)
    if yes then return ret(false,why) end
    MySQL.insert.await([[
        INSERT INTO cookie_tow_scrap_recovery
        (faction_id,vehicle_id,plate,vehicle,owner_citizenid,actor_citizenid)
        VALUES (?,?,?,?,?,?)
    ]],{m.id,row.id,tostring(row.plate or ''),tostring(row.vehicle or ''),tostring(row.citizenid or ''),citizenid(src)})
    MySQL.query.await('DELETE FROM cookie_tow_impound_recovery WHERE vehicle_id=?',{row.id})
    MySQL.query.await('DELETE FROM player_vehicles WHERE id=?',{row.id})
    pcall(function() DeleteEntity(ent) end)
    return ret(true,('%s 차량 폐차 완료'):format(tostring(row.plate or '')))
end)

local function validTarget(src,target,dist)
    target=tonumber(target)
    if not target or target==src or not GetPlayerName(target) then return false end
    local a,b=GetPlayerPed(src),GetPlayerPed(target)
    if a==0 or b==0 then return false end
    return #(GetEntityCoords(a)-GetEntityCoords(b))<=(dist or 4.0)
end

RegisterNetEvent('cookie_faction_recovery:crimeCuff',function(target)
    local src=source
    local m=member(src)
    if not m or m.type~='crime' then return end
    target=tonumber(target)
    if not validTarget(src,target,3.5) then return end
    crimeCuffed[target]=not (crimeCuffed[target]==true)
    if crimeCuffed[target]==false then
        crimeCuffed[target]=nil
        if crimeEscorts[target] then
            crimeEscorts[target]=nil
            TriggerClientEvent('cookie_faction_recovery:setCrimeEscorted',target,nil)
        end
    end
    TriggerClientEvent('cookie_faction_recovery:setCrimeCuffed',target,crimeCuffed[target]==true)
end)

RegisterNetEvent('cookie_faction_recovery:crimeEscort',function(target)
    local src=source
    local m=member(src)
    if not m or m.type~='crime' then return end
    target=tonumber(target)
    if not validTarget(src,target,4.0) or not crimeCuffed[target] then return end
    if crimeEscorts[target]==src then
        crimeEscorts[target]=nil
        TriggerClientEvent('cookie_faction_recovery:setCrimeEscorted',target,nil)
    elseif not crimeEscorts[target] then
        crimeEscorts[target]=src
        TriggerClientEvent('cookie_faction_recovery:setCrimeEscorted',target,src)
    end
end)

AddEventHandler('playerDropped',function()
    local src=source
    crimeCuffed[src]=nil
    crimeEscorts[src]=nil
    for target,escorter in pairs(crimeEscorts) do
        if escorter==src then
            crimeEscorts[target]=nil
            TriggerClientEvent('cookie_faction_recovery:setCrimeEscorted',target,nil)
        end
    end
end)

print('^2[cookie_faction_recovery]^7 SERVER V1.0.0 ready')
