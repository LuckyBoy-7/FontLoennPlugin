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
local menubar = require("ui.menubar")
local viewport_handler = require("viewport_handler")

local event = mods.requireFromPlugin("libraries.event")
local hook = mods.requireFromPlugin("libraries.LuaModHook")
local collision = mods.requireFromPlugin("libraries.collision")
local triggerTextStretcherLib = mods.requireFromPlugin("libraries.trigger_text_stretcher")

local triggerTextStretcher = triggerTextStretcherLib.new()

local library = {}



local modSettings = mods.getModSettings("FontLoennPlugin")

local CONFIG = {
  DEBUG = false,
}


-- default
local function initializeModSettings()
  local defaults = {
    useHiresPixelFont = false,
    extrudeOverlappingTriggerText = false,
    highlightTriggerTextOnSelected = false,
    addShadowToFont = false,
    showCompleteWord = false,
    selectTriggerByClickText = false,
    autoSwitchFont = false,
  }
  
  for key, defaultValue in pairs(defaults) do
    if modSettings[key] == nil then
      modSettings[key] = defaultValue
    end
  end
end

initializeModSettings()

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


local function injectCheckboxes()
    local viewMenu = $(menubar.menubar):find(menu -> menu[1] == "view")[2]
    local fontLoennPluginDropdown = {}
    local fontLoennPluginGroup = {"FontLoennPlugin", fontLoennPluginDropdown}

    table.insert(viewMenu, fontLoennPluginGroup)
    checkbox(fontLoennPluginDropdown, "FontLoennPlugin_useHiresPixelFont",
                function()
                    modSettings.useHiresPixelFont = not modSettings.useHiresPixelFont
                    if not modSettings.autoSwitchFont then
                      fonts:useFont(modSettings.useHiresPixelFont)
                    end
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
      checkbox(fontLoennPluginDropdown, "FontLoennPlugin_showCompleteWord",
                function()
                    modSettings.showCompleteWord = not modSettings.showCompleteWord
                    clearAllCaches()
                end,
                function() return modSettings.showCompleteWord end)
      checkbox(fontLoennPluginDropdown, "FontLoennPlugin_selectTriggerByClickText",
                function()
                    modSettings.selectTriggerByClickText = not modSettings.selectTriggerByClickText
                    clearAllCaches()
                end,
                function() return modSettings.selectTriggerByClickText end)
      checkbox(fontLoennPluginDropdown, "FontLoennPlugin_autoSwitchFont",
                function()
                    modSettings.autoSwitchFont = not modSettings.autoSwitchFont
                    if modSettings.autoSwitchFont then
                      setFontByCurrentScroll()
                    else
                      fonts:useFont(modSettings.useHiresPixelFont)
                    end
                end,
                function() return modSettings.autoSwitchFont end)
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

local function tryStretchTriggerText(x, y, width, height, text)
  if modSettings.showCompleteWord then
    return triggerTextStretcher:stretch(x, y, width, height, text)
  end

  return x, y, width, height
end


local function getTextRect(text, x, y, width, height, font, fontSize, trim)
  x, y, width, height = tryStretchTriggerText(x, y, width, height, text)
  
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
    local lineWidth = font:getWidth(lines[i])  -- 这里有算上字号的
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
  local rectWidth = actualWidth -- 使用实际宽度
  local rectHeight = textHeight * fontSize

  return {
    x = rectX,
    y = rectY,
    width = rectWidth,
    height = rectHeight,
  }
end

local triggerToTextOffsetRect = {}
local roomToTriggerToTextRects = {}
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

  local roomRect = { x = 0, y = 0, width = room.width, height = room.height }
  local extrudedRects = collision.getExtrudedRects(rects, roomRect)
  roomToTriggerToTextRects[room] = {}
  for i, trigger in ipairs(triggersList) do
    triggerToTextOffsetRect[trigger] = extrudedRects[i]
    roomToTriggerToTextRects[room][trigger] = extrudedRects[i]
  end
end


-- 在 load recent map 或者 open new map 的时候清空缓存, 防止 extrude 之类的效果失效
hook.hookOnce(state, "loadFile", state.loadFile, function (orig, filename, roomName)
    orig(filename, roomName)
    clearAllCaches()
end)

-- 管 extrude 那些功能的(得及时刷新)
hook.hookOnce(triggerHandler, "drawSelected", triggerHandler.drawSelected, function (orig, room, layer, trigger, color)
    shouldRedrawRoom = room
    orig(room, layer, trigger, color)
end)


-- 在 task 创建完 batch 后, 尝试调整 trigger 字体的位置
hook.hookOnce(celesteRender, "getTriggerBatch", celesteRender.getTriggerBatch, function (orig, room, triggersList, viewport, registeredTriggers, forceRedraw)
    tryUpdateTriggerTextOffset(room, triggersList)
    local orderedBatches = orig(room, triggersList, viewport, registeredTriggers, forceRedraw)
    return orderedBatches
end)

-- 重新覆盖方法(钩成功了=覆盖, 钩失败了相当于自己覆盖自己)
local depthBatchingFunctions = hook.get_local(celesteRender.forceRoomBatchRender, "depthBatchingFunctions")
for _, value in ipairs(depthBatchingFunctions) do
  if value[1] == "Triggers" then
    value[3] = celesteRender.getTriggerBatch
  end
end

-- 在创建 canvas 和 绘制 的时候根据字号改变缩放倍率
local roomCache = hook.get_local(celesteRender.releaseBatch, "roomCache")

hook.hook_local_func(celesteRender, "getRoomCanvas", celesteRender.forceRoomCanvasRender, function(orig, room, state, selected)
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
hook.hookOnce(celesteRender, "drawRoom", celesteRender.drawRoom, function (orig, room, state, selected, visible)
    -- trick
    local redraw = selected or hook.get_local(celesteRender.drawRoom, "ALWAYS_REDRAW_UNSELECTED_ROOMS")

    love.graphics.draw = function(texture)
      if redraw then
        orig_love_graphics_draw(texture)
        return
      end
      orig_love_graphics_draw(texture, 0, 0, 0, fonts.fontScale, fonts.fontScale)
    end
    orig(room, state, selected, visible)
    love.graphics.draw = orig_love_graphics_draw
end)


-- 修改 trigger 之类的像素字体大小
hook.hookOnce(drawableText, "fromText", drawableText.fromText, function (orig, text, x, y, width, height, font, fontSize, color)
    fontSize = fontSize or 0
    local drawable = orig(text, x, y, width, height, font, fontSize * fonts.fontScale, color)
    return drawable
end)

-- 记录 placement 获取 drawable 的时机, 因为 placement draw 的时候会把像素颜色设为白色, 所以阴影反而会导致糊掉, 所以此时不渲染阴影
local duringPlacement = false
local function tryHookPlacement()
  local placement = tools.tools["placement"]
  if not placement then
    return
  end

  hook.hookOnce(placement, "update", placement.update, function (orig, dt)
      duringPlacement = true
      orig(dt)
      duringPlacement = false
  end)
end


local function tryHookSelection()
  local selection = tools.tools["selection"]
  if not selection then
    return
  end
  hook.hook_local_func(selection, "selectionFinished", selection.mousereleased, function(orig, x, y, fromClick)
    local room = state.getSelectedRoom()
    orig(x, y, fromClick)
    -- rebuild batch
    -- 如果什么都不选 selection.getSelectionTargets() 为空拿不到要重绘的 layer 反而导致没有重绘, 所以我们手动使用另一个函数
    -- selectionUtils.redrawTargetLayers(room, selection.getSelectionTargets())
    toolUtils.redrawTargetLayer(room, { "triggers" })
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

  -- 选中 trigger 字体的时候可以选中 trigger
  hook.hook_local_func(selection, "selectionChanged", selection.mouseclicked, function(orig, x, y, width, height, fromClick)
    if (fromClick and modSettings.selectTriggerByClickText and (selection.layer == "triggers" or type(selection.layer) == "table" and selection.layer._persistenceName == "AllLayers")) then
      local room = state.getSelectedRoom()
      if roomToTriggerToTextRects[room] ~= nil then
        for trigger, triggerTextRect in pairs(roomToTriggerToTextRects[room]) do
          if collision.rectContainsPoint(triggerTextRect, x, y) then
            local rects = {}
            selectionUtils.getSelectionsForItem(room, "triggers", trigger, rects)
            -- 只取 main node, 以防同时选中 main node 和 sub node, 导致无法在 panel 里更改宽高
            for _, node in pairs(rects) do
              if node.node == 0 then
                rects = {node}
                break
              end
            end
            selection.setSelectionPreviews(rects)
            return
          end
        end
      end
    end
    orig(x, y, width, height, fromClick)
  end)
end


local editor = sceneHandler.scenes["Editor"]
hook.hookOnce(editor, "firstEnter", editor.firstEnter, function (orig, self)
    orig(self)
    tryHookPlacement()
    tryHookSelection()
end)


-- ctrl + f5 会生成新的 tools 实例, 所以得重新钩一次
hook.hookOnce(debugUtils, "reloadEverything", debugUtils.reloadEverything, function (orig, self)
    orig(self)
    tryHookPlacement()
    tryHookSelection()
end)

local function setFontScrollWrapper(scrollFunc, force)
  if not modSettings.autoSwitchFont then
    scrollFunc()
    return
  end

  local preScale = viewport_handler.viewport.scale
  scrollFunc()
  local afterScale = viewport_handler.viewport.scale

  if preScale == 1 and afterScale == 2 then
     fonts:useFont(true)
  elseif preScale == 2 and afterScale == 1 then
     fonts:useFont(false)
  end
end

function setFontByCurrentScroll()
  local scale = viewport_handler.viewport.scale
  if scale <= 1 then
    fonts:useFont(false)
    return
  end
  fonts:useFont(true)
end

-- 监听 scroll 尝试自动切换字体
hook.hookOnce(viewport_handler, "zoomIn", viewport_handler.zoomIn, function (orig)
    setFontScrollWrapper(orig)
end)
hook.hookOnce(viewport_handler, "zoomOut", viewport_handler.zoomOut, function (orig)
    setFontScrollWrapper(orig)
end)


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
hook.hookOnce(triggerHandler, "getDrawable", triggerHandler.getDrawable, function (orig, name, handler, room, trigger, viewport)
    local drawables, _ = orig(name, handler, room, trigger, viewport)

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
      textColor = { 1, 1, 0, 1 }
    end
    -- local borderedRectangle = drawableRectangle.fromRectangle("bordered", x, y, width, height, fillColor, borderColor)
    -- local drawables = borderedRectangle:getDrawableSprite()


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
        local borderedRectangle = drawableRectangle.fromRectangle("bordered", origTextRectWithPadding.x - debugPadding,
          origTextRectWithPadding.y - debugPadding, origTextRectWithPadding.width + debugPadding * 2,
          origTextRectWithPadding.height + debugPadding * 2, { 0, 0, 1, 1 }, { 0, 0, 1, 1 })
        table.insert(drawables, borderedRectangle)


        local origTextRect = debugOrigTextRects[trigger]
        local borderedRectangle = drawableRectangle.fromRectangle("bordered", origTextRect.x, origTextRect.y,
          origTextRect.width, origTextRect.height, { 1, 0, 0, 1 }, { 1, 0, 0, 1 })
        table.insert(drawables, borderedRectangle)
      end
    end

    x, y, width, height = tryStretchTriggerText(x, y, width, height, displayName)

    local textDrawable = drawableText.fromText(displayName, x, y, width, height, nil, triggerHandler.triggerFontSize,
      textColor)
    textDrawable.depth = depths.triggers - 1

      -- try remove text part
    local replaceTextSuccess = false
    for i, drawable in ipairs(drawables) do
      if drawable ~= nil and drawable._type == "drawableText" then
        drawables[i] = textDrawable
        replaceTextSuccess = true
        break
      end
    end
    if not replaceTextSuccess then
      table.insert(drawables, textDrawable)
    end

    if addShadow then
      -- shadow
      local offset = fonts.fontScale
      local shadowTextDrawable = drawableText.fromText(displayName, x + offset, y + offset, width, height, nil,
        triggerHandler.triggerFontSize, { 0, 0, 0, 1 })
      shadowTextDrawable.depth = depths.triggers - 0.9
      table.insert(drawables, shadowTextDrawable)
    end



    return drawables, depths.triggers
end)


-- 修改标题字体(因为注册时机比较晚, 所以没办法一开始的时候直接切换 loading 字体)
-- 因为 Loenn 加载场景是先 rerequire 场景的 lua, 然后通过深拷贝实现的, 所以我们得通过索引拿而不是 require 拿
local loading = sceneHandler.scenes["Loading"]
-- 因为访问 scene 中不存在的元素实际上会给 input_device 发一个通知, 而不会返回 nil, 所以这里要 rawget
hook.hookOnce(loading, "setText", loading.setText, function (orig, self, text)
    orig(self, text)
    self.textScale = fonts.fontScale * 8
    self.textOffsetX = (fonts.font:getWidth(self.text .. "..") * self.textScale) / 2
end)

local language = languageRegistry.getLanguage()
loading:setText(language.scenes.loading.loading)


function clearExtrudedTriggerTextCache()
  triggerToTextOffsetRect = {}
  roomToTriggerToTextRects = {}
  roomNameToHaveInitialized = {}
  shouldRedrawRoom = nil
end

function clearAllCaches()
  celesteRender.clearBatchingTasks()
  celesteRender.invalidateRoomCache()
  clearExtrudedTriggerTextCache()
  triggerTextStretcher:clearCache()
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

if modSettings.autoSwitchFont then
  setFontByCurrentScroll()
elseif modSettings.useHiresPixelFont then
  fonts:useFont(true)
else
  fonts:useFont(false)
end

return library
