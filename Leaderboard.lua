-- leaderboard.lua
local Leaderboard = {}
Leaderboard.__index = Leaderboard

-----------------------------------------------------------
-- 辅助函数：二分查找插入位置
-- 在 players 数组中找到一个正确的插入位置，使得数组依然按照 score 降序排列
-- 参数：
--   players: 数组，每个元素为 { member, score }
--   score: 待插入记录的分数
-- 返回值：
--   插入位置的索引（1-based）
-----------------------------------------------------------
local function binarySearchInsertPos(players, score)
    local low = 1
    local high = #players + 1  -- 插入位置可能在末尾之后

    while low < high do
        local mid = math.floor((low + high) / 2)
        -- 因为降序排列：若中间记录的 score 大于等于待插入记录，则插入位置在右边
        if players[mid].score >= score then
            low = mid + 1
        else
            high = mid
        end
    end
    return low
end

-----------------------------------------------------------
-- 构造函数，创建一个新的排行榜实例
-----------------------------------------------------------
function Leaderboard:new()
    local lb = {
        players = {}  -- 按贡献度降序的记录数组，每个记录为 { member = "server:player", score = number }
    }
    setmetatable(lb, Leaderboard)
    return lb
end

-----------------------------------------------------------
-- 根据 member 标识查找记录在 players 数组中的索引
-- 如果找到则返回对应索引，否则返回 nil
-----------------------------------------------------------
local function findPlayerIndex(players, member)
    for index, record in ipairs(players) do
        if record.member == member then
            return index
        end
    end
    return nil
end

-----------------------------------------------------------
-- 添加或更新指定玩家的贡献度
-- 参数：
--   lb        : 排行榜对象（Leaderboard实例）
--   server_id : 服务器 id（数字或字符串均可）
--   player_id : 玩家 id
--   delta     : 要增加的贡献度，可能为负数
-- 返回：
--   更新后的贡献度，如果贡献度<=0时记录被移除，则返回 0
-----------------------------------------------------------
function Leaderboard:addOrUpdateContribution(server_id, player_id, delta)
    local member = server_id .. ":" .. player_id
    local players = self.players

    -- 查找是否已存在该玩家记录
    local index = findPlayerIndex(players, member)
    local newScore = delta

    if index then
        -- 找到已有记录，更新贡献度
        newScore = players[index].score + delta
        -- 移除原来的记录
        table.remove(players, index)
    end

    -- 如果更新后贡献度小于或等于0，则不插入记录
    if newScore <= 0 then
        return 0
    end

    -- 使用二分查找得到插入位置
    local pos = binarySearchInsertPos(players, newScore)
    table.insert(players, pos, { member = member, score = newScore })

    return newScore
end

-----------------------------------------------------------
-- 删除指定玩家的记录
-- 参数：
--   lb        : 排行榜对象
--   server_id : 服务器 id
--   player_id : 玩家 id
-- 返回：
--   true 表示删除成功，false 表示未找到记录
-----------------------------------------------------------
function Leaderboard:removePlayer(server_id, player_id)
    local member = server_id .. ":" .. player_id
    local players = self.players
    local index = findPlayerIndex(players, member)
    if index then
        table.remove(players, index)
        return true
    end
    return false
end

-----------------------------------------------------------
-- 获取排行榜前 N 名玩家数据
-- 参数：
--   lb   : 排行榜对象
--   top_n: 要返回的记录数
-- 返回：
--   一个数组，每个元素为 { member, score }
-----------------------------------------------------------
function Leaderboard:getTopPlayers(top_n)
    local result = {}
    for i = 1, math.min(top_n, #self.players) do
        -- 复制数据，避免外部修改内部结构
        result[#result+1] = {
            member = self.players[i].member,
            score = self.players[i].score
        }
    end
    return result
end

-----------------------------------------------------------
-- 用于打印排行榜，调试使用
-----------------------------------------------------------
function Leaderboard:print()
    for i, record in ipairs(self.players) do
        print(string.format("%d. %s 贡献度: %d", i, record.member, record.score))
    end
end

-----------------------------------------------------------
-- 示例：创建各个地块的排行榜并操作
-----------------------------------------------------------

-- 假设每个地块拥有独立的排行榜，我们用一个 table 来管理
local leaderboards = {}   -- 键为 plot_id，值为 Leaderboard 对象

-- 获取某个地块的排行榜，如果不存在则新建
local function getLeaderboard(plot_id)
    if not leaderboards[plot_id] then
        leaderboards[plot_id] = Leaderboard:new()
    end
    return leaderboards[plot_id]
end

-- 示例操作：
-- 1. 玩家在不同地块上增加贡献
local lb3 = getLeaderboard(3)
print("操作前排行榜(地块3):")
lb3:print()

-- 玩家 1001（服务器1）在地块3增加100贡献
local score = lb3:addOrUpdateContribution(1, 1001, 100)
print(string.format("更新后玩家1:1001的贡献度: %d", score))

-- 玩家 1002（服务器1）在地块3增加95贡献
lb3:addOrUpdateContribution(1, 1002, 95)
-- 玩家 1003（服务器2）在地块3增加110贡献
lb3:addOrUpdateContribution(2, 1003, 110)
-- 玩家 1001 再增加20贡献
lb3:addOrUpdateContribution(1, 1001, 20)

print("\n操作后排行榜(地块3):")
lb3:print()

-- 2. 获取地块3排行榜前 2 名玩家数据
local top2 = lb3:getTopPlayers(2)
print("\n地块3排行榜前2名：")
for i, record in ipairs(top2) do
    print(string.format("%d. %s 贡献度: %d", i, record.member, record.score))
end

-- 3. 如果玩家贡献扣减导致贡献度降至0或以下，则从排行榜中移除
lb3:addOrUpdateContribution(1, 1002, -100)  -- 玩家 1002 贡献从95扣100，应被删除

print("\n扣分后排行榜(地块3):")
lb3:print()

return Leaderboard
