
local function storageSafeQuery(tag, sql, params)
    local ok, result = pcall(function()
        return MySQL.query.await(sql, params or {})
    end)
    if not ok then
        print(('^1[cookie_admin][storage]^7 %s query failed: %s'):format(tostring(tag), tostring(result)))
        return {}
    end
    return result or {}
end

local function storageSafeSingle(tag, sql, params)
    local ok, result = pcall(function()
        return MySQL.single.await(sql, params or {})
    end)
    if not ok then
        print(('^1[cookie_admin][storage]^7 %s query failed: %s'):format(tostring(tag), tostring(result)))
        return nil
    end
    return result
end

local function decodeMeta(raw)
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, value = pcall(json.decode, raw)
    return (ok and type(value) == 'table') and value or {}
end

local function currentCitizenId(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function normalImage(v)
    if type(v) ~= 'string' then return '' end
    return v
end

local function packedRows(citizenid)
    return storageSafeQuery('packed', [[
        SELECT
            o.id,o.reward_type,o.reward_key,o.label,o.state,o.metadata_json,o.asset_uid,o.created_at,
            COALESCE(p.grade,'') AS grade,
            COALESCE(p.image,'') AS prize_image
        FROM cookie_kuji_owned o
        LEFT JOIN cookie_kuji_draw d ON d.id=o.source_draw_id
        LEFT JOIN cookie_kuji_prize p ON p.id=d.prize_id
        WHERE o.citizenid=?
          AND o.reward_type IN ('vehicle','skin','cosmetic','furniture')
          AND o.state IN ('packed','equipped','placed')
        ORDER BY o.id DESC
    ]], { citizenid })
end

local function vehicleImageMap()
    local out={}
    for _,row in ipairs(storageSafeQuery('vehicle_images',
        'SELECT LOWER(model) AS model,image FROM cookie_vehicle_image', {})) do
        out[tostring(row.model or '')]=row.image or ''
    end
    return out
end

local function vehicleLabelMap()
    local out={}
    for _,row in ipairs(storageSafeQuery('vehicle_labels_general',
        'SELECT LOWER(model) AS model,display_name AS label FROM cookie_dealership_vehicles', {})) do
        out[tostring(row.model or '')]=row.label
    end
    for _,row in ipairs(storageSafeQuery('vehicle_labels_limited',
        'SELECT LOWER(model) AS model,label FROM cookie_limited_vehicles', {})) do
        out[tostring(row.model or '')]=row.label
    end
    return out
end

local function limitedVehicleMap()
    local out={}
    for _,row in ipairs(storageSafeQuery('vehicle_limited_models','SELECT LOWER(model) AS model FROM cookie_limited_vehicles', {})) do
        out[tostring(row.model or '')]=true
    end
    return out
end

local function garageVehicles(citizenid, images, labels)
    local rows=storageSafeQuery('garage_vehicles',[[
        SELECT id,LOWER(vehicle) AS model,plate,garage,state,cookie_asset_uid
        FROM player_vehicles
        WHERE citizenid=?
        ORDER BY id DESC
    ]],{citizenid})

    local out={}
    for _,r in ipairs(rows) do
        local model=tostring(r.model or '')
        local state=tonumber(r.state) or 0
        local stateLabel=(state==1 and '차고 보관') or (state==0 and '출고 중') or (state==2 and '압류/보관') or ('상태 '..state)
        out[#out+1]={
            id='garage:'..tostring(r.id),
            kind='vehicle',
            source='garage',
            packed=false,
            key=model,
            label=labels[model] or model,
            image=normalImage(images[model]),
            rarity='일반',
            state=stateLabel,
            description='현재 차량 DB에 등록된 보유 차량입니다.',
            meta={
                model=model,
                plate=tostring(r.plate or '-'),
                garage=tostring(r.garage or '-'),
                assetUid=tostring(r.cookie_asset_uid or '-'),
            }
        }
    end
    return out
end

local function packedAsset(row, images)
    local meta=decodeMeta(row.metadata_json)
    local typ=tostring(row.reward_type or '')
    local key=tostring(row.reward_key or '')
    local image=tostring(row.prize_image or '')
    if image=='' then image=tostring(meta.image or '') end
    if image=='' and typ=='vehicle' then image=tostring(images[key:lower()] or '') end
    if image=='' and (typ=='cosmetic' or typ=='furniture') and key~='' then
        image='nui://ox_inventory/web/images/'..key..'.png'
    end

    local state=tostring(row.state or 'packed')
    local stateLabel=(state=='packed' and '보관 중')
        or (state=='equipped' and '장착 중')
        or (state=='placed' and '설치됨')
        or state
    local desc=tostring(meta.description or '')
    if desc=='' then
        if typ=='vehicle' then desc='포장 상태로 보관 중인 차량입니다.'
        elseif typ=='skin' then desc='보유 중인 한정/영구 스킨입니다.'
        elseif typ=='cosmetic' then desc='보유 중인 치장 아이템입니다.'
        elseif typ=='furniture' then desc='보유 중인 의자·가구 아이템입니다.'
        end
    end

    local infoMeta={}
    if typ=='vehicle' then
        infoMeta.model=tostring(meta.model or key)
        infoMeta.plate=tostring(meta.plate or meta.numberplate or '-')
        infoMeta.assetUid=tostring(row.asset_uid or meta.asset_uid or '-')
        if meta.upgrade ~= nil then infoMeta.upgrade=tostring(meta.upgrade) end
        if meta.color ~= nil then infoMeta.color=tostring(meta.color) end
        if meta.packaged_vehicle ~= nil then infoMeta.packaged_vehicle = meta.packaged_vehicle end
        if meta.limited ~= nil then infoMeta.limited = meta.limited end
    else
        infoMeta.key=key
    end

    return {
        id='packed:'..tostring(row.id),
        kind=typ,
        source='packed',
        packed=(state=='packed'),
        key=key,
        label=tostring(row.label or key),
        image=image,
        rarity=tostring(row.grade or meta.grade or '보유'),
        state=stateLabel,
        description=desc,
        meta=infoMeta,
    }
end


function CookieBuildPersonalStorage(src)
    local cid=currentCitizenId(src)
    if not cid then
        return { vehicle={}, cosmetic={}, chair={}, skin={}, equippedSkin=nil, summary={vehicle=0,cosmetic=0,chair=0,skin=0} }
    end

    local images=vehicleImageMap()
    local limitedModels=limitedVehicleMap()
    local packed=packedRows(cid)

    local data={
        vehicle={},
        cosmetic={},
        chair={},
        skin={},
        equippedSkin=nil,
        summary={vehicle=0,cosmetic=0,chair=0,skin=0},
    }

    for _,r in ipairs(packed) do
        local item=packedAsset(r,images)
        if item.kind=='vehicle' then
            local modelKey = tostring(item.key or ''):lower()
            local metaLimited = item.meta and (item.meta.limited == true or item.meta.packaged_vehicle == true)
            if item.packed and (limitedModels[modelKey] or metaLimited) then
                data.vehicle[#data.vehicle+1]=item
            end
        elseif item.kind=='cosmetic' then
            data.cosmetic[#data.cosmetic+1]=item
        elseif item.kind=='furniture' then
            data.chair[#data.chair+1]=item
        elseif item.kind=='skin' then
            if tostring(r.state or '') == 'equipped' then
                data.equippedSkin=item
                data.equippedSkin.state='장착 중'
            else
                data.skin[#data.skin+1]=item
            end
        end
    end

    data.summary.vehicle=#data.vehicle
    data.summary.cosmetic=#data.cosmetic
    data.summary.chair=#data.chair
    data.summary.skin=#data.skin
    return data
end
exports('GetPersonalStorage',function(src)
    return CookieBuildPersonalStorage(tonumber(src))
end)

RegisterNetEvent('cookie_admin:server:requestPersonalStorage',function()
    local src=source
    TriggerClientEvent('cookie_admin:client:personalStorage',src,CookieBuildPersonalStorage(src))
end)

print('^2[cookie_admin]^7 PERSONAL STORAGE SERVER V1.8.0 ready')
