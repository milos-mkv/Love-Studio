import Foundation

struct AudioCodeGenerator {

    static func generate(config: AudioManagerConfig, mode: LanguageServerMode = .current) -> String {
        let mod = luaIdent(config.managerName.isEmpty ? "Audio" : config.managerName)
        let sourceTypeEnum        = mode == .luaCATS ? "---@enum AudioSourceType\nlocal AudioSourceType = { static = \"static\", stream = \"stream\" }\n\n" : ""
        let groupEnum             = mode == .luaCATS ? "---@enum AudioGroup\nlocal AudioGroup = { sfx = \"sfx\", music = \"music\", ambient = \"ambient\" }\n\n" : ""
        let classAnnotation       = mode == .luaCATS ? "---@class \(luaIdent(config.managerName.isEmpty ? "Audio" : config.managerName))\n" : ""
        let loadAnnotation        = mode == .luaCATS ? "---@return nil\n" : ""
        let updateAnnotation      = mode == .luaCATS ? "---@param dt number\n---@return nil\n" : ""
        let playAnnotation        = mode == .luaCATS ? "---@param name string\n---@param x number?\n---@param y number?\n---@return love.Source?\n" : ""
        let playAtAnnotation      = mode == .luaCATS ? "---@param name string\n---@param x number\n---@param y number\n---@return love.Source?\n" : ""
        let fadeOutAnnotation     = mode == .luaCATS ? "---@param name string\n---@return nil\n" : ""
        let crossfadeAnnotation   = mode == .luaCATS ? "---@param fromName string\n---@param toName string\n---@param duration number\n---@return nil\n" : ""
        let listenerAnnotation    = mode == .luaCATS ? "---@param x number\n---@param y number\n---@return nil\n" : ""
        let stopAnnotation        = mode == .luaCATS ? "---@param name string\n---@return nil\n" : ""
        let pauseAnnotation       = mode == .luaCATS ? "---@param name string\n---@return nil\n" : ""
        let isPlayingAnnotation   = mode == .luaCATS ? "---@param name string\n---@return boolean\n" : ""
        let setVolumeAnnotation   = mode == .luaCATS ? "---@param name string\n---@param v number\n---@return nil\n" : ""
        let setGroupVolAnnotation = mode == .luaCATS ? "---@param group string\n---@param v number\n---@return nil\n" : ""
        let setMasterAnnotation   = mode == .luaCATS ? "---@param v number\n---@return nil\n" : ""
        let applyGroupAnnotation  = mode == .luaCATS ? "---@return nil\n" : ""
        let setFxAnnotation       = mode == .luaCATS ? "---@param name string\n---@param effectName string?\n---@return nil\n" : ""
        let setFilterAnnotation   = mode == .luaCATS ? "---@param name string\n---@param filterType string?\n---@param volume number?\n---@param gain number?\n---@return nil\n" : ""
        let stopAllAnnotation     = mode == .luaCATS ? "---@return nil\n" : ""
        let pauseAllAnnotation    = mode == .luaCATS ? "---@return nil\n" : ""
        let resumeAllAnnotation   = mode == .luaCATS ? "---@return nil\n" : ""
        let unloadAnnotation      = mode == .luaCATS ? "---@return nil\n" : ""
        let mv  = fmt2(config.masterVolume)
        let sv  = fmt2(config.sfxVolume)
        let muv = fmt2(config.musicVolume)
        let av  = fmt2(config.ambientVolume)

        let sfxEntries     = config.entries.filter { $0.group == .sfx }
        let musicEntries   = config.entries.filter { $0.group == .music }
        let ambientEntries = config.entries.filter { $0.group == .ambient }

        let anySpatial = config.entries.contains { $0.spatial }

        // ── Effects setup block ───────────────────────────────────────────────
        let enabledEffects = config.effects.filter { $0.enabled }
        let auxEffects    = enabledEffects.filter { $0.type != .lowpass && $0.type != .highpass }

        var effectLines: [String] = []
        if !auxEffects.isEmpty {
            effectLines.append("    -- Auxiliary effects (reverb, echo, chorus…)")
            for fx in auxEffects {
                effectLines.append(contentsOf: effectLuaLines(fx))
            }
            effectLines.append("")
        }
        if anySpatial {
            effectLines.append("    love.audio.setDistanceModel(\"linear\")")
            effectLines.append("")
        }

        // ── Source load block ─────────────────────────────────────────────────
        var loadLines: [String] = []

        func appendGroup(_ entries: [AudioEntry], label: String) {
            guard !entries.isEmpty else { return }
            loadLines.append("    -- \(label)")
            for e in entries {
                let ident = luaIdent(e.name)
                let path  = e.filePath.isEmpty ? "sounds/\(e.name).wav" : e.filePath
                loadLines.append("    _sources.\(ident) = love.audio.newSource(\"\(path)\", \"\(e.sourceType.rawValue)\")")
                if e.looping { loadLines.append("    _sources.\(ident):setLooping(true)") }
                if abs(e.volume - 1.0) > 0.001 {
                    loadLines.append("    _sources.\(ident):setVolume(\(fmt2(e.volume)))")
                }
                if abs(e.pitch - 1.0) > 0.001 {
                    loadLines.append("    _sources.\(ident):setPitch(\(fmt2(e.pitch)))")
                }
                // Spatial attenuation - LÖVE requires mono sources for 3D positioning
                if e.spatial {
                    loadLines.append("    if _sources.\(ident):getChannelCount() == 1 then")
                    loadLines.append("        _sources.\(ident):setAttenuationDistances(\(fmt2(e.minDistance)), \(fmt2(e.maxDistance)))")
                    loadLines.append("        _sources.\(ident):setRolloffFactor(\(fmt2(e.rolloff)))")
                    loadLines.append("    else")
                    loadLines.append("        print(\"[Audio] WARNING: spatial requires mono source - '\(e.name)' is stereo, spatial skipped.\")")
                    loadLines.append("    end")
                }
                // Assign effect or filter
                let fxName = e.effectName.trimmingCharacters(in: .whitespaces)
                if !fxName.isEmpty, let fx = enabledEffects.first(where: { $0.name == fxName }) {
                    let fxKey = luaIdent(fxName)
                    if fx.type == .lowpass || fx.type == .highpass {
                        loadLines.append(contentsOf: filterApplyLines(ident: ident, fx: fx))
                    } else {
                        loadLines.append("    _sources.\(ident):setEffect(\"\(fxKey)\")")
                    }
                }
            }
        }

        appendGroup(sfxEntries,     label: "SFX")
        appendGroup(musicEntries,   label: "Music")
        appendGroup(ambientEntries, label: "Ambient")

        if loadLines.isEmpty {
            loadLines.append("    -- No sources configured. Add sounds in LÖVE Studio · Audio Manager.")
        }

        let effectsBlock = effectLines.joined(separator: "\n")
        let loadBlock    = loadLines.joined(separator: "\n")
        let groupVolMsg  = config.entries.isEmpty ? "" :
            "\n    \(mod):applyGroupVolumes()"

        // ── Lookup tables ──────────────────────────────────────────────────────
        let pitchVarLines = config.entries.map {
            "    \(luaIdent($0.name)) = \(fmt2($0.pitchVariation)),"
        }.joined(separator: "\n")

        let volVarLines = config.entries.map {
            "    \(luaIdent($0.name)) = \(fmt2($0.volumeVariation)),"
        }.joined(separator: "\n")

        let maxInstLines = config.entries.map {
            "    \(luaIdent($0.name)) = \($0.maxInstances),"
        }.joined(separator: "\n")

        let fadeInLines = config.entries.map {
            "    \(luaIdent($0.name)) = \(fmt2($0.fadeInDuration)),"
        }.joined(separator: "\n")

        let fadeOutLines = config.entries.map {
            "    \(luaIdent($0.name)) = \(fmt2($0.fadeOutDuration)),"
        }.joined(separator: "\n")

        let spatialLines = config.entries.map {
            "    \(luaIdent($0.name)) = \($0.spatial ? "true" : "false"),"
        }.joined(separator: "\n")

        // ── Effects section comment ────────────────────────────────────────────
        let effectsDocLines: String
        if !enabledEffects.isEmpty {
            let fxList = enabledEffects.map { "-- · \($0.name)  [\($0.type.rawValue)]" }.joined(separator: "\n")
            effectsDocLines = """
--
-- EFFECTS  (\(enabledEffects.count) configured)
-- --------------------------------------------------
\(fxList)
-- --------------------------------------------------
-- Assign to a source at runtime:
--
--      Audio:setSourceEffect("shoot", "myEffect")   -- attach
--      Audio:setSourceEffect("shoot", nil)           -- detach
--

"""
        } else {
            effectsDocLines = ""
        }

        return """
--------------------------------------------------------------------------------
-- \(mod).lua
-- Generated by LÖVE Studio · Audio Manager
--------------------------------------------------------------------------------
--
-- QUICK START
-- -----------
-- 1. Require this module at the top of your main.lua:
--
--      local \(mod) = require("\(mod.lowercased())")
--
-- 2. Load all sources once in love.load():
--
--      function love.load()
--          \(mod):load()
--      end
--
-- 3. Call update every frame (required for fades):
--
--      function love.update(dt)
--          \(mod):update(dt)
--      end
--
-- 4. Play a sound anywhere:
--
--      \(mod):play("shoot")            -- plays the "shoot" entry
--      \(mod):play("bgm")              -- starts background music
--      \(mod):play("footstep", x, y)   -- spatial: position the sound in 2D space
--
-- 5. Fade a sound out gracefully:
--
--      \(mod):fadeOut("bgm")
--
-- 6. Crossfade between two music tracks (e.g. on scene change):
--
--      \(mod):crossfade("bgm_menu", "bgm_battle", 2.0)  -- 2 second transition
--
-- 7. Set listener position for spatial audio:
--
--      \(mod):setListenerPosition(player.x, player.y)
--
-- 8. Adjust volumes at runtime:
--
--      \(mod):setMasterVolume(0.5)
--      \(mod):setGroupVolume("music", 0.3)
--
-- 8. Stop everything (e.g. on pause screen):
--
--      \(mod):stopAll()
--
\(effectsDocLines)-- AUDIO ENTRIES  (\(config.entries.count) configured)
-- -------------------------------------------------------
\(config.entries.map { e in
    let path      = e.filePath.isEmpty ? "sounds/\(e.name).wav" : e.filePath
    let paddedName = luaIdent(e.name).padding(toLength: 20, withPad: " ", startingAt: 0)
    let fxTag     = e.effectName.isEmpty ? "" : "  fx=\(e.effectName)"
    let varTag    = (e.pitchVariation > 0 || e.volumeVariation > 0)
                    ? "  pVar=\(fmt2(e.pitchVariation)) vVar=\(fmt2(e.volumeVariation))" : ""
    let instTag   = e.maxInstances > 0 ? "  max=\(e.maxInstances)" : ""
    let fadeTag   = (e.fadeInDuration > 0 || e.fadeOutDuration > 0)
                    ? "  fi=\(fmt2(e.fadeInDuration))s fo=\(fmt2(e.fadeOutDuration))s" : ""
    let spatTag   = e.spatial ? "  spatial" : ""
    return "--   \(paddedName)  \(e.sourceType.rawValue)  vol=\(fmt2(e.volume))  \(e.looping ? "loop" : "    ")  [\(e.group.rawValue)]\(fxTag)\(varTag)\(instTag)\(fadeTag)\(spatTag)  \(path)"
}.joined(separator: "\n"))
-- -------------------------------------------------------
-- Group volumes: sfx=\(sv)  music=\(muv)  ambient=\(av)  master=\(mv)
--------------------------------------------------------------------------------

\(sourceTypeEnum)\(groupEnum)\(classAnnotation)local \(mod) = {}

local _sources   = {}
local _groups = {
    sfx     = \(sv),
    music   = \(muv),
    ambient = \(av),
}
local _master = \(mv)
local _group = {
\(config.entries.map { "    \(luaIdent($0.name)) = \"\($0.group.rawValue)\"," }.joined(separator: "\n"))
}
local _baseVolume = {
\(config.entries.map { "    \(luaIdent($0.name)) = \(fmt2($0.volume))," }.joined(separator: "\n"))
}

-- Variation lookup tables
local _pitchVar = {
\(pitchVarLines)
}
local _volVar = {
\(volVarLines)
}

-- Concurrency
local _maxInst = {
\(maxInstLines)
}
local _instances = {}  -- name -> array of active source clones

-- Fade tables
local _fadeIn = {
\(fadeInLines)
}
local _fadeOut = {
\(fadeOutLines)
}
local _fades = {}  -- source -> { vol, target, rate }

-- Spatial flags
local _spatial = {
\(spatialLines)
}

--------------------------------------------------------------------------------
-- \(mod):load()
--------------------------------------------------------------------------------
\(loadAnnotation)function \(mod):load()
\(effectsBlock)\(loadBlock)\(groupVolMsg)
end

--------------------------------------------------------------------------------
-- \(mod):update(dt)
-- Must be called every frame from love.update(dt) for fades to work.
--------------------------------------------------------------------------------
\(updateAnnotation)function \(mod):update(dt)
    for src, fade in pairs(_fades) do
        local step = fade.rate * dt
        if fade.vol < fade.target then
            fade.vol = math.min(fade.target, fade.vol + step)
        else
            fade.vol = math.max(fade.target, fade.vol - step)
        end
        src:setVolume(fade.vol)
        -- Stop and remove when a fade-out reaches silence
        if fade.target == 0 and fade.vol <= 0 then
            src:stop()
            _fades[src] = nil
        elseif fade.target > 0 and math.abs(fade.vol - fade.target) < 0.001 then
            _fades[src] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- \(mod):play(name [, x, y])
-- Plays the named source. Pass x, y for spatial sources.
-- Static sources are cloned so the same SFX can overlap.
--------------------------------------------------------------------------------
\(playAnnotation)function \(mod):play(name, x, y)
    local s = _sources[name]
    if not s then return end

    -- Max instances check
    local maxInst = _maxInst[name] or 0
    if maxInst > 0 then
        _instances[name] = _instances[name] or {}
        -- Clean out dead instances
        local alive = {}
        for _, inst in ipairs(_instances[name]) do
            if inst:isPlaying() then alive[#alive + 1] = inst end
        end
        _instances[name] = alive
        if #alive >= maxInst then return end
    end

    -- Clone or reuse
    local clone
    if s:getType() == "static" then
        clone = s:clone()
    else
        if s:isPlaying() then s:stop() end
        clone = s
    end

    -- Pitch variation
    local basePitch = clone:getPitch()
    local pv = _pitchVar[name] or 0
    if pv > 0 then
        clone:setPitch(basePitch * (1 + (math.random() * 2 - 1) * pv))
    end

    -- Effective volume with variation
    local g    = _group[name] or "sfx"
    local base = _baseVolume[name] or 1
    local effVol = base * (_groups[g] or 1) * _master
    local vv = _volVar[name] or 0
    if vv > 0 then
        effVol = effVol * (1 + (math.random() * 2 - 1) * vv)
        effVol = math.max(0, math.min(1, effVol))
    end

    -- Fade in
    local fi = _fadeIn[name] or 0
    if fi > 0 then
        clone:setVolume(0)
        _fades[clone] = { vol = 0, target = effVol, rate = effVol / fi }
    else
        clone:setVolume(effVol)
    end

    -- Spatial positioning (mono only - stereo sources silently skip)
    if x and y and (_spatial[name] == true) and clone:getChannelCount() == 1 then
        clone:setPosition(x, y, 0)
    end

    clone:play()

    -- Track instance
    if maxInst > 0 then
        _instances[name] = _instances[name] or {}
        _instances[name][#_instances[name] + 1] = clone
    end
    return clone   -- caller can track/manipulate this source
end

--------------------------------------------------------------------------------
-- \(mod):playAt(name, x, y)  - spatial shorthand
-- Equivalent to M:play(name, x, y). More readable for spatial sources.
--------------------------------------------------------------------------------
\(playAtAnnotation)function \(mod):playAt(name, x, y)
    return self:play(name, x, y)
end

--------------------------------------------------------------------------------
-- \(mod):fadeOut(name)
-- Fades out the source (or last instance) over fadeOutDuration seconds.
--------------------------------------------------------------------------------
\(fadeOutAnnotation)function \(mod):fadeOut(name)
    local fo = _fadeOut[name] or 0
    -- Try last tracked instance first
    local src
    if _instances[name] and #_instances[name] > 0 then
        src = _instances[name][#_instances[name]]
    else
        src = _sources[name]
    end
    if not src or not src:isPlaying() then return end
    local curVol = src:getVolume()
    if fo > 0 then
        _fades[src] = { vol = curVol, target = 0, rate = curVol / fo }
    else
        src:stop()
    end
end

--------------------------------------------------------------------------------
\(crossfadeAnnotation)-- \(mod):crossfade(fromName, toName, duration)
-- Simultaneously fades out 'fromName' and fades in 'toName' over 'duration'
-- seconds. Ideal for music transitions between scenes/levels.
--
-- Example:
--   \(mod):crossfade("bgm_menu", "bgm_battle", 2.0)
--
-- Notes:
--   • 'toName' starts from volume 0 and ramps to its configured base volume.
--   • 'fromName' is stopped automatically when the fade-out completes.
--   • Both sources must already be loaded (call \(mod):load() first).
--   • \(mod):update(dt) must be called every frame for the fade to progress.
--------------------------------------------------------------------------------
function \(mod):crossfade(fromName, toName, duration)
    duration = math.max(0.01, duration or 1.0)

    -- ── Fade out the current track ────────────────────────────────────────────
    local fromSrc
    if _instances[fromName] and #_instances[fromName] > 0 then
        fromSrc = _instances[fromName][#_instances[fromName]]
    else
        fromSrc = _sources[fromName]
    end
    if fromSrc and fromSrc:isPlaying() then
        local curVol = fromSrc:getVolume()
        _fades[fromSrc] = { vol = curVol, target = 0, rate = curVol / duration }
    end

    -- ── Fade in the new track ─────────────────────────────────────────────────
    local toSrc = _sources[toName]
    if not toSrc then return end

    local g      = _group[toName] or "sfx"
    local target = (_baseVolume[toName] or 1) * (_groups[g] or 1) * _master

    -- Stop + rewind if already playing, then start silently
    toSrc:stop()
    toSrc:setVolume(0)
    toSrc:play()

    _fades[toSrc] = { vol = 0, target = target, rate = target / duration }
end

--------------------------------------------------------------------------------
-- \(mod):setListenerPosition(x, y)
-- Updates the OpenAL listener position for spatial audio.
-- Call this every frame with your camera / player position.
--------------------------------------------------------------------------------
\(listenerAnnotation)function \(mod):setListenerPosition(x, y)
    love.audio.setPosition(x, y, 0)
end

--------------------------------------------------------------------------------
-- \(mod):stop(name)
--------------------------------------------------------------------------------
\(stopAnnotation)function \(mod):stop(name)
    local s = _sources[name]
    if s then s:stop() end
end

--------------------------------------------------------------------------------
-- \(mod):pause(name)
--------------------------------------------------------------------------------
\(pauseAnnotation)function \(mod):pause(name)
    local s = _sources[name]
    if s then s:pause() end
end

--------------------------------------------------------------------------------
-- \(mod):isPlaying(name) -> boolean
--------------------------------------------------------------------------------
\(isPlayingAnnotation)function \(mod):isPlaying(name)
    local s = _sources[name]
    return s ~= nil and s:isPlaying()
end

--------------------------------------------------------------------------------
-- \(mod):setVolume(name, v)
--------------------------------------------------------------------------------
\(setVolumeAnnotation)function \(mod):setVolume(name, v)
    _baseVolume[name] = v
    local s = _sources[name]
    if s then
        local g = _group[name] or "sfx"
        s:setVolume(v * (_groups[g] or 1) * _master)
    end
end

--------------------------------------------------------------------------------
-- \(mod):setGroupVolume(group, v)
--------------------------------------------------------------------------------
\(setGroupVolAnnotation)function \(mod):setGroupVolume(group, v)
    _groups[group] = math.max(0, math.min(1, v))
    self:applyGroupVolumes()
end

--------------------------------------------------------------------------------
-- \(mod):setMasterVolume(v)
--------------------------------------------------------------------------------
\(setMasterAnnotation)function \(mod):setMasterVolume(v)
    _master = math.max(0, math.min(1, v))
    self:applyGroupVolumes()
end

--------------------------------------------------------------------------------
-- \(mod):applyGroupVolumes()
--------------------------------------------------------------------------------
\(applyGroupAnnotation)function \(mod):applyGroupVolumes()
    for name, s in pairs(_sources) do
        local g    = _group[name] or "sfx"
        local base = _baseVolume[name] or 1
        s:setVolume(base * (_groups[g] or 1) * _master)
    end
end

--------------------------------------------------------------------------------
\(setFxAnnotation)-- \(mod):setSourceEffect(name, effectName)
-- Attach or detach a named auxiliary effect from a source at runtime.
-- Pass nil to remove all effects.
--
--   \(mod):setSourceEffect("shoot", "myReverb")   -- attach
--   \(mod):setSourceEffect("shoot", nil)           -- detach
--------------------------------------------------------------------------------
function \(mod):setSourceEffect(name, effectName)
    local s = _sources[name]
    if not s then return end
    if effectName then
        s:setEffect(effectName)
    else
        for _, fx in ipairs(love.audio.getActiveEffects()) do
            s:setEffect(fx, false)
        end
    end
end

--------------------------------------------------------------------------------
\(setFilterAnnotation)-- \(mod):setSourceFilter(name, filterType, volume, gain)
-- Apply a lowpass or highpass filter directly on a source at runtime.
--
--   filterType  "lowpass"  or  "highpass"
--   volume      overall source volume scalar (0–1, default 1)
--   gain        how much of the cut frequency survives (0–1, default 0.1)
--
-- Examples:
--   \(mod):setSourceFilter("bgm", "lowpass",  1, 0.05)  -- heavy muffle
--   \(mod):setSourceFilter("bgm", "highpass", 1, 0.1)   -- radio effect
--   \(mod):setSourceFilter("bgm", nil)                  -- remove filter
--------------------------------------------------------------------------------
function \(mod):setSourceFilter(name, filterType, volume, gain)
    local s = _sources[name]
    if not s then return end
    if not filterType then
        s:setFilter()
        return
    end
    local params = { type = filterType, volume = volume or 1 }
    if filterType == "lowpass" then
        params.highgain = gain or 0.1
    elseif filterType == "highpass" then
        params.lowgain = gain or 0.1
    end
    s:setFilter(params)
end

--------------------------------------------------------------------------------
-- \(mod):stopAll()
--------------------------------------------------------------------------------
\(stopAllAnnotation)function \(mod):stopAll()
    for _, s in pairs(_sources) do s:stop() end
end

--------------------------------------------------------------------------------
-- \(mod):pauseAll() / \(mod):resumeAll()
--------------------------------------------------------------------------------
\(pauseAllAnnotation)function \(mod):pauseAll()
    for _, s in pairs(_sources) do
        if s:isPlaying() then s:pause() end
    end
end

\(resumeAllAnnotation)function \(mod):resumeAll()
    for _, s in pairs(_sources) do
        if s:isPaused() then s:play() end
    end
end

--------------------------------------------------------------------------------
-- \(mod):unload()
--------------------------------------------------------------------------------
\(unloadAnnotation)function \(mod):unload()
    for _, s in pairs(_sources) do s:stop(); s:release() end
    _sources   = {}
    _instances = {}
    _fades     = {}
end

return \(mod)
"""
    }

    // MARK: - Filter Lua lines (source:setFilter - insert, filters dry signal)

    private static func filterApplyLines(ident: String, fx: AudioEffect) -> [String] {
        let p = fx.params
        switch fx.type {
        case .lowpass:
            return [
                "    _sources.\(ident):setFilter({",
                "        type     = \"lowpass\",",
                "        volume   = \(fmt2(p.volume)),",
                "        highgain = \(fmt2(p.highGain)),",
                "    })",
            ]
        case .highpass:
            return [
                "    _sources.\(ident):setFilter({",
                "        type    = \"highpass\",",
                "        volume  = \(fmt2(p.volume)),",
                "        lowgain = \(fmt2(p.lowGain)),",
                "    })",
            ]
        default: return []
        }
    }

    // MARK: - Effect Lua lines

    private static func effectLuaLines(_ fx: AudioEffect) -> [String] {
        let key = luaIdent(fx.name)
        let p   = fx.params
        var tableLines: [String] = []

        switch fx.type {
        case .lowpass, .highpass:
            return []   // handled by filterApplyLines()
        case .reverb:
            tableLines.append("        type      = \"reverb\",")
            tableLines.append("        volume    = \(fmt2(p.volume)),")
            tableLines.append("        decaytime = \(fmt2(p.decayTime)),")
            tableLines.append("        density   = \(fmt2(p.density)),")
            tableLines.append("        diffusion = \(fmt2(p.diffusion)),")
        case .echo:
            tableLines.append("        type     = \"echo\",")
            tableLines.append("        volume   = \(fmt2(p.volume)),")
            tableLines.append("        delay    = \(fmt2(p.delay)),")
            tableLines.append("        feedback = \(fmt2(p.feedback)),")
            tableLines.append("        spread   = \(fmt2(p.spread)),")
        case .chorus:
            tableLines.append("        type     = \"chorus\",")
            tableLines.append("        volume   = \(fmt2(p.volume)),")
            tableLines.append("        delay    = \(fmt3(p.delay)),")
            tableLines.append("        feedback = \(fmt2(p.feedback)),")
            tableLines.append("        rate     = \(fmt2(p.rate)),")
            tableLines.append("        depth    = \(fmt2(p.depth)),")
        }

        let inner = tableLines.map { "    " + $0 }.joined(separator: "\n")
        return [
            "    love.audio.setEffect(\"\(key)\", {",
            inner,
            "    })",
        ]
    }

    // MARK: - Helpers

    private static func fmt2(_ v: Double) -> String { String(format: "%.2f", v) }
    private static func fmt3(_ v: Double) -> String { String(format: "%.4f", v) }

    static func luaIdent(_ name: String) -> String {
        let safe = name
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "_")).inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let result = safe.isEmpty ? "audio" : safe
        return result.first?.isNumber == true ? "_\(result)" : result
    }
}
