-- BossUI_Client.lua
local AIO = AIO or require("AIO")

if AIO.AddAddon() then
    return
end

--BossHandlers = AIO.AddHandlers("BossUI", {})
BossHandlers =AIO.AddHandlers("BossUI", {
    ShowBossUI = function(player, data)
        -- 存储必要数据到全局变量
        CURRENT_ROLL_DATA = {
            bossEntry = data.bossEntry,
            roll_coin_id = data.roll_coin_id,  -- 确保这个字段被保存
            difficulty = data.difficulty
        }
        -- 显示弹窗...
    end,
    
    ConfirmRoll = function()
        -- 发送时必须包含所有字段
        AIO.Handle("BossUI", "ProcessRoll", {
            confirm = true,
            bossEntry = CURRENT_ROLL_DATA.bossEntry,
            roll_coin_id = CURRENT_ROLL_DATA.roll_coin_id,  -- 确保包含
            difficulty = CURRENT_ROLL_DATA.difficulty
        })
    end
})


-- ██████ UI配置 ███████████████████████████████████████████
local BossFrame = CreateFrame("Frame", "BossFrame", UIParent)
BossFrame:SetSize(420, 320)
BossFrame:SetPoint("CENTER")
BossFrame:SetFrameStrata("DIALOG")
BossFrame:SetBackdrop({
    bgFile = "Interface\\RAIDFRAME\\UI-RaidFrame-GroupBg",  -- 更改为团队框架背景
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",  -- 金色边框
    edgeSize = 32,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
BossFrame:SetBackdropColor(0, 0, 0, 0.9)  -- 深色半透明背景

-- 添加顶部装饰条
local topBar = BossFrame:CreateTexture(nil, "ARTWORK")
topBar:SetTexture("Interface\\LFGFrame\\UI-LFG-RoleHeader-Glow")
topBar:SetSize(400, 32)
topBar:SetPoint("TOP", 0, 12)
topBar:SetVertexColor(1, 0.8, 0)  -- 金色光效

-- 修改标题样式
local title = BossFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", 0, -20)
title:SetText("|TInterface\\BUTTONS\\UI-GroupLoot-Dice-Up:32:32:0:0|t 幸运币系统")
title:SetShadowOffset(1, -1)
-- 在标题下方添加倒计时文字
local countdownText = BossFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
countdownText:SetPoint("TOP", 0, -50)
countdownText:SetTextColor(1, 0.2, 0.2)  -- 红色强调
countdownText:Hide()

-- 内容区域背景框
local contentBG = CreateFrame("Frame", nil, BossFrame)
contentBG:SetSize(360, 180)
contentBG:SetPoint("CENTER", 0, 0)
contentBG:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Glues\\Common\\Glue-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
contentBG:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

-- 修改内容文本样式
local content = contentBG:CreateFontString(nil, "OVERLAY", "GameFontNormal")
content:SetPoint("CENTER", 0, 0)
content:SetSize(340, 160)
content:SetJustifyH("CENTER")
content:SetJustifyV("MIDDLE")
content:SetTextColor(1, 0.8, 0)  -- 金色文字

-- 按钮容器美化
local buttonContainer = CreateFrame("Frame", nil, BossFrame)
buttonContainer:SetSize(260, 40)
buttonContainer:SetPoint("BOTTOM", 0, 20)



-- 添加底部装饰花纹
local bottomDeco = BossFrame:CreateTexture(nil, "BORDER")
bottomDeco:SetTexture("Interface\\SpellBook\\UI-SpellBookTab-EndPage")
bottomDeco:SetSize(400, 32)
bottomDeco:SetPoint("BOTTOM", 0, -10)
bottomDeco:SetTexCoord(1, 0, 0, 1)  -- 翻转纹理
bottomDeco:SetVertexColor(1, 0.8, 0)  -- 金色

-- ██████ 客户端处理 ███████████████████████████████████████

BossFrame:Hide()


-- 在文件顶部添加计时器框架（放在BossFrame创建之后）
local timerFrame = CreateFrame("Frame")
local currentData = {}



-- 组件初始化


local content = BossFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
content:SetPoint("CENTER", 0, 0)
content:SetText("正在加载挑战信息...")

local buttonContainer = CreateFrame("Frame", nil, BossFrame)
buttonContainer:SetSize(200, 40)
buttonContainer:SetPoint("BOTTOM", 0, 30)

local confirmBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
confirmBtn:SetSize(80, 25)
confirmBtn:SetPoint("LEFT")
confirmBtn:SetText("确定")

-- 修改确认按钮的点击事件
confirmBtn:SetScript("OnClick", function()
    -- 需要传递包含BOSS信息的data对象
    AIO.Handle("BossUI", "ProcessRoll", {
        bossEntry = data.bossEntry,  -- 这里需要访问之前接收到的data
        usedCoin = true
    })
    BossFrame:Hide()
end)

local cancelBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
cancelBtn:SetSize(80, 25)
cancelBtn:SetPoint("RIGHT")
cancelBtn:SetText("取消")
cancelBtn:SetScript("OnClick", function()
    AIO.Handle("BossUI", "ProcessRoll", false)
    BossFrame:Hide()
end)
--右上角的关闭按钮
local closeBtn = CreateFrame("Button", nil, BossFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -5, -5)
closeBtn:SetScript("OnClick", function() 
    timerFrame:SetScript("OnUpdate", nil)
    -- 添加取消请求
    AIO.Handle("BossUI", "ProcessRoll", {
        confirm = false
    })
    BossFrame:Hide() 
end)

-- ██████ 客户端处理 ███████████████████████████████████████
-- 在客户端添加数据缓存

function BossHandlers.ShowBossUI(player, data)
    currentData = data
	local elapsed = 0
    local totalTime = 20  -- 总倒计时时间
    
    -- 初始化倒计时显示
    countdownText:SetText(string.format("|cFFFF0000%d秒|r后自动关闭...", totalTime))
    countdownText:Show()
    
    timerFrame:SetScript("OnUpdate", function(_, updateElapsed)
        elapsed = elapsed + updateElapsed
        local remaining = totalTime - math.floor(elapsed)
        
        -- 更新倒计时文字
        if remaining >= 0 then
            countdownText:SetText(string.format("|cFFFF0000%d秒|r后自动关闭...", remaining))
        end
        
        if elapsed >= totalTime then
            timerFrame:SetScript("OnUpdate", nil)
            AIO.Handle("BossUI", "ProcessRoll", {
                bossEntry = currentData.bossEntry or 0,
                confirm = false
            })
            BossFrame:Hide()
            countdownText:Hide()
        end
    end)
	
    content:SetText(string.format("|cFF00FF00★ 幸运币确认 ★|r\n\n刚刚击败了：\n\n|cFFFFFFFF【%s】|r\n\n拥有|cFF00FF00[%s]|r数量：|cFF00FF00%d|r\n\n是否消耗幸运币额外奖励抽取？",
        data.bossName, 
        GetItemInfo(data.roll_coin_id), 		
        data.coins))
    BossFrame:Show()
    PlaySound(12867)  -- 效果音
end
-- 修改所有关闭操作（添加倒计时隐藏）
local function CloseWindow()
    timerFrame:SetScript("OnUpdate", nil)
    countdownText:Hide()
    BossFrame:Hide()
end
closeBtn:SetScript("OnClick", CloseWindow)



-- 修改按钮点击事件，添加计时器取消
confirmBtn:SetScript("OnClick", function()
	CloseWindow()
    if currentData.bossEntry then
        AIO.Handle("BossUI", "ProcessRoll", {
            bossEntry = currentData.bossEntry,
            confirm = true
        })
    else
        print("|cFFFF0000[错误]|r 未找到BOSS信息")
    end
    BossFrame:Hide()
end)

cancelBtn:SetScript("OnClick", function()
	CloseWindow()
    AIO.Handle("BossUI", "ProcessRoll", {
        bossEntry = currentData.bossEntry or 0,
        confirm = false
    })
    BossFrame:Hide()
end)



function BossHandlers.ShowRollResult(player, resultMsg)
    UIErrorsFrame:AddMessage(resultMsg, 1.0, 1.0, 1.0, 5.0)
    PlaySound(resultMsg:find("恭喜") and 888 or 8952)
end

-- ██████ 窗口行为 █████████████████████████████████████████
BossFrame:SetMovable(true)
BossFrame:EnableMouse(true)
BossFrame:RegisterForDrag("LeftButton")
BossFrame:SetScript("OnDragStart", BossFrame.StartMoving)
BossFrame:SetScript("OnDragStop", BossFrame.StopMovingOrSizing)
tinsert(UISpecialFrames, "BossFrame")