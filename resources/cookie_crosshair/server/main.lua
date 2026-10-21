

local function clog(...) if Config.Crosshair.Debug then  end end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_crosshair (
                citizenid VARCHAR(60) PRIMARY KEY,
                cfg       TEXT NOT NULL,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)
    if ok then
    else  end
end)

local function cidOf(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function clampNum(cfg, key)
    local rng = Config.Crosshair.Range[key]
    local def = Config.Crosshair.Default[key]
    local n = math.floor(tonumber(cfg[key]) or def)
    if rng then
        if n < rng[1] then n = rng[1] elseif n > rng[2] then n = rng[2] end
    end
    return n
end

local function asBool(v, def)
    if v == nil then return def end
    if v == false or v == 0 or v == 'false' then return false end
    if v == true or v == 1 or v == 'true' then return true end
    return def and true or false
end

local function sanitize(cfg)
    if type(cfg) ~= 'table' then return nil end
    local D = Config.Crosshair.Default
    local out = {
        custom  = asBool(cfg.custom,  D.custom),
        base    = asBool(cfg.base,    D.base),
        adsOnly = asBool(cfg.adsOnly, D.adsOnly),
        outline = asBool(cfg.outline, D.outline),
        dot     = asBool(cfg.dot,     D.dot),
        inner   = asBool(cfg.inner,   D.inner),
        outer   = asBool(cfg.outer,   D.outer),
        ring    = asBool(cfg.ring,    D.ring),
        top     = asBool(cfg.top,     D.top),
    }
    for _, k in ipairs({
        'r', 'g', 'b', 'a', 'outlineW', 'outlineA', 'dotW', 'dotA',
        'inW', 'inL', 'inO', 'outW', 'outL', 'outO', 'ringR', 'ringW',
    }) do
        out[k] = clampNum(cfg, k)
    end
    return out
end

local function loadCfg(src)
    local cid = cidOf(src)
    if not cid then return nil end
    local row = MySQL.single.await('SELECT cfg FROM cookie_crosshair WHERE citizenid = ?', { cid })
    if row and row.cfg then
        local ok, decoded = pcall(json.decode, row.cfg)
        if ok then return sanitize(decoded) end
    end
    return nil
end

RegisterNetEvent('cookie_crosshair:server:request', function()
    local src = source
    CreateThread(function()
        local cfg = loadCfg(src) or Config.Crosshair.Default
        TriggerClientEvent('cookie_crosshair:client:apply', src, cfg)
    end)
end)

RegisterNetEvent('cookie_crosshair:server:save', function(cfg)
    local src = source
    local clean = sanitize(cfg)
    if not clean then return end
    local cid = cidOf(src)
    if not cid then return end

    MySQL.query.await([[
        INSERT INTO cookie_crosshair (citizenid, cfg) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE cfg = VALUES(cfg)
    ]], { cid, json.encode(clean) })

    TriggerClientEvent('cookie_crosshair:client:apply', src, clean)
    TriggerClientEvent('cookie_admin:client:notify', src, '크로스헤어를 저장했습니다', false)

end)
