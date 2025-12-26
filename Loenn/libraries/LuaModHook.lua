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

-- 修改/Hook local 函数
function LuaModHook.hook_local_func(func, name, hook)
    local i = 1
    while true do
        local var_name, var_value = debug.getupvalue(func, i)
        if not var_name then break end
        if var_name == name and type(var_value) == "function" then
            local original = var_value
            local hooked = function(...)
                return hook(original, ...)
            end
            debug.setupvalue(func, i, hooked)
            return true
        end
        i = i + 1
    end
    return false
end

return LuaModHook