import Foundation

struct SceneCodeGenerator {

    // MARK: - Main Scene module

    static func generateModule(config: SceneManagerConfig) -> String {
        let mod     = luaIdent(config.moduleName.isEmpty ? "Scene" : config.moduleName)
        let initial = config.entries.first(where: { $0.isInitial }) ?? config.entries.first

        // require lines
        let requireLines = config.entries.map { e -> String in
            let key  = luaIdent(e.name)
            let path = scenePath(e)
            return "local \(firstUpper(key)) = require(\"\(path)\")"
        }.joined(separator: "\n")

        // register lines
        let registerLines = config.entries.map { e -> String in
            let key = luaIdent(e.name)
            return "    \(mod):register(\"\(key)\", \(firstUpper(key)))"
        }.joined(separator: "\n")

        let sceneMetaLines = config.entries.map { e -> String in
            let key = luaIdent(e.name)
            let target = luaStringOrNil(e.completeTarget.isEmpty ? nil : luaIdent(e.completeTarget))
            return "    [\"\(key)\"] = { enter = \"\(e.enterTransition.rawValue)\", enterEase = \"\(e.enterEasing.rawValue)\", leave = \"\(e.leaveTransition.rawValue)\", leaveEase = \"\(e.leaveEasing.rawValue)\", duration = \(fmt(e.transitionDuration)), bg = \(e.backgroundColor.lua), completeTrigger = \"\(e.completeTrigger.rawValue)\", completeAction = \"\(e.completeAction.rawValue)\", completeTarget = \(target), completeDelay = \(fmt(e.completeDelay)) },"
        }.joined(separator: "\n")

        // callback delegates - only emit if at least one scene uses it
        func delegateBlock(_ cb: String, args: String, argsPass: String) -> String {
            """
            --------------------------------------------------------------------------------
            -- \(mod):\(cb)(\(args))
            --------------------------------------------------------------------------------
            function \(mod):\(cb)(\(args))
                local s = self:current()
                if s and s.\(cb) then s:\(cb)(\(argsPass)) end
            end
            """
        }

        let hasKeypressed   = config.entries.contains { $0.hasKeypressed }
        let hasKeyreleased  = config.entries.contains { $0.hasKeyreleased }
        let hasMousepressed = config.entries.contains { $0.hasMousepressed }
        let hasMousereleased = config.entries.contains { $0.hasMousereleased }
        let hasMousemoved   = config.entries.contains { $0.hasMousemoved }
        let hasWheelmoved   = config.entries.contains { $0.hasWheelmoved }
        let hasTextinput    = config.entries.contains { $0.hasTextinput }
        let hasResize       = config.entries.contains { $0.hasResize }

        var extraCallbacks = ""
        if hasKeypressed {
            extraCallbacks += "\n\n" + delegateBlock("keypressed", args: "key, scancode, isrepeat", argsPass: "key, scancode, isrepeat")
        }
        if hasKeyreleased {
            extraCallbacks += "\n\n" + delegateBlock("keyreleased", args: "key, scancode", argsPass: "key, scancode")
        }
        if hasMousepressed {
            extraCallbacks += "\n\n" + delegateBlock("mousepressed", args: "x, y, btn, istouch", argsPass: "x, y, btn, istouch")
        }
        if hasMousereleased {
            extraCallbacks += "\n\n" + delegateBlock("mousereleased", args: "x, y, btn, istouch", argsPass: "x, y, btn, istouch")
        }
        if hasMousemoved {
            extraCallbacks += "\n\n" + delegateBlock("mousemoved", args: "x, y, dx, dy, istouch", argsPass: "x, y, dx, dy, istouch")
        }
        if hasWheelmoved {
            extraCallbacks += "\n\n" + delegateBlock("wheelmoved", args: "x, y", argsPass: "x, y")
        }
        if hasTextinput {
            extraCallbacks += "\n\n" + delegateBlock("textinput", args: "text", argsPass: "text")
        }
        if hasResize {
            extraCallbacks += "\n\n" + delegateBlock("resize", args: "w, h", argsPass: "w, h")
        }

        let sceneList = config.entries.map { e -> String in
            let key   = luaIdent(e.name)
            let init_ = e.isInitial ? "  ← initial" : ""
            return "--   \(key.padding(toLength: 20, withPad: " ", startingAt: 0))  \(e.displayName)\(init_)"
        }.joined(separator: "\n")

        let initialSwitch = initial.map { "    \(mod):switch(\"\(luaIdent($0.name))\")" } ?? "    -- (no scenes configured)"

        let love_hooks_keypressed   = hasKeypressed   ? "\n--      function love.keypressed(k,s,r)  \(mod):keypressed(k,s,r) end" : ""
        let love_hooks_keyreleased  = hasKeyreleased  ? "\n--      function love.keyreleased(k,s)   \(mod):keyreleased(k,s) end" : ""
        let love_hooks_mousepressed = hasMousepressed ? "\n--      function love.mousepressed(x,y,b,t) \(mod):mousepressed(x,y,b,t) end" : ""
        let love_hooks_mousereleased = hasMousereleased ? "\n--      function love.mousereleased(x,y,b,t) \(mod):mousereleased(x,y,b,t) end" : ""
        let love_hooks_mousemoved   = hasMousemoved ? "\n--      function love.mousemoved(x,y,dx,dy,t) \(mod):mousemoved(x,y,dx,dy,t) end" : ""
        let love_hooks_wheelmoved   = hasWheelmoved ? "\n--      function love.wheelmoved(x,y)    \(mod):wheelmoved(x,y) end" : ""
        let love_hooks_textinput    = hasTextinput ? "\n--      function love.textinput(text)    \(mod):textinput(text) end" : ""
        let love_hooks_resize       = hasResize       ? "\n--      function love.resize(w,h)         \(mod):resize(w,h) end" : ""

        return """
--------------------------------------------------------------------------------
-- \(mod).lua
-- Generated by LÖVE Studio · Scene Manager
--------------------------------------------------------------------------------
--
-- QUICK START
-- -----------
-- This file is the central state machine. Each scene is a table with lifecycle
-- methods. Require and register them, then call \(mod):switch() in love.load().
--
-- 1. Require at the top of main.lua (use a GLOBAL, not local, so scenes
--    can call \(mod):switch() without re-requiring and causing circular deps):
--
--      \(mod) = require("\(mod)")   -- no 'local'!
--
-- 2. In love.load():
--
--      function love.load()
--          \(mod):load()          -- registers all scenes + enters the initial one
--      end
--
-- 3. Hook into love callbacks:
--
--      function love.update(dt) \(mod):update(dt) end
--      function love.draw()     \(mod):draw() end\(love_hooks_keypressed)\(love_hooks_keyreleased)\(love_hooks_mousepressed)\(love_hooks_mousereleased)\(love_hooks_mousemoved)\(love_hooks_wheelmoved)\(love_hooks_textinput)\(love_hooks_resize)
--
-- 4. Switch between scenes anywhere:
--
--      \(mod):switch("game")   -- replace current scene
--      \(mod):push("pause")    -- overlay scene (stack)
--      \(mod):pop()            -- return to previous scene
--
-- 5. Scene transitions are generated too:
--
--      -- Per scene you can configure:
--      --   enter effect, leave effect, duration, background color
--      --
--      -- Supported effects:
--      --   none, fade, pop, slide_left, slide_right, slide_up, slide_down
--
-- SCENES  (\(config.entries.count) configured)
-- -------------------------------------------------------
\(sceneList.isEmpty ? "--   (none)" : sceneList)
-- -------------------------------------------------------
--------------------------------------------------------------------------------

\(requireLines.isEmpty ? "-- (no scenes)" : requireLines)

local \(mod) = {}

local _stack  = {}   -- scene stack; top = current
local _scenes = {}   -- registered scene tables
local _transition = nil
local _completion = { scene = nil, elapsed = 0, armed = false }
local _sceneMeta = {
\(sceneMetaLines.isEmpty ? "    -- no scene metadata yet" : sceneMetaLines)
}

local function _sceneFx(scene)
    if not scene or not scene.__sceneKey then
        return { enter = "none", enterEase = "ease_in_out", leave = "none", leaveEase = "ease_in_out", duration = 0.35, bg = { 0.10, 0.10, 0.15, 1.00 }, completeTrigger = "none", completeAction = "none", completeTarget = nil, completeDelay = 1.00 }
    end
    return _sceneMeta[scene.__sceneKey] or { enter = "none", enterEase = "ease_in_out", leave = "none", leaveEase = "ease_in_out", duration = 0.35, bg = { 0.10, 0.10, 0.15, 1.00 }, completeTrigger = "none", completeAction = "none", completeTarget = nil, completeDelay = 1.00 }
end

local function _ease(name, t)
    t = math.max(0, math.min(1, t))
    if name == "linear" then
        return t
    elseif name == "ease_in" then
        return t * t
    elseif name == "ease_out" then
        local inv = 1 - t
        return 1 - inv * inv
    elseif name == "bounce" then
        local n1 = 7.5625
        local d1 = 2.75
        if t < 1 / d1 then
            return n1 * t * t
        elseif t < 2 / d1 then
            t = t - 1.5 / d1
            return n1 * t * t + 0.75
        elseif t < 2.5 / d1 then
            t = t - 2.25 / d1
            return n1 * t * t + 0.9375
        else
            t = t - 2.625 / d1
            return n1 * t * t + 0.984375
        end
    else
        if t < 0.5 then
            return 2 * t * t
        end
        local inv = -2 * t + 2
        return 1 - (inv * inv) / 2
    end
end

local function _transitionDuration(fromScene, toScene)
    local fromFx = _sceneFx(fromScene)
    local toFx   = _sceneFx(toScene)
    return math.max(0.05, fromFx.duration or 0.35, toFx.duration or 0.35)
end

local function _armCompletion(scene)
    local fx = _sceneFx(scene)
    _completion.scene = scene
    _completion.elapsed = 0
    _completion.armed = scene ~= nil and fx.completeTrigger == "timer" and fx.completeAction ~= "none" and (fx.completeDelay or 0) > 0
end

local function _runCompletionForScene(scene)
    if not scene then return end

    local fx = _sceneFx(scene)
    local action = fx.completeAction or "none"
    local target = fx.completeTarget
    if action == "switch" and target and target ~= "" then
        \(mod):switch(target)
    elseif action == "push" and target and target ~= "" then
        \(mod):push(target)
    elseif action == "pop" then
        \(mod):pop()
    end
end

local function _startTransition(fromScene, toScene, kind)
    -- Initial scene should appear immediately, but popping the last scene
    -- should still be allowed to play its leave animation into empty space.
    if not fromScene or fromScene == toScene then
        _transition = nil
        return
    end

    local fromFx = _sceneFx(fromScene)
    local toFx   = _sceneFx(toScene)
    local fromKey = fromScene.__sceneKey
    local toKey = toScene and toScene.__sceneKey or nil

    _transition = {
        from     = fromScene,
        to       = toScene,
        kind     = kind or "switch",
        outFx    = (kind == "push") and "none" or (fromFx.leave or "none"),
        outEase  = fromFx.leaveEase or "ease_in_out",
        inFx     = toFx.enter or "none",
        inEase   = toFx.enterEase or "ease_in_out",
        duration = _transitionDuration(fromScene, toScene),
        time     = 0,
    }

    if fromScene and fromScene.transitionStart then fromScene:transitionStart(kind or "switch", fromKey, toKey) end
    if toScene and toScene.transitionStart then toScene:transitionStart(kind or "switch", fromKey, toKey) end
end

local function _drawSceneBackground(scene, alpha)
    local fx = _sceneFx(scene)
    local bg = fx.bg or { 0.10, 0.10, 0.15, 1.00 }
    love.graphics.setColor(bg[1] or 0.10, bg[2] or 0.10, bg[3] or 0.15, (bg[4] or 1.0) * alpha)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
end

local function _applyWindowBackground(scene)
    local fx = _sceneFx(scene)
    local bg = fx.bg or { 0.10, 0.10, 0.15, 1.00 }
    love.graphics.setBackgroundColor(bg[1] or 0.10, bg[2] or 0.10, bg[3] or 0.15, bg[4] or 1.0)
end

local function _drawSceneNow(scene)
    if not scene then return end
    love.graphics.origin()
    love.graphics.clear(love.graphics.getBackgroundColor())
    _drawSceneBackground(scene, 1)
    love.graphics.setColor(1, 1, 1, 1)
    if scene.draw then scene:draw() end
    love.graphics.present()
end

local function _drawTransitionScene(scene, effect, easing, t, entering)
    if not scene then return end

    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local easedT = _ease(easing or "ease_in_out", t)
    local alpha = 1
    local tx, ty = 0, 0
    local sx, sy = 1, 1

    if effect == "fade" then
        alpha = entering and easedT or (1 - easedT)
    elseif effect == "pop" then
        alpha = entering and easedT or (1 - easedT)
        local scale = entering and (0.90 + 0.10 * easedT) or (1.00 - 0.08 * easedT)
        sx, sy = scale, scale
    elseif effect == "slide_left" then
        tx = entering and ((1 - easedT) * w) or (-easedT * w)
    elseif effect == "slide_right" then
        tx = entering and (-(1 - easedT) * w) or (easedT * w)
    elseif effect == "slide_up" then
        ty = entering and ((1 - easedT) * h) or (-easedT * h)
    elseif effect == "slide_down" then
        ty = entering and (-(1 - easedT) * h) or (easedT * h)
    end

    love.graphics.push("all")

    if effect == "pop" then
        love.graphics.translate(w * 0.5, h * 0.5)
        love.graphics.scale(sx, sy)
        love.graphics.translate(-w * 0.5, -h * 0.5)
    else
        love.graphics.translate(tx, ty)
    end

    _drawSceneBackground(scene, alpha)
    love.graphics.setColor(1, 1, 1, alpha)
    if scene.draw then scene:draw() end
    love.graphics.pop()
end

--------------------------------------------------------------------------------
-- \(mod):register(name, scene)
-- Register a scene table under a string key.
--------------------------------------------------------------------------------
function \(mod):register(name, scene)
    assert(type(scene) == "table", "[Scene] register() expects a table, got " .. type(scene))
    scene.__sceneKey = name
    _scenes[name] = scene
    if scene.load then scene:load() end
end

--------------------------------------------------------------------------------
-- \(mod):current() → scene | nil
-- Returns the top-of-stack (active) scene.
--------------------------------------------------------------------------------
function \(mod):current()
    return _stack[#_stack]
end

--------------------------------------------------------------------------------
-- \(mod):switch(name)
-- Replace the entire stack with a single new scene.
-- Calls :leave() on the old scene, :enter() on the new one.
--------------------------------------------------------------------------------
function \(mod):switch(name)
    local prev = self:current()
    if prev and prev.leave then prev:leave() end
    local next = _scenes[name]
    assert(next, "[Scene] Unknown scene: '" .. tostring(name) .. "'")
    _stack = {}
    table.insert(_stack, next)
    _applyWindowBackground(next)
    if next.enter then next:enter() end
    _startTransition(prev, next, "switch")
    _armCompletion(next)
end

--------------------------------------------------------------------------------
-- \(mod):push(name)
-- Push a new scene on top of the stack (useful for pause/overlay screens).
-- Calls :pause() on the previous scene (if defined), :enter() on the new one.
--------------------------------------------------------------------------------
function \(mod):push(name)
    local prev = self:current()
    if prev and prev.pause then prev:pause() end
    local next = _scenes[name]
    assert(next, "[Scene] Unknown scene: '" .. tostring(name) .. "'")
    table.insert(_stack, next)
    _applyWindowBackground(next)
    if next.enter then next:enter() end
    _startTransition(prev, next, "push")
    _armCompletion(next)
end

--------------------------------------------------------------------------------
-- \(mod):pop()
-- Remove the top scene from the stack.
-- Calls :leave() on the popped scene, :resume() on the one below.
--------------------------------------------------------------------------------
function \(mod):pop()
    local prev = self:current()
    if prev and prev.leave then prev:leave() end
    table.remove(_stack)
    local cur = self:current()
    _applyWindowBackground(cur)
    if cur and cur.resume then cur:resume() end
    _startTransition(prev, cur, "pop")
    _armCompletion(cur)
end

--------------------------------------------------------------------------------
-- \(mod):load()
-- Call once in love.load(). Registers all scenes and switches to the initial one.
--------------------------------------------------------------------------------
function \(mod):load()
\(registerLines.isEmpty ? "    -- No scenes registered." : registerLines)
\(initialSwitch)
    _armCompletion(self:current())
    _drawSceneNow(self:current())
end

--------------------------------------------------------------------------------
-- \(mod):complete()
-- Run the configured "On Complete" action for the current scene.
-- Useful for custom conditions or when a scene animation finishes.
--------------------------------------------------------------------------------
function \(mod):complete()
    _completion.armed = false
    _runCompletionForScene(self:current())
end

--------------------------------------------------------------------------------
-- \(mod):update(dt)
-- Delegates to the current (top) scene only.
--------------------------------------------------------------------------------
function \(mod):update(dt)
    if _transition then
        _transition.time = _transition.time + dt
        if _transition.time >= _transition.duration then
            local finished = _transition
            _transition = nil
            if finished.to and finished.to.enterComplete then
                finished.to:enterComplete(finished.kind or "switch", finished.from and finished.from.__sceneKey or nil)
            end
            if finished.from and finished.from.exitComplete then
                finished.from:exitComplete(finished.kind or "switch", finished.to and finished.to.__sceneKey or nil)
            end
        end
    end

    if _completion.armed and _completion.scene == self:current() then
        _completion.elapsed = _completion.elapsed + dt
        local fx = _sceneFx(_completion.scene)
        if _completion.elapsed >= (fx.completeDelay or 0) then
            _completion.armed = false
            _runCompletionForScene(_completion.scene)
            return
        end
    end

    local s = self:current()
    if s and s.update then s:update(dt) end
end

--------------------------------------------------------------------------------
-- \(mod):draw()
-- Draws all stacked scenes bottom-to-top (so overlays appear on top).
--------------------------------------------------------------------------------
function \(mod):draw()
    if _transition then
        local t = math.max(0, math.min(1, _transition.time / _transition.duration))
        if _transition.kind == "pop" then
            _drawTransitionScene(_transition.to, _transition.inFx, _transition.inEase, t, true)
            _drawTransitionScene(_transition.from, _transition.outFx, _transition.outEase, t, false)
        else
            _drawTransitionScene(_transition.from, _transition.outFx, _transition.outEase, t, false)
            _drawTransitionScene(_transition.to, _transition.inFx, _transition.inEase, t, true)
        end
        return
    end

    for i = 1, #_stack do
        local s = _stack[i]
        if s then
            _drawSceneBackground(s, 1)
            love.graphics.setColor(1, 1, 1, 1)
            if s.draw then s:draw() end
        end
    end
end\(extraCallbacks)

return \(mod)
"""
    }

    // MARK: - Per-scene template

    /// Pass `allEntries` so examples can reference real sibling scene names.
    static func generateSceneTemplate(entry: SceneEntry, allEntries: [SceneEntry] = []) -> String {
        let key  = luaIdent(entry.name)
        let Cap  = firstUpper(key)
        let mod  = "Scene"   // users can rename, but this is the default
        let functionBlocks = sceneFunctionBlocks(entry: entry, allEntries: allEntries)

        // Pick sibling scenes for examples (exclude self)
        let siblings  = allEntries.filter { $0.id != entry.id }
        let nextKey   = siblings.first.map { luaIdent($0.name) } ?? "game"
        let pauseKey  = siblings.first(where: { luaIdent($0.name).lowercased().contains("pause") }).map { luaIdent($0.name) }
                        ?? (siblings.count > 1 ? luaIdent(siblings[1].name) : "pause")

        var lines: [String] = [
            "--------------------------------------------------------------------------------",
            "-- \(Cap).lua  -  \(entry.displayName)",
            "-- Generated by LÖVE Studio · Scene Manager",
            "--------------------------------------------------------------------------------",
            "--",
            "-- HOW TO SWITCH SCENES",
            "-- ---------------------",
            "-- Switch (replace current scene entirely):",
            "--      \(mod):switch(\"\(nextKey)\")",
            "--",
            "-- Push (overlay - current scene stays underneath, useful for pause):",
            "--      \(mod):push(\"\(pauseKey)\")",
            "--",
            "-- Pop (close overlay and return to the scene below):",
            "--      \(mod):pop()",
            "--",
            "-- Check which scene is active:",
            "--      local cur = \(mod):current()",
            "--",
            "-- COMPLETE A SCENE MANUALLY:",
            "--      \(mod):complete()",
            "--",
            "-- LIFECYCLE ORDER",
            "-- ----------------",
            "--   switch(\"x\") → current:leave()  →  x:enter()",
            "--   push(\"x\")   → current:pause()  →  x:enter()",
            "--   pop()        → current:leave()  →  previous:resume()",
            "--------------------------------------------------------------------------------",
            "",
            "-- NOTE: '\(mod)' is the scene manager. To switch scenes from here, declare",
            "-- it as a global in main.lua (no 'local'):  \(mod) = require(\"\(mod)\")",
            "-- Requiring it here would cause a circular dependency.",
            "local \(Cap) = {}",
            "",
        ]
        lines.append(contentsOf: functionBlocks.map(\.block))

        lines += ["", "return \(Cap)"]
        return lines.joined(separator: "\n")
    }

    static func mergeSceneTemplate(existing: String, entry: SceneEntry, allEntries: [SceneEntry] = []) -> String {
        let cap = firstUpper(luaIdent(entry.name))
        let missingBlocks = sceneFunctionBlocks(entry: entry, allEntries: allEntries)
            .filter { !sceneFunctionExists(in: existing, sceneName: cap, functionName: $0.name) }
            .map(\.block)

        guard !missingBlocks.isEmpty else { return existing }

        let insertion = "\n" + missingBlocks.joined(separator: "\n") + "\n"
        let returnMarker = "\nreturn \(cap)"

        if let range = existing.range(of: returnMarker, options: .backwards) {
            return existing.replacingCharacters(in: range, with: insertion + "return \(cap)")
        }

        if existing.hasSuffix("\n") {
            return existing + insertion + "return \(cap)\n"
        }

        return existing + insertion + "return \(cap)\n"
    }

    // MARK: - Helpers

    private static func sceneFunctionBlocks(entry: SceneEntry, allEntries: [SceneEntry]) -> [(name: String, block: String)] {
        let key  = luaIdent(entry.name)
        let cap  = firstUpper(key)
        let mod  = "Scene"

        let siblings  = allEntries.filter { $0.id != entry.id }
        let nextKey   = siblings.first.map { luaIdent($0.name) } ?? "game"
        let pauseKey  = siblings.first(where: { luaIdent($0.name).lowercased().contains("pause") }).map { luaIdent($0.name) }
                        ?? (siblings.count > 1 ? luaIdent(siblings[1].name) : "pause")

        func fn(_ name: String, args: String = "", body: String) -> (name: String, block: String) {
            (name, "function \(cap):\(name)(\(args))\n\(body)\nend\n")
        }

        var blocks: [(name: String, block: String)] = []

        if entry.hasEnter {
            blocks.append(fn("enter", body:
                "    -- Called when this scene becomes active (after switch or push).\n" +
                "    -- Good place to reset state, start music, etc."
            ))
        }
        if entry.hasLeave {
            blocks.append(fn("leave", body:
                "    -- Called when leaving this scene (before switch or pop).\n" +
                "    -- Good place to stop music, save progress, etc."
            ))
        }
        if entry.hasPause {
            blocks.append(fn("pause", body:
                "    -- Called when another scene is pushed on top of this one.\n" +
                "    -- The scene is still in the stack but is no longer on top.\n" +
                "    -- Example: pause background music here."
            ))
        }
        if entry.hasResume {
            blocks.append(fn("resume", body:
                "    -- Called when the scene above this one is popped.\n" +
                "    -- This scene is now on top again.\n" +
                "    -- Example: resume background music."
            ))
        }

        blocks.append(fn("enterComplete", args: "kind, fromKey", body:
            "    -- Called when this scene finishes its enter transition.\n" +
            "    -- kind = switch / push / pop.\n" +
            "    -- Use this for UI reveal, sound cues, etc."
        ))
        blocks.append(fn("exitComplete", args: "kind, toKey", body:
            "    -- Called when this scene finishes its exit transition.\n" +
            "    -- Good place to stop loops or clean up temporary objects."
        ))

        if entry.hasTransitionStart {
            blocks.append(fn("transitionStart", args: "kind, fromKey, toKey", body:
                "    -- Called when a transition begins.\n" +
                "    -- kind = switch / push / pop.\n" +
                "    -- Use this for sound cues, state prep, etc."
            ))
        }
        if entry.hasLoad {
            blocks.append(fn("load", body:
                "    -- Load assets once (called from \(mod):load() or manually).\n" +
                "    -- self.font  = love.graphics.newFont(\"fonts/title.ttf\", 32)\n" +
                "    -- self.music = love.audio.newSource(\"audio/theme.ogg\", \"stream\")"
            ))
        }
        if entry.hasUpdate {
            blocks.append(fn("update", args: "dt", body:
                "    -- Update logic every frame. dt = delta time in seconds.\n" +
                "    -- Example: switch to next scene when a timer runs out:\n" +
                "    --   self.timer = (self.timer or 0) + dt\n" +
                "    --   if self.timer >= 3 then\n" +
                "    --       \(mod):switch(\"\(nextKey)\")\n" +
                "    --   end\n" +
                "    --\n" +
                "    -- For custom conditions, call \(mod):complete() when ready."
            ))
        }
        if entry.hasDraw {
            blocks.append(fn("draw", body:
                "    -- Draw everything for this scene.\n" +
                "    -- Scene.lua already paints the configured background color\n" +
                "    -- before calling this function.\n" +
                "    love.graphics.print(\"\(entry.displayName)\", 10, 10)"
            ))
        }
        if entry.hasKeypressed {
            blocks.append(fn("keypressed", args: "key, scancode, isrepeat", body:
                "    -- Called on key press.\n" +
                "    -- Example: go to next scene on Enter, open pause on Escape:\n" +
                "    if key == \"return\" then\n" +
                "        \(mod):switch(\"\(nextKey)\")\n" +
                "    elseif key == \"escape\" then\n" +
                "        \(mod):push(\"\(pauseKey)\")\n" +
                "    end"
            ))
        }
        if entry.hasKeyreleased {
            blocks.append(fn("keyreleased", args: "key, scancode", body:
                "    -- Called when a key is released."
            ))
        }
        if entry.hasMousepressed {
            blocks.append(fn("mousepressed", args: "x, y, btn, istouch", body:
                "    -- Called on mouse/touch press.\n" +
                "    -- Example: left click switches scene:\n" +
                "    -- if btn == 1 then\n" +
                "    --     \(mod):switch(\"\(nextKey)\")\n" +
                "    -- end"
            ))
        }
        if entry.hasMousereleased {
            blocks.append(fn("mousereleased", args: "x, y, btn, istouch", body:
                "    -- Called when a mouse/touch button is released."
            ))
        }
        if entry.hasMousemoved {
            blocks.append(fn("mousemoved", args: "x, y, dx, dy, istouch", body:
                "    -- Called when the pointer moves."
            ))
        }
        if entry.hasWheelmoved {
            blocks.append(fn("wheelmoved", args: "x, y", body:
                "    -- Called when the mouse wheel / trackpad scroll moves."
            ))
        }
        if entry.hasTextinput {
            blocks.append(fn("textinput", args: "text", body:
                "    -- Called for text input events."
            ))
        }
        if entry.hasResize {
            blocks.append(fn("resize", args: "w, h", body:
                "    -- Called when the window is resized.\n" +
                "    -- Update any layout that depends on window size here."
            ))
        }

        return blocks
    }

    private static func sceneFunctionExists(in source: String, sceneName: String, functionName: String) -> Bool {
        let pattern = #"function\s+\#(sceneName)\s*[:.]\s*\#(functionName)\s*\("#
        return (try? NSRegularExpression(pattern: pattern))
            .map { regex in
                let range = NSRange(source.startIndex..<source.endIndex, in: source)
                return regex.firstMatch(in: source, range: range) != nil
            } ?? false
    }

    static func scenePath(_ entry: SceneEntry) -> String {
        if !entry.filePath.isEmpty {
            // Strip .lua extension for require()
            var p = entry.filePath
            if p.hasSuffix(".lua") { p = String(p.dropLast(4)) }
            return p
        }
        return "scenes/\(luaIdent(entry.name))"
    }

    /// Uppercase only the first character, preserving the rest (e.g. "GameScene" stays "GameScene").
    static func firstUpper(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }

    static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func luaStringOrNil(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "nil" }
        return "\"\(value)\""
    }

    static func luaIdent(_ name: String) -> String {
        let safe = name
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "_")).inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let result = safe.isEmpty ? "scene" : safe
        return result.first?.isNumber == true ? "_\(result)" : result
    }
}
