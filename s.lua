-- BossUI_Server.lua
local AIO = AIO or require("AIO")
if not AIO then
    print("|cFFFF0000[错误]|r AIO模块未加载")
    return
end

-- 初始化事件处理器
local BossHandlers = AIO.AddHandlers("BossUI", {})
if not BossHandlers then
    print("|cFFFF0000[错误]|r 无法初始化BossHandlers")
    return
end

-- ██████ 配置缓存 ███████████████████████████████████████████
local BOSS_CONFIGS = {}

-- ██████ 辅助函数 ███████████████████████████████████████████
local function tContains(table, item)
    for _, value in pairs(table) do
        if value == item then
            return true
        end
    end
    return false
end

local function GetPlayerFromKiller(killer)
    if not killer then return nil end
    if killer:IsPlayer() then return killer end
    local owner = killer:GetOwner()
    return owner and owner:IsPlayer() and owner or nil
end
-- ██████ 日志记录接口███████████████████████████████████████████
local function LogCoinUsage(player, config, rewardType, rewardDetail, mailed)
    local bossName = "未知BOSS"
    local creatureInfo = WorldDBQuery(string.format(
        "SELECT name FROM creature_template WHERE entry = %d", 
        config.entry_id
    ))
    if creatureInfo then
        bossName = creatureInfo:GetString(0)
    end
    local success = WorldDBExecute([[
        INSERT INTO `_幸运币_记录` (
            玩家GUID, 角色名, BOSS编号, BOSS名称, 
            使用ROLL币ID, 使用数量, 奖励类型, 奖励内容, 是否邮件发送
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], 
    player:GetGUIDLow(),
    player:GetName(),
    config.entry_id,
    bossName,
    config.roll_coin_id,
    1,
    rewardType,
    rewardDetail,
    mailed and 1 or 0)

--    if success then
        print(string.format("|cFF00FF00[日志]|r 成功记录玩家【%s】 击杀【%s】奖励数据，奖励类型【%s】，奖励内容【%s】", player:GetName(),bossName,rewardType,rewardDetail))
--     else
--         print("|cFFFF0000[错误]|r 日志写入失败")
 --    end
end

-- ██████ 配置加载 ███████████████████████████████████████████
local function LoadBossConfigs()
    print("\n|cFF00FF00[BossUI]|r 加载数据库配置...")
    local result = WorldDBQuery("SELECT * FROM `_幸运币`")
    
    if not result then
        print("|cFFFF0000[错误]|r 未找到幸运币配置表")
        return
    end
    
    repeat
        local config = {
            entry_id     = result:GetUInt32(0),
            roll_coin_id = result:GetUInt32(1),
            exclude_items = {},
            win_rate     = result:GetUInt32(3) or 90,
            gold_min     = result:GetUInt32(4) or 50,
            gold_max     = result:GetUInt32(5) or 150
        }
        
        local excludeStr = result:GetString(2)
        if excludeStr and excludeStr ~= "" then
            for id in string.gmatch(excludeStr, "%d+") do
                table.insert(config.exclude_items, tonumber(id))
            end
        end
        
        BOSS_CONFIGS[config.entry_id] = config
        print(string.format("|cFF00FF00[加载配置]|r BOSS:%d 排除物品:%d个",
            config.entry_id, #config.exclude_items))
    until not result:NextRow()
end
-- ██████ 修正后的获取生物实际lootid ███████████████████████████████████████
local function GetCreatureLootID(creatureEntry, difficulty)
    -- 基础查询（始终获取原始entry的lootid）
    local baseQuery = WorldDBQuery(string.format(
        "SELECT lootid, difficulty_entry_1, difficulty_entry_2, difficulty_entry_3 FROM creature_template WHERE entry = %d",
        creatureEntry
    ))
    if not baseQuery then return creatureEntry, creatureEntry end  -- 默认返回原始entry
    
    local baseLootID = baseQuery:GetUInt32(0)
    local diffEntries = {
        baseQuery:GetUInt32(1),  -- 难度1
        baseQuery:GetUInt32(2),  -- 难度2
        baseQuery:GetUInt32(3)   -- 难度3
    }
    
    -- 处理有效难度（1-3）
    if difficulty >= 1 and difficulty <= 3 then
        local diffEntry = diffEntries[difficulty]
        if diffEntry and diffEntry ~= 0 then
            local lootQuery = WorldDBQuery(string.format(
                "SELECT lootid FROM creature_template WHERE entry = %d",
                diffEntry
            ))
            if lootQuery then
                local lootID = lootQuery:GetUInt32(0)
                return diffEntry, lootID ~= 0 and lootID or diffEntry  -- 确保lootid有效
            end
        end
    end
    
    -- 默认返回原始entry的lootid
    return creatureEntry, baseLootID ~= 0 and baseLootID or creatureEntry
end

-- ██████ 修改后的掉落获取函数 ███████████████████████████████████████
local function GetBossLoot(creatureEntry, difficulty, excludeList)
    -- 获取实际entry和lootid
    local realEntry, lootID = GetCreatureLootID(creatureEntry, difficulty)
    
    print(string.format("|cFF00FF00[掉落查询]|r 生物Entry:%d 难度:%d => 实际Entry:%d LootID:%d", 
        creatureEntry, difficulty, realEntry, lootID))
    
    local lootItems = {}
    local sql = string.format([[
        SELECT item FROM creature_loot_template 
        WHERE Entry = %d AND Reference = 0
        UNION ALL
        SELECT item FROM reference_loot_template 
        WHERE entry IN (
            SELECT Reference FROM creature_loot_template 
            WHERE Entry = %d AND Reference != 0
        )
    ]], lootID, lootID)
    
    local query = WorldDBQuery(sql)
    
    if query then
        while query:NextRow() do
            local itemId = query:GetUInt32(0)
            if itemId ~= 0 and not tContains(excludeList, itemId) then
                table.insert(lootItems, itemId)
            end
        end
    end
    return lootItems
end


-- ██████ 修正队伍成员处理逻辑 █████████████████████████████████████████
local function OnBossDeath(event, creature, killer)
    local player = GetPlayerFromKiller(killer)
    local entryId = creature:GetEntry()
    local config = BOSS_CONFIGS[entryId]
    local MAX_DISTANCE = 50
    
    if not player or not config then return end

    -- 获取副本难度并修正范围
    local map = player:GetMap()
    local difficulty = map and map:GetDifficulty() or 0
    difficulty = math.min(math.max(difficulty, 0), 3)  -- 确保0-3
    
    -- 获取实际掉落列表
    local lootItems = GetBossLoot(entryId, difficulty, config.exclude_items)
    
    -- [保持原有队伍/团队处理逻辑...]
    
    -- 重新构建玩家列表（修复组队逻辑）
    local players = {}
    table.insert(players, player)  -- 确保包含击杀者
    
    -- 获取有效队伍成员
    if player:IsInGroup() then
        local group = player:GetGroup()
        if group then
            -- 使用更安全的成员获取方式
            local members = group:GetMembers() or {}
            for _, member in pairs(members) do  -- 使用pairs代替ipairs
                if member:GetGUID() ~= player:GetGUID() and 
                   member:IsInWorld() and 
                   creature:GetDistance(member) <= MAX_DISTANCE then
                    table.insert(players, member)
                end
            end
        end
    end
    -- 添加调试输出
    print(string.format("[弹窗检测] 需要通知的玩家数量：%d", #players))
    
    -- 发送弹窗请求
    for _, target in pairs(players) do
        local coinCount = target:GetItemCount(config.roll_coin_id)
        print(string.format("[玩家检查] %s 持有%d个roll币 距离：%.1f码", 
            target:GetName(), 
            coinCount,
            creature:GetDistance(target)))
            
        if coinCount > 0 and creature:GetDistance(target) <= MAX_DISTANCE then
            print(string.format("|cFF00FF00[发送弹窗]|r 给 %s", target:GetName()))
            AIO.Handle(target, "BossUI", "ShowBossUI", {
                coins = coinCount,
                bossEntry = entryId,
                bossName = creature:GetName(),
                roll_coin_id = config.roll_coin_id,
                difficulty = difficulty
            })
        end
    end
end

-- ██████ 修正服务端处理函数 █████████████████████████████████████████
function BossHandlers.ProcessRoll(player, data)
    -- 增强参数验证
    if type(data) ~= "table" then
        print(string.format("|cFFFF0000[协议错误]|r 玩家 %s 发送了非表格数据", player:GetName()))
        return
    end
    
    -- 必要字段检查
    local requiredFields = {"confirm", "bossEntry", "roll_coin_id", "difficulty"}
    for _, field in ipairs(requiredFields) do
        if data[field] == nil then
            print(string.format("|cFFFF0000[协议错误]|r 玩家 %s 缺少必要字段:%s", 
                player:GetName(), field))
            return
        end
    end

    -- 调试输出接收到的数据
    print(string.format("|cFF00FF00[DEBUG]|r 收到 %s 的ROLL请求数据：confirm=%s, bossEntry=%d, coinID=%d, difficulty=%d",
        player:GetName(),
        tostring(data.confirm),
        data.bossEntry,
        data.roll_coin_id,
        data.difficulty
    ))
    if type(data) ~= "table" or not data.bossEntry or not data.roll_coin_id then
        print(string.format("|cFFFF0000[协议错误]|r 玩家 %s 发送了无效数据", player:GetName()))
        return
    end

    -- 添加二次确认检查
    if not data.confirm then
        print(string.format("|cFF00FF00[取消]|r 玩家 %s 取消了ROLL币使用", player:GetName()))
        return 
    end

    -- 添加玩家状态检查
    if player:IsInCombat() then
        AIO.Handle(player, "BossUI", "ShowRollResult", "|cFFFF0000战斗中无法使用ROLL币！|r")
        return
    end

    -- 添加物品持有检查
    if player:GetItemCount(data.roll_coin_id) < 1 then
        AIO.Handle(player, "BossUI", "ShowRollResult", "|cFFFF0000ROLL币数量不足！|r")
        return
    end
	
    -- 新增难度参数处理
    local difficulty = data.difficulty or 0
    difficulty = math.min(math.max(difficulty, 0), 3)  -- 安全范围
    
    -- 获取实际掉落列表
    local lootItems = GetBossLoot(data.bossEntry, difficulty, config.exclude_items)
	
    print(string.format("[DEBUG] 收到请求，bossEntry: %s", tostring(data.bossEntry)))
    local config = BOSS_CONFIGS[data.bossEntry]
    if not config then
        print(string.format("|cFFFF0000[配置错误]|r 未找到entry_id为%d的配置", data.bossEntry))
        return 
    end
    -- 确保此处有执行到物品/金币发放逻辑
    print("|cFF00FF00[DEBUG]|r 进入奖励发放流程")
	
    player:RemoveItem(config.roll_coin_id, 1) --移除一个roll币
        print("|cFFFF0000 物品移除")


    math.randomseed(os.time())
    local rand = math.random(1, 100)
    print(string.format("随机数: %d, 赢率: %d", rand, config.win_rate))
    
    if rand <= config.win_rate then --玩家掷色子中奖处理流程
        print("|cFF00FF00[DEBUG]|r 玩家中奖")
		
   -- 修改掉落获取调用
   -- local lootItems = GetBossLoot(data.bossEntry, difficulty, config.exclude_items)
	
		print(string.format("|cFF00FF00[DEBUG]|r 可用掉落物品数量：%d", #lootItems))
        
        if #lootItems == 0 then   --判断掉该掉落物品组物品数量为0的执行流程
            local gold = config.gold_max
            player:ModifyMoney(gold * 10000)
            AIO.Handle(player, "BossUI", "ShowRollResult", 
                string.format("|cFFFFA500生物掉落表错误，可掉落为0！获得最高%d金币补偿|r", gold))
            LogCoinUsage(player, config, '金币', gold.."金币", false)--记录日志：发送金币
            return
        end
        
        local itemId = lootItems[math.random(#lootItems)]
        if player:AddItem(itemId, 1) then
		--增加个拿到物品喊话功能：开始
		    local itemLink = GetItemLink(itemId)
			local coinName = GetItemLink(config.roll_coin_id)
--			player:SendBroadcastMessage(string.format("|cFF00FF00[幸运币系统]|r 你使用%s获得了：%s", coinName, itemLink))
			-- 使用Yell方法喊话
			player:Yell(string.format("看我至臻好运符，以%s之名，我获得了%s！", coinName, itemLink), 0)
		--增加个拿到物品喊话功能：结束
            AIO.Handle(player, "BossUI", "ShowRollResult", 
                string.format("|cFF00FF00恭喜获得：%s|r", GetItemLink(itemId)))
            LogCoinUsage(player, config, '物品', GetItemLink(itemId), false)----记录日志：发送装备
        else
		-- ██████ 执行包满邮寄装备到邮箱 ████████████
			    print("|cFFFF0000[错误]|r 物品发放失败，尝试邮件发送")
            -- 邮件发送逻辑...
			local GID = player:GetGUIDLow()
            local Mail_title = "幸运币获得物品"
			local Mail_text = "背包已满，幸运币获得物品已发送至邮箱，请尽快提取。"
			local Mail_item_ID  = itemId
			local Mail_item_Num = 1
            local Mail_Type_ID = 61
			print("发送邮件功能：开始")
 			SendMail( Mail_title, Mail_text , GID, 0, Mail_Type_ID, 0, 0, 0, Mail_item_ID, Mail_item_Num )           
			print("发送邮件功能：结束")
            AIO.Handle(player, "BossUI", "ShowRollResult", 
                string.format("|cFFFFA500物品已发送至邮箱：%s|r", GetItemLink(itemId)))
		
			--增加个拿到物品喊话功能：开始
		    local itemLink = GetItemLink(itemId)
			local coinName = GetItemLink(config.roll_coin_id)
			-- 使用Yell方法喊话
			player:Yell(string.format("看我至臻好运符，以%s之名，我获得了%s！", coinName, itemLink), 0)
			
		    LogCoinUsage(player, config, '物品', GetItemLink(itemId), true)--记录日志：发送装备到邮箱
        end
	else--没有中将，发放安慰奖：金币
	    local gold = math.random(config.gold_min, config.gold_max)--获得配置区间一个随机金币数
        player:ModifyMoney(gold * 10000)
        AIO.Handle(player, "BossUI", "ShowRollResult", 
        string.format("|cFFFFA500没有中奖装备，请再接再厉！获得%d金币|r", gold))
        LogCoinUsage(player, config, '金币', gold.."金币", false)--记录日志：发送金币
    end
end

-- ██████ 初始化系统 ███████████████████████████████████████████
LoadBossConfigs()
for entryId in pairs(BOSS_CONFIGS) do
    RegisterCreatureEvent(entryId, 4, OnBossDeath)
    print(string.format("|cFF00FF00[注册事件]|r BOSS:%d 已注册死亡事件", entryId))
end