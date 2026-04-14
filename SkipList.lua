local SkipList = {}
SkipList.__index = SkipList

local MAX_LEVEL = 16
local P = 0.5

-- 节点定义
local function createNode(level, score, player)
    return {
        score = score,
        player = player,
        forward = {},
        level = level
    }
end

-- 创建跳表
function SkipList:new()
    local obj = {
        level = 1,
        header = createNode(MAX_LEVEL, nil, nil),
        length = 0
    }
    setmetatable(obj, self)
    return obj
end

-- 随机层数
function SkipList:randomLevel()
    local level = 1
    while math.random() < P and level < MAX_LEVEL do
        level = level + 1
    end
    return level
end

-- 插入或更新
function SkipList:insert(score, player)
    local update = {}
    local x = self.header

    for i = self.level, 1, -1 do
        while x.forward[i] and x.forward[i].score > score do
            x = x.forward[i]
        end
        update[i] = x
    end

    x = x.forward[1]

    -- 如果已存在该玩家，更新分数
    if x and x.player.id == player.id and x.player.server_id == player.server_id then
        self:delete(player.id)
    end

    local lvl = self:randomLevel()
    if lvl > self.level then
        for i = self.level + 1, lvl do
            update[i] = self.header
        end
        self.level = lvl
    end

    local newNode = createNode(lvl, score, player)
    for i = 1, lvl do
        newNode.forward[i] = update[i].forward[i]
        update[i].forward[i] = newNode
    end

    self.length = self.length + 1

    -- 保持前100名
    if self.length > 100 then
        self:deleteTail()
    end
end

-- 删除
function SkipList:delete(playerId)
    local update = {}
    local x = self.header

    for i = self.level, 1, -1 do
        while x.forward[i] and x.forward[i].player.id ~= playerId do
            x = x.forward[i]
        end
        update[i] = x
    end

    x = x.forward[1]
    if x and x.player.id == playerId then
        for i = 1, self.level do
            if update[i].forward[i] == x then
                update[i].forward[i] = x.forward[i]
            end
        end

        while self.level > 1 and not self.header.forward[self.level] do
            self.level = self.level - 1
        end

        self.length = self.length - 1
    end
end

-- 删除最后一名
function SkipList:deleteTail()
    local x = self.header
    local update = {}

    for i = self.level, 1, -1 do
        while x.forward[i] and x.forward[i].forward[i] do
            x = x.forward[i]
        end
        update[i] = x
    end

    local tail = x.forward[1]
    if tail then
        self:delete(tail.player.id)
    end
end

-- 获取前N名
function SkipList:getTopN(n)
    local result = {}
    local x = self.header.forward[1]
    local count = 0
    while x and count < n do
        table.insert(result, x.player)
        x = x.forward[1]
        count = count + 1
    end
    return result
end

-- 查找玩家排名
function SkipList:getRank(playerId)
    local x = self.header.forward[1]
    local rank = 1
    while x do
        if x.player.id == playerId then
            return rank
        end
        rank = rank + 1
        x = x.forward[1]
    end
    return nil
end

return SkipList
