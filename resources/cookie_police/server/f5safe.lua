-- COOKIE F5 V3.1 SAFE ROUTER
-- 조회형/인트라넷 업무를 기존 대형 MDT 콜백과 분리하여
-- 한 기능의 SQL 오류가 F5 전체 조회를 막지 않도록 한다.

local function clean(v,n)
    local s=tostring(v or ''):gsub('[%c]',' '):gsub('^%s+',''):gsub('%s+$','')
    if n and #s>n then s=s:sub(1,n) end
    return s
end

local function safeQuery(sql,args,fallback,label)
    local ok,res=pcall(function()
        return MySQL.query.await(sql,args or {})
    end)
    if not ok then
        print(('^1[cookie_police F5 SAFE]^7 %s query failed: %s'):format(
            tostring(label or 'query'),tostring(res)
        ))
        return fallback or {}
    end
    return res or fallback or {}
end

local function safeSingle(sql,args,label)
    local ok,res=pcall(function()
        return MySQL.single.await(sql,args or {})
    end)
    if not ok then
        print(('^1[cookie_police F5 SAFE]^7 %s single failed: %s'):format(
            tostring(label or 'single'),tostring(res)
        ))
        return nil
    end
    return res
end

local function success(title,message)
    return {ok=true,kind='success',title=title,message=message}
end

local function tableResult(title,columns,rows,rowActions)
    return {
        ok=true,kind='table',title=title,
        columns=columns or {},rows=rows or {},rowActions=rowActions or {}
    }
end

local function getMember(src)
    if GetResourceState('cookie_admin')~='started' then return nil end
    local ok,m=pcall(function()
        return exports.cookie_admin:getFactionOf(src)
    end)
    if not ok or type(m)~='table' then return nil end
    local t=tostring(m.type or ''):lower()
    if t~='police' and t~='security' then return nil end
    return m
end

local function actorInfo(src)
    local p=exports.qbx_core:GetPlayer(src)
    local pd=p and p.PlayerData or {}
    local ci=pd.charinfo or {}
    local name=clean((ci.firstname or '')..' '..(ci.lastname or ''),80)
    if name=='' then
        pcall(function() name=exports.cookie_core:getNickname(src) end)
    end
    if not name or name=='' then name=GetPlayerName(src) or '-' end
    return {
        source=src,
        citizenid=tostring(pd.citizenid or ''),
        name=name,
        label=name
    }
end

local function guard(src,officerOnly)
    local m=getMember(src)
    if not m then
        return nil,{ok=false,message='경찰청/보안국 소속만 사용할 수 있습니다.'}
    end
    if m.duty~=true then
        return nil,{ok=false,message='출근 상태에서만 사용할 수 있습니다.'}
    end
    if officerOnly and not (m.isOfficer or m.isLeader) then
        return nil,{ok=false,message='간부 이상만 사용할 수 있습니다.'}
    end
    return m,nil
end

local function userRow(q)
    q=clean(q,80)
    if q=='' then return nil,'고번 또는 이름을 입력하세요.' end
    local like='%'..q..'%'
    local rows=safeQuery([[
        SELECT p.citizenid,cu.gobun,cu.nickname
        FROM players p
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
        WHERE CAST(cu.gobun AS CHAR)=? OR cu.nickname LIKE ?
        ORDER BY (CAST(cu.gobun AS CHAR)=?) DESC,(cu.nickname=?) DESC
        LIMIT 20
    ]],{q,like,q,q},{},'userRow')

    if #rows==0 then return nil,'시민을 찾지 못했습니다.' end
    if #rows>1 then
        for _,r in ipairs(rows) do
            if tostring(r.gobun)==q then return r end
        end
        return nil,'동일/유사 이름이 여러 명입니다. 고번으로 입력하세요.'
    end
    return rows[1]
end

local function sourceByCid(cid)
    cid=tostring(cid or '')
    for _,raw in ipairs(GetPlayers()) do
        local src=tonumber(raw)
        local p=src and exports.qbx_core:GetPlayer(src) or nil
        if p and p.PlayerData and tostring(p.PlayerData.citizenid or '')==cid then
            return src
        end
    end
end

local function identityLabel(r)
    return ('%s / %s'):format(tostring(r and r.gobun or '-'),tostring(r and r.nickname or '-'))
end

local function audit(member,actor,action,targetCid,detail)
    pcall(function()
        MySQL.insert.await([[
            INSERT INTO cookie_police_audit
              (faction_id,actor_citizenid,actor_name,action,target_citizenid,detail)
            VALUES (?,?,?,?,?,?)
        ]],{
            member.id,actor.citizenid,actor.name,
            clean(action,40),
            targetCid and tostring(targetCid) or nil,
            clean(detail,500)
        })
    end)
end

local function cookieLog(category,title,description,fields,options)
    if GetResourceState('cookie_logs')~='started' then return end
    pcall(function()
        exports.cookie_logs:Log(category,title,description,fields or {},options or {})
    end)
end

local function ensureSchema()
    local statements={
[[
CREATE TABLE IF NOT EXISTS cookie_police_wanted (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 target_name VARCHAR(80) NULL,
 kind VARCHAR(16) NOT NULL DEFAULT 'wanted',
 reason VARCHAR(500) NOT NULL,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 active TINYINT(1) NOT NULL DEFAULT 1,
 expires_at DATETIME NOT NULL,
 cleared_at DATETIME NULL,
 cleared_by VARCHAR(80) NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_safe_wanted(faction_id,active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_police_wanted_unit (
 wanted_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 officer_name VARCHAR(80) NULL,
 joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(wanted_id,citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_police_warrant (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 citizenid VARCHAR(50) NULL,
 target_name VARCHAR(80) NULL,
 target_faction_id INT NULL,
 target_faction_key VARCHAR(40) NULL,
 target_faction_name VARCHAR(80) NULL,
 target_faction_type VARCHAR(20) NULL,
 warrant_type VARCHAR(16) NOT NULL DEFAULT 'search',
 reason VARCHAR(500) NOT NULL,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 active TINYINT(1) NOT NULL DEFAULT 1,
 expires_at DATETIME NULL,
 closed_at DATETIME NULL,
 closed_by VARCHAR(80) NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_safe_warrant(faction_id,active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_police_case (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 case_no VARCHAR(30) NOT NULL UNIQUE,
 title VARCHAR(120) NOT NULL,
 suspect_citizenid VARCHAR(50) NULL,
 suspect_name VARCHAR(80) NULL,
 summary TEXT NOT NULL,
 result TEXT NULL,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 status VARCHAR(16) NOT NULL DEFAULT 'open',
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 INDEX idx_safe_case(faction_id,status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_police_dispatch (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NULL,
 title VARCHAR(100) NOT NULL,
 detail VARCHAR(500) NULL,
 priority INT NOT NULL DEFAULT 1,
 x DOUBLE NULL,y DOUBLE NULL,z DOUBLE NULL,
 created_by VARCHAR(80) NULL,
 active TINYINT(1) NOT NULL DEFAULT 1,
 closed_by VARCHAR(80) NULL,
 closed_at DATETIME NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_safe_dispatch(faction_id,active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_police_dispatch_unit (
 dispatch_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 officer_name VARCHAR(80) NULL,
 joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(dispatch_id,citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_police_audit (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 actor_citizenid VARCHAR(50) NULL,
 actor_name VARCHAR(80) NULL,
 action VARCHAR(40) NOT NULL,
 target_citizenid VARCHAR(50) NULL,
 detail VARCHAR(500) NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_safe_audit(faction_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_police_fine (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 target_citizenid VARCHAR(50) NOT NULL,
 target_name VARCHAR(80) NULL,
 amount INT NOT NULL DEFAULT 0,
 reason VARCHAR(300) NOT NULL,
 paid TINYINT(1) NOT NULL DEFAULT 0,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_safe_fine(faction_id,officer_citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_police_detention_active (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 target_name VARCHAR(80) NULL,
 charge VARCHAR(200) NOT NULL,
 release_at DATETIME NOT NULL,
 active TINYINT(1) NOT NULL DEFAULT 1,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 released_by VARCHAR(80) NULL,
 released_at DATETIME NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_safe_detention(citizenid,active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_intranet_duty_session (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 member_name VARCHAR(80) NULL,
 start_at DATETIME NOT NULL,
 end_at DATETIME NULL,
 minutes INT NOT NULL DEFAULT 0,
 INDEX idx_safe_duty(faction_id,start_at),
 INDEX idx_safe_duty_cid(citizenid,end_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_intranet_leave (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 member_name VARCHAR(80) NULL,
 start_date DATE NOT NULL,
 end_date DATE NOT NULL,
 reason VARCHAR(500) NOT NULL,
 status VARCHAR(16) NOT NULL DEFAULT 'pending',
 reviewer_cid VARCHAR(50) NULL,
 reviewer_name VARCHAR(80) NULL,
 reviewed_at DATETIME NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_safe_leave(faction_id,status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
[[
CREATE TABLE IF NOT EXISTS cookie_intranet_settlement (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 target_citizenid VARCHAR(50) NOT NULL,
 target_name VARCHAR(80) NULL,
 amount BIGINT NOT NULL,
 note VARCHAR(200) NULL,
 paid_by_cid VARCHAR(50) NULL,
 paid_by_name VARCHAR(80) NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_safe_settlement(faction_id,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
    }

    for _,sql in ipairs(statements) do
        pcall(function() MySQL.query.await(sql) end)
    end

    for _,sql in ipairs({
        "ALTER TABLE cookie_police_warrant ADD COLUMN IF NOT EXISTS target_faction_id INT NULL",
        "ALTER TABLE cookie_police_warrant ADD COLUMN IF NOT EXISTS target_faction_key VARCHAR(40) NULL",
        "ALTER TABLE cookie_police_warrant ADD COLUMN IF NOT EXISTS target_faction_name VARCHAR(80) NULL",
        "ALTER TABLE cookie_police_warrant ADD COLUMN IF NOT EXISTS target_faction_type VARCHAR(20) NULL",
    }) do
        pcall(function() MySQL.query.await(sql) end)
    end
end

CreateThread(function()
    Wait(500)
    ensureSchema()
    print('^2[cookie_police F5 SAFE]^7 safe action router ready')
end)

local function roster(member)
    local rows=safeQuery([[
        SELECT m.citizenid,m.grade,m.duty,r.rank_name,cu.gobun,cu.nickname
        FROM cookie_faction_member m
        LEFT JOIN cookie_faction_rank r
          ON r.faction_id=m.faction_id AND r.grade=m.grade
        LEFT JOIN players p ON p.citizenid=m.citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
        WHERE m.faction_id=? AND m.status='active'
        ORDER BY m.duty DESC,m.grade DESC,cu.gobun ASC
    ]],{member.id},{},'roster')

    local out={}
    for _,r in ipairs(rows) do
        out[#out+1]={
            identity=('%s / %s'):format(tostring(r.gobun or '-'),tostring(r.nickname or '-')),
            rank=r.rank_name or ('G'..tostring(r.grade or 0)),
            duty=(r.duty==1 or r.duty==true) and '근무중' or '퇴근'
        }
    end
    return tableResult('근무자 현황',{
        {key='identity',label='고번 / 이름'},
        {key='rank',label='계급'},
        {key='duty',label='상태'}
    },out)
end

local function wantedBoard(member,actor)
    local actorCid=tostring(actor and actor.citizenid or '')
    local rows=safeQuery([[
        SELECT w.id,w.citizenid,w.target_name,w.kind,w.reason,
               w.officer_citizenid,w.officer_name,
               w.expires_at,UNIX_TIMESTAMP(w.expires_at) expires_ts,
               cu.gobun,cu.nickname,
               (SELECT COUNT(*) FROM cookie_police_wanted_unit u WHERE u.wanted_id=w.id) units,
               (SELECT COUNT(*) FROM cookie_police_wanted_unit u WHERE u.wanted_id=w.id AND u.citizenid=?) joined,
               (SELECT GROUP_CONCAT(u.officer_name ORDER BY u.joined_at SEPARATOR ', ')
                  FROM cookie_police_wanted_unit u WHERE u.wanted_id=w.id) unit_names
        FROM cookie_police_wanted w
        LEFT JOIN players p ON p.citizenid=w.citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
        WHERE w.active=1 AND w.expires_at>NOW()
        ORDER BY w.id DESC LIMIT 50
    ]],{actorCid},{},'wanted_board_v3')

    local out={}
    local now=os.time()
    for _,r in ipairs(rows) do
        local remain=math.max(0,(tonumber(r.expires_ts) or now)-now)
        local kind=r.kind=='escape' and '도주' or '수배'
        out[#out+1]={
            id=r.id,
            kind=kind,
            target=('%s / %s'):format(tostring(r.gobun or '-'),tostring(r.nickname or r.target_name or '-')),
            reason=r.reason,
            officer=r.officer_name or '-',
            remaining=('%02d:%02d'):format(math.floor(remain/60),remain%60),
            participants=('%s명 · %s'):format(tonumber(r.units) or 0,tostring(r.unit_names or '-')),
            joinLabel=kind=='도주' and '도주 참여' or '수배 참여',
            canJoin=(tonumber(r.joined) or 0)==0,
            canClear=tostring(r.officer_citizenid or '')==actorCid
        }
    end
    return tableResult('수배/도주 현황',{
        {key='kind',label='구분'},
        {key='target',label='고번 / 이름'},
        {key='reason',label='사유'},
        {key='officer',label='등록자'},
        {key='remaining',label='남은 시간'},
        {key='participants',label='참여 인원'},
    },out,{
        {action='wanted_join',label='참여',labelKey='joinLabel',tone='blue',showKey='canJoin'},
        {action='wanted_clear',label='종료',tone='green',showKey='canClear'}
    })
end

local function warrantTargets(member)
    local rows=safeQuery([[
        SELECT id,faction_key,faction_type,name
        FROM cookie_faction
        WHERE is_active=1
        ORDER BY faction_type,name
    ]],{},{},'warrant_targets')

    local allowed={private=true,crime=true,civil=true,police=true,security=true,corrections=true,fire=true}
    local labels={
        private='사설팩션',crime='범죄조직',civil='시민직',
        police='경찰청',security='보안국',corrections='교정국',fire='소방청'
    }
    local options={}
    for _,f in ipairs(rows) do
        local t=tostring(f.faction_type or ''):lower()
        if allowed[t] and tonumber(f.id)~=tonumber(member.id) then
            options[#options+1]={
                value=tostring(f.id),
                label=('[%s] %s'):format(labels[t] or t,tostring(f.name or f.faction_key))
            }
        end
    end
    return {ok=true,kind='options',title='영장 대상 팩션/조직',options=options}
end

local function warrantBoard(member)
    local rows=safeQuery([[
        SELECT id,target_faction_id,target_faction_name,target_faction_type,
               warrant_type,reason,officer_name,expires_at
        FROM cookie_police_warrant
        WHERE faction_id=? AND target_faction_id IS NOT NULL
          AND active=1 AND (expires_at IS NULL OR expires_at>NOW())
        ORDER BY id DESC LIMIT 50
    ]],{member.id},{},'warrant_board')

    local out={}
    for _,r in ipairs(rows) do
        out[#out+1]={
            id=r.id,
            type=r.warrant_type=='raid' and '작전 영장' or '수색 영장',
            target=r.target_faction_name or '-',
            reason=r.reason,
            officer=r.officer_name,
            expires=r.expires_at or '무기한'
        }
    end
    return tableResult('팩션/조직 영장 현황',{
        {key='type',label='종류'},
        {key='target',label='대상 팩션/조직'},
        {key='reason',label='사유'},
        {key='officer',label='발부자'},
        {key='expires',label='만료'}
    },out,{{action='warrant_close',label='종료',tone='green'}})
end

local function dispatchBoard(member)
    local rows=safeQuery([[
        SELECT d.id,d.title,d.detail,d.priority,d.created_by,d.created_at,
          (SELECT COUNT(*) FROM cookie_police_dispatch_unit u WHERE u.dispatch_id=d.id) units
        FROM cookie_police_dispatch d
        WHERE d.active=1 AND (d.faction_id IS NULL OR d.faction_id=?)
        ORDER BY d.priority DESC,d.id DESC LIMIT 50
    ]],{member.id},{},'dispatch_board')

    return tableResult('신고/출동 현황',{
        {key='priorityLabel',label='우선'},
        {key='title',label='신고'},
        {key='detail',label='내용'},
        {key='units',label='출동'},
        {key='created_at',label='접수'}
    },(function()
        local out={}
        for _,r in ipairs(rows) do
            r.priorityLabel='P'..tostring(r.priority or 1)
            out[#out+1]=r
        end
        return out
    end)(),{
        {action='dispatch_join',label='출동 참가',tone='blue'},
        {action='dispatch_close',label='종결',tone='green'}
    })
end

local function casesBoard(member)
    local rows=safeQuery([[
        SELECT c.id,c.case_no,c.title,c.suspect_name,c.officer_name,c.status,c.created_at,cu.gobun
        FROM cookie_police_case c
        LEFT JOIN players p ON p.citizenid=c.suspect_citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
        WHERE c.faction_id=?
        ORDER BY c.id DESC LIMIT 50
    ]],{member.id},{},'cases')

    for _,r in ipairs(rows) do
        r.suspect=(r.suspect_name and r.suspect_name~='')
            and (('%s / %s'):format(tostring(r.gobun or '-'),tostring(r.suspect_name)))
            or '-'
    end
    return tableResult('사건 목록',{
        {key='case_no',label='사건번호'},
        {key='title',label='사건명'},
        {key='suspect',label='피의자'},
        {key='officer_name',label='작성자'},
        {key='status',label='상태'},
        {key='created_at',label='작성일'}
    },rows,{{action='case_close',label='종결',tone='green'}})
end

local function auditBoard(member)
    local rows=safeQuery([[
        SELECT actor_name,action,detail,created_at
        FROM cookie_police_audit
        WHERE faction_id=?
        ORDER BY id DESC LIMIT 50
    ]],{member.id},{},'audit')
    return tableResult('업무 로그',{
        {key='actor_name',label='처리자'},
        {key='action',label='업무'},
        {key='detail',label='내용'},
        {key='created_at',label='시간'}
    },rows)
end

local function penaltyData()
    local rows={}
    for _,x in ipairs(Config.PenaltyCatalog or {}) do
        rows[#rows+1]={
            id=x.id,category=x.category,label=x.label,
            description=x.desc,
            fine=tonumber(x.fine) or 0,
            jail=tonumber(x.jail) or 0,
            license=tonumber(x.license) or 0,
            score=tonumber(x.score) or 0,
            settlement=x.settlement==true,
            note=x.note
        }
    end
    return {
        ok=true,kind='calculator',
        title='벌금·구금·면허 계산기',
        offences=rows,
        bailPerMinute=tonumber(Config.PenaltyBailPerMinute) or 0,
        maxLicenseMinutes=tonumber(Config.PenaltyLicenseMaxMinutes) or 60
    }
end

local function intranetHome(member,actor)
    pcall(function()
        if member.duty==true and actor.citizenid~='' then
            MySQL.query.await([[
                INSERT INTO cookie_intranet_duty_session
                  (faction_id,citizenid,member_name,start_at)
                SELECT ?,?,?,NOW()
                WHERE NOT EXISTS(
                  SELECT 1 FROM cookie_intranet_duty_session
                  WHERE citizenid=? AND end_at IS NULL
                )
            ]],{member.id,actor.citizenid,actor.name,actor.citizenid})
        end
    end)

    local f=safeSingle('SELECT budget FROM cookie_faction WHERE id=?',{member.id},'home budget') or {}
    local duty=safeSingle([[
        SELECT COALESCE(SUM(TIMESTAMPDIFF(MINUTE,start_at,COALESCE(end_at,NOW()))),0) m
        FROM cookie_intranet_duty_session
        WHERE faction_id=? AND citizenid=? AND YEARWEEK(start_at,1)=YEARWEEK(NOW(),1)
    ]],{member.id,actor.citizenid},'home duty') or {}
    local perf=safeSingle([[
        SELECT COUNT(*) fine_count,COALESCE(SUM(amount),0) fine_total
        FROM cookie_police_fine
        WHERE faction_id=? AND officer_citizenid=?
          AND YEARWEEK(created_at,1)=YEARWEEK(NOW(),1)
    ]],{member.id,actor.citizenid},'home fine') or {}
    local leave=safeSingle([[
        SELECT COUNT(*) n FROM cookie_intranet_leave
        WHERE faction_id=? AND status='pending'
    ]],{member.id},'home leave') or {}

    return {
        ok=true,kind='summary',title=(member.name or '팩션')..' 인트라넷',
        metrics={
            {label='이번 주 근무',value=(tonumber(duty.m) or 0)..'분'},
            {label='이번 주 벌금 부과',value=tonumber(perf.fine_count) or 0},
            {label='벌금 합계',value=tonumber(perf.fine_total) or 0},
            {label='팩션 공금',value=tonumber(f.budget) or 0},
            {label='휴가 승인 대기',value=tonumber(leave.n) or 0}
        },
        rows={}
    }
end

local function ledger(member)
    local f=safeSingle('SELECT budget FROM cookie_faction WHERE id=?',{member.id},'ledger budget') or {}
    local rows=safeQuery([[
        SELECT delta,balance_after,category,reason,created_at
        FROM cookie_faction_budget_log
        WHERE faction_id=? ORDER BY id DESC LIMIT 60
    ]],{member.id},{},'ledger')
    return {
        ok=true,kind='summary',title='팩션 장부',
        metrics={{label='현재 공금',value=tonumber(f.budget) or 0},{label='최근 기록',value=#rows}},
        columns={
            {key='delta',label='변동'},{key='balance_after',label='잔액'},
            {key='category',label='구분'},{key='reason',label='내용'},{key='created_at',label='시간'}
        },
        rows=rows
    }
end

local function performance(member)
    local rows=safeQuery([[
        SELECT m.citizenid,cu.gobun,cu.nickname,r.rank_name,
          COALESCE((SELECT SUM(TIMESTAMPDIFF(MINUTE,d.start_at,COALESCE(d.end_at,NOW())))
            FROM cookie_intranet_duty_session d
            WHERE d.faction_id=m.faction_id AND d.citizenid=m.citizenid
              AND YEARWEEK(d.start_at,1)=YEARWEEK(NOW(),1)),0) duty_min,
          COALESCE((SELECT COUNT(*) FROM cookie_police_fine f
            WHERE f.faction_id=m.faction_id AND f.officer_citizenid=m.citizenid
              AND YEARWEEK(f.created_at,1)=YEARWEEK(NOW(),1)),0) fine_count,
          COALESCE((SELECT SUM(f.amount) FROM cookie_police_fine f
            WHERE f.faction_id=m.faction_id AND f.officer_citizenid=m.citizenid
              AND YEARWEEK(f.created_at,1)=YEARWEEK(NOW(),1)),0) fine_total,
          COALESCE((SELECT COUNT(*) FROM cookie_faction_detention d2
            WHERE d2.faction_id=m.faction_id AND d2.officer_citizenid=m.citizenid
              AND YEARWEEK(d2.created_at,1)=YEARWEEK(NOW(),1)),0) jail_count,
          COALESCE((SELECT SUM(d2.jail_seconds DIV 60) FROM cookie_faction_detention d2
            WHERE d2.faction_id=m.faction_id AND d2.officer_citizenid=m.citizenid
              AND YEARWEEK(d2.created_at,1)=YEARWEEK(NOW(),1)),0) jail_min,
          COALESCE((SELECT COUNT(*) FROM cookie_police_case c
            WHERE c.faction_id=m.faction_id AND c.officer_citizenid=m.citizenid
              AND YEARWEEK(c.created_at,1)=YEARWEEK(NOW(),1)),0) cases
        FROM cookie_faction_member m
        LEFT JOIN cookie_faction_rank r ON r.faction_id=m.faction_id AND r.grade=m.grade
        LEFT JOIN players p ON p.citizenid=m.citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
        WHERE m.faction_id=? AND m.status='active'
        ORDER BY fine_count DESC,jail_count DESC,duty_min DESC
    ]],{member.id},{},'performance')

    for _,r in ipairs(rows) do
        r.identity=('%s / %s'):format(tostring(r.gobun or '-'),tostring(r.nickname or '-'))
    end
    return tableResult('이번 주 실적',{
        {key='identity',label='고번 / 이름'},
        {key='rank_name',label='계급'},
        {key='duty_min',label='근무(분)'},
        {key='fine_count',label='부과건'},
        {key='fine_total',label='총 벌금'},
        {key='jail_count',label='구금건'},
        {key='jail_min',label='구금(분)'},
        {key='cases',label='사건'}
    },rows)
end

local function leaveBoard(member)
    local rows=safeQuery([[
        SELECT id,member_name,start_date,end_date,reason,status,reviewer_name,created_at
        FROM cookie_intranet_leave
        WHERE faction_id=? ORDER BY id DESC LIMIT 60
    ]],{member.id},{},'leave')
    local actions={}
    if member.isOfficer or member.isLeader then
        actions={
            {action='leave_approve',label='승인',tone='green'},
            {action='leave_reject',label='반려',tone='red'}
        }
    end
    return tableResult('휴가/휴직 신청',{
        {key='member_name',label='신청자'},
        {key='start_date',label='시작'},
        {key='end_date',label='종료'},
        {key='reason',label='사유'},
        {key='status',label='상태'},
        {key='reviewer_name',label='처리자'}
    },rows,actions)
end

local function settlements(member)
    local rows=safeQuery([[
        SELECT target_name,amount,note,paid_by_name,created_at
        FROM cookie_intranet_settlement
        WHERE faction_id=? ORDER BY id DESC LIMIT 60
    ]],{member.id},{},'settlement')
    return tableResult('정산 내역',{
        {key='target_name',label='대상'},
        {key='amount',label='정산액'},
        {key='note',label='내용'},
        {key='paid_by_name',label='처리자'},
        {key='created_at',label='시간'}
    },rows)
end

local function budget(member)
    local f=safeSingle('SELECT budget FROM cookie_faction WHERE id=?',{member.id},'budget') or {}
    local rows=safeQuery([[
        SELECT delta,balance_after,category,reason,created_at
        FROM cookie_faction_budget_log
        WHERE faction_id=? ORDER BY id DESC LIMIT 30
    ]],{member.id},{},'budget log')
    return {
        ok=true,kind='summary',title='팩션 공금',
        metrics={{label='현재 공금',value=tonumber(f.budget) or 0},{label='최근 내역',value=#rows}},
        columns={
            {key='delta',label='변동'},{key='balance_after',label='잔액'},
            {key='category',label='구분'},{key='reason',label='사유'},{key='created_at',label='시간'}
        },rows=rows
    }
end

local officerActions={
    warrant_add=true,
    intranet_settlement_board=true,
    budget_lookup=true
}

lib.callback.register('cookie_police:f5SafeAction',function(source,action,payload)
    local ok,result=xpcall(function()
        local src=source
        action=tostring(action or '')
        payload=type(payload)=='table' and payload or {}

        local member,err=guard(src,officerActions[action]==true)
        if not member then return err end
        local actor=actorInfo(src)

        if action=='roster' then return roster(member) end
        if action=='wanted_board' then return wantedBoard(member,actor) end
        if action=='warrant_targets' then return warrantTargets(member) end
        if action=='warrant_board' then return warrantBoard(member) end
        if action=='dispatch' then return dispatchBoard(member) end
        if action=='cases' then return casesBoard(member) end
        if action=='audit' then return auditBoard(member) end
        if action=='penalty_calculator' then return penaltyData() end
        if action=='intranet_home' then return intranetHome(member,actor) end
        if action=='intranet_ledger' then return ledger(member) end
        if action=='intranet_performance' then return performance(member) end
        if action=='intranet_leave_board' then return leaveBoard(member) end
        if action=='intranet_settlement_board' then return settlements(member) end
        if action=='budget_lookup' then return budget(member) end

        if action=='warrant_add' then
            local targetFactionId=tonumber(payload.targetFactionId)
            if not targetFactionId then return {ok=false,message='대상 팩션/조직을 선택하세요.'} end
            local targetFaction=safeSingle([[
                SELECT id,faction_key,faction_type,name
                FROM cookie_faction WHERE id=? AND is_active=1 LIMIT 1
            ]],{targetFactionId},'warrant target')
            if not targetFaction then return {ok=false,message='대상 팩션/조직을 찾지 못했습니다.'} end
            if tonumber(targetFaction.id)==tonumber(member.id) then
                return {ok=false,message='자기 팩션에는 영장을 발부할 수 없습니다.'}
            end
            local reason=clean(payload.reason,500)
            if reason=='' then return {ok=false,message='영장 발부 사유를 입력하세요.'} end
            local wt=tostring(payload.warrantType or '')=='raid' and 'raid' or 'search'
            local minutes=math.max(0,math.min(43200,math.floor(tonumber(payload.minutes) or 0)))
            local expires=minutes>0 and os.date('%Y-%m-%d %H:%M:%S',os.time()+minutes*60) or nil

            local okInsert,id=pcall(function()
                return MySQL.insert.await([[
                    INSERT INTO cookie_police_warrant
                      (faction_id,citizenid,target_name,
                       target_faction_id,target_faction_key,target_faction_name,target_faction_type,
                       warrant_type,reason,officer_citizenid,officer_name,expires_at)
                    VALUES (?,NULL,NULL,?,?,?,?,?,?,?,?,?)
                ]],{
                    member.id,targetFaction.id,targetFaction.faction_key,
                    targetFaction.name,targetFaction.faction_type,
                    wt,reason,actor.citizenid,actor.name,expires
                })
            end)
            if not okInsert or not id then
                return {ok=false,message='영장 DB 저장에 실패했습니다. 서버 콘솔의 F5 SAFE 로그를 확인하세요.'}
            end

            audit(member,actor,'warrant_add',nil,
                ('%s · %s · %s'):format(
                    tostring(targetFaction.name),
                    wt=='raid' and '작전 영장' or '수색 영장',
                    reason
                )
            )
            cookieLog('warrant','영장 발부',reason,{
                {name='대상',value=tostring(targetFaction.name),inline=true},
                {name='종류',value=wt=='raid' and '작전 영장' or '수색 영장',inline=true},
                {name='유효시간',value=minutes>0 and (minutes..'분') or '무기한',inline=true}
            },{actorSrc=src,actorLabel='발부자',eventKey='warrant'})

            return success('팩션/조직 영장 발부 완료',
                tostring(targetFaction.name)..' · '..(wt=='raid' and '작전 영장' or '수색 영장'))
        end

        return {ok=false,message='SAFE 라우터에 연결되지 않은 업무입니다: '..action}
    end,debug.traceback)

    if not ok then
        print(('^1[cookie_police F5 SAFE]^7 action crash (%s): %s'):format(
            tostring(action),tostring(result)
        ))
        return {
            ok=false,
            message='업무 처리 중 서버 오류가 발생했습니다. 서버 콘솔의 [cookie_police F5 SAFE] 로그를 확인하세요.'
        }
    end

    return result or {ok=false,message='업무 결과가 비어 있습니다.'}
end)

-- 결과 버튼/계산기 처리도 별도 안전 콜백으로 분리.
lib.callback.register('cookie_police:f5SafeResultAction',function(source,action,payload)
    local ok,result=xpcall(function()
        local src=source
        action=tostring(action or '')
        payload=type(payload)=='table' and payload or {}

        local officerOnly=(action=='warrant_close' or action=='leave_approve' or action=='leave_reject')
        local member,err=guard(src,officerOnly)
        if not member then return err end
        local actor=actorInfo(src)

        if action=='leave_approve' or action=='leave_reject' then
            local id=tonumber(payload.id)
            if not id then return {ok=false,message='휴가 신청 번호가 없습니다.'} end
            local status=action=='leave_approve' and 'approved' or 'rejected'
            local n=MySQL.update.await([[
                UPDATE cookie_intranet_leave
                SET status=?,reviewer_cid=?,reviewer_name=?,reviewed_at=NOW()
                WHERE id=? AND faction_id=? AND status='pending'
            ]],{status,actor.citizenid,actor.name,id,member.id})
            if not n or n<1 then return {ok=false,message='이미 처리되었거나 신청을 찾을 수 없습니다.'} end
            return success(status=='approved' and '휴가 승인' or '휴가 반려','처리했습니다.')
        end

        if action=='warrant_close' then
            local id=tonumber(payload.id)
            if not id then return {ok=false,message='영장 번호가 없습니다.'} end
            local n=MySQL.update.await([[
                UPDATE cookie_police_warrant
                SET active=0,closed_at=NOW(),closed_by=?
                WHERE id=? AND faction_id=? AND active=1
            ]],{actor.name,id,member.id})
            if not n or n<1 then return {ok=false,message='활성 영장을 찾지 못했습니다.'} end
            audit(member,actor,'warrant_close',nil,'#'..id)
            return success('영장 종료','영장을 종료했습니다.')
        end

        if action=='dispatch_join' then
            local id=tonumber(payload.id)
            if not id then return {ok=false,message='신고 번호가 없습니다.'} end
            local d=safeSingle([[
                SELECT id FROM cookie_police_dispatch
                WHERE id=? AND active=1 AND (faction_id IS NULL OR faction_id=?)
            ]],{id,member.id},'dispatch join')
            if not d then return {ok=false,message='활성 신고를 찾지 못했습니다.'} end
            MySQL.insert.await([[
                INSERT IGNORE INTO cookie_police_dispatch_unit(dispatch_id,citizenid,officer_name)
                VALUES (?,?,?)
            ]],{id,actor.citizenid,actor.name})
            audit(member,actor,'dispatch_join',nil,'#'..id)
            return success('출동 참가','신고 #'..id..' 출동 인원으로 등록했습니다.')
        end

        if action=='dispatch_close' then
            local id=tonumber(payload.id)
            if not id then return {ok=false,message='신고 번호가 없습니다.'} end
            local n=MySQL.update.await([[
                UPDATE cookie_police_dispatch
                SET active=0,closed_by=?,closed_at=NOW()
                WHERE id=? AND active=1 AND (faction_id IS NULL OR faction_id=?)
            ]],{actor.name,id,member.id})
            if not n or n<1 then return {ok=false,message='활성 신고를 찾지 못했습니다.'} end
            audit(member,actor,'dispatch_close',nil,'#'..id)
            return success('신고 종결','신고 #'..id..'을 종결했습니다.')
        end

        if action=='case_close' then
            local id=tonumber(payload.id)
            if not id then return {ok=false,message='사건 번호가 없습니다.'} end
            local n=MySQL.update.await([[
                UPDATE cookie_police_case SET status='closed'
                WHERE id=? AND faction_id=? AND status<>'closed'
            ]],{id,member.id})
            if not n or n<1 then return {ok=false,message='종결 가능한 사건을 찾지 못했습니다.'} end
            audit(member,actor,'case_close',nil,'#'..id)
            return success('사건 종결','사건을 종결했습니다.')
        end

        if action=='wanted_join' or action=='wanted_clear' then
            local id=tonumber(payload.id)
            if not id then return {ok=false,message='수배/도주 번호가 없습니다.'} end
            local row=safeSingle([[
                SELECT id,citizenid,kind,officer_citizenid,officer_name
                FROM cookie_police_wanted
                WHERE id=? AND active=1 AND expires_at>NOW()
                LIMIT 1
            ]],{id},'wanted action v3')
            if not row then return {ok=false,message='진행 중인 수배/도주를 찾지 못했습니다.'} end

            if action=='wanted_join' then
                local already=safeSingle([[
                    SELECT wanted_id FROM cookie_police_wanted_unit
                    WHERE wanted_id=? AND citizenid=? LIMIT 1
                ]],{id,actor.citizenid},'wanted joined check')
                if already then return {ok=false,message='이미 이 추격전에 참여 중입니다.'} end
                MySQL.insert.await([[
                    INSERT IGNORE INTO cookie_police_wanted_unit(wanted_id,citizenid,officer_name)
                    VALUES (?,?,?)
                ]],{id,actor.citizenid,actor.name})
                audit(member,actor,'chase_join',row.citizenid,'#'..id)
                TriggerEvent('cookie_police:internal:safeChaseJoin',id,actor.citizenid,src)
                return success(row.kind=='escape' and '도주 참여' or '수배 참여','추적에 참여했습니다. 상단에 남은 시간이 표시됩니다.')
            end

            if tostring(row.officer_citizenid or '')~=tostring(actor.citizenid or '') then
                return {ok=false,message='최초 등록자만 이 도주/수배를 종료할 수 있습니다.'}
            end
            local reason=clean(payload.endReason,160)
            if reason=='' then return {ok=false,message='종료 사유를 선택하세요.'} end

            MySQL.update.await([[
                UPDATE cookie_police_wanted
                SET active=0,cleared_at=NOW(),cleared_by=?,clear_reason=?
                WHERE id=? AND active=1
            ]],{actor.name,reason,id})
            audit(member,actor,'chase_end',row.citizenid,('#%d · %s'):format(id,reason))
            TriggerEvent('cookie_police:internal:safeChaseClear',id,reason)
            return success('추격전 종료',(row.kind=='escape' and '도주' or '수배')..' 상황을 종료했습니다. · '..reason)
        end

        if action=='penalty_apply' then
            local row,why=userRow(payload.target)
            if not row then return {ok=false,message=why} end
            local target=sourceByCid(row.citizenid)
            if not target then return {ok=false,message='대상이 접속 중이 아닙니다.'} end

            local a,b=GetPlayerPed(src),GetPlayerPed(target)
            if a==0 or b==0 or #(GetEntityCoords(a)-GetEntityCoords(b))>5.0 then
                return {ok=false,message='대상이 너무 멉니다.'}
            end

            local chosen={}
            for _,id in ipairs(payload.ids or {}) do chosen[tostring(id)]=true end

            local fine,jail,licenseMinutes,crimeScore=0,0,0,0
            local labels,crimeCharges={},{}
            for _,x in ipairs(Config.PenaltyCatalog or {}) do
                if chosen[tostring(x.id)] then
                    fine=fine+(tonumber(x.fine) or 0)
                    jail=jail+(tonumber(x.jail) or 0)
                    licenseMinutes=licenseMinutes+(tonumber(x.license) or 0)
                    local score=math.max(0,math.floor(tonumber(x.score) or 0))
                    crimeScore=crimeScore+score
                    labels[#labels+1]=x.label
                    crimeCharges[#crimeCharges+1]={
                        id=x.id,category=x.category,label=x.label,score=score
                    }
                end
            end
            if #labels==0 then return {ok=false,message='죄목을 하나 이상 선택하세요.'} end
            licenseMinutes=math.min(
                tonumber(Config.PenaltyLicenseMaxMinutes) or 60,
                math.max(0,math.floor(licenseMinutes))
            )

            if jail>0 then
                local cuffOk,cuffed=pcall(function()
                    return exports.cookie_police:IsCuffed(target)
                end)
                if not cuffOk or cuffed~=true then
                    return {ok=false,message='구금이 포함된 처리는 수갑이 채워진 대상에게만 가능합니다.'}
                end
            end

            local reason=table.concat(labels,', ')

            if licenseMinutes>0 then
                if GetResourceState('cookie_license')~='started' then
                    return {ok=false,message='운전면허 시스템이 실행 중이 아닙니다.'}
                end
                local memberType=tostring(member.type or ''):lower()
                local okLic,msg=exports.cookie_license:SuspendByCitizenId(
                    row.citizenid,licenseMinutes,reason,{
                        source=src,type=memberType,name=actor.name,
                        faction=member.name or (memberType=='security' and '보안국' or '경찰청')
                    }
                )
                if not okLic then
                    return {ok=false,message=tostring(msg or '운전면허 정지에 실패했습니다.')}
                end
            end

            local player=exports.qbx_core:GetPlayer(target)
            local paid=false
            local finePaymentMethod='미납'
            local fineReceiptId=nil
            if fine>0 then
                if player and player.Functions.RemoveMoney('bank',fine,'벌금 계산기: '..reason)==true then
                    paid=true
                    finePaymentMethod='은행'
                elseif player and player.Functions.RemoveMoney('cash',fine,'벌금 계산기: '..reason)==true then
                    paid=true
                    finePaymentMethod='현금'
                end
                fineReceiptId=MySQL.insert.await([[
                    INSERT INTO cookie_police_fine
                      (faction_id,target_citizenid,target_name,amount,reason,paid,
                       officer_citizenid,officer_name)
                    VALUES (?,?,?,?,?,?,?,?)
                ]],{member.id,row.citizenid,row.nickname,fine,reason,paid and 1 or 0,actor.citizenid,actor.name})
                TriggerClientEvent('cookie_police:client:fineReceipt',target,{
                    receiptNo=fineReceiptId and ('F-%06d'):format(tonumber(fineReceiptId) or 0) or ('F-%d'):format(os.time()),
                    faction=member.name or (tostring(member.type or ''):lower()=='security' and '보안국' or '경찰청'),
                    officer=actor.name or '-',reason=reason,amount=fine,paid=paid,
                    paymentMethod=finePaymentMethod,issuedAt=os.date('%Y-%m-%d %H:%M:%S')
                })
            end

            if jail>0 then
                pcall(function()
                    MySQL.insert.await([[
                        INSERT INTO cookie_faction_detention
                          (faction_id,officer_citizenid,target_citizenid,target_name,
                           charge,fine_amount,jail_seconds,note)
                        VALUES (?,?,?,?,?,?,?,?)
                    ]],{member.id,actor.citizenid,row.citizenid,row.nickname,reason,
                        paid and fine or 0,jail*60,'벌금·구금 계산기'})
                end)
                MySQL.update.await([[
                    UPDATE cookie_police_detention_active
                    SET active=0,released_at=NOW(),released_by='REPLACED'
                    WHERE citizenid=? AND active=1
                ]],{row.citizenid})
                MySQL.insert.await([[
                    INSERT INTO cookie_police_detention_active
                      (faction_id,citizenid,target_name,charge,release_at,
                       officer_citizenid,officer_name)
                    VALUES (?,?,?,?,DATE_ADD(NOW(),INTERVAL ? SECOND),?,?)
                ]],{member.id,row.citizenid,row.nickname,reason,jail*60,actor.citizenid,actor.name})
                pcall(function() exports.cookie_police:ForceSetCuffed(target,false) end)
                TriggerClientEvent('cookie_police:client:setDetained',target,jail*60,reason,true)
            end

            if GetResourceState('cookie_crime')=='started' then
                local okCrime,recordOk,crimeErr=pcall(function()
                    return exports.cookie_crime:AddRecord({
                        citizenid=row.citizenid,gobun=row.gobun,nickname=row.nickname,
                        charges=crimeCharges,crimeScore=crimeScore,
                        fine=fine,jailMinutes=jail,licenseMinutes=licenseMinutes,
                        sourceType='police_penalty',
                        sourceLabel='벌금·구금·면허 계산기',
                        agencyType=tostring(member.type or ''):lower(),
                        agencyName=member.name,
                        officerCitizenId=actor.citizenid,
                        officerName=actor.name
                    })
                end)
                if not okCrime or recordOk~=true then
                    print(('[cookie_police F5 SAFE] 전과 기록 저장 실패: %s'):format(
                        tostring(okCrime and crimeErr or recordOk)
                    ))
                end
            end

            audit(member,actor,'penalty_apply',row.citizenid,
                ('%s · 벌금 %d · 구금 %d · 면허 %d · 범죄 %d'):format(
                    identityLabel(row),fine,jail,licenseMinutes,crimeScore
                )
            )

            return success('벌금·구금·면허 처리 완료',
                ('%s · 벌금 %d원 · 구금 %d분 · 면허정지 %d분 · 범죄점수 %d점'):format(
                    identityLabel(row),fine,jail,licenseMinutes,crimeScore
                )
            )
        end

        return {ok=false,message='SAFE 결과 처리에 연결되지 않은 업무입니다: '..action}
    end,debug.traceback)

    if not ok then
        print(('^1[cookie_police F5 SAFE]^7 result crash (%s): %s'):format(
            tostring(action),tostring(result)
        ))
        return {
            ok=false,
            message='결과 처리 중 서버 오류가 발생했습니다. 서버 콘솔의 [cookie_police F5 SAFE] 로그를 확인하세요.'
        }
    end
    return result or {ok=false,message='결과 처리 데이터가 비어 있습니다.'}
end)
