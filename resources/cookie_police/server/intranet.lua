local function clean(v,n)local s=tostring(v or ''):gsub('[%c]',' '):gsub('^%s+',''):gsub('%s+$','');if n and #s>n then s=s:sub(1,n)end;return s end

local function cookieIntranetLog(category, title, description, fields, options)
    if GetResourceState('cookie_logs') ~= 'started' then return end
    pcall(function()
        exports.cookie_logs:Log(category, title, description, fields or {}, options or {})
    end)
end


local function srcByCid(cid)for _,raw in ipairs(GetPlayers())do local s=tonumber(raw);local p=s and exports.qbx_core:GetPlayer(s);if p and p.PlayerData and tostring(p.PlayerData.citizenid)==tostring(cid)then return s end end end
local function userRow(q)
 q=clean(q,80);if q==''then return nil,'고번 또는 이름을 입력하세요.'end
 local like='%'..q..'%';local rows=MySQL.query.await([[SELECT p.citizenid,cu.gobun,cu.nickname FROM players p LEFT JOIN cookie_user cu ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci=SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci WHERE CAST(cu.gobun AS CHAR)=? OR cu.nickname LIKE ? ORDER BY (CAST(cu.gobun AS CHAR)=?) DESC,(cu.nickname=?) DESC LIMIT 20]],{q,like,q,q})or{}
 if #rows==0 then return nil,'시민을 찾지 못했습니다.'end;if #rows>1 then for _,r in ipairs(rows)do if tostring(r.gobun)==q then return r end end;return nil,'동일/유사 이름이 여러 명입니다. 고번으로 입력하세요.'end;return rows[1]
end
local function label(r)return ('%s / %s'):format(tostring(r.gobun or '-'),tostring(r.nickname or '-'))end
local function tableResult(title,cols,rows,actions)return{ok=true,kind='table',title=title,columns=cols,rows=rows or{},rowActions=actions or{}}end
local function success(t,m)return{ok=true,kind='success',title=t,message=m}end
local function ensureDuty(src,member,actor)
 if not member or not actor or not actor.citizenid then return end
 if member.duty==true then MySQL.query.await([[INSERT INTO cookie_intranet_duty_session(faction_id,citizenid,member_name,start_at) SELECT ?,?,?,NOW() WHERE NOT EXISTS(SELECT 1 FROM cookie_intranet_duty_session WHERE citizenid=? AND end_at IS NULL)]],{member.id,actor.citizenid,actor.name,actor.citizenid})end
end

CreateThread(function()
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_intranet_duty_session(id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,faction_id INT NOT NULL,citizenid VARCHAR(50) NOT NULL,member_name VARCHAR(80) NULL,start_at DATETIME NOT NULL,end_at DATETIME NULL,minutes INT NOT NULL DEFAULT 0,INDEX idx_duty_faction(faction_id,start_at),INDEX idx_duty_cid(citizenid,end_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_intranet_leave(id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,faction_id INT NOT NULL,citizenid VARCHAR(50) NOT NULL,member_name VARCHAR(80) NULL,start_date DATE NOT NULL,end_date DATE NOT NULL,reason VARCHAR(500) NOT NULL,status VARCHAR(16) NOT NULL DEFAULT 'pending',reviewer_cid VARCHAR(50) NULL,reviewer_name VARCHAR(80) NULL,reviewed_at DATETIME NULL,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,INDEX idx_leave_faction(faction_id,status)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_intranet_settlement(id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,faction_id INT NOT NULL,target_citizenid VARCHAR(50) NOT NULL,target_name VARCHAR(80) NULL,amount BIGINT NOT NULL,note VARCHAR(200) NULL,paid_by_cid VARCHAR(50) NULL,paid_by_name VARCHAR(80) NULL,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,INDEX idx_settlement_faction(faction_id,created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
 print('^2[cookie_police]^7 police/security intranet ready')
end)

AddEventHandler('cookie_police:server:dutyChanged',function(src,onDuty,factionId,cid,name)
 cid=tostring(cid or '');if cid==''then return end
 if onDuty then MySQL.query.await([[INSERT INTO cookie_intranet_duty_session(faction_id,citizenid,member_name,start_at) SELECT ?,?,?,NOW() WHERE NOT EXISTS(SELECT 1 FROM cookie_intranet_duty_session WHERE citizenid=? AND end_at IS NULL)]],{factionId,cid,name,cid})
 else MySQL.update.await('UPDATE cookie_intranet_duty_session SET end_at=NOW(),minutes=GREATEST(0,TIMESTAMPDIFF(MINUTE,start_at,NOW())) WHERE citizenid=? AND end_at IS NULL',{cid})end
end)

local function home(member,actor)
 ensureDuty(nil,member,actor)
 local f=MySQL.single.await('SELECT budget FROM cookie_faction WHERE id=?',{member.id})or{}
 local duty=MySQL.single.await([[SELECT COALESCE(SUM(TIMESTAMPDIFF(MINUTE,start_at,COALESCE(end_at,NOW()))),0) m FROM cookie_intranet_duty_session WHERE faction_id=? AND citizenid=? AND YEARWEEK(start_at,1)=YEARWEEK(NOW(),1)]],{member.id,actor.citizenid})or{}
 local perf=MySQL.single.await([[SELECT COUNT(*) fine_count,COALESCE(SUM(amount),0) fine_total FROM cookie_police_fine WHERE faction_id=? AND officer_citizenid=? AND YEARWEEK(created_at,1)=YEARWEEK(NOW(),1)]],{member.id,actor.citizenid})or{}
 local leave=MySQL.single.await("SELECT COUNT(*) n FROM cookie_intranet_leave WHERE faction_id=? AND status='pending'",{member.id})or{}
 return{ok=true,kind='summary',title=(member.name or '팩션')..' 인트라넷',metrics={{label='이번 주 근무',value=(tonumber(duty.m)or 0)..'분'},{label='이번 주 벌금 부과',value=tonumber(perf.fine_count)or 0},{label='벌금 합계',value=tonumber(perf.fine_total)or 0},{label='팩션 공금',value=tonumber(f.budget)or 0},{label='휴가 승인 대기',value=tonumber(leave.n)or 0}},rows={}}
end
local function ledger(member)
 local f=MySQL.single.await('SELECT budget FROM cookie_faction WHERE id=?',{member.id})or{}
 local rows=MySQL.query.await([[SELECT delta,balance_after,category,reason,created_at FROM cookie_faction_budget_log WHERE faction_id=? ORDER BY id DESC LIMIT 60]],{member.id})or{}
 return{ok=true,kind='summary',title='팩션 장부',metrics={{label='현재 공금',value=tonumber(f.budget)or 0},{label='최근 기록',value=#rows}},columns={{key='delta',label='변동'},{key='balance_after',label='잔액'},{key='category',label='구분'},{key='reason',label='내용'},{key='created_at',label='시간'}},rows=rows}
end
local function performance(member)
 local rows=MySQL.query.await([[SELECT m.citizenid,cu.gobun,cu.nickname,r.rank_name,
   COALESCE((SELECT SUM(TIMESTAMPDIFF(MINUTE,d.start_at,COALESCE(d.end_at,NOW()))) FROM cookie_intranet_duty_session d WHERE d.faction_id=m.faction_id AND d.citizenid=m.citizenid AND YEARWEEK(d.start_at,1)=YEARWEEK(NOW(),1)),0) duty_min,
   COALESCE((SELECT COUNT(*) FROM cookie_police_fine f WHERE f.faction_id=m.faction_id AND f.officer_citizenid=m.citizenid AND YEARWEEK(f.created_at,1)=YEARWEEK(NOW(),1)),0) fine_count,
   COALESCE((SELECT SUM(f.amount) FROM cookie_police_fine f WHERE f.faction_id=m.faction_id AND f.officer_citizenid=m.citizenid AND YEARWEEK(f.created_at,1)=YEARWEEK(NOW(),1)),0) fine_total,
   COALESCE((SELECT COUNT(*) FROM cookie_faction_detention d2 WHERE d2.faction_id=m.faction_id AND d2.officer_citizenid=m.citizenid AND YEARWEEK(d2.created_at,1)=YEARWEEK(NOW(),1)),0) jail_count,
   COALESCE((SELECT SUM(d2.jail_seconds DIV 60) FROM cookie_faction_detention d2 WHERE d2.faction_id=m.faction_id AND d2.officer_citizenid=m.citizenid AND YEARWEEK(d2.created_at,1)=YEARWEEK(NOW(),1)),0) jail_min,
   COALESCE((SELECT COUNT(*) FROM cookie_police_case c WHERE c.faction_id=m.faction_id AND c.officer_citizenid=m.citizenid AND YEARWEEK(c.created_at,1)=YEARWEEK(NOW(),1)),0) cases
 FROM cookie_faction_member m LEFT JOIN cookie_faction_rank r ON r.faction_id=m.faction_id AND r.grade=m.grade LEFT JOIN players p ON p.citizenid=m.citizenid LEFT JOIN cookie_user cu ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci=SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci WHERE m.faction_id=? AND m.status='active' ORDER BY fine_count DESC,jail_count DESC,duty_min DESC]],{member.id})or{}
 for _,r in ipairs(rows)do r.identity=('%s / %s'):format(tostring(r.gobun or '-'),tostring(r.nickname or '-')) end
 return tableResult('이번 주 실적',{{key='identity',label='고번 / 이름'},{key='rank_name',label='계급'},{key='duty_min',label='근무(분)'},{key='fine_count',label='부과건'},{key='fine_total',label='총 벌금'},{key='jail_count',label='구금건'},{key='jail_min',label='구금(분)'},{key='cases',label='사건'}},rows)
end
local function leaveBoard(member)
 local rows=MySQL.query.await([[SELECT id,member_name,start_date,end_date,reason,status,reviewer_name,created_at FROM cookie_intranet_leave WHERE faction_id=? ORDER BY id DESC LIMIT 60]],{member.id})or{}
 local actions={};if member.isOfficer or member.isLeader then actions={{action='leave_approve',label='승인',tone='green'},{action='leave_reject',label='반려',tone='red'}}end
 return tableResult('휴가/휴직 신청',{{key='member_name',label='신청자'},{key='start_date',label='시작'},{key='end_date',label='종료'},{key='reason',label='사유'},{key='status',label='상태'},{key='reviewer_name',label='처리자'}},rows,actions)
end
local function settlements(member)
 local rows=MySQL.query.await([[SELECT target_name,amount,note,paid_by_name,created_at FROM cookie_intranet_settlement WHERE faction_id=? ORDER BY id DESC LIMIT 60]],{member.id})or{}
 return tableResult('정산 내역',{{key='target_name',label='대상'},{key='amount',label='정산액'},{key='note',label='내용'},{key='paid_by_name',label='처리자'},{key='created_at',label='시간'}},rows)
end
local function penaltyData()
 local rows={}
 for _,x in ipairs(Config.PenaltyCatalog or{})do
   rows[#rows+1]={
      id=x.id,category=x.category,label=x.label,
      description=x.desc,
      fine=tonumber(x.fine)or 0,
      jail=tonumber(x.jail)or 0,
      license=tonumber(x.license)or 0,
      score=tonumber(x.score)or 0,
      settlement=x.settlement==true,
      note=x.note
   }
 end
 return{
   ok=true,kind='calculator',
   title='벌금·구금·면허 계산기',
   offences=rows,
   bailPerMinute=tonumber(Config.PenaltyBailPerMinute)or 0,
   maxLicenseMinutes=tonumber(Config.PenaltyLicenseMaxMinutes)or 60
 }
end

function CookieIntranetAction(src,action,payload,member,actor)
 if action=='penalty_calculator'then return penaltyData() end
 if action=='intranet_home'then return home(member,actor)end
 if action=='intranet_ledger'then return ledger(member)end
 if action=='intranet_performance'then return performance(member)end
 if action=='intranet_leave_board'then return leaveBoard(member)end
 if action=='intranet_settlement_board'then if not(member.isOfficer or member.isLeader)then return{ok=false,message='간부 이상만 정산 내역을 관리할 수 있습니다.'}end;return settlements(member)end
 if action=='intranet_leave_request'then
   local sd,ed=clean(payload.startDate,10),clean(payload.endDate,10);local reason=clean(payload.reason,500);if not sd:match('^%d%d%d%d%-%d%d%-%d%d$')or not ed:match('^%d%d%d%d%-%d%d%-%d%d$')then return{ok=false,message='날짜를 YYYY-MM-DD 형식으로 입력하세요.'}end;if reason==''then return{ok=false,message='휴가 사유를 입력하세요.'}end
   MySQL.insert.await('INSERT INTO cookie_intranet_leave(faction_id,citizenid,member_name,start_date,end_date,reason) VALUES(?,?,?,?,?,?)',{member.id,actor.citizenid,actor.label,sd,ed,reason});return success('휴가 신청 완료',sd..' ~ '..ed)
 end
 if action=='intranet_ledger_add'then
   if not(member.isOfficer or member.isLeader)then return{ok=false,message='간부 이상만 장부를 입력할 수 있습니다.'}end
   local kind=tostring(payload.kind or 'expense');local amount=math.max(1,math.floor(tonumber(payload.amount)or 0));local reason=clean(payload.reason,120);if reason==''then return{ok=false,message='장부 내용을 입력하세요.'}end;local f=MySQL.single.await('SELECT budget FROM cookie_faction WHERE id=?',{member.id})or{};local cur=tonumber(f.budget)or 0;local delta=kind=='income'and amount or -amount;if cur+delta<0 then return{ok=false,message='팩션 공금이 부족합니다.'}end;MySQL.update.await('UPDATE cookie_faction SET budget=budget+? WHERE id=?',{delta,member.id});local after=cur+delta;MySQL.insert.await('INSERT INTO cookie_faction_budget_log(faction_id,delta,balance_after,category,reason,actor_citizenid) VALUES(?,?,?,?,?,?)',{member.id,delta,after,'intranet_'..kind,reason,actor.citizenid})
   local accountKey=tostring(member.type or ''):lower()=='security' and 'security_account' or 'police_account'
   cookieIntranetLog(accountKey,tostring(member.type or ''):lower()=='security' and '보안국 공동계좌' or '경찰청 공동계좌',reason,{
      {name='구분',value=kind=='income' and '수입' or '지출',inline=true},
      {name='변동',value=(delta>0 and '+' or '')..tostring(delta)..'원',inline=true},
      {name='잔액',value=tostring(after)..'원',inline=true},
   },{actorSrc=src,actorLabel='처리자',eventKey='account_ledger'})
   return success('장부 기록 완료',(delta>0 and '+' or '')..delta..'원')
 end
 if action=='intranet_settlement_pay'then
   if not(member.isOfficer or member.isLeader)then return{ok=false,message='간부 이상만 정산할 수 있습니다.'}end
   local row,why=userRow(payload.target);if not row then return{ok=false,message=why}end;local amount=math.max(1,math.floor(tonumber(payload.amount)or 0));local note=clean(payload.note,200);local fm=MySQL.single.await("SELECT 1 x FROM cookie_faction_member WHERE faction_id=? AND citizenid=? AND status='active' LIMIT 1",{member.id,row.citizenid});if not fm then return{ok=false,message='같은 팩션 소속에게만 정산할 수 있습니다.'}end;local f=MySQL.single.await('SELECT budget FROM cookie_faction WHERE id=?',{member.id})or{};if (tonumber(f.budget)or 0)<amount then return{ok=false,message='팩션 공금이 부족합니다.'}end;local ts=srcByCid(row.citizenid);if not ts then return{ok=false,message='정산 대상이 접속 중이어야 합니다.'}end;local p=exports.qbx_core:GetPlayer(ts);if not p then return{ok=false,message='대상 플레이어를 찾지 못했습니다.'}end;MySQL.update.await('UPDATE cookie_faction SET budget=budget-? WHERE id=?',{amount,member.id});p.Functions.AddMoney('bank',amount,'팩션 인트라넷 정산');local after=(tonumber(f.budget)or 0)-amount;MySQL.insert.await('INSERT INTO cookie_faction_budget_log(faction_id,delta,balance_after,category,reason,actor_citizenid) VALUES(?,?,?,?,?,?)',{member.id,-amount,after,'settlement',note~=''and note or'팩션 정산',actor.citizenid});MySQL.insert.await('INSERT INTO cookie_intranet_settlement(faction_id,target_citizenid,target_name,amount,note,paid_by_cid,paid_by_name) VALUES(?,?,?,?,?,?,?)',{member.id,row.citizenid,label(row),amount,note,actor.citizenid,actor.label})
   local accountKey=tostring(member.type or ''):lower()=='security' and 'security_account' or 'police_account'
   cookieIntranetLog(accountKey,tostring(member.type or ''):lower()=='security' and '보안국 공동계좌' or '경찰청 공동계좌',note,{
      {name='구분',value='정산',inline=true},
      {name='대상',value=label(row),inline=true},
      {name='정산액',value=tostring(amount)..'원',inline=true},
      {name='잔액',value=tostring(after)..'원',inline=true},
   },{actorSrc=src,targetSrc=ts,actorLabel='처리자',targetLabel='정산 대상',eventKey='account_settlement'})
   return success('정산 완료',label(row)..' · '..amount..'원')
 end
 return nil
end

function CookieIntranetResultAction(src,action,payload,member,actor)
 if action=='leave_approve'or action=='leave_reject'then
   if not(member.isOfficer or member.isLeader)then return{ok=false,message='간부 이상만 처리할 수 있습니다.'}end;local id=tonumber(payload.id);local status=action=='leave_approve'and'approved'or'rejected';local n=MySQL.update.await("UPDATE cookie_intranet_leave SET status=?,reviewer_cid=?,reviewer_name=?,reviewed_at=NOW() WHERE id=? AND faction_id=? AND status='pending'",{status,actor.citizenid,actor.label,id,member.id});if not n or n<1 then return{ok=false,message='이미 처리되었거나 찾을 수 없습니다.'}end;return success(status=='approved'and'휴가 승인'or'휴가 반려','처리했습니다.')
 end
 if action=='penalty_apply'then
   local row,why=userRow(payload.target);if not row then return{ok=false,message=why}end;local target=srcByCid(row.citizenid);if not target then return{ok=false,message='대상이 접속 중이 아닙니다.'}end;local a,b=GetPlayerPed(src),GetPlayerPed(target);if a==0 or b==0 or #(GetEntityCoords(a)-GetEntityCoords(b))>5.0 then return{ok=false,message='대상이 너무 멉니다.'}end
   local chosen={}
   for _,id in ipairs(payload.ids or{})do chosen[tostring(id)]=true end

   local fine,jail,licenseMinutes,crimeScore=0,0,0,0
   local labels={}
   local crimeCharges={}

   for _,x in ipairs(Config.PenaltyCatalog or{})do
      if chosen[tostring(x.id)]then
         fine=fine+(tonumber(x.fine)or 0)
         jail=jail+(tonumber(x.jail)or 0)
         licenseMinutes=licenseMinutes+(tonumber(x.license)or 0)
         local score=math.max(0,math.floor(tonumber(x.score)or 0))
         crimeScore=crimeScore+score
         labels[#labels+1]=x.label
         crimeCharges[#crimeCharges+1]={
            id=x.id,
            category=x.category,
            label=x.label,
            score=score
         }
      end
   end

   if #labels==0 then return{ok=false,message='죄목을 하나 이상 선택하세요.'}end

   licenseMinutes=math.min(
      tonumber(Config.PenaltyLicenseMaxMinutes)or 60,
      math.max(0,math.floor(licenseMinutes))
   )

   if jail>0 then
      local ok,c=pcall(function()return exports.cookie_police:IsCuffed(target)end)
      if not ok or c~=true then
         return{ok=false,message='구금이 포함된 처리는 수갑이 채워진 대상에게만 가능합니다.'}
      end
   end

   if licenseMinutes>0 and GetResourceState('cookie_license')~='started' then
      return{ok=false,message='운전면허 시스템이 실행 중이 아닙니다.'}
   end

   local reason=table.concat(labels,', ')

   if licenseMinutes>0 then
      local memberType=tostring(member.type or ''):lower()
      local actorPayload={
         source=src,
         type=memberType,
         name=actor.name or actor.label,
         faction=member.name or (memberType=='security' and '보안국' or '경찰청')
      }

      local ok,result=exports.cookie_license:SuspendByCitizenId(
         row.citizenid,licenseMinutes,reason,actorPayload
      )
      if not ok then
         return{ok=false,message=tostring(result or '운전면허 정지 처리에 실패했습니다.')}
      end
   end

   local p=exports.qbx_core:GetPlayer(target)
   local paid=false
   local finePaymentMethod='미납'
   local fineReceiptId=nil
   if fine>0 then
      if p and p.Functions.RemoveMoney('bank',fine,'벌금 계산기: '..reason)==true then
         paid=true
         finePaymentMethod='은행'
      elseif p and p.Functions.RemoveMoney('cash',fine,'벌금 계산기: '..reason)==true then
         paid=true
         finePaymentMethod='현금'
      end
      fineReceiptId=MySQL.insert.await('INSERT INTO cookie_police_fine(faction_id,target_citizenid,target_name,amount,reason,paid,officer_citizenid,officer_name) VALUES(?,?,?,?,?,?,?,?)',{member.id,row.citizenid,row.nickname,fine,reason,paid and 1 or 0,actor.citizenid,actor.name})
      TriggerClientEvent('cookie_police:client:fineReceipt',target,{
         receiptNo=fineReceiptId and ('F-%06d'):format(tonumber(fineReceiptId) or 0) or ('F-%d'):format(os.time()),
         faction=member.name or (tostring(member.type or ''):lower()=='security' and '보안국' or '경찰청'),
         officer=actor.name or actor.label or '-',
         reason=reason,amount=fine,paid=paid,paymentMethod=finePaymentMethod,
         issuedAt=os.date('%Y-%m-%d %H:%M:%S')
      })
   end
   if jail>0 then MySQL.insert.await('INSERT INTO cookie_faction_detention(faction_id,officer_citizenid,target_citizenid,target_name,charge,fine_amount,jail_seconds,note) VALUES(?,?,?,?,?,?,?,?)',{member.id,actor.citizenid,row.citizenid,row.nickname,reason,paid and fine or 0,jail*60,'벌금·구금 계산기'});MySQL.update.await("UPDATE cookie_police_detention_active SET active=0,released_at=NOW(),released_by='REPLACED' WHERE citizenid=? AND active=1",{row.citizenid});MySQL.insert.await('INSERT INTO cookie_police_detention_active(faction_id,citizenid,target_name,charge,release_at,officer_citizenid,officer_name) VALUES(?,?,?,?,DATE_ADD(NOW(),INTERVAL ? SECOND),?,?)',{member.id,row.citizenid,row.nickname,reason,jail*60,actor.citizenid,actor.name});pcall(function()exports.cookie_police:ForceSetCuffed(target,false)end);TriggerClientEvent('cookie_police:client:setDetained',target,jail*60,reason,true)end

   if fine>0 then
      cookieIntranetLog('fine','벌금 부과',reason,{
         {name='벌금',value=tostring(fine)..'원',inline=true},
         {name='납부',value=paid and '납부 완료' or '미납',inline=true},
         {name='집행 팩션',value=tostring(member.name or '-'),inline=true},
      },{actorSrc=src,targetSrc=target,actorLabel='부과자',targetLabel='대상',eventKey='penalty_fine'})
   end

   if jail>0 then
      local detentionKey=tostring(member.type or ''):lower()=='security' and 'security_detention' or 'police_detention'
      cookieIntranetLog(detentionKey,tostring(member.type or ''):lower()=='security' and '보안국 구금' or '경찰청 구금',reason,{
         {name='구금시간',value=tostring(jail)..'분',inline=true},
         {name='벌금',value=tostring(fine)..'원',inline=true},
      },{actorSrc=src,targetSrc=target,actorLabel='집행자',targetLabel='구금 대상',eventKey='penalty_detention'})
   end

   -- 공식 죄목 처리 결과를 전과/범죄점수로 영구 기록.
   if GetResourceState('cookie_crime')=='started' then
      local okCrime,recordOk,crimeErr=pcall(function()
         return exports.cookie_crime:AddRecord({
            citizenid=row.citizenid,
            gobun=row.gobun,
            nickname=row.nickname,
            charges=crimeCharges,
            crimeScore=crimeScore,
            fine=fine,
            jailMinutes=jail,
            licenseMinutes=licenseMinutes,
            sourceType='police_penalty',
            sourceLabel='벌금·구금·면허 계산기',
            agencyType=tostring(member.type or ''):lower(),
            agencyName=member.name,
            officerCitizenId=actor.citizenid,
            officerName=actor.name or actor.label
         })
      end)
      if not okCrime or recordOk~=true then
         print(('[cookie_police] 전과 기록 저장 실패: %s'):format(
            tostring(okCrime and crimeErr or recordOk)
         ))
      end
   end

   return success(
      '벌금·구금·면허 처리 완료',
      ('%s · 벌금 %d원 · 구금 %d분 · 면허정지 %d분'):format(label(row),fine,jail,licenseMinutes)
   )
 end
 return nil
end
