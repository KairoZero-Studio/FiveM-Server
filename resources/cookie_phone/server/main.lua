print('^2[COOKIE PHONE]^7 build 20260829-MSGPHOTO-CAMFIX loaded')
-- COOKIE PHONE V2 - CALL SERVER
-- Uses Qbox charinfo.phone and PMA-Voice call channels.

local activeCalls = {}
local playerCall = {}
local nextCallId = 1000
local nextVoiceChannel = 70000

-- Contacts / AirDrop-style contact card sharing
local phoneOpen = {}
local pendingShares = {}
local shareCooldown = {}
local nextShareId = 5000

-- COOKIE BANK
local bankTransferLocks = {}
local bankTransferCooldown = {}

local function cookieDispatchLog(category, title, description, fields, options)
    if GetResourceState('cookie_logs') ~= 'started' then return end
    pcall(function()
        exports.cookie_logs:Log(category, title, description, fields or {}, options or {})
    end)
end



local function normalizePhone(value)
    local s = tostring(value or ''):gsub('%D', '')
    if #s > 16 then s = s:sub(1, 16) end
    return s
end

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function getPlayer(src)
    local ok, player = pcall(function()
        return exports.qbx_core:GetPlayer(src)
    end)
    if ok then return player end
end

-- COOKIE 서버의 실제/공식 전화번호는 cookie_user.phone 입니다.
-- ESC 정보창도 이 값을 먼저 사용하므로 휴대전화 역시 같은 번호를 사용합니다.
local function getCookiePhoneByLicense(license)
    if not license then return '' end
    local row = MySQL.single.await(
        'SELECT phone FROM cookie_user WHERE license = ? LIMIT 1',
        { license }
    )
    return row and tostring(row.phone or '') or ''
end

local function playerIdentity(src)
    local player = getPlayer(src)
    if not player or not player.PlayerData then return nil end

    local pd = player.PlayerData
    local license = getLicense(src)
    local cookiePhone = getCookiePhoneByLicense(license)

    -- cookie_user.phone이 아직 발급되지 않은 특수 상황에서만 Qbox 번호를 폴백으로 사용.
    local qboxPhone = pd.charinfo and pd.charinfo.phone or ''
    local phone = cookiePhone ~= '' and cookiePhone or qboxPhone

    return {
        source = tonumber(src),
        license = tostring(license or ''),
        citizenid = tostring(pd.citizenid or ''),
        phone = normalizePhone(phone),
        phoneDisplay = tostring(phone or ''),
    }
end

local function sourceByLicense(targetLicense)
    if not targetLicense or targetLicense == '' then return nil end
    for _, raw in ipairs(GetPlayers()) do
        local sid = tonumber(raw)
        if sid and getLicense(sid) == targetLicense then
            return sid
        end
    end
end

local function getPhoneOwner(number)
    number = normalizePhone(number)
    if number == '' then return nil end

    return MySQL.single.await([[
        SELECT license, phone
        FROM cookie_user
        WHERE REPLACE(REPLACE(REPLACE(phone, '-', ''), ' ', ''), '.', '') = ?
        LIMIT 1
    ]], { number })
end

local function getOnlineByPhone(number)
    local owner = getPhoneOwner(number)
    if not owner or not owner.license then return nil, owner end

    local sid = sourceByLicense(owner.license)
    if not sid then return nil, owner end

    return playerIdentity(sid), owner
end


local function cleanText(value, maxLen)
    local text = tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #text > maxLen then text = text:sub(1, maxLen) end
    return text
end

local function cleanAvatar(value)
    local avatar = tostring(value or '')
    if avatar == '' then return '' end
    if #avatar > 380000 then return '' end
    if not avatar:match('^data:image/[a-zA-Z0-9%+%-%.]+;base64,') then return '' end
    return avatar
end

local PHONE_GALLERY_LIMIT = 36
local captureBusy = {}

local function cleanGalleryImage(value)
    local image = tostring(value or '')
    if image == '' then return '' end
    if #image > 1800000 then return '' end
    local valid = image:match('^data:image/webp;base64,') or image:match('^data:image/jpeg;base64,') or image:match('^data:image/jpg;base64,') or image:match('^data:image/png;base64,')
    if not valid then return '' end
    return image
end

local function getGalleryPhoto(license, photoId)
    photoId = tonumber(photoId)
    if not license or license == '' or not photoId or photoId <= 0 then return nil end
    return MySQL.single.await([[
        SELECT id, image_data, orientation, camera_mode, zoom, UNIX_TIMESTAMP(created_at) AS created_ts
        FROM cookie_phone_gallery
        WHERE id = ? AND owner_license = ?
        LIMIT 1
    ]], { photoId, license })
end

local function ensureMessagePhoto(ownerLicense, galleryPhotoId)
    local photo = getGalleryPhoto(ownerLicense, galleryPhotoId)
    if not photo then return nil, nil end
    local image = cleanGalleryImage(photo.image_data)
    if image == '' then return nil, nil end

    local existing = MySQL.single.await([[
        SELECT id, image_data, orientation
        FROM cookie_phone_message_photos
        WHERE owner_license = ? AND source_gallery_id = ?
        LIMIT 1
    ]], { ownerLicense, tonumber(galleryPhotoId) })

    if not existing then
        pcall(function()
            MySQL.insert.await([[
                INSERT IGNORE INTO cookie_phone_message_photos
                    (owner_license, source_gallery_id, image_data, orientation)
                VALUES (?, ?, ?, ?)
            ]], {
                ownerLicense, tonumber(galleryPhotoId), image,
                photo.orientation == 'portrait' and 'portrait' or 'landscape'
            })
        end)
        existing = MySQL.single.await([[
            SELECT id, image_data, orientation
            FROM cookie_phone_message_photos
            WHERE owner_license = ? AND source_gallery_id = ?
            LIMIT 1
        ]], { ownerLicense, tonumber(galleryPhotoId) })
    end

    if not existing then return nil, nil end
    return tonumber(existing.id), {
        image = cleanGalleryImage(existing.image_data),
        orientation = existing.orientation == 'portrait' and 'portrait' or 'landscape',
    }
end

local function galleryRowsFor(license)
    if not license or license == '' then return {} end
    local rows = MySQL.query.await([[
        SELECT id, image_data, orientation, camera_mode, zoom, UNIX_TIMESTAMP(created_at) AS created_ts
        FROM cookie_phone_gallery
        WHERE owner_license = ?
        ORDER BY id DESC
        LIMIT 36
    ]], { license }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local image = cleanGalleryImage(row.image_data)
        if image ~= '' then
            out[#out + 1] = {
                id = tonumber(row.id),
                image = image,
                createdAt = tonumber(row.created_ts) or 0,
                orientation = row.orientation == 'portrait' and 'portrait' or 'landscape',
                cameraMode = row.camera_mode == 'front' and 'front' or 'rear',
                zoom = tonumber(row.zoom) or 1.0,
            }
        end
    end
    return out
end

local function sendGallery(src)
    local ident = playerIdentity(src)
    if not ident then return end
    TriggerLatentClientEvent('cookie_phone:client:gallery', src, 1048576, {
        rows = galleryRowsFor(ident.license)
    })
end

local function defaultProfileName(src)
    local player = getPlayer(src)
    local charinfo = player and player.PlayerData and player.PlayerData.charinfo or {}
    local first = cleanText(charinfo and charinfo.firstname, 24)
    local last = cleanText(charinfo and charinfo.lastname, 24)
    local full = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
    if full ~= '' then return full:sub(1, 40) end
    return ('시민 %s'):format(src)
end

local function ensureProfile(src, ident)
    ident = ident or playerIdentity(src)
    if not ident or ident.license == '' then return nil end

    local row = MySQL.single.await([[
        SELECT display_name, avatar, avatar_photo_id
        FROM cookie_phone_profile
        WHERE license = ?
        LIMIT 1
    ]], { ident.license })

    if not row then
        local name = defaultProfileName(src)
        MySQL.insert.await([[
            INSERT INTO cookie_phone_profile (license, phone, display_name, avatar)
            VALUES (?, ?, ?, '')
        ]], { ident.license, ident.phone, name })
        return { display_name = name, avatar = '', avatar_photo_id = nil }
    end

    if normalizePhone(row.phone or '') ~= ident.phone then
        MySQL.update.await(
            'UPDATE cookie_phone_profile SET phone = ? WHERE license = ?',
            { ident.phone, ident.license }
        )
    end

    return {
        display_name = cleanText(row.display_name, 40),
        avatar = cleanAvatar(row.avatar),
        avatar_photo_id = tonumber(row.avatar_photo_id),
    }
end

local function getContacts(ident)
    if not ident or ident.license == '' then return {} end

    local rows = MySQL.query.await([[
        SELECT id, contact_phone, contact_name, avatar, note, favorite, blocked,
               source_license, UNIX_TIMESTAMP(updated_at) AS updated_ts
        FROM cookie_phone_contacts
        WHERE owner_license = ?
        ORDER BY favorite DESC, contact_name ASC, id ASC
    ]], { ident.license }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            id = tonumber(row.id),
            phone = normalizePhone(row.contact_phone),
            name = cleanText(row.contact_name, 40),
            avatar = cleanAvatar(row.avatar),
            note = cleanText(row.note, 160),
            favorite = row.favorite == 1 or row.favorite == true,
            blocked = row.blocked == 1 or row.blocked == true,
            sourceLicense = tostring(row.source_license or ''),
            updatedAt = tonumber(row.updated_ts) or 0,
        }
    end
    return out
end

local function upsertContact(ownerIdent, data)
    if not ownerIdent or ownerIdent.license == '' then return false, 'owner' end

    local number = normalizePhone(data and (data.phone or data.contactPhone))
    if number == '' or #number < 4 then return false, 'number' end
    if number == ownerIdent.phone then return false, 'self' end

    local name = cleanText(data and (data.name or data.contactName), 40)
    if name == '' then name = number end

    local note = cleanText(data and data.note, 160)
    local avatar = cleanAvatar(data and data.avatar)
    local favorite = data and (data.favorite == true or data.favorite == 1) and 1 or 0
    local blocked = data and (data.blocked == true or data.blocked == 1) and 1 or 0
    local sourceLicense = cleanText(data and data.sourceLicense, 255)

    MySQL.query.await([[
        INSERT INTO cookie_phone_contacts
            (owner_license, contact_phone, contact_name, avatar, note, favorite, blocked, source_license)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            contact_name = VALUES(contact_name),
            avatar = CASE WHEN VALUES(avatar) <> '' THEN VALUES(avatar) ELSE avatar END,
            note = VALUES(note),
            favorite = VALUES(favorite),
            blocked = VALUES(blocked),
            source_license = CASE WHEN VALUES(source_license) <> '' THEN VALUES(source_license) ELSE source_license END,
            updated_at = CURRENT_TIMESTAMP
    ]], {
        ownerIdent.license, number, name, avatar, note, favorite, blocked, sourceLicense
    })

    return true, number
end

local function playerDistance(a, b)
    local pedA = GetPlayerPed(a)
    local pedB = GetPlayerPed(b)
    if not pedA or pedA == 0 or not pedB or pedB == 0 then return 9999.0 end
    local ca = GetEntityCoords(pedA)
    local cb = GetEntityCoords(pedB)
    return #(ca - cb)
end

local function publicProfile(src)
    local ident = playerIdentity(src)
    if not ident then return nil end
    local profile = ensureProfile(src, ident) or {}
    return {
        source = src,
        phone = ident.phone,
        name = cleanText(profile.display_name, 40),
        avatar = cleanAvatar(profile.avatar),
        photoId = tonumber(profile.avatar_photo_id) or 0,
    }
end


local function phoneOwnerByNumber(number)
    number = normalizePhone(number)
    if number == '' then return nil end

    local row = MySQL.single.await([[
        SELECT license, phone
        FROM cookie_user
        WHERE REPLACE(REPLACE(REPLACE(phone, '-', ''), ' ', ''), '.', '') = ?
        LIMIT 1
    ]], { number })

    if not row then return nil end
    return {
        license = tostring(row.license or ''),
        phone = normalizePhone(row.phone),
    }
end

local function profileByLicense(license)
    if not license or license == '' then return { name = '', avatar = '' } end
    local row = MySQL.single.await([[
        SELECT display_name, avatar
        FROM cookie_phone_profile
        WHERE license = ?
        LIMIT 1
    ]], { license })

    return {
        name = cleanText(row and row.display_name or '', 40),
        avatar = cleanAvatar(row and row.avatar or ''),
    }
end

local function getContactByPhone(ownerLicense, phone)
    local row = MySQL.single.await([[
        SELECT id, contact_name, avatar, favorite, blocked, note
        FROM cookie_phone_contacts
        WHERE owner_license = ? AND contact_phone = ?
        LIMIT 1
    ]], { ownerLicense, normalizePhone(phone) })

    if not row then return nil end
    return {
        id = tonumber(row.id),
        name = cleanText(row.contact_name, 40),
        avatar = cleanAvatar(row.avatar),
        favorite = row.favorite == 1 or row.favorite == true,
        blocked = row.blocked == 1 or row.blocked == true,
        note = cleanText(row.note, 160),
    }
end

local function isPhoneBlocked(receiverLicense, senderPhone)
    local row = MySQL.single.await([[
        SELECT id
        FROM cookie_phone_contacts
        WHERE owner_license = ? AND contact_phone = ? AND blocked = 1
        LIMIT 1
    ]], { receiverLicense, normalizePhone(senderPhone) })
    return row ~= nil
end

local function getConversationList(ident)
    if not ident or ident.license == '' then return {}, 0 end

    local rows = MySQL.query.await([[
        SELECT m.id, m.sender_license, m.sender_phone, m.receiver_license, m.receiver_phone,
               m.body, m.photo_media_id, m.sent_at,
               UNIX_TIMESTAMP(m.sent_at) AS sent_ts,
               UNIX_TIMESTAMP(m.read_at) AS read_ts
        FROM cookie_phone_messages m
        INNER JOIN (
            SELECT
              CASE
                WHEN sender_license = ? THEN receiver_license
                ELSE sender_license
              END AS other_license,
              MAX(id) AS latest_id
            FROM cookie_phone_messages
            WHERE sender_license = ? OR receiver_license = ?
            GROUP BY other_license
        ) x ON x.latest_id = m.id
        ORDER BY m.id DESC
        LIMIT 80
    ]], { ident.license, ident.license, ident.license }) or {}

    local unreadRows = MySQL.query.await([[
        SELECT sender_license, COUNT(*) AS cnt
        FROM cookie_phone_messages
        WHERE receiver_license = ? AND read_at IS NULL
        GROUP BY sender_license
    ]], { ident.license }) or {}

    local unreadMap = {}
    local totalUnread = 0
    for _, row in ipairs(unreadRows) do
        local count = tonumber(row.cnt) or 0
        unreadMap[tostring(row.sender_license or '')] = count
        totalUnread = totalUnread + count
    end

    local out = {}
    for _, row in ipairs(rows) do
        local outgoing = tostring(row.sender_license or '') == ident.license
        local otherLicense = outgoing and tostring(row.receiver_license or '') or tostring(row.sender_license or '')
        local otherPhone = outgoing and normalizePhone(row.receiver_phone) or normalizePhone(row.sender_phone)
        local contact = getContactByPhone(ident.license, otherPhone)

        out[#out + 1] = {
            license = otherLicense,
            phone = otherPhone,
            name = contact and contact.name or '',
            avatar = contact and contact.avatar or '',
            favorite = contact and contact.favorite or false,
            blocked = contact and contact.blocked or false,
            lastBody = cleanText(row.body, 500),
            lastHasPhoto = tonumber(row.photo_media_id) ~= nil and tonumber(row.photo_media_id) > 0 or false,
            lastAt = tonumber(row.sent_ts) or 0,
            unread = unreadMap[otherLicense] or 0,
            outgoing = outgoing,
        }
    end

    return out, totalUnread
end

local function getMessages(ident, otherLicense, limit)
    if not ident or ident.license == '' or not otherLicense or otherLicense == '' then return {} end
    limit = math.max(10, math.min(120, tonumber(limit) or 80))

    local rows = MySQL.query.await(([[
        SELECT m.id, m.sender_license, m.sender_phone, m.receiver_license, m.receiver_phone,
               m.body, m.photo_media_id, p.image_data AS photo_image, p.orientation AS photo_orientation,
               UNIX_TIMESTAMP(m.sent_at) AS sent_ts,
               UNIX_TIMESTAMP(m.read_at) AS read_ts
        FROM cookie_phone_messages m
        LEFT JOIN cookie_phone_message_photos p ON p.id = m.photo_media_id
        WHERE (m.sender_license = ? AND m.receiver_license = ?)
           OR (m.sender_license = ? AND m.receiver_license = ?)
        ORDER BY m.id DESC
        LIMIT %d
    ]]):format(limit), {
        ident.license, otherLicense,
        otherLicense, ident.license,
    }) or {}

    local out = {}
    for i = #rows, 1, -1 do
        local row = rows[i]
        out[#out + 1] = {
            id = tonumber(row.id),
            outgoing = tostring(row.sender_license or '') == ident.license,
            body = cleanText(row.body, 500),
            photo = cleanGalleryImage(row.photo_image),
            photoOrientation = row.photo_orientation == 'portrait' and 'portrait' or 'landscape',
            sentAt = tonumber(row.sent_ts) or 0,
            readAt = tonumber(row.read_ts) or 0,
        }
    end
    return out
end

local function sendMessageState(src)
    local ident = playerIdentity(src)
    if not ident then return end
    local conversations, unread = getConversationList(ident)
    TriggerClientEvent('cookie_phone:client:messagesState', src, {
        conversations = conversations,
        unread = unread,
    })
end


local PHONE_THEME_DEFAULTS = {
    accent = '#F0C85B',
    accent2 = '#C69A2B',
    wallpaper = 'cookie-bakery',
    customWallpaper = '',
    blur = 0,
    dim = 18,
    glass = 46,
}

local allowedWallpapers = {
    ['solid-black'] = true,
    ['solid-white'] = true,
    ['starry-night'] = true,
    ['caramel-gloss'] = true,
    ['pink-flower'] = true,
    ['cookie-bakery'] = true,
    ['mint-glass'] = true,
    ['lavender-aurora'] = true,
}

local function cleanHex(value, fallback)
    local v = tostring(value or ''):upper()
    if v:match('^#[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$') then return v end
    return fallback
end

local function cleanThemeImage(value)
    local image = tostring(value or '')
    if image == '' then return '' end
    if #image > 1400000 then return '' end

    local mime = image:match('^data:image/([%w%+%-%.]+);base64,')
    if mime ~= 'jpeg' and mime ~= 'jpg' and mime ~= 'png' and mime ~= 'webp' then
        return ''
    end

    return image
end

local function clampInt(value, minV, maxV, fallback)
    local n = math.floor(tonumber(value) or fallback)
    if n < minV then n = minV end
    if n > maxV then n = maxV end
    return n
end

local function getPhoneSettings(license)
    local d = PHONE_THEME_DEFAULTS
    if not license or license == '' then return d end
    local row = MySQL.single.await([[
        SELECT accent, accent2, wallpaper, custom_wallpaper, blur, dim, glass
        FROM cookie_phone_settings
        WHERE license = ?
        LIMIT 1
    ]], { license })

    if not row then
        return {
            accent = d.accent, accent2 = d.accent2, wallpaper = d.wallpaper,
            customWallpaper = d.customWallpaper, blur = d.blur, dim = d.dim, glass = d.glass,
        }
    end

    local wp = tostring(row.wallpaper or d.wallpaper)
    if not allowedWallpapers[wp] then wp = d.wallpaper end
    local custom = ''

    return {
        accent = cleanHex(row.accent, d.accent),
        accent2 = cleanHex(row.accent2, d.accent2),
        wallpaper = wp,
        customWallpaper = custom,
        blur = clampInt(row.blur, 0, 24, d.blur),
        dim = clampInt(row.dim, 0, 55, d.dim),
        glass = clampInt(row.glass, 20, 85, d.glass),
    }
end

local function savePhoneSettings(license, data)
    if not license or license == '' then return nil end
    data = type(data) == 'table' and data or {}
    local d = PHONE_THEME_DEFAULTS
    local wallpaper = tostring(data.wallpaper or d.wallpaper)
    if not allowedWallpapers[wallpaper] then wallpaper = d.wallpaper end

    local custom = ''

    local settings = {
        accent = cleanHex(data.accent, d.accent),
        accent2 = cleanHex(data.accent2, d.accent2),
        wallpaper = wallpaper,
        customWallpaper = custom,
        blur = clampInt(data.blur, 0, 24, d.blur),
        dim = clampInt(data.dim, 0, 55, d.dim),
        glass = clampInt(data.glass, 20, 85, d.glass),
    }

    MySQL.query.await([[
        INSERT INTO cookie_phone_settings
            (license, accent, accent2, wallpaper, custom_wallpaper, blur, dim, glass)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            accent = VALUES(accent),
            accent2 = VALUES(accent2),
            wallpaper = VALUES(wallpaper),
            custom_wallpaper = VALUES(custom_wallpaper),
            blur = VALUES(blur),
            dim = VALUES(dim),
            glass = VALUES(glass),
            updated_at = CURRENT_TIMESTAMP
    ]], {
        license, settings.accent, settings.accent2, settings.wallpaper,
        settings.customWallpaper, settings.blur, settings.dim, settings.glass
    })

    return settings
end


local function bankCitizenIdByLicense(license)
    if not license or license == '' then return nil end
    local row = MySQL.single.await(
        'SELECT citizenid FROM players WHERE license = ? LIMIT 1',
        { license }
    )
    return row and tostring(row.citizenid or '') or nil
end

local function bankBalance(src)
    local amount = exports.qbx_core:GetMoney(src, 'bank')
    return math.max(0, math.floor(tonumber(amount) or 0))
end

local function bankTransferHistory(ident)
    if not ident or ident.license == '' then return {} end

    local rows = MySQL.query.await([[
        SELECT id, sender_license, sender_phone, receiver_license, receiver_phone,
               amount, memo, transfer_mode,
               UNIX_TIMESTAMP(created_at) AS created_ts
        FROM cookie_phone_bank_transfer
        WHERE sender_license = ? OR receiver_license = ?
        ORDER BY id DESC
        LIMIT 40
    ]], { ident.license, ident.license }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local outgoing = tostring(row.sender_license or '') == ident.license
        out[#out + 1] = {
            id = tonumber(row.id),
            direction = outgoing and 'outgoing' or 'incoming',
            phone = outgoing and normalizePhone(row.receiver_phone) or normalizePhone(row.sender_phone),
            amount = math.max(0, math.floor(tonumber(row.amount) or 0)),
            memo = cleanText(row.memo, 80),
            mode = tostring(row.transfer_mode or 'phone'),
            createdAt = tonumber(row.created_ts) or 0,
        }
    end
    return out
end

local function sendBankState(src)
    if not src or not GetPlayerName(src) then return end
    local ident = playerIdentity(src)
    if not ident then return end

    TriggerClientEvent('cookie_phone:client:bankState', src, {
        balance = bankBalance(src),
        phone = ident.phone,
        history = bankTransferHistory(ident),
    })
end

local function bankNotify(src, message, isError)
    if not src or not GetPlayerName(src) then return end
    TriggerClientEvent('cookie_phone:client:bankNotice', src, {
        message = tostring(message or ''),
        isError = isError == true,
    })
end

local function bankWriteRenewedHistory(sender, receiver, amount, memo, targetOnline)
    if GetResourceState('Renewed-Banking') ~= 'started' then return end

    local senderProfile = profileByLicense(sender.license)
    local receiverProfile = profileByLicense(receiver.license)
    local senderName = senderProfile.name ~= '' and senderProfile.name or sender.phone
    local receiverName = receiverProfile.name ~= '' and receiverProfile.name or receiver.phone
    local title = 'COOKIE PHONE 송금'
    local comment = memo ~= '' and memo or '휴대전화 송금'

    local ok, transaction = pcall(function()
        return exports['Renewed-Banking']:handleTransaction(
            sender.citizenid,
            title,
            amount,
            comment,
            senderName,
            receiverName,
            'withdraw'
        )
    end)

    -- Renewed-Banking caches online players. Avoid noisy invalid-account errors
    -- for offline recipients; our own COOKIE BANK history always records it.
    if ok and transaction and targetOnline and receiver.citizenid and receiver.citizenid ~= '' then
        pcall(function()
            exports['Renewed-Banking']:handleTransaction(
                receiver.citizenid,
                title,
                amount,
                comment,
                senderName,
                receiverName,
                'deposit',
                transaction.trans_id
            )
        end)
    end
end

local function bankTransfer(src, request)
    request = type(request) == 'table' and request or {}
    local ident = playerIdentity(src)
    if not ident then return false, '플레이어 정보를 불러올 수 없습니다.' end

    local now = GetGameTimer()
    if bankTransferCooldown[src] and now - bankTransferCooldown[src] < 850 then
        return false, '잠시 후 다시 시도하세요.'
    end
    bankTransferCooldown[src] = now

    local amount = math.floor(tonumber(request.amount) or 0)
    if amount < 1 then return false, '송금 금액을 입력하세요.' end
    if amount > 100000000 then return false, '한 번에 최대 100,000,000원까지 송금할 수 있습니다.' end

    local memo = cleanText(request.memo, 80)
    local mode = tostring(request.mode or 'phone')
    local targetOwner, targetSrc

    if mode == 'nearby' then
        targetSrc = tonumber(request.targetSource)
        if not targetSrc or targetSrc == src or not GetPlayerName(targetSrc) then
            return false, '근처 송금 대상을 찾을 수 없습니다.'
        end
        if not phoneOpen[src] or not phoneOpen[targetSrc] then
            return false, '서로 휴대전화를 켠 상태에서 이용하세요.'
        end
        if playerDistance(src, targetSrc) > 4.5 then
            return false, '상대방이 너무 멀리 있습니다.'
        end

        local targetIdent = playerIdentity(targetSrc)
        if not targetIdent then return false, '상대방 정보를 불러올 수 없습니다.' end
        targetOwner = { license = targetIdent.license, phone = targetIdent.phone }
    else
        mode = 'phone'
        local number = normalizePhone(request.phone)
        if #number < 4 then return false, '전화번호를 정확히 입력하세요.' end
        targetOwner = phoneOwnerByNumber(number)
        if not targetOwner or not targetOwner.license then
            return false, '존재하지 않는 전화번호입니다.'
        end
        targetSrc = sourceByLicense(targetOwner.license)
    end

    local receiverLicense = tostring(targetOwner.license or '')
    local receiverPhone = normalizePhone(targetOwner.phone)
    if receiverLicense == '' or receiverPhone == '' then
        return false, '수신 계좌 정보를 불러올 수 없습니다.'
    end
    if receiverLicense == ident.license or receiverPhone == ident.phone then
        return false, '본인에게는 송금할 수 없습니다.'
    end

    local receiverCitizenId = bankCitizenIdByLicense(receiverLicense)
    if not receiverCitizenId or receiverCitizenId == '' then
        return false, '수신자의 은행 계좌를 찾을 수 없습니다.'
    end

    if bankTransferLocks[ident.license] or bankTransferLocks[receiverLicense] then
        return false, '다른 송금이 처리 중입니다. 잠시 후 다시 시도하세요.'
    end

    bankTransferLocks[ident.license] = true
    bankTransferLocks[receiverLicense] = true

    local function unlock()
        bankTransferLocks[ident.license] = nil
        bankTransferLocks[receiverLicense] = nil
    end

    local balance = bankBalance(src)
    if balance < amount then
        unlock()
        return false, '은행 잔액이 부족합니다.'
    end

    local reason = ('COOKIE PHONE 송금 → %s'):format(receiverPhone)
    local removed = exports.qbx_core:RemoveMoney(src, 'bank', amount, reason)
    if removed == false then
        unlock()
        return false, '송금 금액을 출금하지 못했습니다.'
    end

    local added = exports.qbx_core:AddMoney(receiverCitizenId, 'bank', amount, ('COOKIE PHONE 입금 ← %s'):format(ident.phone))
    if added == false then
        -- Rollback sender money if target credit fails.
        exports.qbx_core:AddMoney(src, 'bank', amount, 'COOKIE PHONE 송금 실패 환불')
        unlock()
        return false, '수신 계좌 입금에 실패했습니다. 금액은 환불되었습니다.'
    end

    MySQL.insert.await([[
        INSERT INTO cookie_phone_bank_transfer
            (sender_license, sender_phone, receiver_license, receiver_phone, amount, memo, transfer_mode)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        ident.license, ident.phone,
        receiverLicense, receiverPhone,
        amount, memo, mode
    })

    local receiver = {
        license = receiverLicense,
        phone = receiverPhone,
        citizenid = receiverCitizenId,
    }
    bankWriteRenewedHistory(ident, receiver, amount, memo, targetSrc ~= nil)

    unlock()

    sendBankState(src)
    bankNotify(src, ('%s원 송금이 완료되었습니다.'):format(amount), false)

    if targetSrc and GetPlayerName(targetSrc) then
        sendBankState(targetSrc)
        TriggerClientEvent('cookie_phone:client:bankIncoming', targetSrc, {
            amount = amount,
            fromPhone = ident.phone,
            memo = memo,
            mode = mode,
        })
    end

    return true
end

local function allocateCall()
    nextCallId = nextCallId + 1
    if nextCallId > 999999 then nextCallId = 1001 end

    nextVoiceChannel = nextVoiceChannel + 1
    if nextVoiceChannel > 89999 then nextVoiceChannel = 70001 end

    return nextCallId, nextVoiceChannel
end

local function pmaSetCall(src, channel)
    if GetResourceState('pma-voice') ~= 'started' then
        return false, 'pma-voice_not_started'
    end

    local ok, err = pcall(function()
        exports['pma-voice']:setPlayerCall(src, channel)
    end)
    return ok, err
end

local function sendError(src, message)
    TriggerClientEvent('cookie_phone:client:error', src, tostring(message or '전화 처리 중 오류가 발생했습니다.'))
end

local function sendPhoneData(src)
    local ident = playerIdentity(src)
    if not ident or ident.phone == '' then
        return TriggerClientEvent('cookie_phone:client:data', src, {
            phone = '',
            profile = { name = '', avatar = '' },
            contacts = {},
            history = {},
        })
    end

    local profile = ensureProfile(src, ident) or { display_name = defaultProfileName(src), avatar = '' }
    local contacts = getContacts(ident)

    local rows = MySQL.query.await([[
        SELECT id, caller_license, caller_citizenid, caller_phone,
               callee_license, callee_citizenid, callee_phone,
               UNIX_TIMESTAMP(started_at) AS started_ts,
               UNIX_TIMESTAMP(answered_at) AS answered_ts,
               UNIX_TIMESTAMP(ended_at) AS ended_ts,
               status, duration_sec
        FROM cookie_phone_calls
        WHERE caller_license = ? OR callee_license = ?
           OR ((caller_license IS NULL OR caller_license = '') AND caller_citizenid = ?)
           OR ((callee_license IS NULL OR callee_license = '') AND callee_citizenid = ?)
        ORDER BY id DESC
        LIMIT 40
    ]], { ident.license, ident.license, ident.citizenid, ident.citizenid }) or {}

    local history = {}
    for _, row in ipairs(rows) do
        local outgoing =
            (tostring(row.caller_license or '') ~= '' and tostring(row.caller_license) == ident.license)
            or ((row.caller_license == nil or tostring(row.caller_license) == '') and tostring(row.caller_citizenid or '') == ident.citizenid)

        history[#history + 1] = {
            id = row.id,
            direction = outgoing and 'outgoing' or 'incoming',
            number = outgoing and normalizePhone(row.callee_phone) or normalizePhone(row.caller_phone),
            status = tostring(row.status or 'ended'),
            startedAt = tonumber(row.started_ts) or 0,
            answeredAt = tonumber(row.answered_ts) or 0,
            endedAt = tonumber(row.ended_ts) or 0,
            duration = tonumber(row.duration_sec) or 0,
        }
    end

    TriggerClientEvent('cookie_phone:client:data', src, {
        phone = ident.phone,
        profile = {
            name = cleanText(profile.display_name, 40),
            avatar = cleanAvatar(profile.avatar),
            photoId = tonumber(profile.avatar_photo_id) or 0,
        },
        contacts = contacts,
        history = history,
        settings = getPhoneSettings(ident.license),
    })
end

local function insertHistory(call, status)
    if not call or call.logged then return end
    call.logged = true

    local now = os.time()
    local answered = tonumber(call.answeredAt)
    local duration = answered and math.max(0, now - answered) or 0

    MySQL.insert.await([[
        INSERT INTO cookie_phone_calls
        (caller_license, caller_citizenid, caller_phone,
         callee_license, callee_citizenid, callee_phone,
         started_at, answered_at, ended_at, status, duration_sec)
        VALUES (?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?),
                CASE WHEN ? > 0 THEN FROM_UNIXTIME(?) ELSE NULL END,
                FROM_UNIXTIME(?), ?, ?)
    ]], {
        call.caller.license, call.caller.citizenid, call.caller.phone,
        call.callee and call.callee.license or nil,
        call.callee and call.callee.citizenid or nil,
        call.number,
        call.createdAt,
        answered or 0, answered or 0,
        now, status, duration
    })
end

local function clearLocks(call)
    if not call then return end
    if call.caller and playerCall[call.caller.source] == call.id then
        playerCall[call.caller.source] = nil
    end
    if call.callee and playerCall[call.callee.source] == call.id then
        playerCall[call.callee.source] = nil
    end
end

local function endCall(callId, reason, actor)
    local call = activeCalls[callId]
    if not call then return end

    local status = tostring(reason or 'ended')
    local wasActive = call.state == 'active'

    if wasActive then
        if call.caller and call.caller.source then pmaSetCall(call.caller.source, 0) end
        if call.callee and call.callee.source then pmaSetCall(call.callee.source, 0) end
        if status == 'ended' then status = 'answered' end
    end

    insertHistory(call, status)

    if call.caller and GetPlayerName(call.caller.source) then
        TriggerClientEvent('cookie_phone:client:ended', call.caller.source, {
            callId = call.id,
            reason = status,
            actor = actor,
        })
        sendPhoneData(call.caller.source)
    end

    if call.callee and GetPlayerName(call.callee.source) then
        TriggerClientEvent('cookie_phone:client:ended', call.callee.source, {
            callId = call.id,
            reason = status,
            actor = actor,
        })
        sendPhoneData(call.callee.source)
    end

    clearLocks(call)
    activeCalls[callId] = nil
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_phone_calls (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            caller_license VARCHAR(255) NULL,
            caller_citizenid VARCHAR(64) NOT NULL,
            caller_phone VARCHAR(24) NOT NULL,
            callee_license VARCHAR(255) NULL,
            callee_citizenid VARCHAR(64) NULL,
            callee_phone VARCHAR(24) NOT NULL,
            started_at DATETIME NOT NULL,
            answered_at DATETIME NULL,
            ended_at DATETIME NULL,
            status VARCHAR(24) NOT NULL DEFAULT 'ended',
            duration_sec INT NOT NULL DEFAULT 0,
            INDEX idx_cookie_phone_caller_license (caller_license),
            INDEX idx_cookie_phone_callee_license (callee_license),
            INDEX idx_cookie_phone_caller (caller_citizenid),
            INDEX idx_cookie_phone_callee (callee_citizenid),
            INDEX idx_cookie_phone_started (started_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- V2.1: 기존 V2 통화기록 테이블을 유지하면서 license 기준 컬럼만 추가합니다.
    pcall(function()
        MySQL.query.await("ALTER TABLE cookie_phone_calls ADD COLUMN caller_license VARCHAR(255) NULL AFTER id")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE cookie_phone_calls ADD COLUMN callee_license VARCHAR(255) NULL AFTER caller_phone")
    end)
    pcall(function()
        MySQL.query.await("CREATE INDEX idx_cookie_phone_caller_license ON cookie_phone_calls (caller_license)")
    end)
    pcall(function()
        MySQL.query.await("CREATE INDEX idx_cookie_phone_callee_license ON cookie_phone_calls (callee_license)")
    end)

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_phone_profile (
            license VARCHAR(255) NOT NULL PRIMARY KEY,
            phone VARCHAR(24) NOT NULL DEFAULT '',
            display_name VARCHAR(40) NOT NULL DEFAULT '',
            avatar MEDIUMTEXT NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_cookie_phone_profile_phone (phone)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])


    pcall(function()
        MySQL.query.await('ALTER TABLE cookie_phone_profile ADD COLUMN avatar_photo_id BIGINT NULL AFTER avatar')
    end)

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_phone_gallery (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            owner_license VARCHAR(255) NOT NULL,
            image_data MEDIUMTEXT NOT NULL,
            orientation VARCHAR(12) NOT NULL DEFAULT 'landscape',
            camera_mode VARCHAR(12) NOT NULL DEFAULT 'rear',
            zoom DECIMAL(4,2) NOT NULL DEFAULT 1.00,
            source_message_id BIGINT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_cookie_phone_gallery_owner (owner_license, id),
            UNIQUE KEY uq_cookie_phone_gallery_message (owner_license, source_message_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    pcall(function()
        MySQL.query.await("ALTER TABLE cookie_phone_gallery ADD COLUMN orientation VARCHAR(12) NOT NULL DEFAULT 'landscape' AFTER image_data")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE cookie_phone_gallery ADD COLUMN camera_mode VARCHAR(12) NOT NULL DEFAULT 'rear' AFTER orientation")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE cookie_phone_gallery ADD COLUMN zoom DECIMAL(4,2) NOT NULL DEFAULT 1.00 AFTER camera_mode")
    end)
    pcall(function()
        MySQL.query.await("ALTER TABLE cookie_phone_gallery ADD COLUMN source_message_id BIGINT NULL AFTER zoom")
    end)
    pcall(function()
        MySQL.query.await("CREATE UNIQUE INDEX uq_cookie_phone_gallery_message ON cookie_phone_gallery(owner_license, source_message_id)")
    end)

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_phone_contacts (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            owner_license VARCHAR(255) NOT NULL,
            contact_phone VARCHAR(24) NOT NULL,
            contact_name VARCHAR(40) NOT NULL,
            avatar MEDIUMTEXT NULL,
            note VARCHAR(160) NOT NULL DEFAULT '',
            favorite TINYINT(1) NOT NULL DEFAULT 0,
            blocked TINYINT(1) NOT NULL DEFAULT 0,
            source_license VARCHAR(255) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uq_cookie_phone_contact (owner_license, contact_phone),
            INDEX idx_cookie_phone_contacts_owner (owner_license),
            INDEX idx_cookie_phone_contacts_phone (contact_phone)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_phone_messages (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            sender_license VARCHAR(255) NOT NULL,
            sender_phone VARCHAR(24) NOT NULL,
            receiver_license VARCHAR(255) NOT NULL,
            receiver_phone VARCHAR(24) NOT NULL,
            body VARCHAR(500) NOT NULL,
            sent_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            read_at TIMESTAMP NULL,
            INDEX idx_cookie_msg_sender (sender_license, receiver_license, id),
            INDEX idx_cookie_msg_receiver (receiver_license, sender_license, id),
            INDEX idx_cookie_msg_unread (receiver_license, read_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_phone_message_photos (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            owner_license VARCHAR(255) NOT NULL,
            source_gallery_id BIGINT NOT NULL,
            image_data MEDIUMTEXT NOT NULL,
            orientation VARCHAR(12) NOT NULL DEFAULT 'landscape',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_cookie_phone_message_photo_source (owner_license, source_gallery_id),
            INDEX idx_cookie_phone_message_photo_owner (owner_license, id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    pcall(function()
        MySQL.query.await('ALTER TABLE cookie_phone_messages ADD COLUMN photo_media_id BIGINT NULL AFTER body')
    end)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_phone_settings (
            license VARCHAR(255) NOT NULL PRIMARY KEY,
            accent VARCHAR(7) NOT NULL DEFAULT '#F0C85B',
            accent2 VARCHAR(7) NOT NULL DEFAULT '#C69A2B',
            wallpaper VARCHAR(32) NOT NULL DEFAULT 'cookie-bakery',
            custom_wallpaper MEDIUMTEXT NULL,
            blur TINYINT UNSIGNED NOT NULL DEFAULT 0,
            dim TINYINT UNSIGNED NOT NULL DEFAULT 18,
            glass TINYINT UNSIGNED NOT NULL DEFAULT 46,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_phone_bank_transfer (
            id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            sender_license VARCHAR(255) NOT NULL,
            sender_phone VARCHAR(24) NOT NULL,
            receiver_license VARCHAR(255) NOT NULL,
            receiver_phone VARCHAR(24) NOT NULL,
            amount BIGINT UNSIGNED NOT NULL,
            memo VARCHAR(80) NOT NULL DEFAULT '',
            transfer_mode VARCHAR(16) NOT NULL DEFAULT 'phone',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_cookie_bank_sender (sender_license, id),
            INDEX idx_cookie_bank_receiver (receiver_license, id),
            INDEX idx_cookie_bank_created (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

RegisterNetEvent('cookie_phone:server:requestData', function()
    sendPhoneData(source)
end)


RegisterNetEvent('cookie_phone:server:phoneState', function(isOpen)
    phoneOpen[source] = isOpen == true
end)

RegisterNetEvent('cookie_phone:server:saveProfile', function(data)
    local src = source
    local ident = playerIdentity(src)
    if not ident then return end

    local name = cleanText(data and data.name, 40)
    if name == '' then name = defaultProfileName(src) end

    local photoId = tonumber(data and data.photoId) or 0
    local avatar = ''
    local savedPhotoId = nil

    if photoId > 0 then
        local photo = getGalleryPhoto(ident.license, photoId)
        avatar = photo and cleanGalleryImage(photo.image_data) or ''
        if avatar == '' then
            TriggerClientEvent('cookie_phone:client:toast', src, '갤러리에 있는 사진만 프로필로 사용할 수 있습니다.', true)
            return
        end
        savedPhotoId = photoId
    end

    MySQL.query.await([[
        INSERT INTO cookie_phone_profile (license, phone, display_name, avatar, avatar_photo_id)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            phone = VALUES(phone),
            display_name = VALUES(display_name),
            avatar = VALUES(avatar),
            avatar_photo_id = VALUES(avatar_photo_id),
            updated_at = CURRENT_TIMESTAMP
    ]], { ident.license, ident.phone, name, avatar, savedPhotoId })

    TriggerClientEvent('cookie_phone:client:toast', src, '내 연락처 카드를 저장했습니다.', false)
    sendPhoneData(src)
end)

RegisterNetEvent('cookie_phone:server:requestGallery', function()
    sendGallery(source)
end)

RegisterNetEvent('cookie_phone:server:deleteGalleryPhoto', function(photoId)
    local src = source
    local ident = playerIdentity(src)
    photoId = tonumber(photoId)
    if not ident or not photoId then return end

    local photo = getGalleryPhoto(ident.license, photoId)
    if not photo then
        TriggerClientEvent('cookie_phone:client:toast', src, '사진을 찾을 수 없습니다.', true)
        return
    end

    MySQL.update.await('DELETE FROM cookie_phone_gallery WHERE id = ? AND owner_license = ?', { photoId, ident.license })
    MySQL.update.await([[
        UPDATE cookie_phone_profile
        SET avatar = '', avatar_photo_id = NULL
        WHERE license = ? AND avatar_photo_id = ?
    ]], { ident.license, photoId })

    TriggerClientEvent('cookie_phone:client:toast', src, '사진을 삭제했습니다.', false)
    sendGallery(src)
    sendPhoneData(src)
end)

-- V13.9.0: 받은 메시지의 이미지를 내 휴대전화 갤러리에 저장.
-- 메시지 ID와 수신자를 서버에서 다시 검증하므로 다른 사람 사진을 임의로 저장할 수 없다.
RegisterNetEvent('cookie_phone:server:saveMessagePhoto', function(messageId)
    local src = source
    local ident = playerIdentity(src)
    messageId = tonumber(messageId)
    if not ident or not messageId or messageId <= 0 then return end

    local row = MySQL.single.await([[
        SELECT m.id, p.image_data, p.orientation
        FROM cookie_phone_messages m
        JOIN cookie_phone_message_photos p ON p.id = m.photo_media_id
        WHERE m.id = ?
          AND m.receiver_license = ?
          AND m.photo_media_id IS NOT NULL
        LIMIT 1
    ]], { messageId, ident.license })

    if not row then
        return TriggerClientEvent('cookie_phone:client:toast', src, '저장할 수 있는 받은 사진이 아닙니다.', true)
    end

    local already = MySQL.single.await([[
        SELECT id FROM cookie_phone_gallery
        WHERE owner_license = ? AND source_message_id = ?
        LIMIT 1
    ]], { ident.license, messageId })

    if already then
        return TriggerClientEvent('cookie_phone:client:toast', src, '이미 갤러리에 저장한 사진입니다.', true)
    end

    local image = cleanGalleryImage(row.image_data)
    if image == '' then
        return TriggerClientEvent('cookie_phone:client:toast', src, '사진 데이터를 불러오지 못했습니다.', true)
    end

    local orientation = row.orientation == 'portrait' and 'portrait' or 'landscape'
    local ok, photoId = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO cookie_phone_gallery
                (owner_license, image_data, orientation, camera_mode, zoom, source_message_id)
            VALUES (?, ?, ?, 'message', 1.00, ?)
        ]], { ident.license, image, orientation, messageId })
    end)

    if not ok or not photoId then
        return TriggerClientEvent('cookie_phone:client:toast', src, '사진 저장에 실패했습니다.', true)
    end

    local oldRows = MySQL.query.await(([[
        SELECT id FROM cookie_phone_gallery
        WHERE owner_license = ?
        ORDER BY id DESC
        LIMIT %d, 500
    ]]):format(PHONE_GALLERY_LIMIT), { ident.license }) or {}

    for _, old in ipairs(oldRows) do
        MySQL.update.await('DELETE FROM cookie_phone_gallery WHERE id = ? AND owner_license = ?', { old.id, ident.license })
    end

    TriggerClientEvent('cookie_phone:client:toast', src, '메시지 사진을 갤러리에 저장했습니다.', false)
    sendGallery(src)
end)

RegisterNetEvent('cookie_phone:server:capturePhoto', function(meta)
    local src = source
    meta = type(meta) == 'table' and meta or {}
    local orientation = meta.orientation == 'portrait' and 'portrait' or 'landscape'
    local cameraMode = meta.cameraMode == 'front' and 'front' or 'rear'
    local zoom = tonumber(meta.zoom) or 1.0
    if zoom < 0.5 then zoom = 0.5 elseif zoom > 3.0 then zoom = 3.0 end
    if captureBusy[src] then return end

    if GetResourceState('screencapture') ~= 'started' then
        TriggerClientEvent('cookie_phone:client:captureFailed', src, 'screencapture 리소스가 실행 중이 아닙니다.')
        return
    end

    local ident = playerIdentity(src)
    if not ident then return end

    local token = ('%d:%d:%d'):format(src, os.time(), math.random(100000, 999999))
    captureBusy[src] = {
        token = token,
        license = ident.license,
        orientation = orientation,
        cameraMode = cameraMode,
        zoom = zoom,
    }

    local ok, err = pcall(function()
        exports.screencapture:serverCapture(src, {
            encoding = 'webp',
            maxWidth = 1280,
            maxHeight = 720,
        }, function(data)
            CreateThread(function()
                local pending = captureBusy[src]
                if not pending or pending.token ~= token then return end
                if not GetPlayerName(src) then captureBusy[src] = nil return end

                local image = cleanGalleryImage(data)
                if image == '' then
                    captureBusy[src] = nil
                    TriggerClientEvent('cookie_phone:client:captureFailed', src, '사진 저장에 실패했습니다.')
                    return
                end

                -- NUI canvas performs a real 9:16 crop for portrait photos and
                -- mirrors front-camera selfies before the final DB save.
                TriggerLatentClientEvent('cookie_phone:client:processCapturedPhoto', src, 1048576, {
                    token = token,
                    image = image,
                    orientation = orientation,
                    cameraMode = cameraMode,
                    zoom = zoom,
                })

                CreateThread(function()
                    Wait(20000)
                    local stale = captureBusy[src]
                    if stale and stale.token == token then
                        captureBusy[src] = nil
                        if GetPlayerName(src) then
                            TriggerClientEvent('cookie_phone:client:captureFailed', src, '사진 처리 시간이 초과되었습니다.')
                        end
                    end
                end)
            end)
        end)
    end)

    if not ok then
        captureBusy[src] = nil
        TriggerClientEvent('cookie_phone:client:captureFailed', src, tostring(err or '사진 저장에 실패했습니다.'))
    end
end)

RegisterNetEvent('cookie_phone:server:saveProcessedPhoto', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local pending = captureBusy[src]
    if not pending then return end
    if tostring(data.token or '') ~= tostring(pending.token or '') then return end

    local current = playerIdentity(src)
    if not current or current.license ~= pending.license then
        captureBusy[src] = nil
        return
    end

    local image = cleanGalleryImage(data.image)
    if image == '' then
        captureBusy[src] = nil
        TriggerClientEvent('cookie_phone:client:captureFailed', src, '사진 변환에 실패했습니다.')
        return
    end

    local photoId = MySQL.insert.await([[
        INSERT INTO cookie_phone_gallery (owner_license, image_data, orientation, camera_mode, zoom)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        pending.license,
        image,
        pending.orientation,
        pending.cameraMode,
        pending.zoom,
    })

    local oldRows = MySQL.query.await([[
        SELECT id FROM cookie_phone_gallery
        WHERE owner_license = ?
        ORDER BY id DESC
        LIMIT 36, 500
    ]], { pending.license }) or {}

    for _, row in ipairs(oldRows) do
        MySQL.update.await('DELETE FROM cookie_phone_gallery WHERE id = ? AND owner_license = ?', { row.id, pending.license })
    end

    local photo = {
        id = tonumber(photoId),
        image = image,
        createdAt = os.time(),
        orientation = pending.orientation,
        cameraMode = pending.cameraMode,
        zoom = pending.zoom,
    }

    captureBusy[src] = nil
    TriggerLatentClientEvent('cookie_phone:client:captureSaved', src, 1048576, photo)
end)

RegisterNetEvent('cookie_phone:server:saveContact', function(data)
    local src = source
    local ident = playerIdentity(src)
    if not ident then return end

    local ok, reason = upsertContact(ident, data or {})
    if not ok then
        local msg = reason == 'self' and '본인 번호는 연락처에 저장할 수 없습니다.'
            or reason == 'number' and '전화번호를 정확히 입력하세요.'
            or '연락처를 저장할 수 없습니다.'
        return sendError(src, msg)
    end

    TriggerClientEvent('cookie_phone:client:toast', src, '연락처를 저장했습니다.', false)
    sendPhoneData(src)
end)

RegisterNetEvent('cookie_phone:server:deleteContact', function(contactId)
    local src = source
    local ident = playerIdentity(src)
    contactId = tonumber(contactId)
    if not ident or not contactId then return end

    MySQL.query.await(
        'DELETE FROM cookie_phone_contacts WHERE id = ? AND owner_license = ?',
        { contactId, ident.license }
    )
    TriggerClientEvent('cookie_phone:client:toast', src, '연락처를 삭제했습니다.', false)
    sendPhoneData(src)
end)

RegisterNetEvent('cookie_phone:server:setFavorite', function(contactId, favorite)
    local src = source
    local ident = playerIdentity(src)
    contactId = tonumber(contactId)
    if not ident or not contactId then return end

    MySQL.update.await(
        'UPDATE cookie_phone_contacts SET favorite = ? WHERE id = ? AND owner_license = ?',
        { favorite == true and 1 or 0, contactId, ident.license }
    )
    sendPhoneData(src)
end)

RegisterNetEvent('cookie_phone:server:setBlocked', function(contactId, blocked)
    local src = source
    local ident = playerIdentity(src)
    contactId = tonumber(contactId)
    if not ident or not contactId then return end

    MySQL.update.await(
        'UPDATE cookie_phone_contacts SET blocked = ? WHERE id = ? AND owner_license = ?',
        { blocked == true and 1 or 0, contactId, ident.license }
    )
    sendPhoneData(src)
end)

RegisterNetEvent('cookie_phone:server:requestNearby', function(candidates)
    local src = source
    if not phoneOpen[src] then
        return TriggerClientEvent('cookie_phone:client:nearby', src, {})
    end

    local result = {}
    local seen = {}

    if type(candidates) == 'table' then
        for _, candidate in ipairs(candidates) do
            local target = tonumber(candidate and candidate.serverId or candidate)
            if target and target ~= src and not seen[target] and GetPlayerName(target) and phoneOpen[target] then
                seen[target] = true
                local distance = playerDistance(src, target)
                if distance <= 4.5 then
                    local profile = publicProfile(target)
                    if profile then
                        result[#result + 1] = {
                            serverId = target,
                            name = profile.name ~= '' and profile.name or ('사용자 #' .. target),
                            avatar = profile.avatar,
                            distance = math.floor(distance * 10 + 0.5) / 10,
                        }
                    end
                end
            end
        end
    end

    table.sort(result, function(a, b) return (a.distance or 999) < (b.distance or 999) end)
    TriggerClientEvent('cookie_phone:client:nearby', src, result)
end)

RegisterNetEvent('cookie_phone:server:shareContact', function(target)
    local src = source
    target = tonumber(target)

    if not target or target == src or not GetPlayerName(target) then
        return sendError(src, '근처 사용자를 찾을 수 없습니다.')
    end
    if not phoneOpen[src] or not phoneOpen[target] then
        return sendError(src, '상대방의 휴대전화가 열려 있어야 합니다.')
    end
    if playerDistance(src, target) > 4.5 then
        return sendError(src, '상대방이 너무 멀리 있습니다.')
    end

    local nowMs = GetGameTimer()
    if shareCooldown[src] and nowMs - shareCooldown[src] < 1800 then
        return sendError(src, '잠시 후 다시 공유하세요.')
    end
    shareCooldown[src] = nowMs

    local profile = publicProfile(src)
    if not profile or profile.phone == '' then
        return sendError(src, '내 연락처 카드를 불러올 수 없습니다.')
    end

    nextShareId = nextShareId + 1
    if nextShareId > 999999 then nextShareId = 5001 end

    pendingShares[nextShareId] = {
        id = nextShareId,
        from = src,
        to = target,
        created = os.time(),
        profile = profile,
    }

    TriggerClientEvent('cookie_phone:client:contactOffer', target, {
        shareId = nextShareId,
        fromSource = src,
        name = profile.name,
        phone = profile.phone,
        avatar = profile.avatar,
    })

    TriggerClientEvent('cookie_phone:client:toast', src, '연락처 카드를 전송했습니다.', false)

    CreateThread(function()
        Wait(15000)
        local share = pendingShares[nextShareId]
        if share and share.id == nextShareId then
            pendingShares[nextShareId] = nil
        end
    end)
end)

RegisterNetEvent('cookie_phone:server:acceptShare', function(shareId)
    local src = source
    shareId = tonumber(shareId)
    local share = shareId and pendingShares[shareId]
    if not share or share.to ~= src or os.time() - share.created > 20 then
        return sendError(src, '연락처 공유 요청이 만료되었습니다.')
    end

    local ident = playerIdentity(src)
    if not ident then return end

    local ok = upsertContact(ident, {
        phone = share.profile.phone,
        name = share.profile.name,
        avatar = share.profile.avatar,
        favorite = false,
        blocked = false,
        note = '',
        sourceLicense = getLicense(share.from),
    })

    pendingShares[shareId] = nil

    if ok then
        TriggerClientEvent('cookie_phone:client:toast', src, '연락처를 저장했습니다.', false)
        if GetPlayerName(share.from) then
            TriggerClientEvent('cookie_phone:client:toast', share.from, '상대방이 연락처를 저장했습니다.', false)
        end
        sendPhoneData(src)
    end
end)

RegisterNetEvent('cookie_phone:server:declineShare', function(shareId)
    local src = source
    shareId = tonumber(shareId)
    local share = shareId and pendingShares[shareId]
    if not share or share.to ~= src then return end
    pendingShares[shareId] = nil

    if GetPlayerName(share.from) then
        TriggerClientEvent('cookie_phone:client:toast', share.from, '상대방이 연락처 공유를 거절했습니다.', true)
    end
end)




RegisterNetEvent('cookie_phone:server:bankInfo', function()
    sendBankState(source)
end)

RegisterNetEvent('cookie_phone:server:bankNearby', function(candidates)
    local src = source
    if not phoneOpen[src] then
        return TriggerClientEvent('cookie_phone:client:bankNearby', src, {})
    end

    local result, seen = {}, {}
    if type(candidates) == 'table' then
        for _, candidate in ipairs(candidates) do
            local target = tonumber(candidate and candidate.serverId or candidate)
            if target and target ~= src and not seen[target] and GetPlayerName(target) and phoneOpen[target] then
                seen[target] = true
                local distance = playerDistance(src, target)
                if distance <= 4.5 then
                    local profile = publicProfile(target)
                    if profile then
                        result[#result + 1] = {
                            serverId = target,
                            name = profile.name ~= '' and profile.name or ('사용자 #' .. target),
                            phone = profile.phone,
                            avatar = profile.avatar,
                            distance = math.floor(distance * 10 + 0.5) / 10,
                        }
                    end
                end
            end
        end
    end

    table.sort(result, function(a, b)
        return (a.distance or 999) < (b.distance or 999)
    end)

    TriggerClientEvent('cookie_phone:client:bankNearby', src, result)
end)

RegisterNetEvent('cookie_phone:server:bankTransfer', function(data)
    local src = source
    local ok, err = bankTransfer(src, data)
    if not ok then
        bankNotify(src, err or '송금 처리 중 오류가 발생했습니다.', true)
        sendBankState(src)
    end
end)

RegisterNetEvent('cookie_phone:server:requestSettings', function()
    local src = source
    local ident = playerIdentity(src)
    if not ident then return end
    TriggerClientEvent('cookie_phone:client:settings', src, getPhoneSettings(ident.license))
end)

RegisterNetEvent('cookie_phone:server:saveSettings', function(data)
    local src = source
    local ident = playerIdentity(src)
    if not ident then return end
    local settings = savePhoneSettings(ident.license, data)
    if not settings then return end
    TriggerClientEvent('cookie_phone:client:settings', src, settings)
    TriggerClientEvent('cookie_phone:client:toast', src, '휴대전화 디자인을 저장했습니다.', false)
end)

RegisterNetEvent('cookie_phone:server:resetSettings', function()
    local src = source
    local ident = playerIdentity(src)
    if not ident then return end
    MySQL.query.await('DELETE FROM cookie_phone_settings WHERE license = ?', { ident.license })
    local settings = getPhoneSettings(ident.license)
    TriggerClientEvent('cookie_phone:client:settings', src, settings)
    TriggerClientEvent('cookie_phone:client:toast', src, '기본 디자인으로 초기화했습니다.', false)
end)

RegisterNetEvent('cookie_phone:server:requestMessages', function()
    sendMessageState(source)
end)

RegisterNetEvent('cookie_phone:server:openConversation', function(rawPhone)
    local src = source
    local ident = playerIdentity(src)
    if not ident then return end

    local number = normalizePhone(rawPhone)
    if number == '' or number == ident.phone then
        return sendError(src, '대화 상대의 전화번호가 올바르지 않습니다.')
    end

    local owner = phoneOwnerByNumber(number)
    if not owner or owner.license == '' then
        return sendError(src, '존재하지 않는 전화번호입니다.')
    end

    MySQL.update.await([[
        UPDATE cookie_phone_messages
        SET read_at = CURRENT_TIMESTAMP
        WHERE receiver_license = ? AND sender_license = ? AND read_at IS NULL
    ]], { ident.license, owner.license })

    local contact = getContactByPhone(ident.license, owner.phone)
    local remoteProfile = profileByLicense(owner.license)
    local messages = getMessages(ident, owner.license, 80)

    TriggerLatentClientEvent('cookie_phone:client:conversation', src, 1048576, {
        phone = owner.phone,
        license = owner.license,
        name = contact and contact.name or '',
        avatar = contact and contact.avatar or '',
        profileName = remoteProfile.name,
        profileAvatar = remoteProfile.avatar,
        blocked = contact and contact.blocked or false,
        messages = messages,
    })

    sendMessageState(src)
end)

RegisterNetEvent('cookie_phone:server:sendMessage', function(data)
    local src = source
    local ident = playerIdentity(src)
    if not ident then return end

    local number = normalizePhone(data and data.phone)
    local body = cleanText(data and data.body, 500)
    local galleryPhotoId = tonumber(data and data.photoId) or 0

    if number == '' or number == ident.phone then
        return sendError(src, '메시지를 보낼 번호가 올바르지 않습니다.')
    end
    if body == '' and galleryPhotoId <= 0 then
        return sendError(src, '메시지 내용이나 사진을 선택하세요.')
    end

    local owner = phoneOwnerByNumber(number)
    if not owner or owner.license == '' then
        return sendError(src, '존재하지 않는 전화번호입니다.')
    end

    if isPhoneBlocked(owner.license, ident.phone) then
        return sendError(src, '메시지를 전달할 수 없습니다.')
    end

    local photoMediaId = nil
    local photoPayload = nil
    if galleryPhotoId > 0 then
        photoMediaId, photoPayload = ensureMessagePhoto(ident.license, galleryPhotoId)
        if not photoMediaId or not photoPayload or photoPayload.image == '' then
            return sendError(src, '인게임 카메라로 촬영한 갤러리 사진만 전송할 수 있습니다.')
        end
    end

    local msgId = MySQL.insert.await([[
        INSERT INTO cookie_phone_messages
            (sender_license, sender_phone, receiver_license, receiver_phone, body, photo_media_id)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        ident.license, ident.phone,
        owner.license, owner.phone,
        body, photoMediaId
    })

    local payload = {
        id = tonumber(msgId),
        body = body,
        photo = photoPayload and photoPayload.image or '',
        photoOrientation = photoPayload and photoPayload.orientation or 'landscape',
        sentAt = os.time(),
    }

    local recipientSrc = sourceByLicense(owner.license)
    if recipientSrc then
        local incoming = {
            id = payload.id,
            fromPhone = ident.phone,
            body = payload.body,
            photo = payload.photo,
            photoOrientation = payload.photoOrientation,
            sentAt = payload.sentAt,
        }
        TriggerLatentClientEvent('cookie_phone:client:newMessage', recipientSrc, 1048576, incoming)
        sendMessageState(recipientSrc)
    end

    TriggerLatentClientEvent('cookie_phone:client:messageSent', src, 1048576, {
        id = payload.id,
        phone = owner.phone,
        body = payload.body,
        photo = payload.photo,
        photoOrientation = payload.photoOrientation,
        sentAt = payload.sentAt,
    })

    sendMessageState(src)
end)

RegisterNetEvent('cookie_phone:server:markConversationRead', function(rawPhone)
    local src = source
    local ident = playerIdentity(src)
    if not ident then return end

    local owner = phoneOwnerByNumber(rawPhone)
    if not owner then return end

    MySQL.update.await([[
        UPDATE cookie_phone_messages
        SET read_at = CURRENT_TIMESTAMP
        WHERE receiver_license = ? AND sender_license = ? AND read_at IS NULL
    ]], { ident.license, owner.license })

    TriggerClientEvent('cookie_phone:client:messagesRead', src, {
        phone = owner.phone
    })
    sendMessageState(src)
end)

RegisterNetEvent('cookie_phone:server:deleteConversation', function(rawPhone)
    local src = source
    local ident = playerIdentity(src)
    if not ident then return end

    local owner = phoneOwnerByNumber(rawPhone)
    if not owner then return end

    MySQL.query.await([[
        DELETE FROM cookie_phone_messages
        WHERE (sender_license = ? AND receiver_license = ?)
           OR (sender_license = ? AND receiver_license = ?)
    ]], {
        ident.license, owner.license,
        owner.license, ident.license
    })

    -- Remove copied message photos that are no longer referenced by any message.
    pcall(function()
        MySQL.query.await([[
            DELETE p FROM cookie_phone_message_photos p
            LEFT JOIN cookie_phone_messages m ON m.photo_media_id = p.id
            WHERE m.id IS NULL
        ]])
    end)

    TriggerClientEvent('cookie_phone:client:toast', src, '대화 기록을 삭제했습니다.', false)
    sendMessageState(src)
end)

RegisterNetEvent('cookie_phone:server:dial', function(rawNumber)
    local src = source
    if playerCall[src] then
        return sendError(src, '이미 다른 통화를 처리 중입니다.')
    end

    local caller = playerIdentity(src)
    if not caller or caller.phone == '' then
        return sendError(src, '본인 전화번호를 불러올 수 없습니다.')
    end

    local number = normalizePhone(rawNumber)
    if #number < 4 then
        return sendError(src, '전화번호를 정확히 입력하세요.')
    end

    if number == caller.phone then
        return sendError(src, '본인에게 전화를 걸 수 없습니다.')
    end

    local callee, owner = getOnlineByPhone(number)

    -- 상대방이 내 번호를 차단한 경우, 차단 사실 자체는 노출하지 않고 연결 불가로 처리.
    if owner and owner.license then
        local blocked = MySQL.single.await([[
            SELECT id
            FROM cookie_phone_contacts
            WHERE owner_license = ? AND contact_phone = ? AND blocked = 1
            LIMIT 1
        ]], { tostring(owner.license), caller.phone })

        if blocked then
            TriggerClientEvent('cookie_phone:client:failed', src, {
                reason = 'unavailable',
                number = number,
            })
            return
        end
    end

    if not callee then
        local ownerLicense = owner and tostring(owner.license or '') or ''
        local offlineCitizen = nil

        if ownerLicense ~= '' then
            local prow = MySQL.single.await(
                'SELECT citizenid FROM players WHERE license = ? LIMIT 1',
                { ownerLicense }
            )
            offlineCitizen = prow and tostring(prow.citizenid or '') or nil
        end

        local callId = allocateCall()
        local fake = {
            id = callId,
            caller = caller,
            callee = owner and {
                license = ownerLicense,
                citizenid = offlineCitizen or '',
                source = nil,
            } or nil,
            number = number,
            createdAt = os.time(),
            state = 'failed',
        }
        insertHistory(fake, owner and 'offline' or 'invalid')

        TriggerClientEvent('cookie_phone:client:failed', src, {
            reason = owner and 'offline' or 'invalid',
            number = number,
        })
        return sendPhoneData(src)
    end

    if playerCall[callee.source] then
        TriggerClientEvent('cookie_phone:client:failed', src, {
            reason = 'busy',
            number = number,
        })
        return
    end

    local callId, channel = allocateCall()
    local call = {
        id = callId,
        channel = channel,
        caller = caller,
        callee = callee,
        number = number,
        createdAt = os.time(),
        state = 'ringing',
        answeredAt = nil,
        logged = false,
    }

    activeCalls[callId] = call
    playerCall[caller.source] = callId
    playerCall[callee.source] = callId

    TriggerClientEvent('cookie_phone:client:outgoing', caller.source, {
        callId = callId,
        number = callee.phone,
    })

    TriggerClientEvent('cookie_phone:client:incoming', callee.source, {
        callId = callId,
        number = caller.phone,
    })

    -- Ring for 30 seconds.
    CreateThread(function()
        Wait(30000)
        local current = activeCalls[callId]
        if current and current.state == 'ringing' then
            endCall(callId, 'missed', 'timeout')
        end
    end)
end)

RegisterNetEvent('cookie_phone:server:accept', function(callId)
    local src = source
    callId = tonumber(callId)
    local call = callId and activeCalls[callId]
    if not call or call.state ~= 'ringing' or not call.callee or call.callee.source ~= src then return end

    local callerAlive = call.caller and GetPlayerName(call.caller.source)
    if not callerAlive then
        return endCall(callId, 'disconnected', src)
    end

    if GetResourceState('pma-voice') ~= 'started' then
        sendError(src, '음성 시스템이 실행 중이 아닙니다.')
        sendError(call.caller.source, '음성 시스템이 실행 중이 아닙니다.')
        return endCall(callId, 'voice_error', src)
    end

    local ok1 = pmaSetCall(call.caller.source, call.channel)
    local ok2 = pmaSetCall(call.callee.source, call.channel)
    if not ok1 or not ok2 then
        return endCall(callId, 'voice_error', src)
    end

    call.state = 'active'
    call.answeredAt = os.time()

    TriggerClientEvent('cookie_phone:client:connected', call.caller.source, {
        callId = call.id,
        number = call.callee.phone,
        answeredAt = call.answeredAt,
    })

    TriggerClientEvent('cookie_phone:client:connected', call.callee.source, {
        callId = call.id,
        number = call.caller.phone,
        answeredAt = call.answeredAt,
    })
end)

RegisterNetEvent('cookie_phone:server:decline', function(callId)
    local src = source
    callId = tonumber(callId)
    local call = callId and activeCalls[callId]
    if not call or call.state ~= 'ringing' or not call.callee or call.callee.source ~= src then return end
    endCall(callId, 'rejected', src)
end)

RegisterNetEvent('cookie_phone:server:cancel', function(callId)
    local src = source
    callId = tonumber(callId)
    local call = callId and activeCalls[callId]
    if not call or call.state ~= 'ringing' or not call.caller or call.caller.source ~= src then return end
    endCall(callId, 'cancelled', src)
end)

RegisterNetEvent('cookie_phone:server:hangup', function(callId)
    local src = source
    callId = tonumber(callId)
    local call = callId and activeCalls[callId]
    if not call then return end
    if (call.caller and call.caller.source == src) or (call.callee and call.callee.source == src) then
        endCall(callId, call.state == 'active' and 'answered' or 'cancelled', src)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    phoneOpen[src] = nil
    shareCooldown[src] = nil
    bankTransferCooldown[src] = nil
    local callId = playerCall[src]
    if callId and activeCalls[callId] then
        endCall(callId, activeCalls[callId].state == 'active' and 'disconnected' or 'missed', src)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, call in pairs(activeCalls) do
        if call.caller and call.caller.source then pmaSetCall(call.caller.source, 0) end
        if call.callee and call.callee.source then pmaSetCall(call.callee.source, 0) end
    end
end)

-- cookie_phone gallery capture cleanup
AddEventHandler('playerDropped', function()
    captureBusy[source] = nil
end)


-- ============================================================
-- COOKIE DISPATCH V1 + AFK
-- 문자형 콜 / 단독 접수 / GPS / 종료사유 / 30분 잠수 연동
-- ============================================================
local DISPATCH_COOLDOWN = 20
local dispatchCooldown = {}

local DISPATCH_GOV_TYPES = { police=true, security=true, corrections=true, fire=true }
local DISPATCH_FACTION_TYPES = { police=true, security=true, corrections=true, fire=true, private=true, crime=true }
local DISPATCH_TYPE_LABEL = {
    police='공무원', security='공무원', corrections='공무원', fire='공무원',
    private='사설팩션', crime='범죄조직'
}
local DISPATCH_SERVICES = {
    { key='admin', label='관리자', category='운영 지원', icon='A' },
    { key='taxi', label='택시', category='시민 서비스', icon='🚕' },
    { key='mechanic', label='긴급정비', category='시민 서비스', icon='🔧' },
}

local function dispatchCleanText(value, maxLen)
    local s=tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then s=s:sub(1,maxLen) end
    return s
end

local function dispatchAfk(src)
    local p=Player(tonumber(src))
    return p and p.state and p.state.cookieAfk == true or false
end

local function dispatchIdentity(src)
    local ident=playerIdentity(src)
    if not ident then return nil end
    local row=MySQL.single.await('SELECT gobun,nickname,phone FROM cookie_user WHERE license=? LIMIT 1',{ident.license}) or {}
    return {
        source=tonumber(src), license=ident.license, citizenid=ident.citizenid,
        gobun=tonumber(row.gobun), name=dispatchCleanText(row.nickname,60) ~= '' and dispatchCleanText(row.nickname,60) or defaultProfileName(src),
        phone=tostring(row.phone or ident.phoneDisplay or '')
    }
end

local function dispatchMember(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil end
    local ok,m=pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    return ok and m or nil
end

local function dispatchCivil(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil end
    local ok,c=pcall(function() return exports.cookie_admin:getCivilJob(src) end)
    return ok and c or nil
end

local function dispatchTargetInfo(target)
    target=tostring(target or '')
    local service=target:match('^service:(.+)$')
    if service then
        for _,s in ipairs(DISPATCH_SERVICES) do
            if s.key==service then return {kind='service',key=s.key,target=target,label=s.label,category=s.category,icon=s.icon,gov=false} end
        end
        return nil
    end
    local fid=tonumber(target:match('^faction:(%d+)$'))
    if not fid then return nil end
    local row=MySQL.single.await('SELECT id,name,color,emoji,faction_type FROM cookie_faction WHERE id=? AND is_active=1 LIMIT 1',{fid})
    if not row or not DISPATCH_FACTION_TYPES[tostring(row.faction_type or '')] then return nil end
    return {
        kind='faction',key=tostring(fid),target=('faction:%d'):format(fid),factionId=fid,
        label=row.name or ('팩션 #'..fid),category=DISPATCH_TYPE_LABEL[tostring(row.faction_type or '')] or '팩션',
        icon=row.emoji or '',color=row.color,gov=DISPATCH_GOV_TYPES[tostring(row.faction_type or '')] == true,
        factionType=tostring(row.faction_type or '')
    }
end

local function dispatchEligibleForTarget(src,targetInfo)
    src=tonumber(src)
    if not src or dispatchAfk(src) then return false end

    if targetInfo.kind=='service' and tostring(targetInfo.key or '')=='admin' then
        if GetResourceState('cookie_admin')~='started' then return false end
        local ok,duty=pcall(function()
            return exports.cookie_admin:isAdminDuty(src,1)
        end)
        return ok and duty==true
    end

    if targetInfo.kind=='service' then
        local civil=dispatchCivil(src)
        return civil and tostring(civil.key or '')==tostring(targetInfo.key) and civil.onDuty==true
    end
    local m=dispatchMember(src)
    if not m or tonumber(m.id)~=tonumber(targetInfo.factionId) then return false end
    if targetInfo.gov then return m.duty==true end
    return true
end

local function dispatchRecipients(targetInfo)
    local out={}
    for _,raw in ipairs(GetPlayers()) do
        local sid=tonumber(raw)
        if sid and dispatchEligibleForTarget(sid,targetInfo) then out[#out+1]=sid end
    end
    return out
end

local function dispatchAvailable(targetInfo)
    return #dispatchRecipients(targetInfo)
end

-- 접수 완료 시 전 서버 채팅에 익명 접수 안내를 표시합니다.
-- 경찰청/보안국/관리자/스태프 계열은 '신고', 그 외는 '호출'로 표시합니다.
local function dispatchAnnouncementKind(targetInfo)
    if not targetInfo then return '호출' end
    if targetInfo.kind == 'service' then
        local key = tostring(targetInfo.key or ''):lower()
        if key == 'admin' or key == 'staff' then return '신고' end
    end
    local factionType = tostring(targetInfo.factionType or ''):lower()
    if factionType == 'police' or factionType == 'security' then return '신고' end
    return '호출'
end

local function dispatchBroadcastAccepted(row, targetInfo, responder)
    if not row or not responder then return end
    local targetLabel = dispatchCleanText(row.target_label or (targetInfo and targetInfo.label) or '팩션', 80)
    if targetLabel == '' then targetLabel = '팩션' end
    local responderName = dispatchCleanText(responder.name or '담당자', 60)
    if responderName == '' then responderName = '담당자' end
    local kind = dispatchAnnouncementKind(targetInfo)
    local acceptedSubject = kind == '신고' and '신고가' or '호출이'
    TriggerClientEvent('chat:addMessage', -1, {
        templateId = 'cookie_system',
        args = { ('익명님의 %s %s 접수되었습니다. 담당자 : %s'):format(targetLabel, acceptedSubject, responderName) }
    })
end

local function dispatchLog(callId,action,actor,detail)
    pcall(function()
        MySQL.insert.await([[INSERT INTO cookie_dispatch_event_log(call_id,action,actor_citizenid,actor_name,detail) VALUES(?,?,?,?,?)]],{
            tonumber(callId),tostring(action or ''),actor and actor.citizenid or nil,actor and actor.name or nil,dispatchCleanText(detail,500)
        })
    end)
end

local function dispatchPublicCall(row)
    if not row then return nil end
    return {
        id=tonumber(row.id), target=row.target_key, targetKind=row.target_kind, targetLabel=row.target_label,
        reason=row.reason or '', status=row.status or '', x=tonumber(row.x),y=tonumber(row.y),z=tonumber(row.z),
        callerName=row.caller_name,callerGobun=tonumber(row.caller_gobun),callerPhone=row.caller_phone,
        acceptedByName=row.accepted_by_name,acceptedByGobun=tonumber(row.accepted_by_gobun),
        closeReason=row.close_reason, responderCount=tonumber(row.responder_count) or 0,
        locationLabel='호출 위치'
    }
end

local function dispatchFetch(callId)
    return MySQL.single.await('SELECT * FROM cookie_dispatch_calls WHERE id=? LIMIT 1',{tonumber(callId)})
end

local function dispatchSendPendingTo(src,row)
    local target=dispatchTargetInfo(row.target_key)
    if not target or not dispatchEligibleForTarget(src,target) then return end
    TriggerClientEvent('cookie_phone:client:dispatchIncoming',src,dispatchPublicCall(row))
end

local function dispatchSyncPendingFor(src)
    if dispatchAfk(src) then
        TriggerClientEvent('cookie_phone:client:dispatchClearIncoming',src)
        return
    end
    TriggerClientEvent('cookie_phone:client:dispatchClearIncoming',src)
    local rows=MySQL.query.await("SELECT * FROM cookie_dispatch_calls WHERE status='pending' ORDER BY id ASC LIMIT 40") or {}
    for _,row in ipairs(rows) do dispatchSendPendingTo(src,row) end
end

local function dispatchTargetsAndCounts()
    local out={}
    for _,s in ipairs(DISPATCH_SERVICES) do
        local ti=dispatchTargetInfo('service:'..s.key)
        ti.available=dispatchAvailable(ti)
        out[#out+1]=ti
    end
    local rows=MySQL.query.await([[SELECT id,name,color,emoji,faction_type FROM cookie_faction WHERE is_active=1 AND faction_type IN ('police','security','corrections','fire','private','crime') ORDER BY FIELD(faction_type,'police','security','corrections','fire','private','crime'),id]]) or {}
    for _,r in ipairs(rows) do
        local ti=dispatchTargetInfo('faction:'..tostring(r.id))
        if ti then ti.available=dispatchAvailable(ti); out[#out+1]=ti end
    end
    return out
end

local function dispatchOverviewFor(src)
    local who=dispatchIdentity(src)
    if not who then return {ok=false,targets={},ownCalls={},assignedCalls={}} end
    local ownRows=MySQL.query.await([[SELECT * FROM cookie_dispatch_calls WHERE caller_citizenid=? AND status IN ('pending','accepted') ORDER BY id DESC LIMIT 10]],{who.citizenid}) or {}
    local assignedRows=MySQL.query.await([[SELECT * FROM cookie_dispatch_calls WHERE accepted_by_citizenid=? AND status='accepted' ORDER BY id DESC LIMIT 10]],{who.citizenid}) or {}
    local own,assigned={},{ }
    for _,r in ipairs(ownRows) do own[#own+1]=dispatchPublicCall(r) end
    for _,r in ipairs(assignedRows) do assigned[#assigned+1]=dispatchPublicCall(r) end
    return {ok=true,targets=dispatchTargetsAndCounts(),ownCalls=own,assignedCalls=assigned,afk=dispatchAfk(src)}
end

local function dispatchPushOverview(src)
    TriggerClientEvent('cookie_phone:client:dispatchOverview',src,dispatchOverviewFor(src))
end

lib.callback.register('cookie_phone:dispatchOverview', function(src)
    return dispatchOverviewFor(src)
end)

lib.callback.register('cookie_phone:dispatchCreate', function(src,data)
    local who=dispatchIdentity(src)
    if not who then return {ok=false,reason='사용자 정보를 불러오지 못했습니다.'} end
    local target=dispatchTargetInfo(data and data.target)
    if not target then return {ok=false,reason='존재하지 않는 연락 대상입니다.'} end
    local reason=dispatchCleanText(data and data.reason,180)
    if #reason<2 then return {ok=false,reason='콜 사유를 입력하세요.'} end
    local cdKey=who.license..'|'..target.target
    local now=os.time(); local last=dispatchCooldown[cdKey] or 0
    if now-last<DISPATCH_COOLDOWN then return {ok=false,reason=('같은 대상에는 %d초 후 다시 호출할 수 있습니다.'):format(DISPATCH_COOLDOWN-(now-last))} end
    local ped=GetPlayerPed(src); local c=ped and ped~=0 and GetEntityCoords(ped) or nil
    if not c then return {ok=false,reason='현재 위치를 확인할 수 없습니다.'} end
    local recipients=dispatchRecipients(target)
    local callId=MySQL.insert.await([[INSERT INTO cookie_dispatch_calls(target_kind,target_key,target_faction_id,target_label,caller_license,caller_citizenid,caller_gobun,caller_name,caller_phone,reason,x,y,z,status,responder_count) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,'pending',?)]],{
        target.kind,target.target,target.factionId,target.label,who.license,who.citizenid,who.gobun,who.name,who.phone,reason,c.x,c.y,c.z,#recipients
    })
    if not callId then return {ok=false,reason='콜을 저장하지 못했습니다.'} end
    dispatchCooldown[cdKey]=now
    local row=dispatchFetch(callId)
    dispatchLog(callId,'created',who,('target=%s responders=%d'):format(target.label,#recipients))

    if target.kind=='service' and tostring(target.key or '')=='admin' then
        cookieDispatchLog('admin_call','관리자 긴급전화',reason,{
            {name='응답 가능 관리자',value=tostring(#recipients)..'명',inline=true},
        },{actorSrc=src,actorLabel='신고자',eventKey='admin_phone_call'})
    elseif target.kind=='faction' and target.factionType=='police' then
        cookieDispatchLog('police_report','경찰청 신고',reason,{
            {name='접수 대상',value=tostring(target.label),inline=true},
            {name='응답 가능',value=tostring(#recipients)..'명',inline=true},
        },{actorSrc=src,actorLabel='신고자',eventKey='police_report'})
    elseif target.kind=='faction' and target.factionType=='security' then
        cookieDispatchLog('security_report','보안국 신고',reason,{
            {name='접수 대상',value=tostring(target.label),inline=true},
            {name='응답 가능',value=tostring(#recipients)..'명',inline=true},
        },{actorSrc=src,actorLabel='신고자',eventKey='security_report'})
    end

    for _,sid in ipairs(recipients) do TriggerClientEvent('cookie_phone:client:dispatchIncoming',sid,dispatchPublicCall(row)) end
    TriggerClientEvent('cookie_phone:client:dispatchNotice',src,{title=('CALL #%04d'):format(callId),message=('%s에 콜을 전송했습니다. 응답 가능 인원 %d명'):format(target.label,#recipients),type='success'})
    return {ok=true,id=callId,callLabel=('CALL #%04d'):format(callId),available=#recipients}
end)

local function dispatchCancelInternal(src,callId)
    local who=dispatchIdentity(src); local row=dispatchFetch(callId)
    if not who or not row then return {ok=false,reason='콜을 찾을 수 없습니다.'} end
    if tostring(row.caller_citizenid or '')~=tostring(who.citizenid or '') then return {ok=false,reason='본인이 보낸 콜만 취소할 수 있습니다.'} end
    if row.status~='pending' and row.status~='accepted' then return {ok=false,reason='이미 종료된 콜입니다.'} end
    local changed=MySQL.update.await([[UPDATE cookie_dispatch_calls SET status='cancelled',cancelled_at=NOW() WHERE id=? AND status IN ('pending','accepted')]],{callId})
    if not changed or changed<1 then return {ok=false,reason='콜 상태가 이미 변경되었습니다.'} end
    local target=dispatchTargetInfo(row.target_key)
    if target then
        for _,sid in ipairs(GetPlayers()) do
            sid=tonumber(sid)
            if sid and dispatchEligibleForTarget(sid,target) then
                TriggerClientEvent('cookie_phone:client:dispatchRemove',sid,callId)
                TriggerClientEvent('cookie_phone:client:dispatchNotice',sid,{title=('CALL #%04d'):format(callId),message=('%s님이 콜을 취소했습니다.'):format(row.caller_name or '신고자'),type='error'})
            end
        end
    end
    if row.accepted_by_citizenid then
        for _,raw in ipairs(GetPlayers()) do
            local sid=tonumber(raw); local ident=sid and dispatchIdentity(sid) or nil
            if ident and ident.citizenid==row.accepted_by_citizenid then
                TriggerClientEvent('cookie_phone:client:dispatchGpsClear',sid)
                TriggerClientEvent('cookie_phone:client:dispatchNotice',sid,{title=('CALL #%04d'):format(callId),message=('%s님이 콜을 취소했습니다.'):format(row.caller_name or '신고자'),type='error'})
            end
        end
    end
    dispatchLog(callId,'cancelled',who,'caller cancelled')
    TriggerClientEvent('cookie_phone:client:dispatchNotice',src,{title=('CALL #%04d'):format(callId),message='콜을 취소했습니다.',type='info'})
    return {ok=true}
end

lib.callback.register('cookie_phone:dispatchCancel', function(src,callId)
    return dispatchCancelInternal(src,tonumber(callId))
end)

local function dispatchAccept(src,callId)
    callId=tonumber(callId); if not callId or dispatchAfk(src) then return end
    local row=dispatchFetch(callId); if not row or row.status~='pending' then TriggerClientEvent('cookie_phone:client:dispatchRemove',src,callId); return end
    local target=dispatchTargetInfo(row.target_key)
    if not target or not dispatchEligibleForTarget(src,target) then
        TriggerClientEvent('cookie_phone:client:dispatchNotice',src,{title=('CALL #%04d'):format(callId),message='현재 이 콜을 접수할 수 있는 상태가 아닙니다.',type='error'}); return
    end
    local who=dispatchIdentity(src); if not who then return end
    -- status='pending' 조건부 UPDATE로 동시 접수 시 단 한 명만 성공한다.
    local changed=MySQL.update.await([[UPDATE cookie_dispatch_calls SET status='accepted',accepted_by_license=?,accepted_by_citizenid=?,accepted_by_gobun=?,accepted_by_name=?,accepted_at=NOW() WHERE id=? AND status='pending']],{
        who.license,who.citizenid,who.gobun,who.name,callId
    })
    if not changed or changed<1 then
        TriggerClientEvent('cookie_phone:client:dispatchRemove',src,callId)
        TriggerClientEvent('cookie_phone:client:dispatchNotice',src,{title=('CALL #%04d'):format(callId),message='다른 팩션원이 먼저 접수했습니다.',type='info'}); return
    end
    row=dispatchFetch(callId)
    local recipients=dispatchRecipients(target)
    for _,sid in ipairs(recipients) do
        TriggerClientEvent('cookie_phone:client:dispatchRemove',sid,callId)
        if sid~=src then TriggerClientEvent('cookie_phone:client:dispatchNotice',sid,{title=('CALL #%04d'):format(callId),message=('%s님이 콜을 접수했습니다.'):format(who.name),type='info'}) end
    end
    TriggerClientEvent('cookie_phone:client:dispatchAcceptedSelf',src,dispatchPublicCall(row))
    local callerSrc=sourceByLicense(row.caller_license)
    if callerSrc then
        local kind=dispatchAnnouncementKind(target)
        local objectText=kind=='신고' and '신고를' or '호출을'
        TriggerClientEvent('cookie_phone:client:dispatchNotice',callerSrc,{title=('CALL #%04d'):format(callId),message=('%s에서 %s 접수했습니다. 담당자: %s'):format(row.target_label or '상대 팩션',objectText,who.name),type='success'})
    end
    dispatchBroadcastAccepted(row,target,who)
    dispatchLog(callId,'accepted',who,('caller=%s'):format(row.caller_name or ''))
end

RegisterNetEvent('cookie_phone:server:dispatchAccept', function(callId) dispatchAccept(source,callId) end)

lib.callback.register('cookie_phone:dispatchGetCall', function(src,callId)
    local who=dispatchIdentity(src); local row=dispatchFetch(callId)
    if not who or not row then return {ok=false,reason='콜을 찾을 수 없습니다.'} end
    if row.status~='accepted' or tostring(row.accepted_by_citizenid or '')~=tostring(who.citizenid or '') then return {ok=false,reason='본인이 접수한 활성 콜만 GPS를 설정할 수 있습니다.'} end
    return {ok=true,call=dispatchPublicCall(row)}
end)

lib.callback.register('cookie_phone:dispatchClose', function(src,callId,reason)
    local who=dispatchIdentity(src); local row=dispatchFetch(callId); reason=dispatchCleanText(reason,180)
    if not who or not row then return {ok=false,reason='콜을 찾을 수 없습니다.'} end
    if row.status~='accepted' then return {ok=false,reason='접수 상태의 콜만 종료할 수 있습니다.'} end
    if tostring(row.accepted_by_citizenid or '')~=tostring(who.citizenid or '') then return {ok=false,reason='콜을 접수한 담당자만 종료할 수 있습니다.'} end
    if #reason<2 then return {ok=false,reason='종료 사유를 입력하세요.'} end
    local changed=MySQL.update.await([[UPDATE cookie_dispatch_calls SET status='closed',close_reason=?,closed_at=NOW() WHERE id=? AND status='accepted' AND accepted_by_citizenid=?]],{reason,callId,who.citizenid})
    if not changed or changed<1 then return {ok=false,reason='콜 상태가 이미 변경되었습니다.'} end
    TriggerClientEvent('cookie_phone:client:dispatchGpsClear',src)
    local callerSrc=sourceByLicense(row.caller_license)
    if callerSrc then TriggerClientEvent('cookie_phone:client:dispatchNotice',callerSrc,{title=('CALL #%04d'):format(callId),message=('%s에서 콜 처리를 완료했습니다. 결과: %s'):format(row.target_label or '상대 팩션',reason),type='success'}) end
    local target=dispatchTargetInfo(row.target_key)
    if target then
        for _,sid in ipairs(dispatchRecipients(target)) do
            if sid~=src then TriggerClientEvent('cookie_phone:client:dispatchNotice',sid,{title=('CALL #%04d'):format(callId),message=('%s님이 콜을 종료했습니다. · %s'):format(who.name,reason),type='info'}) end
        end
    end
    dispatchLog(callId,'closed',who,reason)

    cookieDispatchLog('report_close','신고 종결',reason,{
        {name='신고자',value=('%s / %s'):format(
            tostring(row.caller_gobun or '-'),
            tostring(row.caller_name or '-')
        ),inline=true},
        {name='접수 팩션',value=tostring(row.target_label or '-'),inline=true},
    },{actorSrc=src,actorLabel='종결자',eventKey='report_close'})

    return {ok=true}
end)

RegisterNetEvent('cookie_phone:server:setAfk', function(value)
    local src=source; value=value==true
    Player(src).state:set('cookieAfk',value,true)
    if value then TriggerClientEvent('cookie_phone:client:dispatchClearIncoming',src) else dispatchSyncPendingFor(src) end
end)

RegisterNetEvent('cookie_phone:server:dispatchSyncPending', function() dispatchSyncPendingFor(source) end)
RegisterNetEvent('cookie_phone:server:dispatchOverviewPush', function() dispatchPushOverview(source) end)

AddEventHandler('playerDropped', function()
    dispatchCooldown[tostring(source)] = nil
end)

CreateThread(function()
    Wait(1700)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_dispatch_calls (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            target_kind VARCHAR(16) NOT NULL,
            target_key VARCHAR(64) NOT NULL,
            target_faction_id INT NULL,
            target_label VARCHAR(100) NOT NULL,
            caller_license VARCHAR(255) NOT NULL,
            caller_citizenid VARCHAR(64) NOT NULL,
            caller_gobun INT NULL,
            caller_name VARCHAR(80) NOT NULL,
            caller_phone VARCHAR(40) NULL,
            reason VARCHAR(180) NOT NULL,
            x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
            status VARCHAR(16) NOT NULL DEFAULT 'pending',
            responder_count INT NOT NULL DEFAULT 0,
            accepted_by_license VARCHAR(255) NULL,
            accepted_by_citizenid VARCHAR(64) NULL,
            accepted_by_gobun INT NULL,
            accepted_by_name VARCHAR(80) NULL,
            close_reason VARCHAR(180) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            accepted_at DATETIME NULL,
            cancelled_at DATETIME NULL,
            closed_at DATETIME NULL,
            INDEX idx_dispatch_status_target(status,target_key),
            INDEX idx_dispatch_caller(caller_citizenid,status),
            INDEX idx_dispatch_accept(accepted_by_citizenid,status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_dispatch_event_log (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            call_id BIGINT UNSIGNED NOT NULL,
            action VARCHAR(24) NOT NULL,
            actor_citizenid VARCHAR(64) NULL,
            actor_name VARCHAR(80) NULL,
            detail VARCHAR(500) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_dispatch_log_call(call_id,id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    for _,raw in ipairs(GetPlayers()) do
        local sid=tonumber(raw); if sid then Player(sid).state:set('cookieAfk',false,true) end
    end
end)
print('^2[COOKIE PHONE]^7 MESSAGE PHOTO SAVE + AFKZONE SYNC V13.9.0 ready')
