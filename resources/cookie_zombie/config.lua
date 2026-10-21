

Config = Config or {}
Config.Zombie = {}
Config.Zombie.Debug = false

Config.Zombie.StartNpc = {
    coord      = vec4(2350.0, 3133.0, 48.2, 200.0),
    model      = 's_m_y_dealer_01',
    scenario   = 'WORLD_HUMAN_STAND_IMPATIENT',
    label      = '좀비존 관리인',
    blipSprite = 275, blipColor = 1, blipLabel = '좀비존',
}
Config.Zombie.StagingRadius = 12.0
Config.Zombie.PartyMax      = 4

Config.Zombie.PlayCoord  = vec4(2352.0, 3130.0, 48.2, 20.0)
Config.Zombie.BucketBase = 7100

Config.Zombie.RequireTicket = false
Config.Zombie.TicketItem    = 'zombie_ticket'
Config.Zombie.TicketConsume = true

Config.Zombie.KillTargets    = { [1] = 100, [2] = 250, [3] = 400, [4] = 550 }
Config.Zombie.KillTargetPerExtra = 150

Config.Zombie.Models = {
    'a_m_m_salton_01', 'a_m_m_salton_02', 'a_m_o_salton_01', 'a_m_y_salton_01',
    'a_m_m_hillbilly_01', 'a_m_m_hillbilly_02',
    'a_m_m_rurmeth_01',
    's_m_m_scientist_01',
    'a_m_y_vindouche_01',
    'a_m_m_tramp_01', 'a_f_m_trampbeau_01',
}
Config.Zombie.Model         = 'a_m_m_tramp_01'
Config.Zombie.MaxZombies    = 40
Config.Zombie.SpawnPerTick  = 4
Config.Zombie.SpawnRadius   = { min = 25.0, max = 85.0 }
Config.Zombie.DespawnDist   = 220.0
Config.Zombie.InvincSeconds = 10

Config.Zombie.ForceNight    = false
Config.Zombie.Armour        = 40
Config.Zombie.Accuracy      = 18

Config.Zombie.KillReward = { account = 'cash', moneyMin = 800,  moneyMax = 2200, expPerKill = 1 }
Config.Zombie.WinReward  = { account = 'bank', moneyMin = 80000, moneyMax = 150000 }

Config.Zombie.Drops = {
}

Config.Zombie.RateWindowMs = 3000
Config.Zombie.RateMax      = 15
