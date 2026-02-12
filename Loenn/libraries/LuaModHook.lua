local LuaModHook = {}

-- 获取 local 变量
function LuaModHook.get_local(func, name)
    local i = 1
    while true do
        local var_name, var_value = debug.getupvalue(func, i)
        if not var_name then break end
        if var_name == name then
            return var_value
        end
        i = i + 1
    end
    return nil
end

-- 修改 local 变量
function LuaModHook.set_local(func, name, value)
    local i = 1
    while true do
        local var_name = debug.getupvalue(func, i)
        if not var_name then break end
        if var_name == name then
            debug.setupvalue(func, i, value)
            return true
        end
        i = i + 1
    end
    return false
end

-- 获取 local 函数
function LuaModHook.get_local_func(func, name)
    return LuaModHook.get_local(func, name)
end

function LuaModHook.getFlagName(funcName)
    return funcName .. "_hooked_by_FontLoennPlugin"
end

function LuaModHook.tryHook(class, funcName, callback)
    local flagName = LuaModHook.getFlagName(funcName)
    if not rawget(class, flagName) then
        rawset(class, flagName, true)
        callback()
    end
end

function LuaModHook.hookOnce(class, funcName, origFunc, hook)
    LuaModHook.tryHook(class, funcName, function()
        local hooked = function(...)
            return hook(origFunc, ...)
        end
        class[funcName] = hooked
    end)
end

-- 修改/Hook local 函数
function LuaModHook.hook_local_func(class, funcName, searchedFunc, hook)
    LuaModHook.tryHook(class, funcName, function()
        local i = 1
        while true do
            local var_name, var_value = debug.getupvalue(searchedFunc, i)
            if not var_name then break end
            if var_name == funcName and type(var_value) == "function" then
                local origFunc = var_value

                local hooked = function(...)
                    return hook(origFunc, ...)
                end
                debug.setupvalue(searchedFunc, i, hooked)
            end
            i = i + 1
        end
    end)
end

return LuaModHook
