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
local triggers = require("triggers")

local event = mods.requireFromPlugin("libraries.event")
local hook = mods.requireFromPlugin("libraries.LuaModHook")


local library = {}


local modSettings = mods.getModSettings("FontLoennPlugin")


-- default
modSettings.fontType = modSettings.fontType or "pico8"


-- copied from AurorasLoennPlugin's "copied from AnotherLoenTool lol thanks!!!" lol thanks!!!
local function checkbox(menu, lang, toggle, active)
  local item = $(menu):find(item -> item[1] == lang)
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
    checkbox(viewMenu, "FontLoennPlugin_useHiresPixelFont",
                function()
                    modSettings.useHiresPixelFont = not modSettings.useHiresPixelFont
                    fonts:useFont(modSettings.useHiresPixelFont)
                end,
                function() return modSettings.useHiresPixelFont end)
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
      if (redraw) then
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
    local drawable = orig_drawableText_fromText(text, x, y, width, height, font, fontSize * fonts.fontScale, color)
    return drawable
  end
end


-- 为高清像素字体添加阴影
if not triggers.hooked_by_FontLoennPlugin then
  triggers.hooked_by_FontLoennPlugin = true

  local orig_trigger_getDrawable = triggers.getDrawable
  function triggers.getDrawable(name, handler, room, trigger, viewport)
    if (modSettings.useHiresPixelFont == true) then
        local drawables, triggersDepth = orig_trigger_getDrawable(name, handler, room, trigger, viewport)

        local displayName = triggers.triggerText(room, trigger)
        local x = trigger.x or 0
        local y = trigger.y or 0

        local width = trigger.width or 16
        local height = trigger.height or 16


        local offset = fonts.fontScale
        local shadowTextDrawable = drawableText.fromText(displayName, x + offset, y + offset, width, height, nil, triggers.triggerFontSize, {0, 0, 0, 1})
        shadowTextDrawable.depth = triggersDepth - 0.9
        table.insert(drawables, shadowTextDrawable)
        return drawables, triggersDepth
    end

    return orig_trigger_getDrawable(name, handler, room, trigger, viewport)
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



-- events
fonts.onChanged:add(function()
    celesteRender.clearBatchingTasks()
    celesteRender.invalidateRoomCache()
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
