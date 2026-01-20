-- collision.lua
-- 矩形碰撞检测和分离系统

local collision = {}

-- 配置常量
local CONFIG = {
    MAX_ITERATIONS = 16,
    PADDING = 3,
    CENTER_TOLERANCE = 7, -- 中心点误差容忍范围, 如果在范围内, 就当作是在一个中心, 以便提前以更好看的方式排列, 7 刚好小于一格
    MoveDistRatio = 1,    -- 每次慢慢移动太墨迹了, 尝试以一定倍率移动
    NEIGHBOUR_CHECK_PADDING = 3,
    PADDING_MAX_NEIGHBOUR = 6,    
}

local rectCollidedNeighbourCount = {}
local rectIsOutOfRoom = {}

-- ========== 工具函数 ==========

-- 计算矩形中心点
local function getCenter(rect)
    return {
        x = rect.x + rect.width / 2,
        y = rect.y + rect.height / 2
    }
end

-- 检查矩形是否碰撞
local function isRectOverlapping(a, b, padding)
    if not a or not b then
        return false
    end

    padding = padding or 0

    -- 完全在左侧、右侧、上方或下方
    return not (a.x + a.width <= b.x - 2 * padding or
        a.x >= b.x + b.width + 2 * padding or
        a.y + a.height <= b.y - 2 * padding or
        a.y >= b.y + b.height + 2 * padding)
end

-- 检查矩形是否完全在房间外
local function isRectOutsideRoom(rect, roomRect)
    if not roomRect then
        return false
    end

    -- 完全在左侧、右侧、上方或下方
    return rect.x + rect.width < roomRect.x or
        rect.x > roomRect.x + roomRect.width or
        rect.y + rect.height < roomRect.y or
        rect.y > roomRect.y + roomRect.height
end

-- 检查两个矩形中心是否在误差范围内
local function areCentersClose(rectA, rectB, tolerance)
    local centerA = getCenter(rectA)
    local centerB = getCenter(rectB)

    local dx = math.abs(centerA.x - centerB.x)
    local dy = math.abs(centerA.y - centerB.y)

    return dx <= tolerance and dy <= tolerance
end

-- 计算两个矩形的重叠区域
local function getOverlap(rectA, rectB, padding)
    local overlapX = math.min(rectA.x + rectA.width, rectB.x + rectB.width) -
        math.max(rectA.x, rectB.x) + 2 * padding
    local overlapY = math.min(rectA.y + rectA.height, rectB.y + rectB.height) -
        math.max(rectA.y, rectB.y) + 2 * padding

    return overlapX, overlapY
end

-- ========== 重叠组处理 ==========

-- 找出所有重叠组(中心点接近的矩形)
local function findOverlapGroups(rects, roomRect)
    local groups = {}
    local processed = {}

    for i = 1, #rects do
        -- 跳过房间外的矩形
        if not processed[i] and not isRectOutsideRoom(rects[i], roomRect) then
            local group = { i }
            processed[i] = true

            -- 找出所有与 i 中心接近的矩形
            for j = i + 1, #rects do
                if not processed[j] and not isRectOutsideRoom(rects[j], roomRect) then
                    if areCentersClose(rects[i], rects[j], CONFIG.CENTER_TOLERANCE) then
                        table.insert(group, j)
                        processed[j] = true
                    end
                end
            end

            if #group > 1 then
                table.insert(groups, group)
            end
        end
    end

    return groups
end



-- 分散重叠组中的矩形
local function disperseOverlapGroup(rects, group)
    if #group == 0 then return end

    local baseRect = rects[group[1]]
    local baseCenter = getCenter(baseRect)

    local totalWidth = (CONFIG.PADDING + baseRect.width) * #group - CONFIG.PADDING
    local startX = baseCenter.x - totalWidth / 2

    local totalHeight = (CONFIG.PADDING + baseRect.height) * #group - CONFIG.PADDING
    local startY = baseCenter.y - totalHeight / 2

    for i = 1, #group do
        local idx = group[i]
        local rect = rects[idx]

        -- 根据矩形形状决定排列方向
        if rect.height > rect.width then
            -- 瘦高矩形:水平排列
            local newX = startX + (i - 1) * (CONFIG.PADDING + baseRect.width)


            rect.offsetX = (rect.offsetX or 0) + newX - rect.x
            rect.x = newX

            local newCenterY = baseCenter.y
            local newY = newCenterY - rect.height / 2
            rect.offsetY = (rect.offsetY or 0) + newY - rect.y
            rect.y = newY
        else
            -- 矮宽矩形或正方形:垂直排列
            local newY = startY + (i - 1) * (CONFIG.PADDING + baseRect.height)


            rect.offsetY = (rect.offsetY or 0) + newY - rect.y
            rect.y = newY

            local newCenterX = baseCenter.x
            local newX = newCenterX - rect.width / 2
            rect.offsetX = (rect.offsetX or 0) + newX - rect.x
            rect.x = newX
        end
    end
end

-- ========== 碰撞分离 ==========

-- 计算从中心出发的分离向量
local function calculateSeparationVector(rectA, rectB, overlapX, overlapY)
    local centerA = getCenter(rectA)
    local centerB = getCenter(rectB)

    -- 计算中心向量
    local dx = centerB.x - centerA.x
    local dy = centerB.y - centerA.y

    -- 计算距离
    local distance = math.sqrt(dx * dx + dy * dy)

    -- 避免除零
    if distance < 0.001 then
        -- 如果中心重合, 则默认向下
        local angle = math.pi * 0.5
        return math.cos(angle), math.sin(angle)
    end

    -- 归一化方向向量
    local dirX = dx / distance
    local dirY = dy / distance

    return dirX, dirY
end
local function sign(x)
    return x > 0 and 1 or x < 0 and -1 or 0
end

-- 执行单次碰撞检测和分离迭代
local function performCollisionIteration(rects, roomRect)
    local moveMap = {}
    for i = 1, #rects do
        moveMap[i] = { dx = 0, dy = 0, count = 0 }
    end

    for i = 1, #rects do
        local rectA = rects[i]

        -- 只处理房间内的矩形
        if not rectIsOutOfRoom[i] then
            for j = i + 1, #rects do
                local rectB = rects[j]

                -- 只处理房间内的矩形
                if not rectIsOutOfRoom[j] then
                    -- 当 trigger text 不与其他 trigger text 碰撞时, padding 设为 0, 以防在 text 没有明显重叠的情况下被挤出
                    local averageNeighbourDensity = (rectCollidedNeighbourCount[i] + rectCollidedNeighbourCount[j]) / 2
                    local padding = CONFIG.PADDING * averageNeighbourDensity / CONFIG.PADDING_MAX_NEIGHBOUR
                    if padding > CONFIG.PADDING then
                        padding=CONFIG.PADDING
                    end

                    local overlapX, overlapY = getOverlap(rectA, rectB, padding)

                    -- 检测是否碰撞
                    if overlapX > 0 and overlapY > 0 then
                        -- 计算分离方向(从中心出发)
                        local dirX, dirY = calculateSeparationVector(rectA, rectB, overlapX, overlapY)

                        -- 计算分离距离(取较小重叠 + padding)
                        local separationDist = math.min(overlapX, overlapY) / 2
                        if overlapX < overlapY then
                            dirX = sign(dirX)
                        else
                            dirY = sign(dirY)
                        end

                        -- 计算每个方向的移动量
                        local moveX = dirX * separationDist * CONFIG.MoveDistRatio
                        local moveY = dirY * separationDist * CONFIG.MoveDistRatio

                        -- A 向相反方向移动, B 向正方向移动
                        moveMap[i].dx = moveMap[i].dx - moveX
                        moveMap[i].dy = moveMap[i].dy - moveY
                        moveMap[i].count = moveMap[i].count + 1

                        moveMap[j].dx = moveMap[j].dx + moveX
                        moveMap[j].dy = moveMap[j].dy + moveY
                        moveMap[j].count = moveMap[j].count + 1
                    end
                end
            end
        end
    end

    -- 应用移动
    for i = 1, #rects do
        local move = moveMap[i]
        if move.count > 0 then
            local dx = move.dx / move.count
            local dy = move.dy / move.count

            rects[i].offsetX = (rects[i].offsetX or 0) + dx
            rects[i].offsetY = (rects[i].offsetY or 0) + dy
            rects[i].x = rects[i].x + dx
            rects[i].y = rects[i].y + dy
        end
    end
end

local function updateRectsState(rects, roomRect)
    rectCollidedNeighbourCount = {}
    rectIsOutOfRoom = {}
    for i = 1, #rects do
        rectCollidedNeighbourCount[i] = 0
        for j = 1, #rects do
            if i ~= j and isRectOverlapping(rects[i], rects[j], CONFIG.NEIGHBOUR_CHECK_PADDING) then
                rectCollidedNeighbourCount[i] = rectCollidedNeighbourCount[i] + 1
            end
        end
        rectIsOutOfRoom[i] = isRectOutsideRoom(rects[i], roomRect)
    end
end


-- ========== 主函数 ==========

-- 通过碰撞模拟返回每个矩形的位置
-- @param rects 矩形数组 {{x, y, width, height}, ...}
-- @param roomRect 房间矩形 {x, y, width, height} (可选)
-- @return 修改后的矩形数组(带 offsetX, offsetY 字段)
function collision.getExtrudedRects(rects, roomRect)
    -- 初始化偏移量
    for i = 1, #rects do
        rects[i].offsetX = rects[i].offsetX or 0
        rects[i].offsetY = rects[i].offsetY or 0
    end

    updateRectsState(rects, roomRect)

    -- 1. 处理重叠组(中心接近的矩形)
    local overlapGroups = findOverlapGroups(rects, roomRect)
    for _, group in ipairs(overlapGroups) do
        disperseOverlapGroup(rects, group)
    end

    -- 2. 碰撞分离迭代
    for _ = 1, CONFIG.MAX_ITERATIONS do
        performCollisionIteration(rects, roomRect)
    end


    return rects
end

-- 设置配置参数
function collision.setConfig(config)
    if config.maxIterations then CONFIG.MAX_ITERATIONS = config.maxIterations end
    if config.padding then CONFIG.PADDING = config.padding end
    if config.centerTolerance then CONFIG.CENTER_TOLERANCE = config.centerTolerance end
end

-- 获取当前配置
function collision.getConfig()
    return {
        maxIterations = CONFIG.MAX_ITERATIONS,
        padding = CONFIG.PADDING,
        centerTolerance = CONFIG.CENTER_TOLERANCE,
    }
end

function collision.rectContainsPoint(rect, x, y, padding)
    padding = padding or 0
    return x >= rect.x - padding and x < rect.x + rect.width + padding and y >= rect.y - padding and y < rect.y + rect.height + padding
end


return collision
