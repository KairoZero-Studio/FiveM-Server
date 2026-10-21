-- COOKIE generic faction intranet. Existing police/security routers remain unchanged.
local function fail(msg) return {ok=false,message=msg} end
local function clean(value,max)
    local s=tostring(value or ''):gsub('%c',' '):gsub('^%s+',''):gsub('%s+$','')
    return s:sub(1,max)
end
local function memberFor(src)
    if GetResourceState('cookie_admin')~='started' then return nil,nil end
    local ok,m=pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    if not ok or not m or not m.id then return nil,nil end
    local kind=tostring(m.type or '')
    local valid=MySQL.scalar.await('SELECT id FROM cookie_faction WHERE id=? AND is_active=1',{tonumber(m.id) or -1})
    if not valid then return nil,nil end

    local gov=false
    local status,res=pcall(function()return exports.cookie_admin:isGovernmentFactionType(kind)end)
    if status then gov=res==true end
    if gov and Config.RequireDutyForGovernmentActions and m.duty~=true then return nil,nil end
    local player=exports.qbx_core:GetPlayer(src)
    if not player or not player.PlayerData or not player.PlayerData.citizenid then return nil,nil end
    return m, player.PlayerData
end
local function scope(src)
    local m,p=memberFor(src)
    if not m then return nil,nil,fail('소속 팩션 및 출근 상태를 확인해주세요.') end
    return m,p,nil
end
local function authorizedLeader(m) return m.isLeader==true or m.isOfficer==true end
local function tableResult(title,columns,rows,actions)
    return {ok=true,kind='table',title=title,columns=columns,rows=rows or {},rowActions=actions}
end
local function dbSetup()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_f5_notices (
        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        faction_id INT NOT NULL,
        author VARCHAR(100) NOT NULL,
        title VARCHAR(120) NOT NULL,
        body TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_faction (faction_id, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_f5_reports (
        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        faction_id INT NOT NULL,
        author_id VARCHAR(64) NOT NULL,
        author VARCHAR(100) NOT NULL,
        title VARCHAR(120) NOT NULL,
        body TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_faction (faction_id, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_f5_leaves (
        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        faction_id INT NOT NULL,
        citizenid VARCHAR(64) NOT NULL,
        author VARCHAR(100) NOT NULL,
        start_date DATE NOT NULL,
        end_date DATE NOT NULL,
        reason VARCHAR(600) NOT NULL,
        status VARCHAR(16) NOT NULL DEFAULT 'pending',
        reviewer VARCHAR(100) DEFAULT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_faction (faction_id, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_tow_impound (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, faction_id INT NOT NULL, vehicle_id INT NOT NULL,
        citizenid VARCHAR(64) NOT NULL, plate VARCHAR(32) NOT NULL, model VARCHAR(80) NOT NULL, reason VARCHAR(300) NOT NULL,
        fee BIGINT NOT NULL DEFAULT 0, active TINYINT(1) NOT NULL DEFAULT 1, impounded_by VARCHAR(64) NOT NULL,
        impounded_name VARCHAR(100) NOT NULL, released_by VARCHAR(64) DEFAULT NULL, released_name VARCHAR(100) DEFAULT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, released_at TIMESTAMP NULL DEFAULT NULL,
        INDEX idx_active_vehicle (vehicle_id,active), INDEX idx_faction_active (faction_id,active)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_tow_scrap_log (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, faction_id INT NOT NULL, vehicle_id INT NOT NULL,
        citizenid VARCHAR(64) NOT NULL, plate VARCHAR(32) NOT NULL, model VARCHAR(80) NOT NULL, agreed_amount BIGINT NOT NULL DEFAULT 0,
        reason VARCHAR(300) NOT NULL, handled_by VARCHAR(64) NOT NULL, handled_name VARCHAR(100) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX idx_faction (faction_id,id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
end
CreateThread(function()
    local ok,err=pcall(dbSetup)
    if not ok then print('^1[COOKIE INTRANET] table setup failed: '..tostring(err)..'^7')
    else print('^2[COOKIE INTRANET] generic faction intranet ready^7') end
end)
local function displayName(src) return clean(GetPlayerName(src) or '직원',100) end

local function isPharmacy(m)
    return Config.IsPharmacyFaction and Config.IsPharmacyFaction(m) == true
end

local function isDaiso(m)
    return Config.IsDaisoFaction and Config.IsDaisoFaction(m) == true
end

local function isTow(m)
    return tostring(m and m.type or '') == 'tow'
end

local function isCrime(m)
    return tostring(m and m.type or '') == 'crime'
end

local function invCount(src,item)
    local ok,n=pcall(function() return exports.ox_inventory:Search(src,'count',item) end)
    return ok and (tonumber(n) or 0) or 0
end

local function comma(value)
    local n = math.floor(tonumber(value) or 0)
    local sign = n < 0 and '-' or ''
    local raw = tostring(math.abs(n))
    local out = raw:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return sign .. out
end

local function won(value)
    return comma(value) .. '원'
end

local function ceilTo(value, unit)
    unit = math.max(1, math.floor(tonumber(unit) or 1))
    return math.ceil((tonumber(value) or 0) / unit) * unit
end

local function pharmacyBudget(factionId)
    return tonumber(MySQL.scalar.await('SELECT budget FROM cookie_faction WHERE id=? AND is_active=1',{factionId}) or 0) or 0
end

local function pharmacyLedger(factionId, delta, balanceAfter, category, reason, citizenid)
    MySQL.insert.await([[INSERT INTO cookie_faction_budget_log
        (faction_id,delta,balance_after,category,reason,actor_citizenid)
        VALUES (?,?,?,?,?,?)]],{
        factionId, math.floor(tonumber(delta) or 0), math.floor(tonumber(balanceAfter) or 0),
        clean(category,24), clean(reason,120), clean(citizenid,50)
    })
end
local function invoke(src,action,payload)
    local m,p,denied=scope(src)
    if denied then return denied end
    local faction=tonumber(m.id)
    if not faction then return fail('팩션 ID가 올바르지 않습니다.') end
    payload=type(payload)=='table' and payload or {}
    local officer=authorizedLeader(m)


    if action:sub(1,9)=='ci_crime_' then
        if not isCrime(m) then return fail('조직 팩션 전용 기능입니다.') end

        if action=='ci_crime_goods' then
            local defs={
                {'코카인 원재료','crime_cocaine_raw','원재료 · 조직 NPC 기본 판매'},
                {'대마초 원재료','crime_cannabis_raw','원재료 · 조직 NPC 기본 판매'},
                {'필로폰 원재료','crime_meth_raw','원재료 · 조직 NPC 기본 판매'},
                {'헤로인 원재료','crime_heroin_raw','원재료 · 조직 NPC 기본 판매'},
                {'코카인','crime_cocaine','완제품 · 인벤토리/거래용'},
                {'대마초','crime_cannabis','완제품 · 인벤토리/거래용'},
                {'필로폰','crime_meth','완제품 · 인벤토리/거래용'},
                {'헤로인','crime_heroin','완제품 · 인벤토리/거래용'},
            }
            local rows={}
            for _,v in ipairs(defs) do rows[#rows+1]={label=v[1],code=v[2],owned=comma(invCount(src,v[2]))..'개',desc=v[3]} end
            return tableResult('조직 취급 품목',{
                {key='label',label='품목'},{key='code',label='아이템 코드'},{key='owned',label='내 보유량'},{key='desc',label='설명'}
            },rows)

        elseif action=='ci_crime_robbery_tools' then
            local defs={
                {'락픽','lockpick','차량/강도 RP용 기본 도구'},
                {'고급 락픽','advancedlockpick','고급 잠금 해제 RP 도구'},
                {'전자 키트','electronickit','전자장치 해제 RP 도구'},
                {'써마이트','thermite','강도 RP용 특수 도구'},
                {'드릴','drill','금고/강도 RP용 도구'},
                {'USB 장치','usb_device','전자/해킹 RP용 도구'},
            }
            local rows={}
            for _,v in ipairs(defs) do rows[#rows+1]={label=v[1],code=v[2],owned=comma(invCount(src,v[2]))..'개',desc=v[3]} end
            return tableResult('강도 RP 도구 안내',{
                {key='label',label='도구'},{key='code',label='아이템 코드'},{key='owned',label='내 보유량'},{key='desc',label='용도'}
            },rows)

        elseif action=='ci_crime_trade_calc' then
            local itemName=clean(payload.itemName,80)
            local buyPrice=math.floor(tonumber(payload.buyPrice) or -1)
            local quantity=math.floor(tonumber(payload.quantity) or 0)
            local marginRate=tonumber(payload.marginRate)
            local sellPrice=math.floor(tonumber(payload.sellPrice) or 0)
            local shareRate=tonumber(payload.shareRate)
            if itemName=='' then return fail('거래 품목을 입력하세요.') end
            if buyPrice<0 or buyPrice>100000000 or quantity<1 or quantity>10000 then return fail('매입가 또는 수량이 올바르지 않습니다.') end
            if not marginRate or marginRate<0 or marginRate>1000 then return fail('마진율이 올바르지 않습니다.') end
            if sellPrice<0 or sellPrice>100000000 then return fail('판매가가 올바르지 않습니다.') end
            if not shareRate or shareRate<0 or shareRate>100 then return fail('공계 적립률은 0~100%로 입력하세요.') end
            local recommended=ceilTo(buyPrice*(1+(marginRate/100)),100)
            local unit=sellPrice>0 and sellPrice or recommended
            local cost=buyPrice*quantity
            local sales=unit*quantity
            local profit=sales-cost
            local share=math.floor(math.max(0,profit)*(shareRate/100))
            return tableResult('조직 거래 · 판매 계산 결과',{{key='item',label='항목'},{key='value',label='계산 결과'}},{
                {item='품목',value=itemName},{item='개당 매입가',value=won(buyPrice)},{item='권장 판매가',value=won(recommended)},
                {item='적용 판매가',value=won(unit)},{item='수량',value=comma(quantity)..'개'},{item='총 매입액',value=won(cost)},
                {item='총 판매액',value=won(sales)},{item='예상 이익',value=won(profit)},{item='이익 기준 공계 적립액',value=won(share)}
            })

        elseif action=='ci_crime_exchange_calc' then
            local dirty=math.floor(tonumber(payload.dirtyAmount) or 0)
            local rate=tonumber(payload.exchangeRate)
            local accRate=tonumber(payload.accountRate)
            if dirty<1 or dirty>1000000000 then return fail('환전 요청 금액이 올바르지 않습니다.') end
            if not rate or rate<0 or rate>100 then return fail('지급 비율은 0~100%로 입력하세요.') end
            if not accRate or accRate<0 or accRate>100 then return fail('공계 적립률은 0~100%로 입력하세요.') end
            local payout=math.floor(dirty*(rate/100))
            local fee=dirty-payout
            local account=math.floor(fee*(accRate/100))
            local memberShare=fee-account
            return tableResult('조직 환전 계산 결과',{{key='item',label='항목'},{key='value',label='계산 결과'}},{
                {item='환전 요청 금액',value=won(dirty)},{item='지급 비율',value=string.format('%.1f%%',rate)},
                {item='시민 지급 예정액',value=won(payout)},{item='총 수수료',value=won(fee)},
                {item='공동계좌 적립 예정액',value=won(account)},{item='직원/조직 잔여 수수료',value=won(memberShare)},
                {item='거래 메모',value=clean(payload.note,120)~='' and clean(payload.note,120) or '-'},
                {item='처리 방식',value='계산 전용 · 실제 돈/아이템은 자동 이동하지 않음'},
            })

        elseif action=='ci_crime_account' then
            local balance=pharmacyBudget(faction)
            local player=exports.qbx_core:GetPlayer(src)
            local bank=player and player.PlayerData and player.PlayerData.money and (tonumber(player.PlayerData.money.bank) or 0) or 0
            local logs=MySQL.query.await([[SELECT delta,balance_after,category,reason,created_at FROM cookie_faction_budget_log
                WHERE faction_id=? AND category IN ('crime_deposit','crime_withdraw','fieldphone_deposit','fieldphone_withdraw') ORDER BY id DESC LIMIT 30]],{faction}) or {}
            local rows={{date='-',kind='현재 공동계좌',amount=won(balance),reason='-',balance=won(balance)},{date='-',kind='내 은행 잔액',amount=won(bank),reason='-',balance='-'}}
            for _,row in ipairs(logs) do local d=tonumber(row.delta) or 0; rows[#rows+1]={date=tostring(row.created_at or '-'),kind=d>=0 and '입금' or '출금',amount=(d>=0 and '+' or '-')..won(math.abs(d)),reason=tostring(row.reason or '-'),balance=won(row.balance_after)} end
            return tableResult('조직 공동계좌',{{key='date',label='일시'},{key='kind',label='구분'},{key='amount',label='금액'},{key='reason',label='메모'},{key='balance',label='처리 후 잔액'}},rows)

        elseif action=='ci_crime_deposit' then
            local amount=math.floor(tonumber(payload.amount) or 0); local reason=clean(payload.reason,120)
            if amount<1 or amount>1000000000 then return fail('입금액이 올바르지 않습니다.') end
            if #reason<2 then return fail('입금 메모를 입력하세요.') end
            local player=exports.qbx_core:GetPlayer(src); if not player then return fail('플레이어 정보를 불러오지 못했습니다.') end
            local okRemove,resRemove=pcall(function() return player.Functions.RemoveMoney('bank',amount,'조직 공동계좌 입금') end)
            if not (okRemove and resRemove==true) then return fail('은행 계좌 잔액이 부족합니다.') end
            local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=? AND is_active=1',{amount,faction})
            if not changed or changed<1 then pcall(function() player.Functions.AddMoney('bank',amount,'조직 공동계좌 입금 실패 환불') end); return fail('입금 처리에 실패하여 환불했습니다.') end
            local balance=pharmacyBudget(faction); pharmacyLedger(faction,amount,balance,'crime_deposit',reason,p.citizenid)
            return {ok=true,title='조직 공동계좌 입금 완료',message=('%s 입금했습니다. 현재 잔액: %s'):format(won(amount),won(balance))}

        elseif action=='ci_crime_withdraw' then
            if not officer then return fail('간부 또는 대표 권한이 있는 직급만 출금할 수 있습니다.') end
            local amount=math.floor(tonumber(payload.amount) or 0); local reason=clean(payload.reason,120)
            if amount<1 or amount>1000000000 then return fail('출금액이 올바르지 않습니다.') end
            if #reason<2 then return fail('출금 사유를 입력하세요.') end
            local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget-? WHERE id=? AND is_active=1 AND budget>=?',{amount,faction,amount})
            if not changed or changed<1 then return fail('공동계좌 잔액이 부족합니다.') end
            local player=exports.qbx_core:GetPlayer(src); local added=false
            if player then local okAdd,resAdd=pcall(function() return player.Functions.AddMoney('bank',amount,'조직 공동계좌 출금') end); added=okAdd and resAdd~=false end
            if not added then MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=?',{amount,faction}); return fail('개인 계좌 지급에 실패해 출금을 취소했습니다.') end
            local balance=pharmacyBudget(faction); pharmacyLedger(faction,-amount,balance,'crime_withdraw',reason,p.citizenid)
            return {ok=true,title='조직 공동계좌 출금 완료',message=('%s 출금했습니다. 현재 잔액: %s'):format(won(amount),won(balance))}
        end
    end

    if action:sub(1,7)=='ci_tow_' then
        if not isTow(m) then return fail('렉카 팩션 전용 기능입니다.') end

        if action=='ci_tow_impounds' then
            local rows=MySQL.query.await([[SELECT id,plate,model,reason,fee,impounded_name,created_at
                FROM cookie_tow_impound WHERE faction_id=? AND active=1 ORDER BY id DESC LIMIT 100]],{faction}) or {}
            for _,r in ipairs(rows) do r.fee=won(r.fee) end
            return tableResult('현재 압류 차량',{
                {key='id',label='번호'},{key='plate',label='번호판'},{key='model',label='차량'},
                {key='reason',label='압류 사유'},{key='fee',label='압류비'},{key='impounded_name',label='담당자'},{key='created_at',label='처리일'}
            },rows,officer and {{action='ci_tow_release',label='압류 해제',tone='green'}} or nil)

        elseif action=='ci_tow_scraps' then
            local rows=MySQL.query.await([[SELECT id,plate,model,agreed_amount,reason,handled_name,created_at
                FROM cookie_tow_scrap_log WHERE faction_id=? ORDER BY id DESC LIMIT 100]],{faction}) or {}
            for _,r in ipairs(rows) do r.agreed_amount=won(r.agreed_amount) end
            return tableResult('폐차 처리 기록',{
                {key='id',label='번호'},{key='plate',label='번호판'},{key='model',label='차량'},
                {key='agreed_amount',label='기록 금액'},{key='reason',label='사유'},{key='handled_name',label='담당자'},{key='created_at',label='처리일'}
            },rows)

        elseif action=='ci_tow_fee_calc' then
            local towFee=math.floor(tonumber(payload.towFee) or 0)
            local storage=math.floor(tonumber(payload.storagePerDay) or 0)
            local days=math.floor(tonumber(payload.days) or 0)
            local extra=math.floor(tonumber(payload.extraFee) or 0)
            if towFee<0 or storage<0 or days<0 or extra<0 or days>365 then return fail('요금 입력값이 올바르지 않습니다.') end
            local total=towFee+(storage*days)+extra
            return tableResult('렉카 요금 계산 결과',{{key='item',label='항목'},{key='value',label='금액'}},{
                {item='견인비',value=won(towFee)},{item=('보관료 (%d일)'):format(days),value=won(storage*days)},
                {item='추가 작업비',value=won(extra)},{item='총 합계',value=won(total)},
                {item='메모',value=clean(payload.note,120)~='' and clean(payload.note,120) or '-'}
            })

        elseif action=='ci_tow_account' then
            local balance=pharmacyBudget(faction)
            local player=exports.qbx_core:GetPlayer(src)
            local bank=player and player.PlayerData and player.PlayerData.money and (tonumber(player.PlayerData.money.bank) or 0) or 0
            local logs=MySQL.query.await([[SELECT delta,balance_after,category,reason,created_at FROM cookie_faction_budget_log
                WHERE faction_id=? AND category IN ('tow_deposit','tow_withdraw','fieldphone_deposit','fieldphone_withdraw') ORDER BY id DESC LIMIT 30]],{faction}) or {}
            local rows={{date='-',kind='현재 공동계좌',amount=won(balance),reason='-',balance=won(balance)},{date='-',kind='내 은행 잔액',amount=won(bank),reason='-',balance='-'}}
            for _,row in ipairs(logs) do local d=tonumber(row.delta) or 0;rows[#rows+1]={date=tostring(row.created_at or '-'),kind=d>=0 and '입금' or '출금',amount=(d>=0 and '+' or '-')..won(math.abs(d)),reason=tostring(row.reason or '-'),balance=won(row.balance_after)} end
            return tableResult('렉카 공동계좌',{{key='date',label='일시'},{key='kind',label='구분'},{key='amount',label='금액'},{key='reason',label='메모'},{key='balance',label='처리 후 잔액'}},rows)

        elseif action=='ci_tow_deposit' then
            local amount=math.floor(tonumber(payload.amount) or 0);local reason=clean(payload.reason,120)
            if amount<1 or amount>1000000000 then return fail('입금액이 올바르지 않습니다.') end
            if #reason<2 then return fail('입금 메모를 입력하세요.') end
            local player=exports.qbx_core:GetPlayer(src);if not player then return fail('플레이어 정보를 불러오지 못했습니다.') end
            if player.Functions.RemoveMoney('bank',amount,'렉카 공동계좌 입금')~=true then return fail('은행 계좌 잔액이 부족합니다.') end
            local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=? AND is_active=1',{amount,faction})
            if not changed or changed<1 then player.Functions.AddMoney('bank',amount,'렉카 공계 입금 실패 환불');return fail('입금 처리에 실패했습니다.') end
            local balance=pharmacyBudget(faction);pharmacyLedger(faction,amount,balance,'tow_deposit',reason,p.citizenid)
            return {ok=true,title='공동계좌 입금 완료',message=('%s 입금했습니다. 현재 잔액 %s'):format(won(amount),won(balance))}

        elseif action=='ci_tow_withdraw' then
            if not officer then return fail('간부/대표 권한이 있는 직급만 출금할 수 있습니다.') end
            local amount=math.floor(tonumber(payload.amount) or 0);local reason=clean(payload.reason,120)
            if amount<1 or amount>1000000000 then return fail('출금액이 올바르지 않습니다.') end
            if #reason<2 then return fail('출금 사유를 입력하세요.') end
            local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget-? WHERE id=? AND is_active=1 AND budget>=?',{amount,faction,amount})
            if not changed or changed<1 then return fail('공동계좌 잔액이 부족합니다.') end
            local player=exports.qbx_core:GetPlayer(src);if not player or player.Functions.AddMoney('bank',amount,'렉카 공동계좌 출금')==false then MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=?',{amount,faction});return fail('개인 계좌 지급에 실패했습니다.') end
            local balance=pharmacyBudget(faction);pharmacyLedger(faction,-amount,balance,'tow_withdraw',reason,p.citizenid)
            return {ok=true,title='공동계좌 출금 완료',message=('%s 출금했습니다. 현재 잔액 %s'):format(won(amount),won(balance))}
        end
    end

    if action:sub(1,9)=='ci_daiso_' then
        if not isDaiso(m) then return fail('다이소 팩션 전용 기능입니다.') end

        if action=='ci_daiso_parts' then
            return tableResult('다이소 판매 파츠 5종',{
                {key='label',label='품목'},{key='code',label='아이템 코드'},{key='desc',label='설명'}
            },{
                {label='소음기',code='daiso_suppressor',desc='현재 들고 있는 호환 총기에 소음기를 장착합니다.'},
                {label='손전등',code='daiso_flashlight',desc='현재 들고 있는 호환 총기에 전술 손전등을 장착합니다.'},
                {label='조준경',code='daiso_scope',desc='현재 들고 있는 호환 총기에 알맞은 조준경을 장착합니다.'},
                {label='확장탄창',code='daiso_extended_clip',desc='현재 들고 있는 호환 총기에 확장 탄창을 장착합니다.'},
                {label='그립',code='daiso_grip',desc='현재 들고 있는 호환 총기에 전술 그립을 장착합니다.'},
            })

        elseif action=='ci_daiso_calc' then
            local itemName=clean(payload.itemName,80)
            local buyPrice=math.floor(tonumber(payload.buyPrice) or -1)
            local quantity=math.floor(tonumber(payload.quantity) or 0)
            local marginRate=tonumber(payload.marginRate)
            local sellPrice=math.floor(tonumber(payload.sellPrice) or 0)
            local shareRate=tonumber(payload.shareRate)

            if itemName=='' then return fail('상품명을 입력하세요.') end
            if buyPrice<0 or buyPrice>100000000 then return fail('매입 단가가 올바르지 않습니다.') end
            if quantity<1 or quantity>10000 then return fail('판매 수량이 올바르지 않습니다.') end
            if not marginRate or marginRate<0 or marginRate>1000 then return fail('목표 마진율이 올바르지 않습니다.') end
            if sellPrice<0 or sellPrice>100000000 then return fail('판매가가 올바르지 않습니다.') end
            if not shareRate or shareRate<0 or shareRate>100 then return fail('공동계좌 적립률은 0~100%로 입력하세요.') end

            local recommendedUnit=ceilTo(buyPrice*(1+(marginRate/100)),100)
            local appliedUnit=sellPrice>0 and sellPrice or recommendedUnit
            local totalCost=buyPrice*quantity
            local totalSales=appliedUnit*quantity
            local profit=totalSales-totalCost
            local salesShare=math.floor(totalSales*(shareRate/100))
            local profitShare=profit>0 and math.floor(profit*(shareRate/100)) or 0

            return tableResult('다이소 판매 · 정산 계산 결과',{{key='item',label='항목'},{key='value',label='계산 결과'}},{
                {item='상품',value=itemName},
                {item='개당 매입 단가',value=won(buyPrice)},
                {item='목표 마진율',value=string.format('%.1f%%',marginRate)},
                {item='권장 판매 단가',value=won(recommendedUnit)},
                {item='계산에 적용한 판매 단가',value=won(appliedUnit)},
                {item='판매 수량',value=comma(quantity)..'개'},
                {item='총 매입액',value=won(totalCost)},
                {item='총 판매액',value=won(totalSales)},
                {item='예상 손익',value=won(profit)},
                {item='공동계좌 적립률',value=string.format('%.1f%%',shareRate)},
                {item='매출 기준 공계 입금액',value=won(salesShare)},
                {item='이익 기준 공계 입금액',value=won(profitShare)},
            })

        elseif action=='ci_daiso_account' then
            local balance=pharmacyBudget(faction)
            local player=exports.qbx_core:GetPlayer(src)
            local bank=0
            if player and player.PlayerData and player.PlayerData.money then
                bank=tonumber(player.PlayerData.money.bank) or 0
            end
            local logs=MySQL.query.await([[SELECT delta,balance_after,category,reason,created_at
                FROM cookie_faction_budget_log
                WHERE faction_id=? AND category IN ('daiso_deposit','daiso_withdraw','fieldphone_deposit','fieldphone_withdraw')
                ORDER BY id DESC LIMIT 30]],{faction}) or {}
            local rows={
                {date='-',kind='현재 공동계좌',amount=won(balance),reason='-',balance=won(balance)},
                {date='-',kind='내 은행 잔액',amount=won(bank),reason='-',balance='-'},
            }
            for _,row in ipairs(logs) do
                local delta=tonumber(row.delta) or 0
                rows[#rows+1]={
                    date=tostring(row.created_at or '-'),
                    kind=delta>=0 and '입금' or '출금',
                    amount=(delta>=0 and '+' or '-')..won(math.abs(delta)),
                    reason=tostring(row.reason or '-'),
                    balance=won(row.balance_after),
                }
            end
            return tableResult('다이소 공동계좌',{
                {key='date',label='일시'},{key='kind',label='구분'},{key='amount',label='금액'},
                {key='reason',label='메모'},{key='balance',label='처리 후 잔액'}
            },rows)

        elseif action=='ci_daiso_deposit' then
            local amount=math.floor(tonumber(payload.amount) or 0)
            local reason=clean(payload.reason,120)
            if amount<1 or amount>1000000000 then return fail('입금액이 올바르지 않습니다.') end
            if #reason<2 then return fail('입금 메모를 입력하세요.') end

            local player=exports.qbx_core:GetPlayer(src)
            if not player then return fail('플레이어 정보를 불러오지 못했습니다.') end
            local okRemove,resRemove=pcall(function()
                return player.Functions.RemoveMoney('bank',amount,'다이소 공동계좌 입금')
            end)
            if not (okRemove and resRemove==true) then return fail('은행 계좌 잔액이 부족합니다.') end

            local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=? AND is_active=1',{amount,faction})
            if not changed or changed<1 then
                pcall(function() player.Functions.AddMoney('bank',amount,'다이소 공동계좌 입금 실패 환불') end)
                return fail('공동계좌 입금 처리에 실패하여 금액을 환불했습니다.')
            end
            local balance=pharmacyBudget(faction)
            pharmacyLedger(faction,amount,balance,'daiso_deposit',reason,p.citizenid)
            return {ok=true,title='공동계좌 입금 완료',message=('%s 입금했습니다. 현재 공동계좌: %s'):format(won(amount),won(balance))}

        elseif action=='ci_daiso_withdraw' then
            if not officer then return fail('간부 또는 대표 권한이 있는 직급만 공동계좌에서 출금할 수 있습니다.') end
            local amount=math.floor(tonumber(payload.amount) or 0)
            local reason=clean(payload.reason,120)
            if amount<1 or amount>1000000000 then return fail('출금액이 올바르지 않습니다.') end
            if #reason<2 then return fail('출금 사유를 입력하세요.') end

            local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget-? WHERE id=? AND is_active=1 AND budget>=?',{amount,faction,amount})
            if not changed or changed<1 then return fail('공동계좌 잔액이 부족합니다.') end

            local player=exports.qbx_core:GetPlayer(src)
            local added=false
            if player then
                local okAdd,resAdd=pcall(function()
                    return player.Functions.AddMoney('bank',amount,'다이소 공동계좌 출금')
                end)
                added=okAdd and resAdd~=false
            end
            if not added then
                MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=?',{amount,faction})
                return fail('개인 계좌 지급에 실패하여 공동계좌 출금을 취소했습니다.')
            end

            local balance=pharmacyBudget(faction)
            pharmacyLedger(faction,-amount,balance,'daiso_withdraw',reason,p.citizenid)
            return {ok=true,title='공동계좌 출금 완료',message=('%s 출금했습니다. 현재 공동계좌: %s'):format(won(amount),won(balance))}
        end
    end

    if action:sub(1,12)=='ci_pharmacy_' then
        if not isPharmacy(m) then return fail('약국 팩션 전용 기능입니다.') end

        if action=='ci_pharmacy_calc' then
            local itemName=clean(payload.itemName,80)
            local buyPrice=math.floor(tonumber(payload.buyPrice) or -1)
            local quantity=math.floor(tonumber(payload.quantity) or 0)
            local marginRate=tonumber(payload.marginRate)
            local sellPrice=math.floor(tonumber(payload.sellPrice) or 0)
            local shareRate=tonumber(payload.shareRate)

            if itemName=='' then return fail('상품명을 입력하세요.') end
            if buyPrice<0 or buyPrice>100000000 then return fail('매입 단가가 올바르지 않습니다.') end
            if quantity<1 or quantity>10000 then return fail('판매 수량이 올바르지 않습니다.') end
            if not marginRate or marginRate<0 or marginRate>1000 then return fail('목표 마진율이 올바르지 않습니다.') end
            if sellPrice<0 or sellPrice>100000000 then return fail('판매가가 올바르지 않습니다.') end
            if not shareRate or shareRate<0 or shareRate>100 then return fail('공동계좌 적립률은 0~100%로 입력하세요.') end

            -- 직접 판매가가 0이면 목표 마진율을 적용하고 100원 단위로 올림합니다.
            local recommendedUnit=ceilTo(buyPrice*(1+(marginRate/100)),100)
            local appliedUnit=sellPrice>0 and sellPrice or recommendedUnit
            local totalCost=buyPrice*quantity
            local totalSales=appliedUnit*quantity
            local profit=totalSales-totalCost
            local salesShare=math.floor(totalSales*(shareRate/100))
            local profitShare=profit>0 and math.floor(profit*(shareRate/100)) or 0

            return tableResult('약국 판매 · 정산 계산 결과',{{key='item',label='항목'},{key='value',label='계산 결과'}},{
                {item='상품',value=itemName},
                {item='개당 매입 단가',value=won(buyPrice)},
                {item='목표 마진율',value=string.format('%.1f%%',marginRate)},
                {item='권장 판매 단가',value=won(recommendedUnit)},
                {item='계산에 적용한 판매 단가',value=won(appliedUnit)},
                {item='판매 수량',value=comma(quantity)..'개'},
                {item='총 매입액',value=won(totalCost)},
                {item='총 판매액',value=won(totalSales)},
                {item='예상 손익',value=won(profit)},
                {item='공동계좌 적립률',value=string.format('%.1f%%',shareRate)},
                {item='매출 기준 공계 입금액',value=won(salesShare)},
                {item='이익 기준 공계 입금액',value=won(profitShare)},
            })

        elseif action=='ci_pharmacy_account' then
            local balance=pharmacyBudget(faction)
            local player=exports.qbx_core:GetPlayer(src)
            local bank=0
            if player and player.PlayerData and player.PlayerData.money then
                bank=tonumber(player.PlayerData.money.bank) or 0
            end
            local logs=MySQL.query.await([[SELECT delta,balance_after,category,reason,created_at
                FROM cookie_faction_budget_log
                WHERE faction_id=? AND category IN ('pharmacy_deposit','pharmacy_withdraw','fieldphone_deposit','fieldphone_withdraw')
                ORDER BY id DESC LIMIT 30]],{faction}) or {}
            local rows={
                {date='-',kind='현재 공동계좌',amount=won(balance),reason='-',balance=won(balance)},
                {date='-',kind='내 은행 잔액',amount=won(bank),reason='-',balance='-'},
            }
            for _,row in ipairs(logs) do
                local delta=tonumber(row.delta) or 0
                rows[#rows+1]={
                    date=tostring(row.created_at or '-'),
                    kind=delta>=0 and '입금' or '출금',
                    amount=(delta>=0 and '+' or '-')..won(math.abs(delta)),
                    reason=tostring(row.reason or '-'),
                    balance=won(row.balance_after),
                }
            end
            return tableResult('약국 공동계좌',{
                {key='date',label='일시'},{key='kind',label='구분'},{key='amount',label='금액'},
                {key='reason',label='메모'},{key='balance',label='처리 후 잔액'}
            },rows)

        elseif action=='ci_pharmacy_deposit' then
            local amount=math.floor(tonumber(payload.amount) or 0)
            local reason=clean(payload.reason,120)
            if amount<1 or amount>1000000000 then return fail('입금액이 올바르지 않습니다.') end
            if #reason<2 then return fail('입금 메모를 입력하세요.') end

            local player=exports.qbx_core:GetPlayer(src)
            if not player then return fail('플레이어 정보를 불러오지 못했습니다.') end
            local paid=false
            local okRemove,resRemove=pcall(function()
                return player.Functions.RemoveMoney('bank',amount,'약국 공동계좌 입금')
            end)
            paid=okRemove and resRemove==true
            if not paid then return fail('은행 계좌 잔액이 부족합니다.') end

            local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=? AND is_active=1',{amount,faction})
            if not changed or changed<1 then
                pcall(function() player.Functions.AddMoney('bank',amount,'약국 공동계좌 입금 실패 환불') end)
                return fail('공동계좌 입금 처리에 실패하여 금액을 환불했습니다.')
            end
            local balance=pharmacyBudget(faction)
            pharmacyLedger(faction,amount,balance,'pharmacy_deposit',reason,p.citizenid)
            return {ok=true,title='공동계좌 입금 완료',message=('%s 입금했습니다. 현재 공동계좌: %s'):format(won(amount),won(balance))}

        elseif action=='ci_pharmacy_withdraw' then
            if not officer then return fail('간부 또는 대표만 공동계좌에서 출금할 수 있습니다.') end
            local amount=math.floor(tonumber(payload.amount) or 0)
            local reason=clean(payload.reason,120)
            if amount<1 or amount>1000000000 then return fail('출금액이 올바르지 않습니다.') end
            if #reason<2 then return fail('출금 사유를 입력하세요.') end

            local changed=MySQL.update.await('UPDATE cookie_faction SET budget=budget-? WHERE id=? AND is_active=1 AND budget>=?',{amount,faction,amount})
            if not changed or changed<1 then return fail('공동계좌 잔액이 부족합니다.') end

            local player=exports.qbx_core:GetPlayer(src)
            local added=false
            if player then
                local okAdd,resAdd=pcall(function()
                    return player.Functions.AddMoney('bank',amount,'약국 공동계좌 출금')
                end)
                added=okAdd and resAdd~=false
            end
            if not added then
                MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=?',{amount,faction})
                return fail('개인 계좌 지급에 실패하여 공동계좌 출금을 취소했습니다.')
            end

            local balance=pharmacyBudget(faction)
            pharmacyLedger(faction,-amount,balance,'pharmacy_withdraw',reason,p.citizenid)
            return {ok=true,title='공동계좌 출금 완료',message=('%s 출금했습니다. 현재 공동계좌: %s'):format(won(amount),won(balance))}
        end
    end
    if action=='ci_catalog' then
        return tableResult('팩션 판매 품목 · 가격', {{key='label',label='품목'},{key='item_code',label='코드'},{key='price',label='가격(원)'},{key='description',label='설명'}},
            MySQL.query.await('SELECT label,item_code,price,description FROM cookie_intranet_catalog WHERE faction_id=? AND active=1 ORDER BY id DESC LIMIT 200',{faction}))
    end
    if action=='ci_home' then
        local notices=MySQL.scalar.await('SELECT COUNT(*) FROM cookie_f5_notices WHERE faction_id=?',{faction}) or 0
        local reports=MySQL.scalar.await('SELECT COUNT(*) FROM cookie_f5_reports WHERE faction_id=?',{faction}) or 0
        local leave=MySQL.scalar.await("SELECT COUNT(*) FROM cookie_f5_leaves WHERE faction_id=? AND status='pending'",{faction}) or 0
        return tableResult('인트라넷 홈',{{key='item',label='항목'},{key='value',label='현황'}},{
            {item='소속',value=m.name or '팩션'},{item='직급',value=m.rankName or '-'},
            {item='근무 상태',value=m.duty and '출근' or '퇴근'},
            {item='등록된 공지',value=notices},{item='업무 보고',value=reports},{item='대기 중 휴가',value=leave}
        })
    elseif action=='ci_notice_list' then
        return tableResult('팩션 공지',{{key='title',label='제목'},{key='body',label='내용'},{key='author',label='작성자'},{key='created_at',label='등록일'}},MySQL.query.await('SELECT title,body,author,created_at FROM cookie_f5_notices WHERE faction_id=? ORDER BY id DESC LIMIT 30',{faction}))
    elseif action=='ci_notice_add' then
        if not officer then return fail('간부 이상만 공지사항을 등록할 수 있습니다.') end
        local title,body=clean(payload.title,120),clean(payload.body,3000)
        if title=='' or body=='' then return fail('제목과 내용을 입력하세요.') end
        MySQL.insert.await('INSERT INTO cookie_f5_notices (faction_id,author,title,body) VALUES (?,?,?,?)',{faction,displayName(src),title,body})
        return {ok=true,message='팩션 공지가 등록됐습니다.'}
    elseif action=='ci_report_list' then
        return tableResult('업무 보고서',{{key='title',label='제목'},{key='body',label='내용'},{key='author',label='작성자'},{key='created_at',label='작성일'}},MySQL.query.await('SELECT title,body,author,created_at FROM cookie_f5_reports WHERE faction_id=? ORDER BY id DESC LIMIT 40',{faction}))
    elseif action=='ci_report_add' then
        local title,body=clean(payload.title,120),clean(payload.body,4000)
        if title=='' or body=='' then return fail('제목과 내용을 입력하세요.') end
        MySQL.insert.await('INSERT INTO cookie_f5_reports (faction_id,author_id,author,title,body) VALUES (?,?,?,?,?)',{faction,p.citizenid,displayName(src),title,body})
        return {ok=true,message='업무 보고서가 저장됐습니다.'}
    elseif action=='ci_leave_list' then
        local sql='SELECT id,author,start_date,end_date,reason,status,reviewer FROM cookie_f5_leaves WHERE faction_id=?'
        local params={faction}
        if not officer then sql=sql..' AND citizenid=?';params[2]=p.citizenid end
        sql=sql..' ORDER BY id DESC LIMIT 40'
        return tableResult('휴가 신청 현황',{{key='id',label='번호'},{key='author',label='신청자'},{key='start_date',label='시작'},{key='end_date',label='종료'},{key='reason',label='사유'},{key='status',label='상태'}},MySQL.query.await(sql,params),officer and {{action='ci_leave_approve',label='승인',tone='green'},{action='ci_leave_reject',label='반려',tone='red'}} or nil)
    elseif action=='ci_leave_apply' then
        local first,last=clean(payload.startDate,10),clean(payload.endDate,10)
        if not first:match('^%d%d%d%d%-%d%d%-%d%d$') or not last:match('^%d%d%d%d%-%d%d%-%d%d$') or last<first then return fail('휴가 날짜를 YYYY-MM-DD 형식으로 입력하세요.') end
        local reason=clean(payload.reason,600)
        if reason=='' then return fail('신청 사유를 입력하세요.') end
        MySQL.insert.await('INSERT INTO cookie_f5_leaves (faction_id,citizenid,author,start_date,end_date,reason) VALUES (?,?,?,?,?,?)',{faction,p.citizenid,displayName(src),first,last,reason})
        return {ok=true,message='휴가 신청이 접수됐습니다.'}
    end
    return fail('지원하지 않는 인트라넷 기능입니다.')
end
local function resolve(src,action,payload)
    local m,p,denied=scope(src)
    if denied then return denied end
    if action=='ci_tow_release' then
        if not isTow(m) then return fail('렉카 팩션 전용 기능입니다.') end
        if not authorizedLeader(m) then return fail('간부/대표 권한이 필요합니다.') end
        local id=tonumber(type(payload)=='table' and payload.id)
        if not id then return fail('압류 기록 번호가 올바르지 않습니다.') end
        if GetResourceState('cookie_factionphone')~='started' then return fail('팩션 현장전화 리소스가 실행 중이 아닙니다.') end
        local ok,msg=exports.cookie_factionphone:releaseImpound(src,id)
        return ok and {ok=true,message=msg or '압류를 해제했습니다.'} or fail(msg or '압류 해제에 실패했습니다.')
    end
    if not authorizedLeader(m) then return fail('간부 이상의 권한이 필요합니다.') end
    if action~='ci_leave_approve' and action~='ci_leave_reject' then return fail('허용되지 않는 처리입니다.') end
    local id=tonumber(type(payload)=='table' and payload.id)
    if not id or id%1~=0 or id<1 then return fail('신청 번호가 잘못됐습니다.') end
    local status=action=='ci_leave_approve' and 'approved' or 'rejected'
    local changed=MySQL.update.await("UPDATE cookie_f5_leaves SET status=?,reviewer=? WHERE id=? AND faction_id=? AND status='pending'",{status,displayName(src),id,tonumber(m.id)})
    return changed and changed>0 and {ok=true,message='휴가 신청을 처리했습니다.'} or fail('처리 가능한 신청이 아닙니다.')
end
lib.callback.register('cookie_factionmenu:intranetAction',function(source,action,payload)
    local ok,res=pcall(invoke,source,tostring(action or ''),payload)
    if ok then return res end
    print('^1[COOKIE INTRANET] action: '..tostring(res)..'^7')
    return fail('업무망 DB 처리 중 오류가 발생했습니다.')
end)
lib.callback.register('cookie_factionmenu:intranetResult',function(source,action,payload)
    local ok,res=pcall(resolve,source,tostring(action or ''),payload)
    if ok then return res end
    print('^1[COOKIE INTRANET] result: '..tostring(res)..'^7')
    return fail('업무망 처리 중 오류가 발생했습니다.')
end)
