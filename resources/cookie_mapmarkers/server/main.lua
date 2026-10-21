local function auth(src)
    local ok,v=pcall(function() return exports.cookie_admin:isAdminDuty(src,Config.AdminMinLevel or 1) end)
    return ok and v==true
end
local function ensureColumn(tableName,columnName,definition)
    local rows=MySQL.query.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName),{columnName}) or {}
    if #rows==0 then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tableName,definition)) end
end
local function rows() return MySQL.query.await('SELECT * FROM cookie_map_marker ORDER BY sort_order,id') or {} end
local function presetRows()
    local out={}
    for key,p in pairs(Config.CustomImagePresets or {}) do out[#out+1]={key=key,label=p.label,sprite=p.sprite,colour=p.colour,scale=p.scale,texture=p.texture} end
    table.sort(out,function(a,b)return tostring(a.label)<tostring(b.label)end)
    return out
end
local function broadcast() TriggerClientEvent('cookie_mapmarkers:client:set',-1,rows()) end
CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_map_marker(
      id INT AUTO_INCREMENT PRIMARY KEY,label VARCHAR(80) NOT NULL,x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL DEFAULT 0,
      sprite INT NOT NULL DEFAULT 280,colour INT NOT NULL DEFAULT 3,scale DECIMAL(4,2) NOT NULL DEFAULT 0.85,alpha INT NOT NULL DEFAULT 255,
      short_range TINYINT(1) NOT NULL DEFAULT 1,is_active TINYINT(1) NOT NULL DEFAULT 1,sort_order INT NOT NULL DEFAULT 100,
      icon_key VARCHAR(40) NULL,created_by VARCHAR(60) NULL,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    pcall(function() ensureColumn('cookie_map_marker','icon_key','`icon_key` VARCHAR(40) NULL AFTER `sort_order`') end)

    -- Keep rows created with a preset synchronized with the current custom YTD slot table.
    for key, preset in pairs(Config.CustomImagePresets or {}) do
        MySQL.update.await(
            'UPDATE cookie_map_marker SET sprite=?, colour=?, scale=? WHERE icon_key=?',
            { tonumber(preset.sprite) or Config.DefaultSprite, tonumber(preset.colour) or Config.DefaultColour, tonumber(preset.scale) or Config.DefaultScale, key }
        )
    end

    print('^2[cookie_mapmarkers]^7 native + COOKIE custom YTD map marker server ready')
end)
lib.callback.register('cookie_mapmarkers:canAdmin',function(source)return auth(source)end)
lib.callback.register('cookie_mapmarkers:adminData',function(source)
    if not auth(source)then return{ok=false}end
    return{ok=true,rows=rows(),presets=presetRows(),ytdResource=GetResourceState(Config.YtdResource or 'cookie_mapblips')=='started'}
end)
RegisterNetEvent('cookie_mapmarkers:server:request',function()TriggerClientEvent('cookie_mapmarkers:client:set',source,rows())end)
RegisterNetEvent('cookie_mapmarkers:server:save',function(d)
    local src=source;if not auth(src)or type(d)~='table'then return end
    local label=tostring(d.label or ''):gsub('^%s+',''):gsub('%s+$',''):sub(1,80);if label==''then return end
    local x,y,z=tonumber(d.x),tonumber(d.y),tonumber(d.z);if not x or not y or not z then return end
    local id=tonumber(d.id);local iconKey=tostring(d.iconKey or ''):sub(1,40);local preset=(Config.CustomImagePresets or {})[iconKey]
    local sprite=math.max(1,math.floor(tonumber(d.sprite)or Config.DefaultSprite));local colour=math.max(0,math.floor(tonumber(d.colour)or Config.DefaultColour));local scale=math.max(.25,math.min(2.0,tonumber(d.scale)or Config.DefaultScale));local alpha=math.max(40,math.min(255,math.floor(tonumber(d.alpha)or 255)))
    if preset then sprite=tonumber(preset.sprite)or sprite;colour=tonumber(preset.colour)or colour;scale=tonumber(preset.scale)or scale else iconKey='' end
    if id and id>0 then
        MySQL.update.await('UPDATE cookie_map_marker SET label=?,x=?,y=?,z=?,sprite=?,colour=?,scale=?,alpha=?,short_range=?,is_active=?,icon_key=? WHERE id=?',{label,x,y,z,sprite,colour,scale,alpha,d.shortRange==false and 0 or 1,d.active==false and 0 or 1,iconKey~='' and iconKey or nil,id})
    else
        local c=MySQL.single.await('SELECT COUNT(*) n FROM cookie_map_marker');if tonumber(c and c.n or 0)>=(Config.MaxMarkers or 300)then return end
        MySQL.insert.await('INSERT INTO cookie_map_marker(label,x,y,z,sprite,colour,scale,alpha,short_range,is_active,icon_key,created_by) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',{label,x,y,z,sprite,colour,scale,alpha,d.shortRange==false and 0 or 1,d.active==false and 0 or 1,iconKey~='' and iconKey or nil,exports.cookie_admin:getAdminName(src)or'-'})
    end
    broadcast()
end)
RegisterNetEvent('cookie_mapmarkers:server:delete',function(id)local src=source;if not auth(src)then return end;MySQL.update.await('DELETE FROM cookie_map_marker WHERE id=?',{tonumber(id)});broadcast()end)
RegisterNetEvent('cookie_mapmarkers:server:toggle',function(id,active)local src=source;if not auth(src)then return end;MySQL.update.await('UPDATE cookie_map_marker SET is_active=? WHERE id=?',{active==true and 1 or 0,tonumber(id)});broadcast()end)
