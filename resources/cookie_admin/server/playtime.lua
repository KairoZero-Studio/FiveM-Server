

local ACCRUE_MS = 60000
local ready = false

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await("ALTER TABLE `cookie_user` ADD COLUMN IF NOT EXISTS `rp_minute` INT NOT NULL DEFAULT 0", {})
        MySQL.query.await("ALTER TABLE `cookie_user` ADD COLUMN IF NOT EXISTS `job_minute` INT NOT NULL DEFAULT 0", {})
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_job_lifetime_stats (
                license VARCHAR(255) NOT NULL,
                job_key VARCHAR(64) NOT NULL,
                job_label VARCHAR(80) NOT NULL DEFAULT '',
                minute INT UNSIGNED NOT NULL DEFAULT 0,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (license, job_key),
                INDEX idx_cookie_job_lifetime_minute (minute)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]])
        MySQL.query.await([[ALTER TABLE cookie_job_lifetime_stats
            MODIFY COLUMN license VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL]])
    end)

    if ok then
        ready = true

    else

        Wait(5000)
        local ok2 = pcall(function()
            MySQL.query.await("ALTER TABLE `cookie_user` ADD COLUMN IF NOT EXISTS `rp_minute` INT NOT NULL DEFAULT 0", {})
            MySQL.query.await("ALTER TABLE `cookie_user` ADD COLUMN IF NOT EXISTS `job_minute` INT NOT NULL DEFAULT 0", {})
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_job_lifetime_stats (
                license VARCHAR(255) NOT NULL,
                job_key VARCHAR(64) NOT NULL,
                job_label VARCHAR(80) NOT NULL DEFAULT '',
                minute INT UNSIGNED NOT NULL DEFAULT 0,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (license, job_key),
                INDEX idx_cookie_job_lifetime_minute (minute)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]])
        end)
        ready = ok2 and true or false

    end
end)

local function licenseOf(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

CreateThread(function()
    while true do
        Wait(ACCRUE_MS)
        if ready then
            for _, pid in ipairs(GetPlayers()) do
                local src = tonumber(pid)
                local license = src and licenseOf(src)
                if license then
                    local player = exports.qbx_core:GetPlayer(src)
                    local job = player and player.PlayerData and player.PlayerData.job

                    local onJobDuty = job and job.name and job.name ~= 'unemployed' and job.onduty == true

                    if onJobDuty and CookieIsIdle and CookieIsIdle(src) then
                        onJobDuty = false
                    end

                    pcall(function()
                        if onJobDuty then
                            MySQL.update.await(
                                'UPDATE cookie_user SET rp_minute = rp_minute + 1, job_minute = job_minute + 1 WHERE license = ?',
                                { license }
                            )

                            local jobKey = tostring(job.name):sub(1, 64)
                            local jobLabel = tostring(job.label or job.name):sub(1, 80)
                            MySQL.query.await([[
                                INSERT INTO cookie_job_lifetime_stats (license, job_key, job_label, minute)
                                VALUES (?, ?, ?, 1)
                                ON DUPLICATE KEY UPDATE
                                    minute = minute + 1,
                                    job_label = VALUES(job_label)
                            ]], { license, jobKey, jobLabel })
                        else
                            MySQL.update.await(
                                'UPDATE cookie_user SET rp_minute = rp_minute + 1 WHERE license = ?',
                                { license }
                            )
                        end
                    end)

                    if CookieOpenEventAccrue then
                        pcall(CookieOpenEventAccrue, src, license, job, onJobDuty)
                    end
                end
            end
        end
    end
end)
