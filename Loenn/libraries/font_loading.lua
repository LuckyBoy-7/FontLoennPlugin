local maxTestedLoennVersion = require("utils.version_parser")("1.0.5")
local tooHighLoennVersion = require("utils.version_parser")("1.0.6")
local currentLoennVersion = require("meta").version
local logging = require("logging")

if currentLoennVersion >= tooHighLoennVersion then
  logging.error("Font Loenn Plugin/font_loading.lua NOT loaded, version is not 1.0.5 or under")
  return nil
elseif currentLoennVersion > maxTestedLoennVersion then
  logging.info("Font Loenn Plugin/font_loading.lua was loaded but this version has not been tested(> 1.0.5).")
end

local mods = require("mods")
local fonts = require("fonts")
local drawableText = require("structs.drawable_text")
local languageRegistry = require("language_registry")
local sceneHandler = require("scene_handler")
local celesteRender = require("celeste_render")
local tasks = require("utils.tasks")
local triggerHandler = require("triggers")
local utils = require("utils")
local depths = require("consts.object_depths")
local drawableRectangle = require("structs.drawable_rectangle")
local tools = require("tools")
local state = require("loaded_state")
local selectionUtils = require("selections")
local toolUtils = require("tool_utils")
local debugUtils = require("debug_utils")

local event = mods.requireFromPlugin("libraries.event")
local hook = mods.requireFromPlugin("libraries.LuaModHook")
local collision = mods.requireFromPlugin("libraries.collision")


local library = {}



local modSettings = mods.getModSettings("FontLoennPlugin")

local CONFIG = {
    DEBUG = false,
}


-- default
if modSettings.useHiresPixelFont == nil then
    modSettings.useHiresPixelFont = false
elseif modSettings.extrudeOverlappingTriggerText == nil then
    modSettings.extrudeOverlappingTriggerText = false
elseif modSettings.highlightTriggerTextOnSelected == nil then
    modSettings.highlightTriggerTextOnSelected = false
elseif modSettings.addShadowToFont == nil then
    modSettings.addShadowToFont = false
elseif modSettings.stretchTextOnSmallTrigger == nil then
    modSettings.stretchTextOnSmallTrigger = false
end

-- copied from AurorasLoennPlugin's "copied from AnotherLoenTool lol thanks!!!" lol thanks!!!
local function checkbox(menu, lang, toggle, active)
  local item = $(menu):find(item -> item[1] == lang )
  if not item then
    item = {}
    table.insert(menu, item)
  end
  item[1] = lang
  item[2] = toggle
  item[3] = "checkbox"
  item[4] = active
end


local MoveDevice = {}
local function injectCheckboxes()
    local menubar = require("ui.menubar").menubar
    local viewMenu = $(menubar):find(menu -> menu[1] == "view")[2]
    local fontLoennPluginDropdown = {}
    local fontLoennPluginGroup = {"FontLoennPlugin", fontLoennPluginDropdown}

    table.insert(viewMenu, fontLoennPluginGroup)
    checkbox(fontLoennPluginDropdown, "FontLoennPlugin_useHiresPixelFont",
                function()
                    modSettings.useHiresPixelFont = not modSettings.useHiresPixelFont
                    fonts:useFont(modSettings.useHiresPixelFont)
                end,
                function() return modSettings.useHiresPixelFont end)
    checkbox(fontLoennPluginDropdown, "FontLoennPlugin_extrudeOverlappingTriggerText",
                function()
                    modSettings.extrudeOverlappingTriggerText = not modSettings.extrudeOverlappingTriggerText
                    clearAllCaches()
                end,
                function() return modSettings.extrudeOverlappingTriggerText end)
    checkbox(fontLoennPluginDropdown, "FontLoennPlugin_highlightTriggerTextOnSelected",
                function()
                    modSettings.highlightTriggerTextOnSelected = not modSettings.highlightTriggerTextOnSelected
                    clearAllCaches()
                end,
                function() return modSettings.highlightTriggerTextOnSelected end)
     checkbox(fontLoennPluginDropdown, "FontLoennPlugin_addShadowToFont",
                function()
                    modSettings.addShadowToFont = not modSettings.addShadowToFont
                    clearAllCaches()
                end,
                function() return modSettings.addShadowToFont end)
      checkbox(fontLoennPluginDropdown, "FontLoennPlugin_stretchTextOnSmallTrigger",
                function()
                    modSettings.stretchTextOnSmallTrigger = not modSettings.stretchTextOnSmallTrigger
                    clearAllCaches()
                end,
                function() return modSettings.stretchTextOnSmallTrigger end)
end

injectCheckboxes()


local pico8FontPath = "fonts/pico8_font.png"
local pico8FontString = [=[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"'`-_/1234567890!?[](){}.,;:<>+=%#^*~ ]=]
local pico8FFont = love.graphics.newImageFont(pico8FontPath, pico8FontString, 1)
local pico8FontScale = 1

local hiresFontPath = string.format("%s/Graphics/Atlases/%s/%s.png", mods.commonModContent, "Loenn/FontLoennPlugin",
  "hi-res_pixel_font")
local hiresFontString = [=[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,!?-+/():;%&`'*#=[]"_{}<>^~ ]=]
local hiresFont = love.graphics.newImageFont(hiresFontPath, hiresFontString, 1)
local hiresFontScale = 0.5

-- 更改字体
if not fonts.hooked_by_FontLoennPlugin then
  fonts.hooked_by_FontLoennPlugin = true


  function fonts:useFont(hires)
    if (hires) then
      self.fontString = hiresFontString
      self.font = hiresFont
      -- based on fontScale of pico8 font
      self.fontScale = hiresFontScale
    else
      self.fontString = pico8FontString
      self.font = pico8FFont
      self.fontScale = pico8FontScale
    end

    fonts.font:setLineHeight(1.25)

    if (self.font ~= love.graphics.getFont()) then
      love.graphics.setFont(self.font)
      fonts.onChanged:invoke()
    end
  end

  fonts.onChanged = event.new()
end

local StretchTextSizeThreshold2 = 32
local StretchTextSizeThreshold4 = 16

local function tryStretchTriggerText(x, y, width, height)
  if modSettings.stretchTextOnSmallTrigger then
    if width < StretchTextSizeThreshold4 then
      x = x - width * 1.5
      width = width * 4
    elseif width < StretchTextSizeThreshold2 then
      x = x - width / 2
      width = width * 2
    end

    if height < StretchTextSizeThreshold4 then
       y = y - height * 1.5
      height = height * 4
    elseif height < StretchTextSizeThreshold2 then
      y = y - height / 2
      height = height * 2
    end
  end
  return x, y, width, height
end


local function getTextRect(text, x, y, width, height, font, fontSize, trim)
  x, y, width, height = tryStretchTriggerText(x, y, width, height)
  
  font = font or love.graphics.getFont()
  fontSize = fontSize or 1

  if trim ~= false then
    text = utils.trim(text)
  end


  -- 文字尺寸
  local fontHeight = font:getHeight()
  local fontLineHeight = font:getLineHeight()
  local _, lines = font:getWrap(text, width / fontSize)
  local textHeight = (#lines - 1) * (fontHeight * fontLineHeight) + fontHeight

  -- 计算实际文本宽度（取所有行中最宽的）
  local maxWidth = 0
  for i = 1, #lines do
    local lineWidth = font:getWidth(lines[i])
    if lineWidth > maxWidth then
      maxWidth = lineWidth
    end
  end

  -- 居中偏移
  local actualWidth = maxWidth * fontSize
  local offsetX = math.floor((width - actualWidth) / 2) + 1
  local offsetY = math.floor((height - textHeight * fontSize) / 2) + 1

  -- 实际矩形
  local rectX = x + offsetX
  local rectY = y + offsetY
  local rectWidth = actualWidth  -- 使用实际宽度
  local rectHeight = textHeight * fontSize

  return {
    x = rectX,
    y = rectY,
    width = rectWidth,
    height = rectHeight,
  }
end

local triggerToTextOffsetRect = {}
local roomNameToHaveInitialized = {}
local shouldRedrawRoom = nil

local function checkShouldRebuildTriggerTextOffset(room)
  local roomName = room.name
  -- 如果还没初始化
  if roomNameToHaveInitialized[roomName] == nil then
    roomNameToHaveInitialized[roomName] = true
    return true
  end

  if shouldRedrawRoom == nil then
    return false
  end
  if shouldRedrawRoom.name == roomName then
    shouldRedrawRoom = nil
    return true
  end
  return false
end

local debugOrigTextRects = {}

local function tryUpdateTriggerTextOffset(room, triggersList)
  if modSettings.extrudeOverlappingTriggerText == false then
    return
  end
  if checkShouldRebuildTriggerTextOffset(room) == false then
    return
  end

  local rects = {}

  for _, trigger in ipairs(triggersList) do
    local displayName = triggerHandler.triggerText(room, trigger)


    local x = trigger.x or 0
    local y = trigger.y or 0

    local width = trigger.width or 16
    local height = trigger.height or 16
    local triggerTextRect = getTextRect(displayName, x, y, width, height, fonts.font,
      fonts.fontScale * triggerHandler.triggerFontSize)
    table.insert(rects, triggerTextRect)
    if CONFIG.DEBUG then
      debugOrigTextRects[trigger] = triggerTextRect
    end
  end

  local roomRect = {x = 0, y = 0, width = room.width, height = room.height}
  local extrudedRects = collision.getExtrudedRects(rects, roomRect)
  for i, trigger in ipairs(triggersList) do
    triggerToTextOffsetRect[trigger] = extrudedRects[i]
  end
end


if not rawget(triggerHandler, "drawSelected_hooked_by_FontLoennPlugin") then
  rawset(triggerHandler, "drawSelected_hooked_by_FontLoennPlugin", true)

  local orig_drawSelected = triggerHandler.drawSelected
  function triggerHandler.drawSelected(room, layer, trigger, color)
    shouldRedrawRoom = room
    orig_drawSelected(room, layer, trigger, color)
  end
end



-- 在 task 创建完 batch 后, 尝试调整 trigger 字体的位置
if not rawget(celesteRender, "getTriggerBatch_hooked_by_FontLoennPlugin") then
  rawset(celesteRender, "getTriggerBatch_hooked_by_FontLoennPlugin", true)

  local orig_getTriggerBatch = celesteRender.getTriggerBatch
  function celesteRender.getTriggerBatch(room, triggersList, viewport, registeredTriggers, forceRedraw)
    tryUpdateTriggerTextOffset(room, triggersList)
    local orderedBatches = orig_getTriggerBatch(room, triggersList, viewport, registeredTriggers, forceRedraw)
    return orderedBatches
  end

  -- 重新覆盖方法
  local depthBatchingFunctions = hook.get_local(celesteRender.forceRoomBatchRender, "depthBatchingFunctions")
  for _, value in ipairs(depthBatchingFunctions) do
    if value[1] == "Triggers" then
      value[3] = celesteRender.getTriggerBatch
    end
  end
end


-- 在创建 canvas 和 绘制 的时候根据字号改变缩放倍率
local roomCache = hook.get_local(celesteRender.releaseBatch, "roomCache")

hook.hook_local_func(celesteRender.forceRoomCanvasRender, "getRoomCanvas", function(orig, room, state, selected)
  roomCache = hook.get_local(celesteRender.releaseBatch, "roomCache")
  local viewport = state.viewport
  local orderedBatches = celesteRender.getRoomBatches(room, state)
  local roomName = room.name

  local cache = roomCache[roomName]

  if not cache then
    cache = {}
    roomCache[roomName] = cache
  end

  if orderedBatches and not cache.canvas then
    local batchingTasks = hook.get_local(celesteRender.clearBatchingTasks, "batchingTasks")
    cache.canvas = tasks.newTask(
      function(task)
        local scale = 1 / fonts.fontScale
        local width = (room.width or 0) * scale
        local height = (room.height or 0) * scale

        local canvas = love.graphics.newCanvas(width, height)

        canvas:renderTo(function()
          if scale ~= 1 then
            love.graphics.push()
            love.graphics.scale(scale, scale)
          end

          for _, batch in ipairs(orderedBatches) do
            for _, drawable in ipairs(batch) do
              drawable:draw()
            end
          end

          if scale ~= 1 then
            love.graphics.pop()
          end
        end)

        tasks.update(canvas)
      end,
      nil,
      batchingTasks,
      { room = room }
    )
  end


  return cache.canvas and cache.canvas.result, cache.canvas
end)


-- 在应用 canvas 的时候根据字号改变缩放倍率
local orig_love_graphics_draw = love.graphics.draw
if not rawget(celesteRender, "drawRoom_hooked_by_FontLoennPlugin") then
  rawset(celesteRender, "drawRoom_hooked_by_FontLoennPlugin", true)

  local orig_draw_room = celesteRender.drawRoom
  function celesteRender.drawRoom(room, state, selected, visible)
    -- trick
    local redraw = selected or hook.get_local(celesteRender.drawRoom, "ALWAYS_REDRAW_UNSELECTED_ROOMS")

    love.graphics.draw = function(texture)
      if redraw then
        orig_love_graphics_draw(texture)
        return
      end
      orig_love_graphics_draw(texture, 0, 0, 0, fonts.fontScale, fonts.fontScale)
    end
    orig_draw_room(room, state, selected, visible)
    love.graphics.draw = orig_love_graphics_draw
  end
end



-- 修改 trigger 之类的像素字体大小
if not drawableText.hooked_by_FontLoennPlugin then
  drawableText.hooked_by_FontLoennPlugin = true

  local orig_drawableText_fromText = drawableText.fromText
  function drawableText.fromText(text, x, y, width, height, font, fontSize, color)
    fontSize = fontSize or 0
    local drawable = orig_drawableText_fromText(text, x, y, width, height, font, fontSize * fonts.fontScale, color)
    return drawable
  end
end


-- 记录 placement 获取 drawable 的时机, 因为 placement draw 的时候会把像素颜色设为白色, 所以阴影反而会导致糊掉, 所以此时不渲染阴影
local duringPlacement = false
local function tryHookPlacement()
  local placement = tools.tools["placement"]
  if not placement then
    return
  end
  if not placement.hooked_by_FontLoennPlugin then
    placement.hooked_by_FontLoennPlugin = true

    local orig_update = placement.update
    function placement.update(dt)
      duringPlacement = true
      orig_update(dt)
      duringPlacement = false
    end
  end
end


local function tryHookSelection()
  local selection = tools.tools["selection"]
  if not selection then
    return
  end
  hook.hook_local_func(selection.mousereleased, "selectionFinished", function(orig, x, y, fromClick)
      local room = state.getSelectedRoom()
      orig(x, y, fromClick)
      -- rebuild batch
      -- 如果什么都不选 selection.getSelectionTargets() 为空拿不到要重绘的 layer 反而导致没有重绘, 所以我们手动使用另一个函数
      -- selectionUtils.redrawTargetLayers(room, selection.getSelectionTargets())
      toolUtils.redrawTargetLayer(room, {"triggers"})
  end)


  local layerSortingPriority = hook.get_local(selectionUtils.orderSelectionsByScore, "layerSortingPriority")
  function selectionUtils.orderSelectionsByScore(selections)
      table.sort(selections, function(lhs, rhs)
        local lhsPriority = layerSortingPriority[lhs.layer] or 1
        local rhsPriority = layerSortingPriority[rhs.layer] or 1

        if lhsPriority ~= rhsPriority then
            return lhsPriority > rhsPriority
        end

        local lhsArea = lhs.width * lhs.height
        local rhsArea = rhs.width * rhs.height

        if lhsArea ~= rhsArea then
            return lhsArea < rhsArea
        end

        -- 如果层级和面积都一样，强制按 ID 排序，保证稳定性(使得 trigger 叠一起的时候能以更舒服的顺序选择)
        -- 注意：这里假设 lhs.item 存在且有 _id 属性
        local lhsId = (lhs.item and lhs.item._id) or 0
        local rhsId = (rhs.item and rhs.item._id) or 0
        return lhsId < rhsId
    end)

    return selections
  end
end

local editor = sceneHandler.scenes["Editor"]
if not rawget(editor, "hooked_by_FontLoennPlugin") then
  editor.hooked_by_FontLoennPlugin = true

  local orig_firstEnter = editor.firstEnter
  function editor.firstEnter(self)
    orig_firstEnter(self)
    tryHookPlacement()
    tryHookSelection()
  end
end

-- ctrl + f5 会生成新的 tools 实例, 所以得重新钩一次
if not rawget(debugUtils, "hooked_by_FontLoennPlugin") then
  debugUtils.hooked_by_FontLoennPlugin = true

  local orig_reloadEverything = debugUtils.reloadEverything
  function debugUtils.reloadEverything(self)
    orig_reloadEverything(self)
    tryHookPlacement()
    tryHookSelection()
  end
end

local function isItemSelected(item, selections)
    if not selections then
        return false
    end
    
    for _, target in ipairs(selections.getSelectionTargets()) do
        if target.item == item then
            return true
        end
    end
    
    return false
end
-- 为高清像素字体添加阴影
-- 在 task 创建完 batch 后, 尝试调整 trigger 字体的位置(不知道 lua 有没有类似 il 一样的插入方式, 感觉还是直接整体替换方便点, 反正我一个版本更一版应该问题不大())
if not triggerHandler.hooked_by_FontLoennPlugin then
  triggerHandler.hooked_by_FontLoennPlugin = true

  local orig_trigger_getDrawable = triggerHandler.getDrawable
  function triggerHandler.getDrawable(name, handler, room, trigger, viewport)
    local addShadow = modSettings.addShadowToFont and not duringPlacement
    local extrudeTriggerText = modSettings.extrudeOverlappingTriggerText


    local displayName = triggerHandler.triggerText(room, trigger)

    local x = trigger.x or 0
    local y = trigger.y or 0


    local width = (trigger.width or 16)
    local height = trigger.height or 16

    

    local fillColor, borderColor, textColor = triggerHandler.triggerColor(room, trigger)

    -- highlight
    if modSettings.highlightTriggerTextOnSelected and isItemSelected(trigger, tools.tools["selection"]) then
      textColor = {1, 1, 0, 1}      
    end
    local borderedRectangle = drawableRectangle.fromRectangle("bordered", x, y, width, height, fillColor, borderColor)
    local drawables = borderedRectangle:getDrawableSprite()


    -- extrude
    if (extrudeTriggerText and triggerToTextOffsetRect[trigger] ~= nil) then
      local dx, dy = triggerToTextOffsetRect[trigger].offsetX, triggerToTextOffsetRect[trigger].offsetY
      x = x + dx
      y = y + dy
    end

    -- 查看 textRect 范围
    if CONFIG.DEBUG then
      if debugOrigTextRects[trigger] then
          -- local textRect = getTextRect(displayName, x, y, width, height)
          local origTextRectWithPadding = debugOrigTextRects[trigger]
          local debugPadding = 3
          local borderedRectangle = drawableRectangle.fromRectangle("bordered", origTextRectWithPadding.x - debugPadding, origTextRectWithPadding.y - debugPadding, origTextRectWithPadding.width + debugPadding * 2, origTextRectWithPadding.height + debugPadding * 2, {0, 0, 1, 1}, {0, 0, 1, 1})
          table.insert(drawables, borderedRectangle)


          local origTextRect = debugOrigTextRects[trigger]
          local borderedRectangle = drawableRectangle.fromRectangle("bordered", origTextRect.x, origTextRect.y, origTextRect.width, origTextRect.height, {1, 0, 0, 1}, {1, 0, 0, 1})
          table.insert(drawables, borderedRectangle)
      end
    end

    x, y, width, height = tryStretchTriggerText(x, y, width, height)
    
    local textDrawable = drawableText.fromText(displayName, x, y, width, height, nil, triggerHandler.triggerFontSize,
      textColor)
    textDrawable.depth = depths.triggers - 1
   
    table.insert(drawables, textDrawable)
    if addShadow then
       -- shadow
      local offset = fonts.fontScale
      local shadowTextDrawable = drawableText.fromText(displayName, x + offset, y + offset, width, height, nil,
      triggerHandler.triggerFontSize, { 0, 0, 0, 1 })
      shadowTextDrawable.depth = depths.triggers - 0.9
      table.insert(drawables, shadowTextDrawable)
    end



    return drawables, depths.triggers
  end
end



-- 修改标题字体(因为注册时机比较晚, 所以没办法一开始的时候直接切换 loading 字体)
-- 因为 Loenn 加载场景是先 rerequire 场景的 lua, 然后通过深拷贝实现的, 所以我们得通过索引拿而不是 require 拿
local loading = sceneHandler.scenes["Loading"]
-- 因为访问 scene 中不存在的元素实际上会给 input_device 发一个通知, 而不会返回 nil, 所以这里要 rawget
if not rawget(loading, "hooked_by_FontLoennPlugin") then
  loading.hooked_by_FontLoennPlugin = true

  local orig_loading_setText = loading.setText
  function loading:setText(text)
    orig_loading_setText(self, text)
    self.textScale = fonts.fontScale * 8
    self.textOffsetX = (fonts.font:getWidth(self.text .. "..") * self.textScale) / 2
  end

  local language = languageRegistry.getLanguage()
  loading:setText(language.scenes.loading.loading)
end



function clearExtrudedTriggerTextCache()
  triggerToTextOffsetRect = {}
  roomNameToHaveInitialized = {}
  shouldRedrawRoom = nil
end

function clearAllCaches()
  celesteRender.clearBatchingTasks()
  celesteRender.invalidateRoomCache()
  clearExtrudedTriggerTextCache()
end

-- events
fonts.onChanged:add(function()
  clearAllCaches()
end
)

fonts.onChanged:add(function()
  if (loading == nil) then
    return
  end
  local language = languageRegistry.getLanguage()
  loading:setText(language.scenes.loading.loading)
end
)


fonts:useFont(modSettings.useHiresPixelFont)

return library
