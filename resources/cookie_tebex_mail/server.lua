local function log(s) print('[cookie_tebex_mail] '..tostring(s)) end
local function clean(x,max)
    x=tostring(x or ''):gsub('^%s+',''):gsub('%s+$','')
    if #x > max then return nil end
    return x
end
local function getFivemId(src)
    local id=GetPlayerIdentifierByType(src,'fivem')
    if id then return id:lower() end
    return nil
end
local function checkReward(key)
    local reward=Config.Products[key]
    if type(reward)~='table' then return nil,'Unknown configured package key' end
    if reward.type=='vehicle' then
        local model=clean(reward.model,60)
        if not model or not model:match('^[%w_%-]+$') then return nil,'Invalid vehicle model' end
        local row=MySQL.single.await('SELECT model,label FROM cookie_limited_vehicles WHERE LOWER(model)=? AND active=1 LIMIT 1',{model:lower()})
        if row then return {type='vehicle',model=model:lower(),garageType='limited',label=clean(reward.label,120) or (row.label or model)} end
        row=MySQL.single.await('SELECT model,display_name FROM cookie_dealership_vehicles WHERE LOWER(model)=? AND active=1 LIMIT 1',{model:lower()})
        if row then return {type='vehicle',model=model:lower(),garageType='general',label=clean(reward.label,120) or (row.display_name or model)} end
        return nil,'Vehicle not in registered general/limited catalog'
    elseif reward.type=='item' then
        local item=clean(reward.item,80)
        local qty=math.floor(tonumber(reward.quantity) or 0)
        if not item or not item:match('^[%w_%-]+$') or qty<1 or qty>9999 then return nil,'Invalid item or quantity' end
        local items=exports.ox_inventory:Items()
        if not items or not items[item] then return nil,'Item not registered in ox_inventory' end
        return {type='item',item=item,quantity=qty,label=clean(reward.label,120) or items[item].label or item}
    end
    return nil,'Only vehicle/item supported'
end
local function indexPlayer(src)
    local fivem=getFivemId(src)
    if not fivem then return end
    local p=exports.qbx_core:GetPlayer(src)
    local cid=p and p.PlayerData and p.PlayerData.citizenid
    if not cid then return end
    MySQL.query.await([[
        INSERT INTO cookie_tebex_identity (fivem_identifier, citizenid, updated_at)
        VALUES (?, ?, NOW()) ON DUPLICATE KEY UPDATE citizenid=VALUES(citizenid), updated_at=NOW()
    ]], { fivem,cid })
end
local function matchCid(raw)
    raw=clean(raw,100)
    if not raw or not raw:match('^[%w:_%-]+$') then return nil end
    local id=raw:lower()
    if id:match('^%d+$') then id='fivem:'..id end
    if not id:match('^fivem:%d+$') then return nil end
    for _,idSrc in ipairs(GetPlayers()) do
        local src=tonumber(idSrc)
        if getFivemId(src)==id then indexPlayer(src) end
    end
    return MySQL.scalar.await('SELECT citizenid FROM cookie_tebex_identity WHERE fivem_identifier=?',{id}), id
end
local function attemptDelivery(orderKey)
    local row=MySQL.single.await('SELECT * FROM cookie_tebex_orders WHERE order_key=? LIMIT 1',{orderKey})
    if not row or row.status=='delivered' then return end
    local cid, fid=matchCid(row.buyer_identifier)
    if not cid then return end -- safely retained for player connection later
    local reward,err=checkReward(row.product_key)
    if not reward then log(('Order %s pending: %s'):format(orderKey,err));return end
    -- Transactional unique ledger insert + existing mailbox insert; duplicate attempts roll back.
    local sql1='INSERT INTO cookie_tebex_delivery (order_key) VALUES (?)'
    local sql2=[[
      INSERT INTO cookie_mailbox
        (recipient_citizenid, recipient_name, sender_type, sender_name, sender_license,
        mail_type, reward_label, account, amount, item_name, quantity, vehicle_model, vehicle_type, reason, status)
      VALUES (?, ?, 'tebex', 'COOKIE SERVER', NULL, ?, ?, NULL, 0, ?, ?, ?, ?, 'Tebex에서 구매한 상품입니다.', 'pending')
    ]]
    local ok,res=pcall(function()
        return MySQL.transaction.await({
            {query=sql1,values={orderKey}},
            {query=sql2,values={cid,cid,reward.type,reward.label,reward.item,reward.quantity or 1,reward.model,reward.garageType}}
        })
    end)
    if ok and res==true then
        MySQL.update.await("UPDATE cookie_tebex_orders SET status='delivered' WHERE order_key=?",{orderKey})
        log('Delivered order to mailbox: '..orderKey)
    elseif Config.Debug then
        log('Order pending/duplicate; check DB logs: '..orderKey)
    end
end
CreateThread(function()
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS cookie_tebex_identity (
        fivem_identifier VARCHAR(100) PRIMARY KEY, citizenid VARCHAR(64) NOT NULL,
        updated_at DATETIME NOT NULL
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS cookie_tebex_orders (
        order_key VARCHAR(180) PRIMARY KEY, buyer_identifier VARCHAR(100) NOT NULL,
        product_key VARCHAR(64) NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS cookie_tebex_delivery (
        order_key VARCHAR(180) PRIMARY KEY
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    Wait(1500)
    for _,src in ipairs(GetPlayers()) do indexPlayer(tonumber(src)) end
    while true do
        Wait(30000)
        for _,src in ipairs(GetPlayers()) do indexPlayer(tonumber(src)) end
        local orders=MySQL.query.await("SELECT order_key FROM cookie_tebex_orders WHERE status='pending' ORDER BY created_at ASC LIMIT 100") or {}
        for _,row in ipairs(orders) do attemptDelivery(row.order_key) end
    end
end)
RegisterCommand('cookie_tebex_grant',function(src,args)
    if src~=0 then log('Rejected non-console command');return end
    local buyer=clean(args[1],100)
    local trans=clean(args[2],100)
    local key=clean(args[3],64)
    if not buyer or not trans or not key or not trans:match('^[%w_%-]+$') or not key:match('^[%w_%-]+$') then
        log('Usage: cookie_tebex_grant <fivem_id> <transaction> <product_key>');return
    end
    local reward,err=checkReward(key)
    if not reward then log('Rejected: '..err);return end
    local orderKey=trans..':'..key
    MySQL.insert.await([[
        INSERT IGNORE INTO cookie_tebex_orders(order_key,buyer_identifier,product_key)
        VALUES (?,?,?)
    ]],{orderKey,buyer,key})
    attemptDelivery(orderKey)
end,true)
