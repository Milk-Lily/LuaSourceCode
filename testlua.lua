print("on do file testlua.lua")

local a = 10
local b = a
b = 11
print("a = " .. a)


-- 初始化随机种子
math.randomseed(os.time())

local SkipList = require("skiplist")

-- 假设你已经从MySQL中加载完数据
local data = {
    {id = 1, server_id = 101, land_id = 1, score = 300},
    {id = 2, server_id = 102, land_id = 1, score = 500},
    {id = 3, server_id = 101, land_id = 2, score = 250},
    {id = 4, server_id = 101, land_id = 1, score = 750},
    {id = 5, server_id = 101, land_id = 2, score = 450},
    {id = 6, server_id = 101, land_id = 1, score = 50},
    {id = 7, server_id = 101, land_id = 1, score = 7250},
    {id = 8, server_id = 101, land_id = 1, score = 450},
    {id = 9, server_id = 101, land_id = 2, score = 850},
    {id = 10, server_id = 101, land_id = 1, score = 750},
    {id = 11, server_id = 101, land_id = 2, score = 550},
}

-- 每个地块一个排行榜
local landRankings = {}

for _, row in ipairs(data) do
    local landId = row.land_id
    landRankings[landId] = landRankings[landId] or SkipList:new()

    landRankings[landId]:insert(row.score, {id = row.id, server_id = row.server_id, score = row.score })
end

landRankings[1]:insert(790, {id = 4, server_id = 101, score = 790 })
-- 获取地块1的前10名
local top10 = landRankings[1]:getTopN(10)
for i, player in ipairs(top10) do
    print(string.format("Rank %d: Player %d, Server %d, Contribution %d", i, player.id, player.server_id, player.score))
end

-- 查找某个玩家的排名
local rank = landRankings[1]:getRank(2)
print("Player 2's rank on land 1:", rank or "not in top 100")

