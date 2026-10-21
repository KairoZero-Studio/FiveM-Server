local requests,requestByPlayer,sessions,sessionByPlayer={},{},{},{}
local nextRequestId,nextTradeId=1000,5000


local function cookieAllowAction(src,key,windowMs,maxCount)
    if GetResourceState('cookie_core')=='started' then
        local ok,allowed=pcall(function() return exports.cookie_core:Allow(src,key,windowMs,maxCount) end)
        if ok then return allowed==true end
    end
    return true
end

local function decodeJson(raw)
    if type(raw)~='string' or raw=='' then return {} end
    local ok,v=pcall(json.decode,raw)
    return ok and type(v)=='table' and v or {}
end

local function tradeRecovery(category,cid,uid,payload)
    pcall(function()
        MySQL.insert.await('INSERT INTO cookie_recovery_log(category,citizenid,asset_uid,payload_json) VALUES(?,?,?,?)',{
            category,cid,uid,json.encode(payload or {})
        })
    end)
end

-- 경찰청/보안국 운전면허증 제시 요청
local driverLicenseRequests={}
local nextDriverLicenseRequestId=8000

local function cookieTradeLog(category, title, description, fields, options)
    if GetResourceState('cookie_logs') ~= 'started' then return end
    pcall(function()
        exports.cookie_logs:Log(category, title, description, fields or {}, options or {})
    end)
end



local function clean(v,n) local s=tostring(v or ''):gsub('[%c]',' '):gsub('^%s+',''):gsub('%s+$',''); if n and #s>n then s=s:sub(1,n) end; return s end
local function player(src) return exports.qbx_core:GetPlayer(src) end
local function citizenid(src) local p=player(src); return p and p.PlayerData and tostring(p.PlayerData.citizenid or '') or nil end
local function gobun(src) local ok,v=pcall(function() return exports.cookie_core:getGobun(src) end); return ok and tonumber(v) or nil end
local function nickname(src) local ok,v=pcall(function() return exports.cookie_core:getNickname(src) end); if ok and clean(v,60)~='' then return clean(v,60) end; return clean(GetPlayerName(src) or ('#'..src),60) end
local function faction(src) local ok,m=pcall(function() return exports.cookie_admin:getFactionMember(src) end); if not ok or not m then return nil end; return {id=tonumber(m.id),name=clean(m.name or m.factionName or m.key or '팩션',80),type=clean(m.type,30),rank=clean(m.rankName,50),duty=m.duty==true} end
local function profile(src) local g,n=gobun(src),nickname(src); return {source=src,gobun=g,name=n,label=('%s / %s'):format(tostring(g or '-'),n),faction=faction(src)} end

local function canRequestDriverLicense(src)
    local f=faction(src)
    if not f or f.duty~=true then return false end
    local t=tostring(f.type or ''):lower()
    return t=='police' or t=='security'
end

local function dist(a,b) if not GetPlayerName(a) or not GetPlayerName(b) then return 9999 end; local pa,pb=GetPlayerPed(a),GetPlayerPed(b); if pa==0 or pb==0 then return 9999 end; return #(GetEntityCoords(pa)-GetEntityCoords(pb)) end
local function notify(src,msg,err) if GetPlayerName(src) then TriggerClientEvent('cookie_admin:client:notify',src,msg,err==true) end end
local function money(src,k)
    local p=player(src)
    if not p then return 0 end

    if p.Functions and p.Functions.GetMoney then
        local ok,value=pcall(function()
            return p.Functions.GetMoney(k)
        end)
        if ok and tonumber(value) then
            return math.max(0,math.floor(tonumber(value) or 0))
        end
    end

    return math.max(0,math.floor(tonumber(
        p.PlayerData and p.PlayerData.money and p.PlayerData.money[k]
    ) or 0))
end
local function other(s,src) return s.a==src and s.b or (s.b==src and s.a or nil) end
local function session(src,id) local s=sessions[tonumber(id)]; if s and (s.a==src or s.b==src) then return s end end
local function reset(s) s.ready[s.a]=false;s.ready[s.b]=false;s.confirmed[s.a]=false;s.confirmed[s.b]=false end
local function metaBlocked(m) if type(m)~='table' then return false end; for _,k in ipairs(Config.BlockMetadataKeys or {}) do if m[k]==true or m[k]==1 or m[k]=='true' then return true end end; return false end
local function slotItem(src,slot) local ok,item=pcall(function() return exports.ox_inventory:GetSlot(src,slot) end); return ok and type(item)=='table' and item or nil end

local function safeQuery(label,sql,args)
    local ok,result=pcall(function()
        return MySQL.query.await(sql,args or {})
    end)
    if not ok then
        print(('[cookie_interaction TRADE ASSETS] %s query failed: %s'):format(
            tostring(label),tostring(result)
        ))
        return {}
    end
    return type(result)=='table' and result or {}
end

local function inventoryAssets(src)
    local items=nil

    local ok,list=pcall(function()
        return exports.ox_inventory:GetInventoryItems(src)
    end)
    if ok and type(list)=='table' then
        items=list
    end

    if type(items)~='table' then
        local okInv,inv=pcall(function()
            return exports.ox_inventory:GetInventory(src)
        end)
        if okInv and type(inv)=='table' and type(inv.items)=='table' then
            items=inv.items
        end
    end

    if type(items)~='table' then
        print(('[cookie_interaction TRADE ASSETS] inventory read failed for source %s'):format(src))
        return {}
    end

    local out={}
    for k,item in pairs(items) do
        if type(item)=='table' and item.name and (tonumber(item.count) or 0)>0 then
            local meta=type(item.metadata)=='table' and item.metadata or {}
            local lower=tostring(item.name):lower()

            if not (Config.BlockedItems and Config.BlockedItems[lower])
               and not metaBlocked(meta)
            then
                local slot=tonumber(item.slot or k)
                if slot then
                    local label=clean(item.label or item.name,80)

                    -- 일부 ox_inventory 버전은 슬롯 데이터에 label을 넣지 않으므로 아이템 정의에서 보충.
                    if label=='' or label==tostring(item.name) then
                        pcall(function()
                            local def=exports.ox_inventory:Items(item.name)
                            if def and clean(def.label,80)~='' then
                                label=clean(def.label,80)
                            end
                        end)
                    end

                    out[#out+1]={
                        type='item',
                        id=slot,
                        slot=slot,
                        name=tostring(item.name),
                        label=label~='' and label or tostring(item.name),
                        count=math.floor(tonumber(item.count) or 0),
                        weapon=tostring(item.name):upper():sub(1,7)=='WEAPON_',
                        serial=clean(meta.serial,80),
                        ammo=tonumber(meta.ammo)
                    }
                end
            end
        end
    end

    table.sort(out,function(a,b)
        return tostring(a.label)<tostring(b.label)
    end)
    return out
end

local function limitedVehicles(src)
    -- 차량은 반드시 '포장 상태'에서만 거래 목록에 노출한다.
    local cid=citizenid(src)
    if not cid or cid=='' then return {} end

    local rows=safeQuery('packed vehicles',[=[
        SELECT id,reward_key AS model,label,metadata_json,asset_uid
        FROM cookie_kuji_owned
        WHERE citizenid=? AND reward_type='vehicle' AND state='packed'
        ORDER BY id DESC
    ]=],{cid})

    local out={}
    for _,r in ipairs(rows) do
        local meta=decodeJson(r.metadata_json)
        out[#out+1]={
            type='vehicle',
            id=tonumber(r.id),
            model=tostring(meta.model or r.model or ''),
            plate=clean(meta.plate or '-',24),
            label=clean(r.label or r.model,80),
            assetUid=clean(r.asset_uid or meta.asset_uid,40),
            packed=true
        }
    end
    return out
end

local function titleAssets(src)
    local g=gobun(src)
    if not g then return {} end

    local rows=safeQuery('titles',[[
        SELECT t.id,t.kind,t.name,'ownership' AS ownership_type
        FROM cookie_title_ownership o
        JOIN cookie_title_catalog t ON t.id=o.title_id
        WHERE o.gobun=? AND t.is_active=1 AND t.kind IN ('chat','head')

        UNION ALL

        SELECT t.id,t.kind,t.name,'custom' AS ownership_type
        FROM cookie_title_catalog t
        WHERE t.target_gobun=? AND t.scope_type='custom'
          AND t.is_active=1 AND t.kind IN ('chat','head')
        ORDER BY kind,name
    ]],{g,g})

    local out,seen={},{}
    for _,r in ipairs(rows) do
        local id=tonumber(r.id)
        if id and not seen[id] then
            seen[id]=true
            out[#out+1]={
                type='title',
                id=id,
                kind=tostring(r.kind),
                ownershipType=tostring(r.ownership_type),
                label=clean(r.name,80)
            }
        end
    end
    return out
end

local function digitalAssets(src)
    local g=gobun(src)
    if not g then return {} end

    local rows=safeQuery('digital assets',[[
        SELECT c.id,c.kind,c.asset_key,c.label
        FROM cookie_trade_asset_ownership o
        JOIN cookie_trade_asset_catalog c ON c.id=o.asset_id
        WHERE o.gobun=? AND c.is_active=1 AND c.tradeable=1
        ORDER BY c.kind,c.label
    ]],{g})

    local out={}
    for _,r in ipairs(rows) do
        out[#out+1]={
            type='asset',
            id=tonumber(r.id),
            kind=tostring(r.kind),
            key=tostring(r.asset_key),
            label=clean(r.label,80)
        }
    end
    return out
end
local function assets(src)
    local result={
        money={
            cash=Config.AllowCash and money(src,'cash') or nil,
            bank=Config.AllowBank and money(src,'bank') or nil
        },
        items={},
        vehicles={},
        titles={},
        assets={},
        assetKinds=Config.AssetKinds or {}
    }

    local okItems,itemRows=pcall(inventoryAssets,src)
    if okItems and type(itemRows)=='table' then
        result.items=itemRows
    else
        print(('[cookie_interaction TRADE ASSETS] item assets failed source=%s error=%s'):format(
            src,tostring(itemRows)
        ))
    end

    local okVehicles,vehicleRows=pcall(limitedVehicles,src)
    if okVehicles and type(vehicleRows)=='table' then
        result.vehicles=vehicleRows
    end

    local okTitles,titleRows=pcall(titleAssets,src)
    if okTitles and type(titleRows)=='table' then
        result.titles=titleRows
    end

    local okAssets,digitalRows=pcall(digitalAssets,src)
    if okAssets and type(digitalRows)=='table' then
        result.assets=digitalRows
    end

    return result
end
local function offerList(map) local out={};for _,v in pairs(map or {}) do out[#out+1]=v end;table.sort(out,function(a,b)return tostring(a.key)<tostring(b.key) end);return out end

local function tradeMoney(n)
    n=math.floor(tonumber(n) or 0)
    local s=tostring(math.abs(n))
    local out=''
    while #s>3 do out=','..s:sub(-3)..out;s=s:sub(1,-4) end
    return (n<0 and '-' or '')..s..out..'원'
end

local function tradeVehicleName(row)
    -- UI offer에는 현재 번호판이 붙어 있어도 Discord에는 절대 표시하지 않음.
    local label=clean(row.label,100)
    local head=label:match('^(.-)%s+·%s+')
    return clean(head or label,100)
end

local function tradeItemName(row)
    -- 총기/아이템 Discord 로그에는 serial/ammo metadata를 넣지 않음.
    local itemName=clean(row.name,80)
    local label=''
    pcall(function()
        local def=exports.ox_inventory:Items(itemName)
        if def and def.label then label=clean(def.label,80) end
    end)
    if label=='' then label=itemName~='' and itemName or '아이템' end
    return ('%s x%d'):format(label,math.max(1,math.floor(tonumber(row.count) or 1)))
end

local function tradeOfferDiscord(map)
    local rows=offerList(map)
    if #rows==0 then return '없음' end

    local out={}
    for _,row in ipairs(rows) do
        if row.type=='money' then
            out[#out+1]=('• %s %s'):format(
                row.moneyType=='cash' and '현금' or '계좌',
                tradeMoney(row.amount)
            )
        elseif row.type=='item' then
            out[#out+1]='• '..tradeItemName(row)
        elseif row.type=='vehicle' then
            out[#out+1]='• 한정차량 · '..tradeVehicleName(row)
        elseif row.type=='title' or row.type=='asset' then
            out[#out+1]='• '..clean(row.label,120)
        end
    end

    local text=table.concat(out,'\n')
    if #text>1000 then text=text:sub(1,997)..'...' end
    return text
end

local function stateFor(s,viewer) local o=other(s,viewer);return {tradeId=s.id,me=profile(viewer),other=profile(o),myOffer=offerList(s.offers[viewer]),theirOffer=offerList(s.offers[o]),myReady=s.ready[viewer]==true,theirReady=s.ready[o]==true,myConfirmed=s.confirmed[viewer]==true,theirConfirmed=s.confirmed[o]==true,bothReady=s.ready[viewer]==true and s.ready[o]==true,expiresAt=s.expiresAt} end
local function broadcast(s) if GetPlayerName(s.a) then TriggerClientEvent('cookie_interaction:client:tradeState',s.a,stateFor(s,s.a)) end;if GetPlayerName(s.b) then TriggerClientEvent('cookie_interaction:client:tradeState',s.b,stateFor(s,s.b)) end end
local function closeSession(s,msg,err) if not s then return end;sessions[s.id]=nil;if sessionByPlayer[s.a]==s.id then sessionByPlayer[s.a]=nil end;if sessionByPlayer[s.b]==s.id then sessionByPlayer[s.b]=nil end;for _,src in ipairs({s.a,s.b}) do if GetPlayerName(src) then TriggerClientEvent('cookie_interaction:client:tradeClosed',src,{message=msg,isError=err==true}) end end end
local function clearRequest(id) local r=requests[id];if not r then return end;requestByPlayer[r.from]=nil;requestByPlayer[r.to]=nil;requests[id]=nil end
local function canCarry(src,name,count,metadata) local ok,v=pcall(function() return exports.ox_inventory:CanCarryItem(src,name,count,metadata) end);return ok and v==true end

local function addOffer(s,src,d)
    local kind=tostring(d.type or '');local offers=s.offers[src]
    if kind=='money' then
        local mt=tostring(d.moneyType or '');if mt~='cash' and mt~='bank' then return false,'금액 종류가 올바르지 않습니다.' end
        local amount=math.floor(tonumber(d.amount) or 0);if amount<1 or amount>(Config.MaxMoney or 1000000000) then return false,'거래 금액을 확인해주세요.' end;if money(src,mt)<amount then return false,'보유 금액이 부족합니다.' end
        local key='money:'..mt;offers[key]={key=key,type='money',moneyType=mt,amount=amount,label=(mt=='cash' and '현금' or '은행')..' '..amount..'원'}
    elseif kind=='item' then
        local slot=math.floor(tonumber(d.id) or 0);local count=math.floor(tonumber(d.count) or 1);local item=slotItem(src,slot)
        if not item or not item.name or count<1 or (tonumber(item.count) or 0)<count then return false,'아이템 상태가 변경되었습니다.' end
        if Config.BlockedItems and Config.BlockedItems[tostring(item.name):lower()] then return false,'거래할 수 없는 아이템입니다.' end;if metaBlocked(item.metadata) then return false,'귀속 아이템은 거래할 수 없습니다.' end
        local serial=type(item.metadata)=='table' and clean(item.metadata.serial,60) or '';local key='item:'..slot
        offers[key]={key=key,type='item',slot=slot,name=tostring(item.name),count=count,weapon=tostring(item.name):upper():sub(1,7)=='WEAPON_',label=clean(item.label or item.name,80)..' x'..count..(serial~='' and (' · '..serial) or '')}
    elseif kind=='vehicle' then
        local id=math.floor(tonumber(d.id) or 0)
        local cid=citizenid(src)
        local row=cid and MySQL.single.await([[
            SELECT id,label,reward_key,metadata_json,asset_uid
            FROM cookie_kuji_owned
            WHERE id=? AND citizenid=? AND reward_type='vehicle' AND state='packed' LIMIT 1
        ]],{id,cid})
        if not row then return false,'포장 상태인 본인 차량만 거래할 수 있습니다.' end
        local meta=decodeJson(row.metadata_json)
        local plate=clean(meta.plate,24)
        local key='vehicle:'..id
        offers[key]={
            key=key,type='vehicle',id=id,
            assetUid=clean(row.asset_uid or meta.asset_uid,40),
            label=clean(row.label or row.reward_key,80)..(plate~='' and (' · '..plate) or '')
        }
    elseif kind=='title' then
        local id=math.floor(tonumber(d.id) or 0);local found=nil;for _,r in ipairs(titleAssets(src)) do if r.id==id then found=r break end end;if not found then return false,'거래 가능한 보유 칭호가 아닙니다.' end
        local key='title:'..id;offers[key]={key=key,type='title',id=id,kind=found.kind,ownershipType=found.ownershipType,label=(found.kind=='chat' and '채팅칭호 · ' or '머리위칭호 · ')..found.label}
    elseif kind=='asset' then
        local id=math.floor(tonumber(d.id) or 0);local found=nil;for _,r in ipairs(digitalAssets(src)) do if r.id==id then found=r break end end;if not found then return false,'거래 가능한 보유 상품이 아닙니다.' end
        local key='asset:'..id;offers[key]={key=key,type='asset',id=id,kind=found.kind,label=((Config.AssetKinds or {})[found.kind] or found.kind)..' · '..found.label}
    else return false,'지원하지 않는 거래 종류입니다.' end
    local n=0;for _ in pairs(offers) do n=n+1 end;if n>(Config.MaxOfferLines or 40) then return false,'거래 항목이 너무 많습니다.' end;reset(s);return true
end

local function validateSide(s,src,recv)
    local out={};local sg,rg=gobun(src),gobun(recv);local sc,rc=citizenid(src),citizenid(recv);if not sg or not rg or not sc or not rc then return nil,'캐릭터 정보를 확인하지 못했습니다.' end
    for _,r in pairs(s.offers[src]) do
        if r.type=='money' then if money(src,r.moneyType)<r.amount then return nil,r.label..' 보유액이 부족합니다.' end;out[#out+1]={type='money',moneyType=r.moneyType,amount=r.amount,label=r.label}
        elseif r.type=='item' then local item=slotItem(src,r.slot);if not item or tostring(item.name)~=r.name or (tonumber(item.count) or 0)<r.count or metaBlocked(item.metadata) then return nil,r.label..' 상태가 변경되었습니다.' end;local meta=type(item.metadata)=='table' and item.metadata or {};if not canCarry(recv,r.name,r.count,meta) then return nil,'상대방 인벤토리에 '..r.label..'을 넣을 공간이 없습니다.' end;out[#out+1]={type='item',slot=r.slot,name=r.name,count=r.count,metadata=meta,label=r.label}
        elseif r.type=='vehicle' then
            local row=MySQL.single.await([[
                SELECT id,asset_uid FROM cookie_kuji_owned
                WHERE id=? AND citizenid=? AND reward_type='vehicle' AND state='packed' LIMIT 1
            ]],{r.id,sc})
            if not row then return nil,r.label..' 포장 상태가 변경되었습니다.' end
            out[#out+1]={type='vehicle',id=r.id,srcCid=sc,recvCid=rc,assetUid=row.asset_uid,label=r.label}
        elseif r.type=='title' then local mine=false;for _,t in ipairs(titleAssets(src)) do if t.id==r.id then mine=true break end end;if not mine then return nil,r.label..' 소유권이 변경되었습니다.' end;if r.ownershipType~='custom' then local dup=MySQL.single.await('SELECT 1 AS x FROM cookie_title_ownership WHERE title_id=? AND gobun=? LIMIT 1',{r.id,rg});if dup then return nil,'상대방이 이미 '..r.label..'을 보유하고 있습니다.' end end;out[#out+1]={type='title',id=r.id,ownershipType=r.ownershipType,srcGobun=sg,recvGobun=rg,label=r.label}
        elseif r.type=='asset' then local mine=MySQL.single.await('SELECT 1 AS x FROM cookie_trade_asset_ownership WHERE asset_id=? AND gobun=? LIMIT 1',{r.id,sg});if not mine then return nil,r.label..' 소유권이 변경되었습니다.' end;local dup=MySQL.single.await('SELECT 1 AS x FROM cookie_trade_asset_ownership WHERE asset_id=? AND gobun=? LIMIT 1',{r.id,rg});if dup then return nil,'상대방이 이미 '..r.label..'을 보유하고 있습니다.' end;out[#out+1]={type='asset',id=r.id,srcGobun=sg,recvGobun=rg,label=r.label} end
    end
    return out
end

local function rollbackRemoved(rows) for _,r in ipairs(rows) do if r.type=='item' then pcall(function() exports.ox_inventory:AddItem(r.src,r.name,r.count,r.metadata) end) elseif r.type=='money' then local p=player(r.src);if p then p.Functions.AddMoney(r.moneyType,r.amount,'COOKIE 거래 롤백') end end end end
local function transferTitle(r)
    MySQL.update.await([[UPDATE cookie_title_equipped SET chat_title_id=IF(chat_title_id=?,NULL,chat_title_id),chat_text_title_id=IF(chat_text_title_id=?,NULL,chat_text_title_id),head_title_id=IF(head_title_id=?,NULL,head_title_id) WHERE gobun=?]],{r.id,r.id,r.id,r.srcGobun})
    if r.ownershipType=='custom' then local n=MySQL.update.await("UPDATE cookie_title_catalog SET target_gobun=? WHERE id=? AND scope_type='custom' AND target_gobun=?",{r.recvGobun,r.id,r.srcGobun});return n and n>0 end
    local n=MySQL.update.await("UPDATE cookie_title_ownership SET gobun=?,granted_by='TRADE' WHERE title_id=? AND gobun=?",{r.recvGobun,r.id,r.srcGobun});return n and n>0
end

local function executeTrade(s)
    if s.busy then return false,'거래 처리 중입니다.' end
    s.busy=true
    if dist(s.a,s.b)>(Config.TradeDistance or 6.0) then s.busy=false;return false,'상대방과 거리가 너무 멉니다.' end

    local ar,ae=validateSide(s,s.a,s.b)
    if not ar then s.busy=false;return false,ae end
    local br,be=validateSide(s,s.b,s.a)
    if not br then s.busy=false;return false,be end

    local removed={}
    local function removeSide(src,rows)
        for _,r in ipairs(rows) do
            if r.type=='item' then
                local ok,v=pcall(function() return exports.ox_inventory:RemoveItem(src,r.name,r.count,r.metadata,r.slot) end)
                if not ok or v~=true then return false,r.label..' 제거 실패' end
                removed[#removed+1]={type='item',src=src,name=r.name,count=r.count,metadata=r.metadata}
            elseif r.type=='money' then
                local p=player(src)
                if not p or p.Functions.RemoveMoney(r.moneyType,r.amount,'COOKIE 거래')~=true then return false,r.label..' 차감 실패' end
                removed[#removed+1]={type='money',src=src,moneyType=r.moneyType,amount=r.amount}
            end
        end
        return true
    end

    local ok,err=removeSide(s.a,ar)
    if not ok then rollbackRemoved(removed);s.busy=false;return false,err end
    ok,err=removeSide(s.b,br)
    if not ok then rollbackRemoved(removed);s.busy=false;return false,err end

    local dbQueries={}
    local function addDb(rows)
        for _,r in ipairs(rows) do
            if r.type=='vehicle' then
                dbQueries[#dbQueries+1]={
                    query="UPDATE cookie_kuji_owned SET citizenid=? WHERE id=? AND citizenid=? AND reward_type='vehicle' AND state='packed'",
                    values={r.recvCid,r.id,r.srcCid}
                }
            elseif r.type=='title' then
                dbQueries[#dbQueries+1]={
                    query='UPDATE cookie_title_equipped SET chat_title_id=IF(chat_title_id=?,NULL,chat_title_id),chat_text_title_id=IF(chat_text_title_id=?,NULL,chat_text_title_id),head_title_id=IF(head_title_id=?,NULL,head_title_id) WHERE gobun=?',
                    values={r.id,r.id,r.id,r.srcGobun}
                }
                if r.ownershipType=='custom' then
                    dbQueries[#dbQueries+1]={query="UPDATE cookie_title_catalog SET target_gobun=? WHERE id=? AND scope_type='custom' AND target_gobun=?",values={r.recvGobun,r.id,r.srcGobun}}
                else
                    dbQueries[#dbQueries+1]={query="UPDATE cookie_title_ownership SET gobun=?,granted_by='TRADE' WHERE title_id=? AND gobun=?",values={r.recvGobun,r.id,r.srcGobun}}
                end
            elseif r.type=='asset' then
                dbQueries[#dbQueries+1]={query="UPDATE cookie_trade_asset_ownership SET gobun=?,granted_by='TRADE' WHERE asset_id=? AND gobun=?",values={r.recvGobun,r.id,r.srcGobun}}
            end
        end
    end
    addDb(ar);addDb(br)

    local dbOk=true
    if #dbQueries>0 then
        local txOk,tx=pcall(function() return MySQL.transaction.await(dbQueries) end)
        dbOk=txOk and tx==true
    end
    if not dbOk then
        rollbackRemoved(removed)
        s.busy=false
        return false,'소유권 이전 중 DB 거래가 취소되었습니다.'
    end

    local delivered={}
    local function give(recv,src,rows)
        for _,r in ipairs(rows) do
            if r.type=='item' then
                local gok,v=pcall(function() return exports.ox_inventory:AddItem(recv,r.name,r.count,r.metadata) end)
                if not gok or v~=true then return false,r.label..' 지급 실패' end
                delivered[#delivered+1]={type='item',recv=recv,src=src,name=r.name,count=r.count,metadata=r.metadata}
            elseif r.type=='money' then
                local p=player(recv)
                if not p then return false,'상대방 접속 상태 변경' end
                local v=p.Functions.AddMoney(r.moneyType,r.amount,'COOKIE 거래')
                if v==false then return false,r.label..' 지급 실패' end
                delivered[#delivered+1]={type='money',recv=recv,src=src,moneyType=r.moneyType,amount=r.amount}
            end
        end
        return true
    end

    local function reverseDb()
        local q={}
        local function rev(rows)
            for _,r in ipairs(rows) do
                if r.type=='vehicle' then
                    q[#q+1]={query="UPDATE cookie_kuji_owned SET citizenid=? WHERE id=? AND citizenid=? AND reward_type='vehicle' AND state='packed'",values={r.srcCid,r.id,r.recvCid}}
                elseif r.type=='title' then
                    if r.ownershipType=='custom' then
                        q[#q+1]={query="UPDATE cookie_title_catalog SET target_gobun=? WHERE id=? AND scope_type='custom' AND target_gobun=?",values={r.srcGobun,r.id,r.recvGobun}}
                    else
                        q[#q+1]={query="UPDATE cookie_title_ownership SET gobun=?,granted_by='TRADE_ROLLBACK' WHERE title_id=? AND gobun=?",values={r.srcGobun,r.id,r.recvGobun}}
                    end
                elseif r.type=='asset' then
                    q[#q+1]={query="UPDATE cookie_trade_asset_ownership SET gobun=?,granted_by='TRADE_ROLLBACK' WHERE asset_id=? AND gobun=?",values={r.srcGobun,r.id,r.recvGobun}}
                end
            end
        end
        rev(ar);rev(br)
        if #q==0 then return true end
        local rok,rv=pcall(function() return MySQL.transaction.await(q) end)
        return rok and rv==true
    end

    local function rollbackDelivered()
        local allOk=true
        for i=#delivered,1,-1 do
            local r=delivered[i]
            if r.type=='item' then
                local rok,rv=pcall(function() return exports.ox_inventory:RemoveItem(r.recv,r.name,r.count,r.metadata) end)
                if not rok or rv~=true then allOk=false end
            elseif r.type=='money' then
                local p=player(r.recv)
                if not p or p.Functions.RemoveMoney(r.moneyType,r.amount,'COOKIE 거래 롤백')~=true then allOk=false end
            end
        end
        return allOk
    end

    local function verifyVehicleOwnership(rows)
        for _,r in ipairs(rows) do
            if r.type=='vehicle' then
                local row=MySQL.single.await([[SELECT citizenid,state,asset_uid FROM cookie_kuji_owned
                    WHERE id=? AND reward_type='vehicle' LIMIT 1]],{r.id})
                if not row or tostring(row.citizenid or '')~=tostring(r.recvCid or '') or tostring(row.state or '')~='packed' then
                    return false,r
                end
                if r.assetUid and tostring(r.assetUid)~='' and tostring(row.asset_uid or '')~=tostring(r.assetUid) then
                    return false,r
                end
            end
        end
        return true
    end

    local ownA,badA=verifyVehicleOwnership(ar)
    local ownB,badB=verifyVehicleOwnership(br)
    if not ownA or not ownB then
        local ownershipRollback=reverseDb()
        rollbackRemoved(removed)
        tradeRecovery('trade_vehicle_postcheck_failed',citizenid(s.a),(badA or badB) and (badA or badB).assetUid or nil,{tradeId=s.id,ownershipRollback=ownershipRollback})
        s.busy=false
        return false,'차량 소유권 무결성 검사에 실패해 거래를 취소했습니다.'
    end

    ok,err=give(s.b,s.a,ar)
    if ok then ok,err=give(s.a,s.b,br) end
    if not ok then
        local deliveryRollback=rollbackDelivered()
        local ownershipRollback=reverseDb()
        rollbackRemoved(removed)
        if not deliveryRollback or not ownershipRollback then
            tradeRecovery('trade_rollback_incomplete',citizenid(s.a),nil,{tradeId=s.id,error=err,deliveryRollback=deliveryRollback,ownershipRollback=ownershipRollback})
        end
        s.busy=false
        return false,err or '거래 지급 오류로 거래를 되돌렸습니다.'
    end

    pcall(function() exports.cookie_admin:refreshTitleState(s.a) end)
    pcall(function() exports.cookie_admin:refreshTitleState(s.b) end)
    local pa,pb=profile(s.a),profile(s.b)
    MySQL.insert.await([[INSERT INTO cookie_trade_log(trade_id,a_gobun,a_name,a_faction,b_gobun,b_name,b_faction,a_offer,b_offer,status) VALUES(?,?,?,?,?,?,?,?,?,'completed')]],{tostring(s.id),pa.gobun,pa.name,pa.faction and pa.faction.name or nil,pb.gobun,pb.name,pb.faction and pb.faction.name or nil,json.encode(offerList(s.offers[s.a])),json.encode(offerList(s.offers[s.b]))})

    cookieTradeLog('trade','통합 거래 완료','',{
        {name=pa.label or '거래자 A',value=tradeOfferDiscord(s.offers[s.a]),inline=false},
        {name=pb.label or '거래자 B',value=tradeOfferDiscord(s.offers[s.b]),inline=false},
    },{
        actorSrc=s.a,targetSrc=s.b,actorLabel='거래자 A',targetLabel='거래자 B',eventKey='trade_complete'
    })

    s.busy=false
    return true
end

lib.callback.register('cookie_interaction:getAssets',function(source)
    return assets(source)
end)

lib.callback.register('cookie_interaction:getMyTradeData',function(source)
    local src=source
    local p=profile(src)
    local a=assets(src)

    return {
        ok=true,
        profile=p,
        assets=a,
        debug={
            cash=tonumber(a.money and a.money.cash) or 0,
            bank=tonumber(a.money and a.money.bank) or 0,
            itemCount=#(a.items or {}),
            vehicleCount=#(a.vehicles or {}),
            titleCount=#(a.titles or {}),
            assetCount=#(a.assets or {})
        }
    }
end)

lib.callback.register('cookie_interaction:getTarget',function(source,target)
    local src=source
    target=tonumber(target)

    if not target or target==src or not GetPlayerName(target) then
        return {ok=false,message='상대방을 찾을 수 없습니다.'}
    end

    if dist(src,target)>(Config.LookDistance or 4)+1 then
        return {ok=false,message='상대방이 너무 멉니다.'}
    end

    local targetProfile=profile(target)
    targetProfile.canRequestLicense=canRequestDriverLicense(src)

    return {ok=true,target=targetProfile}
end)

RegisterNetEvent('cookie_interaction:server:requestDriverLicense',function(target)
    local src=source
    target=tonumber(target)

    if not canRequestDriverLicense(src) then
        return notify(src,'경찰청/보안국 출근 상태에서만 운전면허증 제시를 요청할 수 있습니다.',true)
    end

    if not target or target==src or not GetPlayerName(target) then
        return notify(src,'상대방을 찾을 수 없습니다.',true)
    end

    if dist(src,target)>(Config.LookDistance or 4)+1 then
        return notify(src,'상대방이 너무 멉니다.',true)
    end

    for id,r in pairs(driverLicenseRequests) do
        if r.from==src or r.to==target then
            if os.time() <= (r.expiresAt or 0) then
                return notify(src,'이미 처리 중인 운전면허증 제시 요청이 있습니다.',true)
            end
            driverLicenseRequests[id]=nil
        end
    end

    nextDriverLicenseRequestId=nextDriverLicenseRequestId+1
    local id=nextDriverLicenseRequestId
    local officer=profile(src)

    driverLicenseRequests[id]={
        id=id,
        from=src,
        to=target,
        expiresAt=os.time()+15
    }

    TriggerClientEvent('cookie_interaction:client:driverLicenseRequest',target,{
        requestId=id,
        officer=officer,
        expiresAt=driverLicenseRequests[id].expiresAt
    })

    notify(src,profile(target).label..' 시민에게 운전면허증 제시를 요청했습니다.',false)
end)

RegisterNetEvent('cookie_interaction:server:replyDriverLicense',function(requestId,accepted)
    local target=source
    local id=tonumber(requestId)
    local r=id and driverLicenseRequests[id] or nil

    if not r or r.to~=target then return end
    driverLicenseRequests[id]=nil

    local officer=tonumber(r.from)
    if not officer or not GetPlayerName(officer) then return end

    if os.time()>(r.expiresAt or 0) then
        return notify(target,'운전면허증 제시 요청이 만료되었습니다.',true)
    end

    if dist(officer,target)>(Config.LookDistance or 4)+1 then
        notify(officer,'상대방과 거리가 멀어져 면허증 확인이 취소되었습니다.',true)
        return notify(target,'상대방과 거리가 멀어져 면허증 확인이 취소되었습니다.',true)
    end

    if not canRequestDriverLicense(officer) then
        return notify(target,'요청자의 업무 상태가 변경되어 요청이 취소되었습니다.',true)
    end

    if accepted~=true then
        notify(officer,profile(target).label..' 시민이 운전면허증 제시 요청을 거절했습니다.',true)
        return notify(target,'운전면허증 제시 요청을 거절했습니다.',false)
    end

    if GetResourceState('cookie_license')~='started' then
        notify(officer,'운전면허 시스템이 실행 중이 아닙니다.',true)
        return notify(target,'운전면허 정보를 불러올 수 없습니다.',true)
    end

    local ok,dl=pcall(function()
        return exports.cookie_license:GetBySource(target)
    end)

    if not ok or type(dl)~='table' then
        notify(officer,'상대방의 운전면허 정보를 불러오지 못했습니다.',true)
        return notify(target,'운전면허 정보를 불러오지 못했습니다.',true)
    end

    local holder=profile(target)
    local suspendedUntil='-'
    if dl.suspended and tonumber(dl.suspendedUntil) then
        suspendedUntil=os.date('%Y-%m-%d %H:%M:%S',tonumber(dl.suspendedUntil))
    end

    TriggerClientEvent('cookie_interaction:client:driverLicenseCard',officer,{
        holder=holder,
        licenseNo=tostring(dl.licenseNo or '-'),
        statusLabel=dl.suspended and '정지' or '정상',
        suspended=dl.suspended==true,
        suspendedUntil=suspendedUntil,
        reason=dl.suspended and tostring(dl.reason or '-') or '-'
    })

    notify(target,officer and profile(officer).label..' 담당자에게 운전면허증을 제시했습니다.' or '운전면허증을 제시했습니다.',false)
end)

RegisterNetEvent('cookie_interaction:server:requestTrade',function(target) local src=source;if not cookieAllowAction(src,'trade_request',1000,1) then return end;target=tonumber(target);if not target or target==src or not GetPlayerName(target) then return end;if dist(src,target)>(Config.LookDistance or 4)+1 then return notify(src,'상대방이 너무 멉니다.',true) end;if sessionByPlayer[src] or sessionByPlayer[target] or requestByPlayer[src] or requestByPlayer[target] then return notify(src,'한쪽이 이미 다른 거래를 진행 중입니다.',true) end;nextRequestId=nextRequestId+1;local id=nextRequestId;requests[id]={id=id,from=src,to=target,expiresAt=os.time()+(Config.InviteSeconds or 20)};requestByPlayer[src]=id;requestByPlayer[target]=id;TriggerClientEvent('cookie_interaction:client:tradeInvite',target,{requestId=id,from=profile(src),expiresAt=requests[id].expiresAt});notify(src,profile(target).label..' 시민에게 거래 요청을 보냈습니다.',false) end)
RegisterNetEvent('cookie_interaction:server:replyTrade',function(requestId,accepted) local src=source;if not cookieAllowAction(src,'trade_reply',500,2) then return end;local r=requests[tonumber(requestId)];if not r or r.to~=src then return end;if os.time()>r.expiresAt or not GetPlayerName(r.from) or dist(r.from,r.to)>(Config.TradeDistance or 6) then clearRequest(r.id);return notify(src,'거래 요청이 만료되었습니다.',true) end;if accepted~=true then notify(r.from,profile(src).label..' 시민이 거래 요청을 거절했습니다.',true);clearRequest(r.id);return end;local a,b=r.from,r.to;clearRequest(r.id);nextTradeId=nextTradeId+1;local s={id=nextTradeId,a=a,b=b,offers={[a]={},[b]={}},ready={[a]=false,[b]=false},confirmed={[a]=false,[b]=false},expiresAt=os.time()+(Config.TradeSeconds or 180),busy=false};sessions[s.id]=s;sessionByPlayer[a]=s.id;sessionByPlayer[b]=s.id;for _,viewer in ipairs({a,b}) do TriggerClientEvent('cookie_interaction:client:tradeOpen',viewer,{tradeId=s.id,state=stateFor(s,viewer),assets=assets(viewer)}) end end)
RegisterNetEvent('cookie_interaction:server:refreshAssets',function(id) local s=session(source,id);if s then TriggerClientEvent('cookie_interaction:client:tradeAssets',source,assets(source)) end end)
RegisterNetEvent('cookie_interaction:server:addOffer',function(id,d) local src=source;if not cookieAllowAction(src,'trade_offer',500,8) then return end;local s=session(src,id);if not s or s.busy then return end;if dist(s.a,s.b)>(Config.TradeDistance or 6) then return closeSession(s,'거리가 멀어져 거래가 취소되었습니다.',true) end;local ok,msg=addOffer(s,src,type(d)=='table' and d or {});if not ok then return notify(src,msg,true) end;broadcast(s) end)
RegisterNetEvent('cookie_interaction:server:removeOffer',function(id,key) local s=session(source,id);if not s or s.busy then return end;s.offers[source][tostring(key or '')]=nil;reset(s);broadcast(s) end)
RegisterNetEvent('cookie_interaction:server:setReady',function(id,ready) local src=source;local s=session(src,id);if not s or s.busy then return end;s.ready[src]=ready==true;s.confirmed[src]=false;if not s.ready[src] then s.confirmed[other(s,src)]=false end;broadcast(s) end)
RegisterNetEvent('cookie_interaction:server:confirm',function(id) local src=source;if not cookieAllowAction(src,'trade_confirm',1000,1) then return end;local s=session(src,id);if not s or s.busy then return end;local o=other(s,src);if not (s.ready[src] and s.ready[o]) then return notify(src,'양쪽 모두 거래 준비를 먼저 눌러야 합니다.',true) end;s.confirmed[src]=true;broadcast(s);if s.confirmed[s.a] and s.confirmed[s.b] then local ok,msg=executeTrade(s);if ok then closeSession(s,'거래가 완료되었습니다.',false) else closeSession(s,msg or '거래 처리 실패',true) end end end)
RegisterNetEvent('cookie_interaction:server:cancel',function(id,msg) local s=session(source,id);if s then closeSession(s,clean(msg,120)~='' and clean(msg,120) or '거래가 취소되었습니다.',true) end end)
AddEventHandler('playerDropped',function()
    local src=source
    local sid=sessionByPlayer[src]
    if sid and sessions[sid] then
        closeSession(sessions[sid],'상대방 접속이 종료되어 거래가 취소되었습니다.',true)
    end

    local rid=requestByPlayer[src]
    if rid then clearRequest(rid) end

    for id,r in pairs(driverLicenseRequests) do
        if r.from==src or r.to==src then
            local otherSrc=r.from==src and r.to or r.from
            driverLicenseRequests[id]=nil
            if otherSrc and GetPlayerName(otherSrc) then
                notify(otherSrc,'상대방 접속이 종료되어 운전면허증 확인이 취소되었습니다.',true)
            end
        end
    end
end)

local function registerAsset(kind,key,label,tradeable)
    kind=clean(kind,20):lower();key=clean(key,80);label=clean(label,100);if not Config.AssetKinds[kind] or key=='' or label=='' then return nil end
    MySQL.query.await([[INSERT INTO cookie_trade_asset_catalog(kind,asset_key,label,tradeable,is_active) VALUES(?,?,?,?,1) ON DUPLICATE KEY UPDATE label=VALUES(label),tradeable=VALUES(tradeable),is_active=1]],{kind,key,label,tradeable==false and 0 or 1})
    local row=MySQL.single.await('SELECT id FROM cookie_trade_asset_catalog WHERE kind=? AND asset_key=? LIMIT 1',{kind,key});return row and tonumber(row.id) or nil
end
exports('RegisterAsset',registerAsset)
exports('GrantAsset',function(g,kind,key,label) g=tonumber(g);if not g then return false end;local id=registerAsset(kind,key,label,true);if not id then return false end;MySQL.query.await("INSERT IGNORE INTO cookie_trade_asset_ownership(asset_id,gobun,granted_by) VALUES(?,?,'SYSTEM')",{id,g});return true end)
exports('OwnsAsset',function(g,kind,key) g=tonumber(g);if not g then return false end;local row=MySQL.single.await([[SELECT 1 AS x FROM cookie_trade_asset_ownership o JOIN cookie_trade_asset_catalog c ON c.id=o.asset_id WHERE o.gobun=? AND c.kind=? AND c.asset_key=? AND c.is_active=1 LIMIT 1]],{g,clean(kind,20):lower(),clean(key,80)});return row~=nil end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_trade_asset_catalog(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,kind VARCHAR(20) NOT NULL,asset_key VARCHAR(80) NOT NULL,label VARCHAR(100) NOT NULL,tradeable TINYINT(1) NOT NULL DEFAULT 1,is_active TINYINT(1) NOT NULL DEFAULT 1,created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,UNIQUE KEY uq_cookie_trade_asset(kind,asset_key)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_trade_asset_ownership(asset_id BIGINT UNSIGNED NOT NULL,gobun INT NOT NULL,granted_by VARCHAR(60) NULL,granted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY(asset_id,gobun),INDEX idx_cookie_trade_asset_owner(gobun)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_trade_log(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,trade_id VARCHAR(40) NOT NULL,a_gobun INT NULL,a_name VARCHAR(60) NULL,a_faction VARCHAR(80) NULL,b_gobun INT NULL,b_name VARCHAR(60) NULL,b_faction VARCHAR(80) NULL,a_offer LONGTEXT NULL,b_offer LONGTEXT NULL,status VARCHAR(20) NOT NULL DEFAULT 'completed',created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,INDEX idx_cookie_trade_gobun_a(a_gobun),INDEX idx_cookie_trade_gobun_b(b_gobun)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    print('^2[cookie_interaction]^7 secure trade server ready')
end)
CreateThread(function() while true do Wait(1000);local now=os.time();local expired={};for id,r in pairs(requests) do if now>r.expiresAt then expired[#expired+1]=id end end;for _,id in ipairs(expired) do local r=requests[id];if r then notify(r.from,'거래 요청이 만료되었습니다.',true);notify(r.to,'거래 요청이 만료되었습니다.',true);clearRequest(id) end end;local dead={};for id,s in pairs(sessions) do if now>s.expiresAt or dist(s.a,s.b)>(Config.TradeDistance or 6) then dead[#dead+1]=id end end;for _,id in ipairs(dead) do if sessions[id] then closeSession(sessions[id],'거래 시간이 만료되었거나 거리가 멀어져 취소되었습니다.',true) end end end end)
