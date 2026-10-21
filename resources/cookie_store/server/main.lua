local prefix='[cookie_store] '
local locks={}
local function notify(src,msg,bad)
    TriggerClientEvent('cookie_store:client:notify',src,msg,bad==true)
end
local function player(src)
    local p=exports.qbx_core:GetPlayer(src)
    if not p or not p.PlayerData or not p.PlayerData.citizenid then return nil end
    return p,p.PlayerData.citizenid
end
local function admin(src)
    if src==0 then return true end
    local license=GetPlayerIdentifierByType(src,'license2') or GetPlayerIdentifierByType(src,'license')
    if not license then return false end
    local row=MySQL.single.await('SELECT admin_level FROM cookie_admin WHERE license=? AND is_active=1 LIMIT 1',{license})
    if not row or tonumber(row.admin_level or 0)<Config.AdminMinLevel then return false end
    -- Respect cookie_admin duty state when its global helper is available.
    if type(CookieGetAdminState)=='function' and CookieGetAdminState(src)~='duty' then return false end
    return true
end
local function identifier(src)
    local id=GetPlayerIdentifierByType(src,'fivem')
    return id and id:lower() or nil
end
local function validateReward(t,key,count)
    if t=='item' then
        if type(key)~='string' or not key:match('^[%w_%-]+$') or #key>80 then return nil end
        local ok,items=pcall(function() return exports.ox_inventory:Items() end)
        if not ok or not items or not items[key] then return nil end
        return {mail_type='item',item_name=key,quantity=count or 1,vehicle_model=nil,vehicle_type=nil}
    elseif t=='vehicle' then
        if type(key)~='string' or not key:match('^[%w_%-]+$') or #key>60 then return nil end
        local v=MySQL.single.await('SELECT model FROM cookie_limited_vehicles WHERE LOWER(model)=LOWER(?) AND active=1 LIMIT 1',{key})
        if v then return {mail_type='vehicle',item_name=nil,quantity=1,vehicle_model=key,vehicle_type='limited'} end
        v=MySQL.single.await('SELECT model FROM cookie_dealership_vehicles WHERE LOWER(model)=LOWER(?) AND active=1 LIMIT 1',{key})
        if v then return {mail_type='vehicle',item_name=nil,quantity=1,vehicle_model=key,vehicle_type='general'} end
    end
    return nil
end
local function clean(v,max)
    v=tostring(v or ''):gsub('^%s+',''):gsub('%s+$','')
    if #v>max then return nil end
    return v
end
local function mailQuery(cid,name,r,reason,sender)
    return {query=[[INSERT INTO cookie_mailbox (recipient_citizenid,recipient_name,sender_type,sender_name,sender_license,mail_type,reward_label,account,amount,item_name,quantity,vehicle_model,vehicle_type,reason,status)
     VALUES (?,?,'shop',?,NULL,?,?,NULL,0,?,?,?,? ,?,'pending')]],
        values={cid,cid,sender or 'COOKIE STORE',r.mail_type,name,r.item_name,r.quantity,r.vehicle_model,r.vehicle_type,reason}}
end
CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_store_products (
        id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(120) NOT NULL, description VARCHAR(1000) NOT NULL DEFAULT '', image_url VARCHAR(512) NOT NULL DEFAULT '',
        category VARCHAR(40) NOT NULL DEFAULT 'general', reward_type VARCHAR(20) NOT NULL, reward_key VARCHAR(80) NOT NULL,
        quantity INT NOT NULL DEFAULT 1, price_krw INT UNSIGNED NOT NULL DEFAULT 0, money_price INT UNSIGNED NOT NULL DEFAULT 0,
        tebex_package VARCHAR(80) NOT NULL DEFAULT '', sell_tebex TINYINT NOT NULL DEFAULT 0,
        sell_mileage TINYINT NOT NULL DEFAULT 0, sell_money TINYINT NOT NULL DEFAULT 0, enabled TINYINT NOT NULL DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_store_wallets (citizenid VARCHAR(64) PRIMARY KEY,points BIGINT NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_store_logs (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,citizenid VARCHAR(64),product_id INT,payment VARCHAR(20),amount BIGINT NOT NULL DEFAULT 0, details VARCHAR(255) NOT NULL DEFAULT '',created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_store_vouchers (
        voucher VARCHAR(100) PRIMARY KEY, fivem_id VARCHAR(100) NOT NULL, product_id INT UNSIGNED NOT NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'unused', redeemed_cid VARCHAR(64) NULL,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    print(prefix..'tables ready')
end)
local function productList(includeDisabled)
    local rows=MySQL.query.await(includeDisabled and 'SELECT * FROM cookie_store_products ORDER BY id DESC LIMIT 200' or 'SELECT * FROM cookie_store_products WHERE enabled=1 ORDER BY id DESC LIMIT 200') or {}
    for _,r in ipairs(rows) do
        r.mileage_price=(tonumber(r.price_krw) or 0)*Config.MileagePerWon*Config.MileageMultiplier
        -- never expose internal reward_key for locked products if unnecessary, but UI needs type label
    end
    return rows
end
local function open(src,manage)
    local p,cid=player(src);if not p then return end
    if manage and not admin(src) then notify(src,'F3 시스템 관리 권한이 없습니다',true);return end
    local points=tonumber(MySQL.scalar.await('SELECT points FROM cookie_store_wallets WHERE citizenid=?',{cid})) or 0
    TriggerClientEvent('cookie_store:client:open',src,{products=productList(manage==true),points=points,admin=manage==true,tebex=Config.TebexURL})
end
RegisterNetEvent('cookie_store:server:open',function(manage) open(source,manage==true) end)
RegisterCommand(Config.ShopCommand,function(src) if src>0 then open(src,false) end end,false)
RegisterCommand(Config.AdminCommand,function(src) if src>0 then open(src,true) end end,false)
local function after(src,txt) notify(src,txt);open(src,false) end
RegisterNetEvent('cookie_store:server:buy',function(rawId,method)
    local src=source; local p,cid=player(src);if not p then return end
    local id=math.floor(tonumber(rawId) or 0);if id<1 or (method~='money' and method~='mileage') then return end
    if locks[cid] then return notify(src,'구매 처리 중입니다',true) end
    locks[cid]=true
    local ok,err=pcall(function()
        local r=MySQL.single.await('SELECT * FROM cookie_store_products WHERE id=? AND enabled=1',{id})
        if not r then return notify(src,'판매되지 않는 상품입니다',true) end
        local reward=validateReward(r.reward_type,r.reward_key,math.max(1,math.min(9999,tonumber(r.quantity) or 1)))
        if not reward then return notify(src,'지급할 수 없는 아이템/차량입니다. 관리자에게 문의하세요',true) end
        if method=='mileage' then
            if tonumber(r.sell_mileage)~=1 or tonumber(r.price_krw)<=0 then return notify(src,'마일리지 판매 상품이 아닙니다',true) end
            local price=tonumber(r.price_krw)*Config.MileagePerWon*Config.MileageMultiplier
            local current=tonumber(MySQL.scalar.await('SELECT points FROM cookie_store_wallets WHERE citizenid=?',{cid})) or 0
            if current<price then return notify(src,'마일리지가 부족합니다',true) end
            local done=MySQL.transaction.await({
                {query='UPDATE cookie_store_wallets SET points=points-? WHERE citizenid=? AND points>=?',values={price,cid,price}},
                mailQuery(cid,r.name,reward,'마일리지 상점에서 구매한 상품입니다.','COOKIE STORE'),
                {query='INSERT INTO cookie_store_logs(citizenid,product_id,payment,amount) VALUES (?,?,?,?)',values={cid,id,'mileage',price}}
            })
            -- MySQL.transaction updates that affect zero rows do not fail: first make balance check under Lua lock.
            -- Safe from double-spend only when no external writers bypass this resource.
            if done then after(src,'마일리지 구매 처리 완료: 우편함 확인') else notify(src,'마일리지 처리 실패',true) end
        else
            if tonumber(r.sell_money)~=1 or tonumber(r.money_price)<=0 then return notify(src,'게임머니 판매 상품이 아닙니다',true) end
            local price=tonumber(r.money_price)
            local before=p.Functions.GetMoney('bank') or 0
            if before<price then return notify(src,'은행 잔액이 부족합니다',true) end
            local paid=p.Functions.RemoveMoney('bank',price,'cookie-store-purchase')
            if paid==false then return notify(src,'차감에 실패했습니다',true) end
            local delivered=MySQL.transaction.await({mailQuery(cid,r.name,reward,'인게임 머니 상점에서 구매한 상품입니다.','COOKIE STORE'),{query='INSERT INTO cookie_store_logs(citizenid,product_id,payment,amount) VALUES (?,?,?,?)',values={cid,id,'money',price}}})
            if delivered then after(src,'구매 완료: 기존 F3 우편함 확인') else p.Functions.AddMoney('bank',price,'cookie-store-refund');notify(src,'우편 전송 실패로 환불했습니다',true) end
        end
    end)
    locks[cid]=nil
    if not ok then print(prefix..'purchase error '..tostring(err));notify(src,'상점 처리 오류',true) end
end)
RegisterNetEvent('cookie_store:server:redeem',function(value)
    local src=source;local p,cid=player(src);if not p then return end
    local code=clean(value,100)
    if not code or not code:match('^[%w_%-]+$') then return notify(src,'코드 형식이 잘못됐습니다',true) end
    if locks[cid] or locks['voucher:'..code] then return end
    locks[cid]=true;locks['voucher:'..code]=true
    local ok,err=pcall(function()
        local v=MySQL.single.await('SELECT * FROM cookie_store_vouchers WHERE voucher=? AND status=?',{code,'unused'})
        if not v then return notify(src,'인증할 수 없는 코드이거나 이미 사용한 코드입니다',true) end
        if not identifier(src) or identifier(src)~=v.fivem_id then return notify(src,'이 코드를 구매한 계정과 일치하지 않습니다',true) end
        local r=MySQL.single.await('SELECT * FROM cookie_store_products WHERE id=? AND enabled=1',{v.product_id})
        if not r then return notify(src,'등록되지 않은 상품입니다',true) end
        local reward=validateReward(r.reward_type,r.reward_key,math.max(1,math.min(9999,tonumber(r.quantity) or 1)))
        if not reward then return notify(src,'상품 지급 설정을 확인해야 합니다',true) end
        local done=MySQL.transaction.await({
            {query="UPDATE cookie_store_vouchers SET status='used',redeemed_cid=? WHERE voucher=? AND status='unused'",values={cid,code}},
            mailQuery(cid,r.name,reward,'Tebex에서 구매한 상품입니다.','COOKIE SERVER'),
            {query='INSERT INTO cookie_store_logs(citizenid,product_id,payment,details) VALUES (?,?,?,?)',values={cid,r.id,'tebex',code}}
        })
        if done then after(src,'Tebex 구매 확인 완료! F3 우편함을 확인하세요') else notify(src,'인증 처리 실패',true) end
    end)
    locks[cid]=nil;locks['voucher:'..code]=nil
    if not ok then print(prefix..'redeem error '..tostring(err));notify(src,'인증 처리 오류',true) end
end)
-- Tebex console-only command: cookie_shop_voucher <fivem_identifier> <transaction_id> <product_id>
-- Requires actual verified Tebex command execution. Transaction reference is the redemption code.
RegisterCommand('cookie_shop_voucher',function(src,args)
    if src~=0 then return end
    local fid=clean(args[1],100); local code=clean(args[2],100);local id=tonumber(args[3])
    if fid and fid:match('^%d+$') then fid='fivem:'..fid end
    if not fid or not fid:match('^fivem:%d+$') or not code or not code:match('^[%w_%-]+$') or not id then return print(prefix..'usage: cookie_shop_voucher <fivem_id> <transaction> <product_id>') end
    local p=MySQL.single.await('SELECT id FROM cookie_store_products WHERE id=? AND sell_tebex=1',{id})
    if not p then return print(prefix..'invalid Tebex product id') end
    local inserted=MySQL.insert.await('INSERT IGNORE INTO cookie_store_vouchers(voucher,fivem_id,product_id) VALUES (?,?,?)',{code,fid:lower(),id})
    print(prefix..(inserted and inserted>0 and 'verified transaction voucher stored' or 'duplicate transaction ignored'))
end,true)
RegisterNetEvent('cookie_store:server:adminSave',function(data)
    local src=source;if not admin(src) or type(data)~='table' then return end
    local name=clean(data.name,120);local description=clean(data.description,1000) or ''
    local category=clean(data.category,40) or 'general';local rewardType=clean(data.reward_type,20);local key=clean(data.reward_key,80)
    local qty=math.max(1,math.min(9999,math.floor(tonumber(data.quantity) or 1)))
    local krw=math.max(0,math.min(100000000,math.floor(tonumber(data.price_krw) or 0)))
    local money=math.max(0,math.min(2000000000,math.floor(tonumber(data.money_price) or 0)))
    local pkg=clean(data.tebex_package,80) or ''
    local img=clean(data.image_url,512) or ''
    if img~='' and not img:match('^https://[%w%.%-/%%_?=&]+$') then img='' end
    if not name or #name<1 or not category:match('^[%w_%-]+$') or not validateReward(rewardType,key,qty) then return notify(src,'상품명·지급 아이템/차량·코드를 확인하세요',true) end
    local flag=function(v) return (v==true or v==1) and 1 or 0 end
    local id=math.floor(tonumber(data.id) or 0)
    local args={name,description,img,category,rewardType,key,qty,krw,money,pkg,flag(data.sell_tebex),flag(data.sell_mileage),flag(data.sell_money),flag(data.enabled)}
    if id>0 then
        args[#args+1]=id
        MySQL.update.await('UPDATE cookie_store_products SET name=?,description=?,image_url=?,category=?,reward_type=?,reward_key=?,quantity=?,price_krw=?,money_price=?,tebex_package=?,sell_tebex=?,sell_mileage=?,sell_money=?,enabled=? WHERE id=?',args)
    else
        MySQL.insert.await('INSERT INTO cookie_store_products(name,description,image_url,category,reward_type,reward_key,quantity,price_krw,money_price,tebex_package,sell_tebex,sell_mileage,sell_money,enabled) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',args)
    end
    notify(src,'상점 상품 저장 완료');open(src,true)
end)
RegisterNetEvent('cookie_store:server:adminPoints',function(target,delta)
    local src=source;if not admin(src) then return end
    local targetId=math.floor(tonumber(target) or -1);local change=math.floor(tonumber(delta) or 0)
    if targetId<1 or change==0 or math.abs(change)>10000000 then return notify(src,'고번/마일리지 숫자를 확인하세요',true) end
    local _,cid=player(targetId);if not cid then return notify(src,'접속 중인 대상만 지정할 수 있습니다',true) end
    MySQL.query.await('INSERT IGNORE INTO cookie_store_wallets(citizenid,points) VALUES (?,0)',{cid})
    local current=tonumber(MySQL.scalar.await('SELECT points FROM cookie_store_wallets WHERE citizenid=?',{cid})) or 0
    if current+change<0 then return notify(src,'대상 마일리지가 부족합니다',true) end
    MySQL.update.await('UPDATE cookie_store_wallets SET points=points+? WHERE citizenid=?',{change,cid})
    MySQL.insert.await('INSERT INTO cookie_store_logs(citizenid,product_id,payment,amount,details) VALUES (?,NULL,?,?,?)',{cid,'admin_points',change,'by admin'})
    notify(src,'마일리지 변경 완료')
    notify(targetId,('마일리지 변경: %+dP'):format(change))
end)
