-- F3 faction intranet catalog. Server-side permissions required for every mutation.
local CrimeDefaultCatalog = {
    { code='crime_cocaine_raw',  label='코카인 원재료', price=50000, description='조직 범죄 RP용 원재료' },
    { code='crime_cannabis_raw', label='대마초 원재료', price=20000, description='조직 범죄 RP용 원재료' },
    { code='crime_meth_raw',     label='필로폰 원재료', price=45000, description='조직 범죄 RP용 원재료' },
    { code='crime_heroin_raw',   label='헤로인 원재료', price=60000, description='조직 범죄 RP용 원재료' },
}

function CookieSeedCrimeCatalog(factionId)
    factionId=tonumber(factionId)
    if not factionId then return false end
    local isCrime=MySQL.scalar.await("SELECT id FROM cookie_faction WHERE id=? AND faction_type='crime' AND is_active=1",{factionId})
    if not isCrime then return false end
    for _,v in ipairs(CrimeDefaultCatalog) do
        MySQL.query.await([[INSERT IGNORE INTO cookie_intranet_catalog(faction_id,item_code,label,description,price,active)
          VALUES (?,?,?,?,?,1)]],{factionId,v.code,v.label,v.description,v.price})
    end
    return true
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_intranet_catalog (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        faction_id INT NOT NULL,
        item_code VARCHAR(80) NOT NULL,
        label VARCHAR(100) NOT NULL,
        description VARCHAR(500) NOT NULL DEFAULT '',
        price BIGINT NOT NULL DEFAULT 0,
        active TINYINT(1) NOT NULL DEFAULT 1,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uniq_faction_item (faction_id,item_code),
        KEY idx_faction_active (faction_id,active),
        CONSTRAINT fk_ci_catalog_faction FOREIGN KEY (faction_id) REFERENCES cookie_faction(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local rows=MySQL.query.await("SELECT id FROM cookie_faction WHERE faction_type='crime' AND is_active=1") or {}
    for _,r in ipairs(rows) do pcall(CookieSeedCrimeCatalog,r.id) end
end)
local function auth(src,fid)
    if not CookieAdminTeamAuth(src,'faction') then return nil end
    fid=tonumber(fid)
    if not fid or fid%1~=0 or fid<1 then return nil end
    local exists=MySQL.scalar.await('SELECT id FROM cookie_faction WHERE id=? AND is_active=1',{fid})
    if not exists then return nil end
    return fid
end
local function send(src,fid)
    local rows=MySQL.query.await('SELECT id,item_code,label,description,price,active FROM cookie_intranet_catalog WHERE faction_id=? ORDER BY id DESC LIMIT 200',{fid}) or {}
    TriggerClientEvent('cookie_admin:ciCatalogData',src,fid,rows)
end
RegisterNetEvent('cookie_admin:ciCatalogList',function(fid)
    local src=source;fid=auth(src,fid);if not fid then return end
    send(src,fid)
end)
RegisterNetEvent('cookie_admin:ciCatalogSave',function(d)
    local src=source;if type(d)~='table' then return end
    local fid=auth(src,d.factionId);if not fid then return end
    local code=tostring(d.itemCode or '')
    local label=tostring(d.label or ''):sub(1,100)
    local description=tostring(d.description or ''):sub(1,500)
    local price=tonumber(d.price)
    if #code<1 or #code>80 or code:find('[^%w_:%-]') or #label<1 or not price or price%1~=0 or price<0 or price>2000000000 then return end
    local count=MySQL.scalar.await('SELECT COUNT(*) FROM cookie_intranet_catalog WHERE faction_id=?',{fid}) or 0
    local existing=MySQL.scalar.await('SELECT id FROM cookie_intranet_catalog WHERE faction_id=? AND item_code=?',{fid,code})
    if not existing and tonumber(count)>=200 then return end
    MySQL.query.await([[INSERT INTO cookie_intranet_catalog(faction_id,item_code,label,description,price,active)
      VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE label=VALUES(label),description=VALUES(description),price=VALUES(price),active=VALUES(active)]],
      {fid,code,label,description,price,d.active==true and 1 or 0})
    send(src,fid)
end)
RegisterNetEvent('cookie_admin:ciCatalogDelete',function(d)
    local src=source;if type(d)~='table' then return end
    local fid=auth(src,d.factionId);local id=tonumber(d.id)
    if not fid or not id or id%1~=0 or id<1 then return end
    MySQL.update.await('DELETE FROM cookie_intranet_catalog WHERE id=? AND faction_id=?',{id,fid})
    send(src,fid)
end)
