-- COOKIE COUPLE SYSTEM V1
-- F3 Community > Couple System
-- Ring shop + CAPSLOCK look-at proposal + relationship day counter.

local RING_ITEM = 'diamond_ring' -- already exists in current ox_inventory
local PROPOSAL_TTL = 30
local MAX_PROPOSAL_DISTANCE = 4.0

local proposals = {}
local targetProposal = {}
local proposerProposal = {}
local relationshipLocks = {}
local nextProposalId = 1000
local schemaReady = false
local schemaError = nil

local function player(src)
    return exports.qbx_core:GetPlayer(src)
end

local function citizenId(src)
    local p = player(src)
    return p and p.PlayerData and tostring(p.PlayerData.citizenid or '') or nil
end

local function licenseOf(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function cleanText(v, maxLen)
    local s = tostring(v or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #s > (maxLen or 80) then s = s:sub(1, maxLen or 80) end
    return s
end

local function effectiveAdmin(src)
    local license = licenseOf(src)
    if not license then return nil end

    local row = MySQL.single.await([[
        SELECT admin_name, admin_level, (pw_hash IS NOT NULL) AS has_pw
        FROM cookie_admin
        WHERE license = ? AND is_active = 1
        LIMIT 1
    ]], { license })

    if not row then return nil end
    local level = tonumber(row.admin_level) or 0
    local hasPw = row.has_pw == 1 or row.has_pw == true
    if level >= 5 and not hasPw then level = 4 end
    if level < 5 then return nil end

    row.effective_level = level
    return row
end

local function notify(src, message, isError)
    if not src or not GetPlayerName(src) then return end
    TriggerClientEvent('cookie_admin:client:notify', src, tostring(message or ''), isError == true)
end

local function sourceDistance(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return 9999.0 end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

local function liveSourceByCitizen(cid)
    cid = tostring(cid or '')
    if cid == '' then return nil end

    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src and tostring(citizenId(src) or '') == cid then
            return src
        end
    end

    return nil
end

local function cookieUserByLicense(license)
    license = cleanText(license, 96)
    if license == '' then return nil end

    -- 쿠키 온보딩은 license2를 우선 저장하지만 Qbox players.license는
    -- 환경에 따라 license: 값을 가질 수 있어 정확 일치만으로 JOIN하면
    -- 닉네임을 놓칠 수 있다.
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT license, nickname, gobun
            FROM cookie_user
            WHERE license = ?
            LIMIT 1
        ]], { license })
    end)

    if ok and row then return row end

    local suffix = license:match('^[^:]+:(.+)$')
    if not suffix or suffix == '' then return nil end

    local okSuffix, suffixRow = pcall(function()
        return MySQL.single.await([[
            SELECT license, nickname, gobun
            FROM cookie_user
            WHERE SUBSTRING_INDEX(license, ':', -1) = ?
            LIMIT 1
        ]], { suffix })
    end)

    return okSuffix and suffixRow or nil
end

local function profileByCitizen(cid)
    cid = tostring(cid or '')
    if cid == '' then
        return { name = '알 수 없음', gobun = nil, license = nil }
    end

    -- 상대가 접속 중이면 citizenid -> 현재 source -> license2 순서로
    -- 쿠키서버 별명을 직접 찾는다. 고백 직후 표시에는 이 경로가 우선이다.
    local onlineSrc = liveSourceByCitizen(cid)
    if onlineSrc then
        local liveLicense = licenseOf(onlineSrc)
        local liveUser = cookieUserByLicense(liveLicense)

        local liveName = liveUser and cleanText(liveUser.nickname, 40) or ''
        if liveName == '' then
            local p = player(onlineSrc)
            local charinfo = p and p.PlayerData and p.PlayerData.charinfo or nil
            if type(charinfo) == 'table' then
                liveName = cleanText(
                    ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('%s+$', ''),
                    40
                )
            end
        end
        if liveName == '' then
            liveName = cleanText(GetPlayerName(onlineSrc), 40)
        end
        if liveName == '' then liveName = ('고번 %s'):format(tostring(liveUser and liveUser.gobun or '?')) end

        return {
            name = liveName,
            gobun = liveUser and liveUser.gobun or nil,
            license = (liveUser and liveUser.license) or liveLicense,
        }
    end

    -- 오프라인 연인은 players.citizenid로 계정 license를 찾은 뒤
    -- cookie_user의 license/license2 접두사가 달라도 식별자 본문으로 재조회한다.
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT license, charinfo, name
            FROM players
            WHERE citizenid = ?
            LIMIT 1
        ]], { cid })
    end)

    if not ok then
        print(('[cookie_admin][couple] profile query failed cid=%s: %s'):format(cid, tostring(row)))
        row = nil
    end

    if not row then
        return { name = '알 수 없음', gobun = nil, license = nil }
    end

    local u = cookieUserByLicense(row.license)
    local name = u and cleanText(u.nickname, 40) or ''

    if name == '' then
        local okChar, charinfo = pcall(json.decode, row.charinfo or '{}')
        if okChar and type(charinfo) == 'table' then
            name = cleanText(
                ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('%s+$', ''),
                40
            )
        end
    end

    if name == '' then
        name = cleanText(row.name, 40)
    end
    if name == '' then
        name = u and u.gobun and ('고번 %s'):format(tostring(u.gobun)) or '알 수 없음'
    end

    return {
        name = name,
        gobun = u and u.gobun or nil,
        license = (u and u.license) or row.license,
    }
end

local function profileBySource(src)
    src = tonumber(src)
    if not src then return { name = '알 수 없음', gobun = nil, license = nil } end

    local cid = citizenId(src)
    local license = licenseOf(src)
    local u = cookieUserByLicense(license)

    local name = u and cleanText(u.nickname, 40) or ''
    if name == '' then
        local p = player(src)
        local charinfo = p and p.PlayerData and p.PlayerData.charinfo or nil
        if type(charinfo) == 'table' then
            name = cleanText(
                ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('%s+$', ''),
                40
            )
        end
    end
    if name == '' then name = cleanText(GetPlayerName(src), 40) end
    if name == '' then name = '알 수 없음' end

    return {
        name = name,
        gobun = u and u.gobun or nil,
        license = (u and u.license) or license,
        citizenid = cid,
        serverId = src,
    }
end

local function coupleConfig()
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT shop_enabled, ring_price
            FROM cookie_couple_config
            WHERE id = 1
            LIMIT 1
        ]])
    end)

    if not ok then
        print(('[cookie_admin][couple] config query failed: %s'):format(tostring(row)))
        row = nil
    end
    row = row or {}

    return {
        shopEnabled = row.shop_enabled == nil and true or (row.shop_enabled == 1 or row.shop_enabled == true),
        ringPrice = math.max(1, math.floor(tonumber(row.ring_price) or 500000)),
        ringItem = RING_ITEM,
    }
end

local function activeRelationship(cid)
    if not cid or cid == '' then return nil end

    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT id, citizen_a, citizen_b, started_at,
                   DATEDIFF(CURDATE(), DATE(started_at)) + 1 AS couple_days
            FROM cookie_couple_relationship
            WHERE status = 'active' AND (citizen_a = ? OR citizen_b = ?)
            ORDER BY id DESC
            LIMIT 1
        ]], { cid, cid })
    end)

    if not ok then
        print(('[cookie_admin][couple] relationship query failed cid=%s: %s'):format(tostring(cid), tostring(row)))
        return nil
    end
    return row
end

local function partnerCitizen(rel, myCid)
    if not rel then return nil end
    if tostring(rel.citizen_a) == tostring(myCid) then return tostring(rel.citizen_b) end
    return tostring(rel.citizen_a)
end

local function ringCount(src)
    if GetResourceState('ox_inventory') ~= 'started' then return 0 end
    local ok, count = pcall(function()
        return exports.ox_inventory:Search(src, 'count', RING_ITEM)
    end)
    return ok and math.max(0, tonumber(count) or 0) or 0
end

local function buildCoupleState(src)
    local cid = citizenId(src)
    local cfg = coupleConfig()
    local me = profileBySource(src)
    local rel = activeRelationship(cid)

    local data = {
        shopEnabled = cfg.shopEnabled,
        ringPrice = cfg.ringPrice,
        ringItem = cfg.ringItem,
        ringCount = ringCount(src),
        me = {
            name = me.name,
            gobun = me.gobun,
        },
        relationship = nil,
    }

    if rel then
        local partnerCid = partnerCitizen(rel, cid)
        local partner = profileByCitizen(partnerCid)

        data.relationship = {
            id = tonumber(rel.id),
            days = math.max(1, tonumber(rel.couple_days) or 1),
            startedAt = tostring(rel.started_at or ''),
            partner = {
                citizenid = partnerCid,
                name = partner.name,
                gobun = partner.gobun,
            }
        }
    end

    return data
end

local function pushCoupleState(src, message, isError)
    if not src or not GetPlayerName(src) then return end
    TriggerClientEvent('cookie_admin:client:coupleData', src, buildCoupleState(src), message, isError == true)
end

local function refreshTag(src)
    if src and GetPlayerName(src) and CookieRefreshNameTag then
        pcall(CookieRefreshNameTag, src)
    end
end

local function sourceByCitizen(cid)
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src and citizenId(src) == cid then return src end
    end
    return nil
end

local function clearProposal(id)
    local p = proposals[id]
    if not p then return end
    if targetProposal[p.target] == id then targetProposal[p.target] = nil end
    if proposerProposal[p.proposer] == id then proposerProposal[p.proposer] = nil end
    proposals[id] = nil
end

-- Used by cookie_admin/server/nametag.lua
function CookieCouplePartnerOf(src)
    local cid = citizenId(src)
    if not cid then return nil end
    local rel = activeRelationship(cid)
    if not rel then return nil end
    local partner = profileByCitizen(partnerCitizen(rel, cid))
    return partner and partner.name or nil
end

local function ensureCoupleSchema()
    if schemaReady then return true end

    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_couple_config (
                id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
                shop_enabled TINYINT(1) NOT NULL DEFAULT 1,
                ring_price BIGINT UNSIGNED NOT NULL DEFAULT 500000,
                updated_by VARCHAR(64) NULL,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_couple_relationship (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                citizen_a VARCHAR(64) NOT NULL,
                citizen_b VARCHAR(64) NOT NULL,
                status VARCHAR(16) NOT NULL DEFAULT 'active',
                started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                ended_at TIMESTAMP NULL,
                ended_by VARCHAR(64) NULL,
                INDEX idx_cookie_couple_a (citizen_a, status),
                INDEX idx_cookie_couple_b (citizen_b, status),
                INDEX idx_cookie_couple_status (status, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_couple_log (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                action VARCHAR(24) NOT NULL,
                citizen_a VARCHAR(64) NOT NULL,
                citizen_b VARCHAR(64) NOT NULL,
                detail VARCHAR(255) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_cookie_couple_log_a (citizen_a, id),
                INDEX idx_cookie_couple_log_b (citizen_b, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])

        MySQL.insert.await([[
            INSERT IGNORE INTO cookie_couple_config(id, shop_enabled, ring_price)
            VALUES(1, 1, 500000)
        ]])
    end)

    schemaReady = ok
    schemaError = ok and nil or tostring(err)
    if not ok then
        print(('[cookie_admin][couple] schema init failed: %s'):format(schemaError or 'unknown'))
    end
    return ok
end

CreateThread(function()
    ensureCoupleSchema()
end)

RegisterNetEvent('cookie_admin:server:requestCouple', function()
    local src = source

    -- Never leave the NUI waiting forever. Even if one DB query fails,
    -- always send at least a usable ring-shop payload back to the client.
    local cfg = { shopEnabled = true, ringPrice = 500000, ringItem = RING_ITEM }
    local okCfg, cfgResult = pcall(coupleConfig)
    if okCfg and type(cfgResult) == 'table' then cfg = cfgResult end

    if not schemaReady then
        ensureCoupleSchema()
    end

    local fallback = {
        shopEnabled = cfg.shopEnabled ~= false,
        ringPrice = math.max(1, tonumber(cfg.ringPrice) or 500000),
        ringItem = RING_ITEM,
        ringCount = ringCount(src),
        me = { name = '시민', gobun = nil },
        relationship = nil,
    }

    local cid = citizenId(src)
    if cid then
        local okProfile, me = pcall(profileBySource, src)
        if okProfile and type(me) == 'table' then
            fallback.me = { name = me.name or '시민', gobun = me.gobun }
        end
    end

    local okState, state = pcall(buildCoupleState, src)
    if okState and type(state) == 'table' then
        return TriggerClientEvent('cookie_admin:client:coupleData', src, state)
    end

    print(('[cookie_admin][couple] requestCouple fallback source=%s error=%s')
        :format(tostring(src), tostring(state)))

    TriggerClientEvent('cookie_admin:client:coupleData', src, fallback,
        '커플 정보 일부를 불러오지 못해 상점 정보만 표시합니다.', true)
end)

RegisterNetEvent('cookie_admin:server:buyCoupleRing', function()
    local src = source
    if not schemaReady and not ensureCoupleSchema() then
        return pushCoupleState(src, '커플 시스템 DB를 준비하지 못했습니다.', true)
    end
    local p = player(src)
    if not p then return end

    local cfg = coupleConfig()
    if not cfg.shopEnabled then
        return pushCoupleState(src, '현재 커플링 판매가 중지되어 있습니다.', true)
    end

    if cfg.ringPrice <= 0 then
        return pushCoupleState(src, '커플링 가격 설정을 확인해주세요.', true)
    end

    if GetResourceState('ox_inventory') ~= 'started' then
        return pushCoupleState(src, '인벤토리 시스템을 사용할 수 없습니다.', true)
    end

    local okItem, item = pcall(function()
        return exports.ox_inventory:Items(RING_ITEM)
    end)
    if not okItem or not item then
        return pushCoupleState(src, ('반지 아이템 "%s"을 찾을 수 없습니다.'):format(RING_ITEM), true)
    end

    local bank = math.max(0, tonumber(exports.qbx_core:GetMoney(src, 'bank')) or 0)
    if bank < cfg.ringPrice then
        return pushCoupleState(src, '계좌 잔액이 부족합니다.', true)
    end

    local removed = exports.qbx_core:RemoveMoney(src, 'bank', cfg.ringPrice, 'COOKIE 커플링 구매')
    if removed == false then
        return pushCoupleState(src, '결제에 실패했습니다.', true)
    end

    local okAdd, added, response = pcall(function()
        return exports.ox_inventory:AddItem(src, RING_ITEM, 1, {
            description = 'COOKIE SERVER 커플 고백에 사용하는 커플링'
        })
    end)

    if not okAdd or added == false then
        exports.qbx_core:AddMoney(src, 'bank', cfg.ringPrice, 'COOKIE 커플링 구매 실패 환불')
        return pushCoupleState(src, response or '인벤토리 공간이 부족해 결제가 취소되었습니다.', true)
    end

    pushCoupleState(src, ('커플링을 구매했습니다. · %s원'):format(cfg.ringPrice), false)
end)

RegisterNetEvent('cookie_admin:server:requestCoupleInteraction', function(target)
    local src = source
    target = tonumber(target)

    if not target or target == src or not GetPlayerName(target) then return end
    if sourceDistance(src, target) > MAX_PROPOSAL_DISTANCE then
        return notify(src, '상대방에게 조금 더 가까이 가주세요.', true)
    end

    local myCid, targetCid = citizenId(src), citizenId(target)
    if not myCid or not targetCid then return end

    if activeRelationship(myCid) then
        return notify(src, '이미 연인이 있습니다.', true)
    end
    if activeRelationship(targetCid) then
        return notify(src, '상대방은 이미 연인이 있습니다.', true)
    end

    if ringCount(src) < 1 then
        return notify(src, '고백하려면 커플링이 필요합니다. F3 > 커뮤니티 > 커플 시스템에서 구매하세요.', true)
    end

    local targetProfile = profileBySource(target)
    TriggerClientEvent('cookie_admin:client:coupleInteraction', src, {
        target = target,
        name = targetProfile.name,
        gobun = targetProfile.gobun,
        ringCount = ringCount(src),
    })
end)

RegisterNetEvent('cookie_admin:server:sendCoupleProposal', function(target)
    local src = source
    target = tonumber(target)

    if not target or target == src or not GetPlayerName(target) then
        return notify(src, '고백할 상대를 찾을 수 없습니다.', true)
    end

    if sourceDistance(src, target) > MAX_PROPOSAL_DISTANCE then
        return notify(src, '상대방이 너무 멀리 있습니다.', true)
    end

    local myCid, targetCid = citizenId(src), citizenId(target)
    if not myCid or not targetCid then return end

    if activeRelationship(myCid) then return notify(src, '이미 연인이 있습니다.', true) end
    if activeRelationship(targetCid) then return notify(src, '상대방은 이미 연인이 있습니다.', true) end
    if ringCount(src) < 1 then return notify(src, '커플링이 없습니다.', true) end

    if proposerProposal[src] then
        return notify(src, '이미 상대방의 답변을 기다리고 있습니다.', true)
    end
    if targetProposal[target] then
        return notify(src, '상대방이 다른 고백을 확인 중입니다.', true)
    end

    -- V13.5: 실제 고백 1회당 커플링(diamond_ring) 1개를 즉시 소모합니다.
    -- 거절/시간초과여도 반환하지 않습니다.
    local removeOk, removed, removeResponse = pcall(function()
        return exports.ox_inventory:RemoveItem(src, RING_ITEM, 1)
    end)

    if not removeOk or not removed then
        return notify(src, removeResponse or '커플링 1개를 소모하지 못해 고백을 보낼 수 없습니다.', true)
    end

    nextProposalId = nextProposalId + 1
    local id = nextProposalId
    local me = profileBySource(src)

    proposals[id] = {
        id = id,
        proposer = src,
        target = target,
        proposerCid = myCid,
        targetCid = targetCid,
        createdAt = os.time(),
        ringConsumed = true,
    }
    proposerProposal[src] = id
    targetProposal[target] = id

    TriggerClientEvent('cookie_admin:client:coupleProposalIncoming', target, {
        id = id,
        proposer = src,
        name = me.name,
        gobun = me.gobun,
        seconds = PROPOSAL_TTL,
    })

    TriggerClientEvent('cookie_admin:client:coupleInteractionClose', src)
    notify(src, ('%s님에게 고백했습니다. 답변을 기다려주세요.'):format(me.name == profileBySource(target).name and '상대방' or profileBySource(target).name), false)

    SetTimeout(PROPOSAL_TTL * 1000, function()
        local proposal = proposals[id]
        if not proposal then return end
        clearProposal(id)
        if GetPlayerName(proposal.proposer) then
            notify(proposal.proposer, '고백 시간이 만료되었습니다. 다음 기회에 다시 시도해보세요.', true)
        end
        if GetPlayerName(proposal.target) then
            TriggerClientEvent('cookie_admin:client:coupleProposalClosed', proposal.target)
        end
    end)
end)

RegisterNetEvent('cookie_admin:server:replyCoupleProposal', function(id, accepted)
    local target = source
    id = tonumber(id)
    local proposal = id and proposals[id] or nil

    if not proposal or proposal.target ~= target then
        return TriggerClientEvent('cookie_admin:client:coupleProposalClosed', target)
    end

    local proposer = proposal.proposer
    if not GetPlayerName(proposer) then
        clearProposal(id)
        TriggerClientEvent('cookie_admin:client:coupleProposalClosed', target)
        return notify(target, '상대방이 접속을 종료했습니다.', true)
    end

    if accepted ~= true then
        local proposerName = profileBySource(proposer).name
        local targetName = profileBySource(target).name
        clearProposal(id)
        TriggerClientEvent('cookie_admin:client:coupleProposalClosed', target)
        notify(target, '고백을 거절했습니다.', false)
        notify(proposer, ('아쉽게도 %s님이 고백을 거절했습니다.'):format(targetName), true)
        MySQL.insert.await([[
            INSERT INTO cookie_couple_log(action, citizen_a, citizen_b, detail)
            VALUES('reject', ?, ?, ?)
        ]], { proposal.proposerCid, proposal.targetCid, targetName .. ' rejected' })
        return
    end

    if sourceDistance(proposer, target) > 8.0 then
        clearProposal(id)
        TriggerClientEvent('cookie_admin:client:coupleProposalClosed', target)
        return notify(target, '상대방과 거리가 너무 멀어 고백이 취소되었습니다.', true)
    end

    if activeRelationship(proposal.proposerCid) or activeRelationship(proposal.targetCid) then
        clearProposal(id)
        TriggerClientEvent('cookie_admin:client:coupleProposalClosed', target)
        return notify(target, '이미 연인 관계가 등록되어 고백을 수락할 수 없습니다.', true)
    end

    local lockA = proposal.proposerCid
    local lockB = proposal.targetCid
    if relationshipLocks[lockA] or relationshipLocks[lockB] then
        return notify(target, '커플 등록을 처리 중입니다. 잠시 후 다시 시도해주세요.', true)
    end
    relationshipLocks[lockA], relationshipLocks[lockB] = true, true

    local inserted = MySQL.insert.await([[
        INSERT INTO cookie_couple_relationship(citizen_a, citizen_b, status)
        VALUES(?, ?, 'active')
    ]], { proposal.proposerCid, proposal.targetCid })

    relationshipLocks[lockA], relationshipLocks[lockB] = nil, nil

    if not inserted then
        clearProposal(id)
        TriggerClientEvent('cookie_admin:client:coupleProposalClosed', target)
        return notify(target, '커플 등록에 실패했습니다.', true)
    end

    local proposerName = profileBySource(proposer).name
    local targetName = profileBySource(target).name

    MySQL.insert.await([[
        INSERT INTO cookie_couple_log(action, citizen_a, citizen_b, detail)
        VALUES('start', ?, ?, ?)
    ]], { proposal.proposerCid, proposal.targetCid, proposerName .. ' ♥ ' .. targetName })

    clearProposal(id)
    TriggerClientEvent('cookie_admin:client:coupleProposalClosed', target)

    notify(proposer, ('%s님이 고백을 받아주셨습니다! 오늘부터 커플 1일차입니다 ♥'):format(targetName), false)
    notify(target, ('%s님의 고백을 수락했습니다! 오늘부터 커플 1일차입니다 ♥'):format(proposerName), false)

    pushCoupleState(proposer)
    pushCoupleState(target)
    refreshTag(proposer)
    refreshTag(target)
end)

RegisterNetEvent('cookie_admin:server:breakupCouple', function()
    local src = source
    local cid = citizenId(src)
    if not cid then return end

    local rel = activeRelationship(cid)
    if not rel then return pushCoupleState(src, '현재 연인 관계가 없습니다.', true) end

    local partnerCid = partnerCitizen(rel, cid)
    MySQL.update.await([[
        UPDATE cookie_couple_relationship
        SET status = 'ended', ended_at = CURRENT_TIMESTAMP, ended_by = ?
        WHERE id = ? AND status = 'active'
    ]], { cid, rel.id })

    MySQL.insert.await([[
        INSERT INTO cookie_couple_log(action, citizen_a, citizen_b, detail)
        VALUES('breakup', ?, ?, ?)
    ]], { tostring(rel.citizen_a), tostring(rel.citizen_b), cid .. ' ended relationship' })

    local partnerSrc = sourceByCitizen(partnerCid)
    local partner = profileByCitizen(partnerCid)

    pushCoupleState(src, ('%s님과의 연인 관계를 해제했습니다.'):format(partner.name), false)
    refreshTag(src)

    if partnerSrc then
        local me = profileBySource(src)
        pushCoupleState(partnerSrc)
        notify(partnerSrc, ('%s님이 연인 관계를 해제했습니다.'):format(me.name), true)
        refreshTag(partnerSrc)
    end
end)

RegisterNetEvent('cookie_admin:server:requestCoupleAdmin', function()
    local src = source
    if not effectiveAdmin(src) then return end

    local cfg = coupleConfig()
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM cookie_couple_relationship WHERE status = 'active'
    ]]) or 0

    TriggerClientEvent('cookie_admin:client:coupleAdminData', src, {
        config = cfg,
        activeCouples = tonumber(count) or 0,
    })
end)

RegisterNetEvent('cookie_admin:server:saveCoupleAdmin', function(data)
    local src = source
    local admin = effectiveAdmin(src)
    if not admin or type(data) ~= 'table' then return end

    local price = math.max(0, math.min(1000000000, math.floor(tonumber(data.ringPrice) or 0)))
    local enabled = data.shopEnabled == true and 1 or 0

    if price <= 0 then
        return TriggerClientEvent('cookie_admin:client:coupleAdminSaved', src, false, '커플링 가격은 1원 이상이어야 합니다.')
    end

    MySQL.update.await([[
        UPDATE cookie_couple_config
        SET shop_enabled = ?, ring_price = ?, updated_by = ?
        WHERE id = 1
    ]], { enabled, price, cleanText(admin.admin_name, 64) })

    TriggerClientEvent('cookie_admin:client:coupleAdminSaved', src, true, '커플 시스템 설정을 저장했습니다.')
    TriggerClientEvent('cookie_admin:client:coupleAdminData', src, {
        config = coupleConfig(),
        activeCouples = tonumber(MySQL.scalar.await(
            "SELECT COUNT(*) FROM cookie_couple_relationship WHERE status = 'active'"
        )) or 0,
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    local p1 = proposerProposal[src]
    local p2 = targetProposal[src]

    if p1 and proposals[p1] then
        local target = proposals[p1].target
        clearProposal(p1)
        if GetPlayerName(target) then
            TriggerClientEvent('cookie_admin:client:coupleProposalClosed', target)
            notify(target, '상대방이 접속을 종료해 고백이 취소되었습니다.', true)
        end
    end

    if p2 and proposals[p2] then
        local proposer = proposals[p2].proposer
        clearProposal(p2)
        if GetPlayerName(proposer) then
            notify(proposer, '상대방이 접속을 종료해 고백이 취소되었습니다.', true)
        end
    end
end)

print('^2[cookie_admin]^7 COUPLE NICKNAME RESOLVE V13.3 ready')

print('^2[cookie_admin]^7 COUPLE RING CONSUME V13.5 ready')
