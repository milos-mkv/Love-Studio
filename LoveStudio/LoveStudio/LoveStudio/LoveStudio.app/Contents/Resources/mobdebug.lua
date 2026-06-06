-- mobdebug.lua -- MobDebug-compatible debugger for LÖVE Studio
-- Protocol compatible with MobDebug by Paul Kulchenko (MIT License)
-- Step over/out use stack-depth polling (reliable under LuaJIT).

local M = {}
local socket = require("socket")

-- capture own source reference so we can filter ourselves out of the hook
local SELF_SOURCE = debug.getinfo(1, "S").source

-- turn off JIT so debug hooks fire reliably (same as real MobDebug)
local jit = rawget(_G or _ENV, "jit")
if jit and jit.off then jit.off() end

local conn
local breakpoints = {}

local stepMode           = nil   -- "step" | "over" | "out" | nil
local stepTargetFunc     = nil   -- function identity where OVER/OUT was initiated
local stepTargetDepth    = 0     -- Lua depth at that point (for "out" detection)
local stepOriginLoveCB   = nil   -- ancestor love.* callback we were nested in when step started

local LOVE_CALLBACKS = {"load","update","draw","keypressed","keyreleased",
    "mousepressed","mousereleased","mousemoved","wheelmoved",
    "focus","quit","resize","textinput","gamepadpressed","gamepadreleased"}

-- Walk the full call stack and return the first love.* callback found (our ancestor),
-- or nil if we are not inside any love callback.
-- Must be called from within hook() - level 2 = hook, level 3+ = user frames.
local function ancestorLoveCB()
    if type(love) ~= "table" then return nil end
    local level = 2
    while true do
        local info = debug.getinfo(level, "f")
        if not info then break end
        if info.func then
            for _, cb in ipairs(LOVE_CALLBACKS) do
                if love[cb] == info.func then return info.func end
            end
        end
        level = level + 1
    end
    return nil
end

-- Count only Lua frames so C-stack variations don't affect us
local function luaDepth()
    local n = 0
    local level = 2
    while true do
        local info = debug.getinfo(level, "S")
        if not info then break end
        if info.what == "Lua" then n = n + 1 end
        level = level + 1
    end
    return n
end

local function normFile(src)
    if not src then return "?" end
    if src:sub(1, 1) == "@" then return src:sub(2) end
    return src
end

local function send(msg)
    if not conn then return end
    local ok, err = conn:send(msg .. "\n")
    if not ok then
        debug.sethook()
        conn = nil
    end
end

local function recv()
    if not conn then return nil end
    local line, err = conn:receive("*l")
    if not line then
        debug.sethook()
        conn = nil
        return nil
    end
    return line
end

-- ── Command loop ─────────────────────────────────────────────────────────────

local function commandLoop()
    while true do
        local cmd = recv()
        if not cmd then return "RUN" end

        if cmd == "RUN" or cmd == "STEP" or cmd == "OVER" or cmd == "OUT" then
            return cmd

        elseif cmd:match("^SETB ") then
            local f, l = cmd:match("^SETB%s+(.-)%s+(%d+)$")
            if f and l then
                breakpoints[f] = breakpoints[f] or {}
                breakpoints[f][tonumber(l)] = true
            end

        elseif cmd:match("^DELB ") then
            local f, l = cmd:match("^DELB%s+(.-)%s+(%d+)$")
            if f and l and breakpoints[f] then
                breakpoints[f][tonumber(l)] = nil
            end

        elseif cmd:match("^LOAD ") then
            local size, name = cmd:match("^LOAD%s+(%d+)%s+(.-)%s*$")
            size = tonumber(size)
            if size and size > 0 then
                local source = conn:receive(size)
                if source then
                    local loader = loadstring or load
                    local fn, err = loader(source, "@" .. (name or "?"))
                    if fn then
                        local ok, rerr = pcall(fn)
                        if ok then
                            send("200 OK 0")
                        else
                            local msg = tostring(rerr)
                            send("401 Error in Expression " .. #msg)
                            send(msg)
                        end
                    else
                        local msg = tostring(err)
                        send("401 Error in Expression " .. #msg)
                        send(msg)
                    end
                else
                    send("401 Error in Expression 13")
                    send("receive error")
                end
            else
                send("200 OK 0")
            end

        elseif cmd:match("^EXEC ") then
            local expr = cmd:match("^EXEC%s+(.+)$")
            local loader = loadstring or load
            local fn, err = loader("return " .. expr, "=(eval)")
            if not fn then fn, err = loader(expr, "=(eval)") end
            if fn then
                local ok, res = pcall(fn)
                if ok then
                    send("200 OK")
                    send(tostring(res or "nil"))
                    send("END")
                else
                    send("401 Error 0 " .. tostring(res))
                end
            else
                send("401 Error 0 " .. tostring(err))
            end

        elseif cmd:match("^STACK") then
            local frames = {}
            local level = 2
            while true do
                local info = debug.getinfo(level, "Sln")
                if not info then break end
                -- skip debugger-internal frames
                if info.source ~= SELF_SOURCE then
                    table.insert(frames, string.format(
                        "{file=%q,line=%d,name=%q}",
                        normFile(info.source),
                        info.currentline or 0,
                        info.name or "?"
                    ))
                end
                level = level + 1
            end
            send("200 OK")
            send("{" .. table.concat(frames, ",") .. "}")
            send("END")

        elseif cmd:match("^LOCALS") then
            local vars  = {}
            local seen  = {}
            local level = 3

            _LuaAppReg  = {}
            _LuaAppRegN = 0

            local function regKey(val)
                _LuaAppRegN = _LuaAppRegN + 1
                local k = tostring(_LuaAppRegN)
                _LuaAppReg[k] = val
                return k
            end

            local function fmtVar(name, val, scope)
                local tv = type(val)
                local sv = tostring(val)
                if #sv > 80 then sv = sv:sub(1, 80) .. "…" end
                local tk = tv == "table" and regKey(val) or ""
                return string.format(
                    '{name=%q,value=%q,type=%q,scope=%q,tkey=%q}',
                    name, sv, tv, scope, tk
                )
            end

            local i = 1
            while true do
                local name, val = debug.getlocal(level, i)
                if not name then break end
                if name:sub(1, 1) ~= "(" then
                    seen[name] = true
                    table.insert(vars, fmtVar(name, val, "local"))
                end
                i = i + 1
            end

            local info = debug.getinfo(level, "f")
            if info and info.func then
                local j = 1
                while true do
                    local name, val = debug.getupvalue(info.func, j)
                    if not name then break end
                    if not seen[name] and name:sub(1, 1) ~= "(" then
                        seen[name] = true
                        table.insert(vars, fmtVar(name, val, "upvalue"))
                    end
                    j = j + 1
                end
            end

            local builtins = {
                love=1,math=1,table=1,string=1,io=1,os=1,package=1,
                coroutine=1,debug=1,utf8=1,bit=1,jit=1,socket=1,
                print=1,pairs=1,ipairs=1,next=1,type=1,tostring=1,
                tonumber=1,error=1,assert=1,pcall=1,xpcall=1,select=1,
                unpack=1,rawget=1,rawset=1,rawequal=1,rawlen=1,
                setmetatable=1,getmetatable=1,require=1,dofile=1,
                load=1,loadfile=1,collectgarbage=1,gcinfo=1,
                _G=1,_VERSION=1,arg=1,_LuaAppReg=1,_LuaAppRegN=1,
            }
            for k, v in pairs(_G) do
                if type(k) == "string" and not seen[k] and not builtins[k] then
                    seen[k] = true
                    table.insert(vars, fmtVar(k, v, "global"))
                end
            end

            send("200 OK")
            send("{" .. table.concat(vars, ",") .. "}")
            send("END")
        end
    end
end

-- ── Debug hook ────────────────────────────────────────────────────────────────

local function hook(event, line)
    if event ~= "line" then return end

    local info = debug.getinfo(2, "S")
    local file = normFile(info and info.source)

    -- never pause inside debugger internals (compare exact source reference)
    if info.source == SELF_SOURCE or file == "?" then return end

    local shouldPause = false

    if stepMode == "step" then
        shouldPause = true
    elseif stepMode == "over" then
        -- pause when depth <= target: same function next line, returned from target,
        -- or moved to a sibling function at the same level (e.g. love.load → love.update)
        shouldPause = luaDepth() <= stepTargetDepth
    elseif stepMode == "out" then
        -- pause when we've exited the function we started in
        shouldPause = luaDepth() < stepTargetDepth
    else
        if breakpoints[file] then
            shouldPause = breakpoints[file][line] == true
        end
    end

    if not shouldPause then return end

    -- Skip internal LÖVE Lua files (absolute path = not user code) for over/out
    if (stepMode == "over" or stepMode == "out") and file:sub(1, 1) == "/" then
        stepMode = nil
        return
    end

    -- All step modes: cancel if we have crossed into a DIFFERENT love.* callback
    -- than the one we started in (stepOriginLoveCB).
    -- ancestorLoveCB() walks the full stack, so we correctly handle both:
    --   • paused directly in love.update → stepOriginLoveCB = love.update
    --   • paused in bbb() called from love.load → stepOriginLoveCB = love.load
    -- Returning to the SAME love callback (e.g. bbb returns to love.load) is
    -- allowed; only jumping to a DIFFERENT one is cancelled.
    -- If stepOriginLoveCB is nil we exited all callbacks → cancel immediately.
    if stepMode ~= nil then
        local curLoveCB = ancestorLoveCB()
        if curLoveCB ~= stepOriginLoveCB then
            stepMode = nil
            return
        end
    end

    stepMode = nil

    send(string.format("202 Paused %s %d", file, line))

    local cmd = commandLoop()
    local fi  = debug.getinfo(2, "f")
    -- Record the ancestor love.* callback we are currently nested inside.
    -- ancestorLoveCB() walks the full stack, so this is correct even when
    -- paused inside a helper function called from a love callback.
    stepOriginLoveCB = ancestorLoveCB()
    if cmd == "STEP" then
        stepMode       = "step"
        stepTargetFunc = nil
    elseif cmd == "OVER" then
        stepMode        = "over"
        stepTargetFunc  = fi and fi.func
        stepTargetDepth = luaDepth()
    elseif cmd == "OUT" then
        stepMode        = "out"
        stepTargetFunc  = nil
        stepTargetDepth = luaDepth()
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.start(host, port)
    host = host or "localhost"
    port = port or 8172

    conn = socket.tcp()
    conn:settimeout(10)
    local ok, err = conn:connect(host, port)
    if not ok then
        print("[mobdebug] Cannot connect: " .. tostring(err))
        conn = nil
        return
    end
    conn:settimeout(nil)
    print("[mobdebug] Connected")

    local cmd = commandLoop()
    stepOriginLoveCB = nil  -- not inside any love callback at startup
    if cmd == "STEP" then
        stepMode       = "step"
        stepTargetFunc = nil
    elseif cmd == "OVER" then
        stepMode        = "over"
        stepTargetFunc  = nil
        stepTargetDepth = luaDepth()
    elseif cmd == "OUT" then
        stepMode        = "out"
        stepTargetFunc  = nil
        stepTargetDepth = luaDepth()
    end
    debug.sethook(hook, "l")
end

function M.done()
    debug.sethook()
    if conn then conn:close(); conn = nil end
end

return M
