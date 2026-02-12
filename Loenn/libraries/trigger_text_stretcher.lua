-- TriggerTextStretcher 类
-- 用于计算和缓存 Trigger 文本的拉伸矩形

local utils = require("utils")
local fonts = require("fonts")

local TriggerTextStretcher = {}
TriggerTextStretcher.__index = TriggerTextStretcher

-- 创建新实例
function TriggerTextStretcher.new()
    local self = setmetatable({}, TriggerTextStretcher)
    self.cache = {} -- 缓存格式: { [text] = maxWordWidth }
    return self
end

-- 清空缓存
function TriggerTextStretcher:clearCache()
    self.cache = {}
end

-- 计算文本中最长单词的宽度
function TriggerTextStretcher:calculateMaxWordWidth(text, font, fontScale)
    local maxWordWidth = 0

    -- 先按换行符切分
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        line = utils.trim(line) -- 去除首尾空白

        -- 检查是否首尾是括号
        local isWrappedInParens = (string.sub(line, 1, 1) == "(" and string.sub(line, -1) == ")")

        if isWrappedInParens then
            -- 整行作为一个单词
            local wordWidth = font:getWidth(line) * fontScale
            if wordWidth > maxWordWidth then
                maxWordWidth = wordWidth
            end
        else
            -- 按空格切分
            for word in string.gmatch(line, "[^%s]+") do
                local wordWidth = font:getWidth(word) * fontScale
                if wordWidth > maxWordWidth then
                    maxWordWidth = wordWidth
                end
            end
        end
    end

    return maxWordWidth
end

-- 从缓存获取该文本的最长单词宽度
function TriggerTextStretcher:getFromCache(text)
    return self.cache[text]
end

-- 保存该文本的最长单词宽度到缓存
function TriggerTextStretcher:saveToCache(text, maxWordWidth)
    self.cache[text] = maxWordWidth
end

-- 计算拉伸后的矩形（带缓存）
function TriggerTextStretcher:stretch(x, y, width, height, text)
    -- 尝试从缓存获取该文本的最长单词宽度
    local maxWordWidth = self:getFromCache(text)

    if not maxWordWidth then
        -- 计算该文本的最长单词宽度
        local font = love.graphics.getFont()
        maxWordWidth = self:calculateMaxWordWidth(text, font, fonts.fontScale)

        -- 保存到缓存 (text -> maxWordWidth)
        self:saveToCache(text, maxWordWidth)
    end

    -- 如果最大单词宽度超过原始宽度，则拉伸
    if maxWordWidth > width then
        x = x - (maxWordWidth - width) / 2
        width = maxWordWidth
    end

    return x, y, width, height
end

return TriggerTextStretcher
