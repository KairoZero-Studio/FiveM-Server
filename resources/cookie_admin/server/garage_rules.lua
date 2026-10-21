-- COOKIE SERVER - strict garage separation rules
-- 일반 / 한정 / 팩션 차량의 데이터 소스를 서버 단계에서 분리한다.
-- 실제 차고 UI(cookie_garage)는 이 API를 기준으로 목록을 요청하면 된다.

CookieGarageRules = CookieGarageRules or {}

local function normModel(v)
    return tostring(v or ''):lower():gsub('%s+', '')
end

local function currentPlayer(src)
    local p = exports.qbx_core:GetPlayer(tonumber(src))
    if not p or not p.PlayerData then return nil end
    return p
end

local function factionRow(fid)
    fid = math.floor(tonumber(fid) or 0)
    if fid <= 0 then return nil end
    return MySQL.single.await([[
        SELECT id, name, faction_key, faction_type, garage_key
        FROM cookie_faction
        WHERE id=? AND is_active=1
        LIMIT 1
    ]], { fid })
end

local function factionGarageKey(f)
    if not f then return nil end
    if f.garage_key and f.garage_key ~= '' then return f.garage_key end
    if f.faction_type == 'police' then return 'cookie_lspd' end
    return 'cookie_' .. tostring(f.faction_key or f.id)
end

local function factionMembership(src, wantedFactionId)
    local p = currentPlayer(src)
    if not p or not p.PlayerData.citizenid then return nil end
    local cid = p.PlayerData.citizenid
    local row = MySQL.single.await([[
        SELECT m.faction_id, m.grade, m.duty, f.name, f.faction_key, f.faction_type, f.garage_key
        FROM cookie_faction_member m
        JOIN cookie_faction f ON f.id=m.faction_id AND f.is_active=1
        WHERE m.citizenid=? AND m.status='active'
        LIMIT 1
    ]], { cid })
    if not row then return nil end
    if wantedFactionId and tonumber(row.faction_id) ~= tonumber(wantedFactionId) then return nil end
    return row
end

function CookieGarageRules.NormalizeModel(model)
    return normModel(model)
end

-- 우선순위: 팩션 > 한정 > 일반
-- 동일 모델이 잘못 중복 등록되어도 일반 차고로 새는 것을 방지한다.
function CookieGarageRules.ClassifyModel(model)
    local m = normModel(model)
    if m == '' then return nil end

    local f = MySQL.single.await([[
        SELECT fs.faction_id, fs.label, f.name AS faction_name
        FROM cookie_faction_shop fs
        JOIN cookie_faction f ON f.id=fs.faction_id AND f.is_active=1
        WHERE LOWER(fs.model)=? AND fs.active=1
        LIMIT 1
    ]], { m })
    if f then
        return 'faction', {
            factionId = tonumber(f.faction_id),
            label = f.label or m,
            factionName = f.faction_name,
        }
    end

    local l = MySQL.single.await([[
        SELECT id, label FROM cookie_limited_vehicles
        WHERE LOWER(model)=? AND active=1 LIMIT 1
    ]], { m })
    if l then
        return 'limited', { id = l.id, label = l.label or m }
    end

    local g = MySQL.single.await([[
        SELECT id, display_name FROM cookie_dealership_vehicles
        WHERE LOWER(model)=? AND active=1 LIMIT 1
    ]], { m })
    if g then
        return 'general', { id = g.id, label = g.display_name or m }
    end

    return nil
end

-- 등록 단계에서 종류가 섞이지 않게 막는다.
-- 팩션 차량끼리는 여러 팩션에 같은 모델을 의도적으로 지정할 수 있다.
function CookieGarageRules.CanRegister(model, kind, factionId)
    local m = normModel(model)
    if m == '' then return false, '차량 모델이 비어있습니다' end

    if kind ~= 'general' then
        local g = MySQL.single.await(
            'SELECT id FROM cookie_dealership_vehicles WHERE LOWER(model)=? AND active=1 LIMIT 1', { m })
        if g then return false, '이미 일반 차량으로 등록된 모델입니다. 일반 차량 등록에서 먼저 제거해주세요.' end
    end

    if kind ~= 'limited' then
        local l = MySQL.single.await(
            'SELECT id FROM cookie_limited_vehicles WHERE LOWER(model)=? AND active=1 LIMIT 1', { m })
        if l then return false, '이미 한정 차량으로 등록된 모델입니다. 한정 차량 등록에서 먼저 제거해주세요.' end
    end

    if kind ~= 'faction' then
        local f = MySQL.single.await([[
            SELECT fs.id, f.name
            FROM cookie_faction_shop fs
            JOIN cookie_faction f ON f.id=fs.faction_id AND f.is_active=1
            WHERE LOWER(fs.model)=? AND fs.active=1
            LIMIT 1
        ]], { m })
        if f then
            return false, ('이미 %s 팩션 차량으로 등록된 모델입니다.'):format(f.name or '다른')
        end
    end

    return true
end

function CookieGarageRules.GetCatalog(kind, factionId)
    kind = tostring(kind or ''):lower()

    if kind == 'general' then
        return MySQL.query.await([[
            SELECT g.id, LOWER(g.model) AS model, g.display_name AS label, g.price,
                   g.category, g.spec, g.image, g.sort_order
            FROM cookie_dealership_vehicles g
            WHERE g.active=1
              AND NOT EXISTS (
                  SELECT 1 FROM cookie_limited_vehicles l
                  WHERE l.active=1 AND LOWER(l.model)=LOWER(g.model)
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM cookie_faction_shop fs
                  JOIN cookie_faction f ON f.id=fs.faction_id AND f.is_active=1
                  WHERE fs.active=1 AND LOWER(fs.model)=LOWER(g.model)
              )
            ORDER BY g.sort_order, g.id
        ]], {}) or {}
    end

    if kind == 'limited' then
        -- 한정 차량은 '전체 공개 카탈로그' 용도가 아니다.
        -- 이 반환값은 소유차 판정/관리용이며 일반 차고 목록에는 절대 합치지 않는다.
        return MySQL.query.await([[
            SELECT l.id, LOWER(l.model) AS model, l.label
            FROM cookie_limited_vehicles l
            WHERE l.active=1
              AND NOT EXISTS (
                  SELECT 1
                  FROM cookie_faction_shop fs
                  JOIN cookie_faction f ON f.id=fs.faction_id AND f.is_active=1
                  WHERE fs.active=1 AND LOWER(fs.model)=LOWER(l.model)
              )
            ORDER BY l.label, l.id
        ]], {}) or {}
    end

    if kind == 'faction' then
        local fid = math.floor(tonumber(factionId) or 0)
        if fid <= 0 then return {} end
        return MySQL.query.await([[
            SELECT fs.id, LOWER(fs.model) AS model, fs.label, fs.price, fs.min_grade
            FROM cookie_faction_shop fs
            JOIN cookie_faction f ON f.id=fs.faction_id AND f.is_active=1
            WHERE fs.faction_id=? AND fs.active=1
            ORDER BY fs.min_grade, fs.price, fs.id
        ]], { fid }) or {}
    end

    return {}
end

-- 실제 플레이어가 차고에서 보게 될 '소유 차량' 목록.
-- 일반/한정은 같은 player_vehicles 저장소를 써도 모델 분류로 완전히 분리된다.
-- 팩션 차고는 FACTION_<id> 소유 + 해당 팩션 fleet 등록만 허용한다.
function CookieGarageRules.GetOwnedVehicles(src, kind, factionId)
    src = tonumber(src)
    if not src then return {}, '플레이어를 찾을 수 없습니다' end
    kind = tostring(kind or ''):lower()

    if kind == 'general' or kind == 'limited' then
        local p = currentPlayer(src)
        if not p or not p.PlayerData.citizenid then return {}, '시민 정보를 찾을 수 없습니다' end
        local cid = p.PlayerData.citizenid

        if kind == 'general' then
            local rows = MySQL.query.await([[
                SELECT pv.id, pv.citizenid, pv.vehicle AS model, pv.plate, pv.garage, pv.state,
                       g.display_name AS label
                FROM player_vehicles pv
                JOIN cookie_dealership_vehicles g
                  ON LOWER(g.model)=LOWER(pv.vehicle) AND g.active=1
                WHERE pv.citizenid=?
                  AND NOT EXISTS (
                      SELECT 1 FROM cookie_limited_vehicles l
                      WHERE l.active=1 AND LOWER(l.model)=LOWER(pv.vehicle)
                  )
                  AND NOT EXISTS (
                      SELECT 1
                      FROM cookie_faction_shop fs
                      JOIN cookie_faction f ON f.id=fs.faction_id AND f.is_active=1
                      WHERE fs.active=1 AND LOWER(fs.model)=LOWER(pv.vehicle)
                  )
                ORDER BY g.display_name, pv.id
            ]], { cid }) or {}
            return rows
        else
            local rows = MySQL.query.await([[
                SELECT pv.id, pv.citizenid, pv.vehicle AS model, pv.plate, pv.garage, pv.state,
                       l.label
                FROM player_vehicles pv
                JOIN cookie_limited_vehicles l
                  ON LOWER(l.model)=LOWER(pv.vehicle) AND l.active=1
                WHERE pv.citizenid=?
                  AND NOT EXISTS (
                      SELECT 1
                      FROM cookie_faction_shop fs
                      JOIN cookie_faction f ON f.id=fs.faction_id AND f.is_active=1
                      WHERE fs.active=1 AND LOWER(fs.model)=LOWER(pv.vehicle)
                  )
                ORDER BY l.label, pv.id
            ]], { cid }) or {}
            return rows
        end
    end

    if kind == 'faction' then
        local member = factionMembership(src, factionId)
        if not member then return {}, '해당 팩션 차고에 접근할 수 없습니다' end

        local fid = tonumber(member.faction_id)
        local f = factionRow(fid)
        if not f then return {}, '팩션 정보를 찾을 수 없습니다' end
        local garage = factionGarageKey(f)
        local ownerCid = 'FACTION_' .. tostring(fid)
        local grade = math.max(0, math.floor(tonumber(member.grade) or 0))

        local rows = MySQL.query.await([[
            SELECT pv.id, pv.citizenid, pv.vehicle AS model, pv.plate, pv.garage, pv.state,
                   COALESCE(fs.label, pv.vehicle) AS label,
                   COALESCE(fv.min_grade, fs.min_grade, 0) AS min_grade
            FROM player_vehicles pv
            LEFT JOIN cookie_faction_shop fs
              ON fs.faction_id=? AND fs.active=1 AND LOWER(fs.model)=LOWER(pv.vehicle)
            LEFT JOIN cookie_faction_vehicle fv
              ON fv.faction_id=? AND LOWER(fv.model)=LOWER(pv.vehicle)
            WHERE pv.citizenid=? AND pv.garage=?
              AND EXISTS (
                  SELECT 1 FROM cookie_faction_vehicle x
                  WHERE x.faction_id=? AND LOWER(x.model)=LOWER(pv.vehicle)
                    AND COALESCE(x.min_grade,0) <= ?
              )
            GROUP BY pv.id, pv.citizenid, pv.vehicle, pv.plate, pv.garage, pv.state, fs.label, fv.min_grade, fs.min_grade
            ORDER BY label, pv.id
        ]], { fid, fid, ownerCid, garage, fid, grade }) or {}

        return rows
    end

    return {}, '잘못된 차고 종류입니다'
end

function CookieGarageRules.PlayerFaction(src)
    return factionMembership(src)
end

function CookieGarageRules.FactionGarageKey(fid)
    return factionGarageKey(factionRow(fid))
end

exports('ClassifyGarageVehicle', function(model)
    return CookieGarageRules.ClassifyModel(model)
end)

exports('GetGarageCatalog', function(kind, factionId)
    return CookieGarageRules.GetCatalog(kind, factionId)
end)

exports('GetGarageVehicleList', function(src, kind, factionId)
    return CookieGarageRules.GetOwnedVehicles(src, kind, factionId)
end)

-- cookie_garage 연동용 범용 이벤트.
-- UI/클라이언트는 context만 넘기고, 실제 목록 판정은 서버가 수행한다.
RegisterNetEvent('cookie_admin:server:requestStrictGarageList', function(kind, factionId)
    local src = source
    local rows, err = CookieGarageRules.GetOwnedVehicles(src, kind, factionId)
    TriggerClientEvent('cookie_admin:client:strictGarageList', src, {
        kind = tostring(kind or ''),
        factionId = tonumber(factionId),
        rows = rows or {},
        error = err,
    })
end)

-- 기존 데이터에 겹침이 있으면 삭제하지 않고 경고만 한다.
-- 관리자가 어느 분류를 유지할지 결정한 뒤 제거해야 안전하다.
CreateThread(function()
    Wait(1500)
    local overlaps = MySQL.query.await([[
        SELECT model,
               MAX(in_general) AS in_general,
               MAX(in_limited) AS in_limited,
               MAX(in_faction) AS in_faction
        FROM (
            SELECT LOWER(model) AS model, 1 AS in_general, 0 AS in_limited, 0 AS in_faction
              FROM cookie_dealership_vehicles WHERE active=1
            UNION ALL
            SELECT LOWER(model), 0, 1, 0
              FROM cookie_limited_vehicles WHERE active=1
            UNION ALL
            SELECT LOWER(fs.model), 0, 0, 1
              FROM cookie_faction_shop fs
              JOIN cookie_faction f ON f.id=fs.faction_id AND f.is_active=1
             WHERE fs.active=1
        ) x
        GROUP BY model
        HAVING (MAX(in_general)+MAX(in_limited)+MAX(in_faction)) > 1
        ORDER BY model
    ]], {}) or {}

    if #overlaps > 0 then
        print(('^3[cookie_admin/garage]^7 차량 분류 중복 %d개 감지. 목록 노출은 팩션 > 한정 > 일반 우선순위로 안전 차단합니다.'):format(#overlaps))
        for i = 1, math.min(#overlaps, 30) do
            local r = overlaps[i]
            print(('^3[cookie_admin/garage]^7 overlap model=%s general=%s limited=%s faction=%s'):format(
                tostring(r.model), tostring(r.in_general), tostring(r.in_limited), tostring(r.in_faction)))
        end
    else
        print('^2[cookie_admin/garage]^7 일반/한정/팩션 차량 분류 중복 없음')
    end
end)
