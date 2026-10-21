local crimeEscorts={}
local function getMember(src)
 if GetResourceState('cookie_admin')~='started' then return nil end
 local ok,m=pcall(function() return exports.cookie_admin:getFactionOf(src) end);if not ok then return nil end;return m
end
local function isTow(m) if not m then return false end;local t=tostring(m.type or m.faction_type or ''):lower();return t=='tow' or tostring(m.name or ''):find('렉카',1,true)~=nil end
local function isCrime(m) return m and tostring(m.type or m.faction_type or ''):lower()=='crime' end
local function playerObj(src) return exports.qbx_core:GetPlayer(src) end
local function playerCid(src) local p=playerObj(src);return p and p.PlayerData and p.PlayerData.citizenid or nil end
local function validNear(src,target,dist) target=tonumber(target);if not target or not GetPlayerName(target) then return false end;local a,b=GetPlayerPed(src),GetPlayerPed(target);if a==0 or b==0 then return false end;return #(GetEntityCoords(a)-GetEntityCoords(b))<=(dist or 4.5) end
local function normPlate(v) return tostring(v or ''):upper():gsub('%s+','') end

CreateThread(function()
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_tow_impound (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,faction_id INT NOT NULL,vehicle_id INT NOT NULL,citizenid VARCHAR(64) NOT NULL,plate VARCHAR(20) NOT NULL,vehicle VARCHAR(80) NOT NULL,old_garage VARCHAR(100) NULL,old_state INT NOT NULL DEFAULT 1,reason VARCHAR(255) NOT NULL DEFAULT '렉카 압류',actor_citizenid VARCHAR(64) NULL,active TINYINT(1) NOT NULL DEFAULT 1,created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,released_at TIMESTAMP NULL DEFAULT NULL,KEY idx_active_faction (faction_id,active),KEY idx_plate (plate)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_tow_scrap_log (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,faction_id INT NOT NULL,vehicle_id INT NOT NULL,citizenid VARCHAR(64) NOT NULL,plate VARCHAR(20) NOT NULL,vehicle VARCHAR(80) NOT NULL,actor_citizenid VARCHAR(64) NULL,created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end)

lib.callback.register('cookie_factionphone:getProfile',function(src)
 local m=getMember(src);if not m then return {allowed=false,reason='가입된 팩션이 없습니다.'} end
 local t=tostring(m.type or m.faction_type or ''):lower();local mode=isTow(m) and 'tow' or t
 return {allowed=true,faction={id=tonumber(m.id),name=tostring(m.name or '팩션'),type=t,mode=mode,rank=tostring(m.rank or m.rank_name or m.grade_label or '직원'),grade=tonumber(m.grade or 0) or 0,duty=m.duty~=false,isOfficer=m.isOfficer==true or m.is_officer==true,isLeader=m.isLeader==true or m.is_leader==true}}
end)

lib.callback.register('cookie_factionphone:account',function(src)
 local m=getMember(src);if not m then return {ok=false,message='팩션 소속이 아닙니다.'} end
 local balance=tonumber(MySQL.scalar.await('SELECT budget FROM cookie_faction WHERE id=?',{m.id}) or 0) or 0
 local p=playerObj(src);local bank=p and p.PlayerData and p.PlayerData.money and tonumber(p.PlayerData.money.bank or 0) or 0
 return {ok=true,balance=balance,bank=bank,canWithdraw=(m.isOfficer==true or m.is_officer==true or m.isLeader==true or m.is_leader==true)}
end)

lib.callback.register('cookie_factionphone:accountAction',function(src,mode,amount,reason)
 local m=getMember(src);if not m then return {ok=false,message='팩션 소속이 아닙니다.'} end
 amount=math.floor(tonumber(amount) or 0);if amount<=0 then return {ok=false,message='금액을 확인해주세요.'} end;if amount>1000000000 then return {ok=false,message='한 번에 처리할 수 있는 금액을 초과했습니다.'} end
 reason=tostring(reason or ''):sub(1,180);local p=playerObj(src);if not p then return {ok=false,message='플레이어 정보를 찾지 못했습니다.'} end;local cid=playerCid(src)
 if mode=='deposit' then
  if p.Functions.RemoveMoney('bank',amount,'팩션 공동계좌 입금')~=true then return {ok=false,message='은행 잔액이 부족합니다.'} end
  MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=?',{amount,m.id});local bal=tonumber(MySQL.scalar.await('SELECT budget FROM cookie_faction WHERE id=?',{m.id}) or 0) or 0
  pcall(function() MySQL.insert.await('INSERT INTO cookie_faction_budget_log (faction_id,delta,balance_after,category,reason,actor_citizenid) VALUES (?,?,?,?,?,?)',{m.id,amount,bal,'field_deposit',reason~='' and reason or '현장 단말기 입금',cid}) end)
  return {ok=true,message='공동계좌에 입금했습니다.',balance=bal}
 elseif mode=='withdraw' then
  local officer=m.isOfficer==true or m.is_officer==true or m.isLeader==true or m.is_leader==true;if not officer then return {ok=false,message='출금 권한이 없습니다.'} end
  local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget-? WHERE id=? AND budget>=?',{amount,m.id,amount});if not changed or changed<1 then return {ok=false,message='공동계좌 잔액이 부족합니다.'} end
  p.Functions.AddMoney('bank',amount,'팩션 공동계좌 출금');local bal=tonumber(MySQL.scalar.await('SELECT budget FROM cookie_faction WHERE id=?',{m.id}) or 0) or 0
  pcall(function() MySQL.insert.await('INSERT INTO cookie_faction_budget_log (faction_id,delta,balance_after,category,reason,actor_citizenid) VALUES (?,?,?,?,?,?)',{m.id,-amount,bal,'field_withdraw',reason~='' and reason or '현장 단말기 출금',cid}) end)
  return {ok=true,message='공동계좌에서 출금했습니다.',balance=bal}
 end
 return {ok=false,message='잘못된 요청입니다.'}
end)

RegisterNetEvent('cookie_factionphone:server:crimeCuff',function(target)
 local src=source;local m=getMember(src);if not isCrime(m) or not validNear(src,target,4.0) then return end;target=tonumber(target)
 local bag=Player(target);local current=bag and bag.state and bag.state.cookieCuffed==true;local nextState=not current
 if bag and bag.state then bag.state:set('cookieCuffed',nextState,true) end
 if not nextState and crimeEscorts[target] then crimeEscorts[target]=nil;TriggerClientEvent('cookie_factionphone:client:setCrimeEscorted',target,nil) end
 TriggerClientEvent('cookie_factionphone:client:setCrimeCuffed',target,nextState);TriggerClientEvent('cookie_factionphone:client:notify',src,nextState and '대상에게 수갑을 채웠습니다.' or '수갑을 해제했습니다.',false)
end)

RegisterNetEvent('cookie_factionphone:server:crimeEscort',function(target)
 local src=source;local m=getMember(src);if not isCrime(m) or not validNear(src,target,4.5) then return end;target=tonumber(target)
 local bag=Player(target);if not (bag and bag.state and bag.state.cookieCuffed==true) then return TriggerClientEvent('cookie_factionphone:client:notify',src,'수갑 상태 대상만 끌고 갈 수 있습니다.',true) end
 if crimeEscorts[target]==src then crimeEscorts[target]=nil;TriggerClientEvent('cookie_factionphone:client:setCrimeEscorted',target,nil);return TriggerClientEvent('cookie_factionphone:client:notify',src,'끌고가기를 해제했습니다.',false) end
 crimeEscorts[target]=src;TriggerClientEvent('cookie_factionphone:client:setCrimeEscorted',target,src);TriggerClientEvent('cookie_factionphone:client:notify',src,'대상을 끌고 갑니다.',false)
end)

local function towVehicleRow(plate) return MySQL.single.await("SELECT id,citizenid,vehicle,plate,garage,state FROM player_vehicles WHERE REPLACE(UPPER(plate),' ','')=? ORDER BY id DESC LIMIT 1",{normPlate(plate)}) end
local function towBlocked(row)
 if not row then return true,'소유 차량이 아닙니다.' end
 local factionGarage=MySQL.single.await('SELECT id FROM cookie_faction WHERE garage_key=? LIMIT 1',{row.garage});if factionGarage then return true,'팩션 차량은 처리할 수 없습니다.' end
 local limited=MySQL.single.await('SELECT id FROM cookie_limited_vehicles WHERE LOWER(model)=LOWER(?) AND active=1 LIMIT 1',{row.vehicle});if limited then return true,'한정/특수 차량은 처리할 수 없습니다.' end
 return false
end

lib.callback.register('cookie_factionphone:towImpound',function(src,data)
 local m=getMember(src);if not isTow(m) then return {ok=false,message='렉카 팩션 전용 기능입니다.'} end
 local row=towVehicleRow(data and data.plate);local blocked,why=towBlocked(row);if blocked then return {ok=false,message=why} end
 if MySQL.single.await('SELECT id FROM cookie_tow_impound WHERE vehicle_id=? AND active=1 LIMIT 1',{row.id}) then return {ok=false,message='이미 압류된 차량입니다.'} end
 MySQL.insert.await('INSERT INTO cookie_tow_impound (faction_id,vehicle_id,citizenid,plate,vehicle,old_garage,old_state,actor_citizenid) VALUES (?,?,?,?,?,?,?,?)',{m.id,row.id,row.citizenid,row.plate,row.vehicle,row.garage,row.state,playerCid(src)})
 MySQL.update.await("UPDATE player_vehicles SET state=2,garage='cookie_tow_impound' WHERE id=?",{row.id})
 return {ok=true,message=('차량 %s을(를) 압류했습니다.'):format(row.plate)}
end)

lib.callback.register('cookie_factionphone:towScrap',function(src,data)
 local m=getMember(src);if not isTow(m) then return {ok=false,message='렉카 팩션 전용 기능입니다.'} end
 local row=towVehicleRow(data and data.plate);local blocked,why=towBlocked(row);if blocked then return {ok=false,message=why} end
 MySQL.insert.await('INSERT INTO cookie_tow_scrap_log (faction_id,vehicle_id,citizenid,plate,vehicle,actor_citizenid) VALUES (?,?,?,?,?,?)',{m.id,row.id,row.citizenid,row.plate,row.vehicle,playerCid(src)})
 MySQL.update.await('UPDATE cookie_tow_impound SET active=0,released_at=NOW() WHERE vehicle_id=? AND active=1',{row.id});MySQL.query.await('DELETE FROM player_vehicles WHERE id=?',{row.id})
 return {ok=true,message=('차량 %s을(를) 폐차했습니다.'):format(row.plate)}
end)

lib.callback.register('cookie_factionphone:towList',function(src)
 local m=getMember(src);if not isTow(m) then return {ok=false,rows={}} end
 local rows=MySQL.query.await('SELECT id,plate,vehicle,reason,created_at FROM cookie_tow_impound WHERE faction_id=? AND active=1 ORDER BY id DESC LIMIT 100',{m.id}) or {}
 return {ok=true,rows=rows,canRelease=(m.isOfficer==true or m.is_officer==true or m.isLeader==true or m.is_leader==true)}
end)

lib.callback.register('cookie_factionphone:towRelease',function(src,id)
 local m=getMember(src);if not isTow(m) then return {ok=false,message='렉카 팩션 전용 기능입니다.'} end
 local officer=m.isOfficer==true or m.is_officer==true or m.isLeader==true or m.is_leader==true;if not officer then return {ok=false,message='압류 해제 권한이 없습니다.'} end
 local row=MySQL.single.await('SELECT * FROM cookie_tow_impound WHERE id=? AND faction_id=? AND active=1',{id,m.id});if not row then return {ok=false,message='압류 정보를 찾을 수 없습니다.'} end
 MySQL.update.await('UPDATE player_vehicles SET garage=?,state=? WHERE id=?',{row.old_garage or 'pillboxgarage',tonumber(row.old_state) or 1,row.vehicle_id});MySQL.update.await('UPDATE cookie_tow_impound SET active=0,released_at=NOW() WHERE id=?',{row.id})
 return {ok=true,message='압류를 해제했습니다.'}
end)

AddEventHandler('playerDropped',function() local src=source;crimeEscorts[src]=nil;for target,officer in pairs(crimeEscorts) do if officer==src then crimeEscorts[target]=nil;TriggerClientEvent('cookie_factionphone:client:setCrimeEscorted',target,nil) end end end)
print('^2[COOKIE FACTION TABLET]^7 server V2.0.0 ready')
