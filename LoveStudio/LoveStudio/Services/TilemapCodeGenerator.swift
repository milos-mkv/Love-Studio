import Foundation

struct TilemapCodeGenerator {

    static func generate(config: TilemapConfig) -> String {
        let regularLayers   = config.layers.filter { !$0.isCollision }
        let collisionLayers = config.layers.filter {  $0.isCollision }

        // ── Layer data ─────────────────────────────────────────────────────────
        let layersLua = regularLayers.map { layer in
            if layer.layerType == .object {
                let objectsStr = layer.objects.map { obj in
                    let propsStr = obj.properties.map { p in
                        "      { key = \"\(p.key)\", value = \"\(p.value)\", type = \"\(p.type.rawValue)\" },"
                    }.joined(separator: "\n")
                    let propsBlock = obj.properties.isEmpty ? "{}" : "{\n\(propsStr)\n      }"
                    return """
          { name = "\(obj.name)", type = "\(obj.type)", x = \(obj.tileX), y = \(obj.tileY), w = \(obj.tileW), h = \(obj.tileH), properties = \(propsBlock) },
    """
                }.joined(separator: "\n")
                let objectsBlock = layer.objects.isEmpty ? "    {}" : "\(objectsStr)"
                return """
      {
        name       = "\(layer.name)",
        layerType  = "object",
        visible    = \(layer.visible ? "true" : "false"),
        opacity    = \(String(format: "%.2f", layer.opacity)),
        foreground = \(layer.isForeground ? "true" : "false"),
        objects    = {
    \(objectsBlock)
        },
        tiles      = {},
      }
    """
            } else {
                let tilesStr = stride(from: 0, to: layer.tiles.count, by: config.mapWidth).map { row in
                    let end = min(row + config.mapWidth, layer.tiles.count)
                    return "    " + layer.tiles[row..<end].map { String($0) }.joined(separator: ", ")
                }.joined(separator: ",\n")

                return """
      {
        name       = "\(layer.name)",
        layerType  = "tile",
        visible    = \(layer.visible ? "true" : "false"),
        opacity    = \(String(format: "%.2f", layer.opacity)),
        foreground = \(layer.isForeground ? "true" : "false"),
        tiles      = {
    \(tilesStr)
        },
      }
    """
            }
        }.joined(separator: ",\n")

        // ── Tileset table ──────────────────────────────────────────────────────
        let tilesetTable: String
        if config.tilesets.isEmpty {
            tilesetTable = "  -- No tilesets loaded yet.\n  -- Add: { path = \"images/tileset.png\", firstGID = 0 }"
        } else {
            tilesetTable = config.tilesets.enumerated().map { i, ts in
                let firstGID = i * TilesetInfo.GID_STRIDE
                return "  { path = \"\(ts.fileName)\", firstGID = \(firstGID) },"
            }.joined(separator: "\n")
        }

        // ── Collision section ──────────────────────────────────────────────────
        let collisionSection: String
        if collisionLayers.isEmpty {
            collisionSection = ""
        } else {
            let count  = config.mapWidth * config.mapHeight
            var merged = Array(repeating: 0, count: count)
            for layer in collisionLayers {
                for i in 0 ..< min(count, layer.tiles.count) {
                    if layer.tiles[i] >= 0 { merged[i] = 1 }
                }
            }
            let collisionStr = stride(from: 0, to: merged.count, by: config.mapWidth).map { row in
                let end = min(row + config.mapWidth, merged.count)
                return "  " + merged[row..<end].map { String($0) }.joined(separator: ", ")
            }.joined(separator: ",\n")

            collisionSection = """


--------------------------------------------------------------------------------
-- Collision grid
-- 1 = solid, 0 = passable · row-major, top-to-bottom, left-to-right
-- Use M:isSolid(col, row) instead of reading this table directly.
--------------------------------------------------------------------------------
M.collision = {
\(collisionStr)
}

"""
        }

        // ── Origin offset ──────────────────────────────────────────────────────
        let originLines: String
        let originComment: String
        let worldToTileComment: String
        switch config.origin {
        case .topLeft:
            originLines = ""
            originComment = "top-left  (0, 0) is the top-left corner of the map"
            worldToTileComment = """
--      local col = math.floor(worldX / Map.tileSize)
--      local row = math.floor(worldY / Map.tileSize)
"""
        case .center:
            originLines = """

M.originX = -math.floor(M.width  * M.tileSize / 2)
M.originY = -math.floor(M.height * M.tileSize / 2)
"""
            originComment = "center    (0, 0) is the center of the map"
            worldToTileComment = """
--      local col = math.floor((worldX - Map.originX) / Map.tileSize)
--      local row = math.floor((worldY - Map.originY) / Map.tileSize)
"""
        case .bottomLeft:
            originLines = """

M.originX = 0
M.originY = -(M.height * M.tileSize)
"""
            originComment = "bottom-left  (0, 0) is the bottom-left corner, Y axis points up"
            worldToTileComment = """
--      local col = math.floor((worldX - Map.originX) / Map.tileSize)
--      local row = math.floor((-worldY + Map.originY + Map.height * Map.tileSize) / Map.tileSize)
"""
        }

        let hasOriginOffset = config.origin != .topLeft

        // ── Animations table ───────────────────────────────────────────────────
        let hasAnimations = !config.animations.isEmpty
        let animationsTable: String
        if hasAnimations {
            let rows = config.animations.map { anim in
                let framesStr = anim.frames.map { f in
                    "      { gid = \(f.gid), duration = \(String(format: "%.4f", f.duration)) },"
                }.joined(separator: "\n")
                return """
      {
        sourceGID = \(anim.sourceGID),
        flipH     = \(anim.flipH ? "true" : "false"),
        flipV     = \(anim.flipV ? "true" : "false"),
        frames    = {
    \(framesStr)
        },
      }
    """
            }.joined(separator: ",\n")
            animationsTable = rows
        } else {
            animationsTable = ""
        }

        // ── Tile properties table ──────────────────────────────────────────────
        let hasTileProperties = !config.tileProperties.isEmpty
        let tilePropertiesSection: String
        if hasTileProperties {
            let rows = config.tileProperties.sorted { Int($0.key) ?? 0 < Int($1.key) ?? 0 }.map { (key, props) in
                let propsStr = props.map { p in
                    "    { key = \"\(p.key)\", value = \"\(p.value)\", type = \"\(p.type.rawValue)\" },"
                }.joined(separator: "\n")
                return "  [\(key)] = {\n\(propsStr)\n  },"
            }.joined(separator: "\n")
            tilePropertiesSection = """


--------------------------------------------------------------------------------
-- Tile properties
--------------------------------------------------------------------------------
M.tileProperties = {
\(rows)
}

"""
        } else {
            tilePropertiesSection = ""
        }

        let hasCollision = !collisionLayers.isEmpty
        let layerCount   = regularLayers.count
        let tilesetCount = config.tilesets.count

        return """
--------------------------------------------------------------------------------
-- \(config.name).lua  ·  generated by LÖVE Studio
--------------------------------------------------------------------------------
--
-- MAP INFO
--   Size      : \(config.mapWidth) × \(config.mapHeight) tiles  (\(config.mapWidth * config.tileSize) × \(config.mapHeight * config.tileSize) px)
--   Tile size : \(config.tileSize) × \(config.tileSize) px
--   Layers    : \(layerCount) layer\(layerCount == 1 ? "" : "s")
--   Tilesets  : \(tilesetCount) tileset\(tilesetCount == 1 ? "" : "s")
--   Animations: \(config.animations.count) animated tile\(config.animations.count == 1 ? "" : "s")
--   Origin    : \(originComment)\(hasCollision ? "\n--   Collision : enabled - use Map:isSolid(col, row)" : "")
--
--------------------------------------------------------------------------------
-- SETUP
--------------------------------------------------------------------------------
--
-- Require the map in any file that needs it:
--
--   local Map = require("tiles/\(config.name)")
--
-- In love.load(), load the tileset images into GPU memory:
--
--   function love.load()
--       Map:load()
--   end
--
-- In love.update(dt), advance tile animations:
--
--   function love.update(dt)
--       Map:update(dt)
--   end
--
-- In love.draw(), render the map.  Two approaches:
--
--   -- Simple: draw everything in one call
--   function love.draw()
--       Map:draw(-camX, -camY)
--   end
--
--   -- Layered: draw the player between background and foreground
--   function love.draw()
--       Map:drawBackground(-camX, -camY)   -- tiles behind the player
--       player:draw()
--       Map:drawForeground(-camX, -camY)   -- tiles in front of the player
--   end
--
-- When the map is no longer needed (e.g. on scene change), release GPU memory:
--
--   Map:unload()
--\(hasCollision ? """

--------------------------------------------------------------------------------
-- COLLISION
--------------------------------------------------------------------------------
--
-- Tiles painted on a Collision layer are baked into Map.collision[] - a flat
-- array of 1s (solid) and 0s (passable) in row-major order.  The layer itself
-- is never drawn; it only provides the data for isSolid().
--
-- Check whether a tile cell blocks movement:
--
--   if Map:isSolid(col, row) then
--       -- wall - reject the move or resolve the overlap
--   end
--
-- Convert a world pixel position to a tile cell first:
--
\(worldToTileComment)--   if Map:isSolid(col, row) then ... end
--
-- Out-of-bounds cells return M.solidOutOfBounds (true by default).
-- Set Map.solidOutOfBounds = false for open worlds with no map boundary.
--
-- ── Option A: 4-corner check (fast, O(1)) ───────────────────────────────────
-- Works correctly only when the entity is smaller than one tile.
-- If the hitbox is wider/taller than a tile, solid cells between the corners
-- will be missed.
--
--   local function collidesWithMap(x, y, w, h)
--       local ts = Map.tileSize
--       local c1 = math.floor( x      / ts)
--       local c2 = math.floor((x+w-1) / ts)
--       local r1 = math.floor( y      / ts)
--       local r2 = math.floor((y+h-1) / ts)
--       return Map:isSolid(c1,r1) or Map:isSolid(c2,r1)
--           or Map:isSolid(c1,r2) or Map:isSolid(c2,r2)
--   end
--
-- ── Option B: full AABB sweep (correct for any size hitbox) ─────────────────
-- Checks every tile the hitbox overlaps - for a typical entity this is still
-- only 2×2 to 4×4 tiles, so performance cost is negligible.
-- Use this when the entity hitbox is larger than one tile, or when using a
-- map scale factor (mapScale) that makes tiles appear bigger on screen.
--
--   local mapScale = 2   -- same scale you pass to Map:draw()
--
--   local function collidesWithMap(x, y, w, h)
--       local ts = Map.tileSize * mapScale
--       local c1 = math.floor( x      / ts)
--       local c2 = math.floor((x+w-1) / ts)
--       local r1 = math.floor( y      / ts)
--       local r2 = math.floor((y+h-1) / ts)
--       for row = r1, r2 do
--           for col = c1, c2 do
--               if Map:isSolid(col, row) then return true end
--           end
--       end
--       return false
--   end
--
-- ── Resolving collisions (same for both options) ─────────────────────────────
-- Move X and Y separately so the player slides along walls instead of stopping:
--
--   -- Move the player and resolve X/Y axes separately:
--   player.x = player.x + vx * dt
--   if collidesWithMap(player.x, player.y, player.w, player.h) then
--       player.x = player.x - vx * dt   -- revert horizontal move
--       vx = 0
--   end
--   player.y = player.y + vy * dt
--   if collidesWithMap(player.x, player.y, player.w, player.h) then
--       player.y = player.y - vy * dt   -- revert vertical move
--       vy = 0
--   end
--
""" : """

""")
--------------------------------------------------------------------------------
-- OBJECTS  (spawn points, triggers, NPCs, …)
--------------------------------------------------------------------------------
--
-- Fetch every object of a given type across all object layers:
--
--   local spawns = Map:getObjectsByType("spawn")
--   for _, spawn in ipairs(spawns) do
--       player.x = spawn.x * Map.tileSize
--       player.y = spawn.y * Map.tileSize
--   end
--
-- Fetch a single object by its unique name:
--
--   local door = Map:getObjectByName("exit_door")
--   if door then
--       -- door.x, door.y, door.w, door.h, door.type, door.properties
--   end
--
-- Each object has these fields:
--   name        string   - unique label set in the editor
--   type        string   - category ("spawn", "trigger", "npc", …)
--   x, y        number   - top-left cell (tile coordinates)
--   w, h        number   - size in tiles
--   properties  table    - custom key/value pairs added in the editor
--
--------------------------------------------------------------------------------
-- OTHER UTILITIES
--------------------------------------------------------------------------------
--
-- Read the tile GID at a specific cell (layerIndex is 1-based):
--
--   local gid = Map:getTile(layerIndex, col, row)
--   -- returns -1 when the cell is empty or out of range
--
-- Read a custom property attached to a tile GID:
--
--   local speed = Map:getTileProperty(gid, "speed")
--
-- Show or hide a layer by name at runtime:
--
--   Map:setLayerVisible("Foreground", false)
--
-- Edit a tile at runtime and rebuild the sprite batches:
--
--   Map.layers[1].tiles[ row * Map.width + col + 1 ] = newGID
--   Map:rebuild()
--
--------------------------------------------------------------------------------

local M = {}

M.width    = \(config.mapWidth)
M.height   = \(config.mapHeight)
M.tileSize = \(config.tileSize)\(originLines)

M.tilesets = {
\(tilesetTable)
}

M.layers = {
\(layersLua)
}\(hasAnimations ? """

--------------------------------------------------------------------------------
-- Tile animations
-- Call Map:update(dt) every frame to advance these.
--------------------------------------------------------------------------------
M.animations = {
\(animationsTable)
}
""" : "")\(collisionSection)\(tilePropertiesSection)
--------------------------------------------------------------------------------
-- Internal state
--------------------------------------------------------------------------------

local _images      = {}
local _quads       = {}
local _batches     = {}
local _animMap     = {}   -- sourceGID → animation index
local _animState   = {}   -- sourceGID → { frame, timer, currentGID }
local _animTiles   = {}   -- layerIndex → list of { x, y, ti, sourceGID }
local _flipTiles   = {}   -- layerIndex → list of { x, y, gid, flipH, flipV }

local GID_STRIDE = \(TilesetInfo.GID_STRIDE)
local FLIP_H     = \(TilemapConfig.FLIP_H)   -- bit 28
local FLIP_V     = \(TilemapConfig.FLIP_V)   -- bit 29
local FLIP_BITS  = \(TilemapConfig.FLIP_BITS)

--------------------------------------------------------------------------------
-- M:load()
-- Loads tileset images and builds SpriteBatches.  Call once in love.load().
--------------------------------------------------------------------------------
function M:load()
    _images    = {}
    _quads     = {}
    _batches   = {}
    _animMap   = {}
    _animState = {}
    _animTiles = {}
    _flipTiles = {}

    for i, ts in ipairs(self.tilesets) do
        local img  = love.graphics.newImage(ts.path)
        _images[i] = img
        local iw   = img:getWidth()
        local ih   = img:getHeight()
        local cols = math.floor(iw / self.tileSize)
        local rows = math.floor(ih / self.tileSize)
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                local localIdx = r * cols + c
                local gid      = ts.firstGID + localIdx
                _quads[gid]    = love.graphics.newQuad(
                    c * self.tileSize, r * self.tileSize,
                    self.tileSize, self.tileSize, iw, ih
                )
            end
        end
    end

    -- Build animation lookup table
    if self.animations then
        for ai, anim in ipairs(self.animations) do
            _animMap[anim.sourceGID] = anim
            _animState[anim.sourceGID] = {
                frame      = 1,
                timer      = 0.0,
                currentGID = anim.frames[1] and anim.frames[1].gid or anim.sourceGID,
            }
            -- Also build quads for any frame GIDs not already covered
            for _, f in ipairs(anim.frames) do
                if not _quads[f.gid] then
                    local ti  = math.floor(f.gid / GID_STRIDE) + 1
                    local img = _images[ti]
                    if img then
                        local localIdx = f.gid % GID_STRIDE
                        local iw   = img:getWidth()
                        local cols = math.floor(iw / self.tileSize)
                        local c    = localIdx % cols
                        local r    = math.floor(localIdx / cols)
                        _quads[f.gid] = love.graphics.newQuad(
                            c * self.tileSize, r * self.tileSize,
                            self.tileSize, self.tileSize, iw, img:getHeight()
                        )
                    end
                end
            end
        end
    end

    for li, layer in ipairs(self.layers) do
        local layerBatches    = {}
        local animTilesForLayer = {}
        for i, _ in ipairs(self.tilesets) do
            layerBatches[i] = {
                batch   = love.graphics.newSpriteBatch(_images[i], self.width * self.height),
                visible = layer.visible,
            }
        end
        local flipTilesForLayer = {}
        for idx, rawgid in ipairs(layer.tiles) do
            if rawgid >= 0 then
                local fH  = rawgid >= FLIP_H and math.floor(rawgid / FLIP_H) % 2 == 1
                local fV  = rawgid >= FLIP_V and math.floor(rawgid / FLIP_V) % 2 == 1
                -- rawgid % FLIP_H keeps bits 0-27 only, stripping both flip bits (28 and 29)
                local gid = rawgid % FLIP_H
                if _quads[gid] then
                    local col = (idx - 1) % self.width
                    local row = math.floor((idx - 1) / self.width)
                    local x   = col * self.tileSize
                    local y   = row * self.tileSize
                    local ti  = math.floor(gid / GID_STRIDE) + 1
                    if _animMap[gid] then
                        -- Animated tile: skip batch, record position + flip for individual draw
                        local adef = _animMap[gid]
                        table.insert(animTilesForLayer, {
                            x = x, y = y, ti = ti, sourceGID = gid,
                            flipH = fH or (adef and adef.flipH or false),
                            flipV = fV or (adef and adef.flipV or false),
                        })
                    elseif fH or fV then
                        -- Flipped tile: cannot use SpriteBatch, draw individually
                        table.insert(flipTilesForLayer, { x = x, y = y, gid = gid, ti = ti, flipH = fH, flipV = fV })
                    elseif layerBatches[ti] then
                        layerBatches[ti].batch:add(_quads[gid], x, y)
                    end
                end
            end
        end
        _batches[li] = {
            batches = layerBatches,
            visible = layer.visible,
            opacity = layer.opacity or 1,
        }
        _animTiles[li] = animTilesForLayer
        _flipTiles[li] = flipTilesForLayer
    end
end

--------------------------------------------------------------------------------
-- M:update(dt)
-- Advances all tile animations.  Call every frame in love.update(dt).
--------------------------------------------------------------------------------
function M:update(dt)
    if not self.animations then return end
    for _, anim in ipairs(self.animations) do
        local st = _animState[anim.sourceGID]
        if st and #anim.frames > 0 then
            st.timer = st.timer + dt
            local dur = (anim.frames[st.frame] and anim.frames[st.frame].duration) or 0.1
            while st.timer >= dur do
                st.timer = st.timer - dur
                st.frame = (st.frame % #anim.frames) + 1
                dur = (anim.frames[st.frame] and anim.frames[st.frame].duration) or 0.1
            end
            st.currentGID = anim.frames[st.frame].gid
        end
    end
end

--------------------------------------------------------------------------------
-- M:draw([ox, oy, scale])
-- Draws all layers (background + foreground) in one call.
--   ox, oy - camera scroll offset in pixels  (default 0)
--   scale  - uniform zoom factor             (default 1)
--
--   Map:draw()                  -- no camera
--   Map:draw(-camX, -camY)      -- with camera scroll
--   Map:draw(-camX, -camY, 2)   -- camera + 2× zoom
--------------------------------------------------------------------------------
function M:draw(ox, oy, scale)
    self:drawBackground(ox, oy, scale)
    self:drawForeground(ox, oy, scale)
end

--------------------------------------------------------------------------------
-- M:_drawLayers(foreground, ox, oy, scale)
-- Internal - called by drawBackground / drawForeground.
--------------------------------------------------------------------------------
function M:_drawLayers(foreground, ox, oy, scale)
    ox    = (ox or 0)\(hasOriginOffset ? " + (self.originX or 0)" : "")
    oy    = (oy or 0)\(hasOriginOffset ? " + (self.originY or 0)" : "")
    scale = scale or 1
    local r, g, b, a = love.graphics.getColor()
    love.graphics.push()
    love.graphics.scale(scale, scale)
    local sox = ox / scale
    local soy = oy / scale
    for li, layer in ipairs(_batches) do
        local layerDef = self.layers[li]
        if layer.visible and ((layerDef.foreground and foreground) or (not layerDef.foreground and not foreground)) then
            love.graphics.setColor(r, g, b, a * (layer.opacity or 1))
            for _, entry in ipairs(layer.batches) do
                love.graphics.draw(entry.batch, sox, soy)
            end
            local animLayer = _animTiles[li]
            if animLayer then
                for _, at in ipairs(animLayer) do
                    local st  = _animState[at.sourceGID]
                    local gid = st and st.currentGID or at.sourceGID
                    local q   = _quads[gid]
                    local ti  = math.floor(gid / GID_STRIDE) + 1
                    if q and _images[ti] then
                        local sx = at.flipH and -1 or 1
                        local sy = at.flipV and -1 or 1
                        local ox = at.flipH and self.tileSize or 0
                        local oy = at.flipV and self.tileSize or 0
                        love.graphics.draw(_images[ti], q, sox + at.x + ox, soy + at.y + oy, 0, sx, sy)
                    end
                end
            end
            local flipLayer = _flipTiles[li]
            if flipLayer then
                for _, ft in ipairs(flipLayer) do
                    local q = _quads[ft.gid]
                    if q and _images[ft.ti] then
                        local sx = ft.flipH and -1 or 1
                        local sy = ft.flipV and -1 or 1
                        local ox = ft.flipH and self.tileSize or 0
                        local oy = ft.flipV and self.tileSize or 0
                        love.graphics.draw(_images[ft.ti], q, sox + ft.x + ox, soy + ft.y + oy, 0, sx, sy)
                    end
                end
            end
        end
    end
    love.graphics.pop()
    love.graphics.setColor(r, g, b, a)
end

--------------------------------------------------------------------------------
-- M:drawBackground([ox, oy, scale])
-- Draws layers marked as background (foreground = false).
-- Call this before drawing your player/entities.
--------------------------------------------------------------------------------
function M:drawBackground(ox, oy, scale)
    self:_drawLayers(false, ox, oy, scale)
end

--------------------------------------------------------------------------------
-- M:drawForeground([ox, oy, scale])
-- Draws layers marked as foreground (foreground = true).
-- Call this after drawing your player/entities.
--------------------------------------------------------------------------------
function M:drawForeground(ox, oy, scale)
    self:_drawLayers(true, ox, oy, scale)
end

--------------------------------------------------------------------------------
-- M:unload()
-- Releases all GPU resources (images, sprite batches).
-- Call when switching scenes or destroying the map.
--------------------------------------------------------------------------------
function M:unload()
    for _, img in ipairs(_images) do img:release() end
    for _, layer in ipairs(_batches) do
        for _, entry in ipairs(layer.batches) do entry.batch:release() end
    end
    _images  = {}
    _quads   = {}
    _batches = {}
end

--------------------------------------------------------------------------------
-- M:getTile(layerIndex, col, row) → gid
-- Returns the tile GID at (col, row) on the given layer (1-based index).
-- Returns -1 if the cell is empty or out of range.
--------------------------------------------------------------------------------
function M:getTile(layerIndex, col, row)
    local layer = self.layers[layerIndex]
    if not layer then return -1 end
    local idx = row * self.width + col + 1
    return layer.tiles[idx] or -1
end\(hasCollision ? """


--------------------------------------------------------------------------------
-- M.solidOutOfBounds
-- Controls what isSolid() returns when (col, row) is outside the map.
--   true  (default) - treat map edges as solid walls
--   false           - treat outside the map as passable (open world)
--------------------------------------------------------------------------------
M.solidOutOfBounds = true

--------------------------------------------------------------------------------
-- M:isInBounds(col, row) → boolean
-- Returns true if (col, row) is a valid cell inside the map.
--------------------------------------------------------------------------------
function M:isInBounds(col, row)
    return col >= 0 and row >= 0 and col < self.width and row < self.height
end

--------------------------------------------------------------------------------
-- M:isSolid(col, row) → boolean
--------------------------------------------------------------------------------
function M:isSolid(col, row)
    if not self:isInBounds(col, row) then
        return self.solidOutOfBounds
    end
    local idx = row * self.width + col + 1
    return (self.collision and self.collision[idx] == 1) or false
end
""" : "")

--------------------------------------------------------------------------------
-- M:setLayerVisible(name, visible)
-- Shows or hides a layer by name at runtime.
--   Map:setLayerVisible("Foreground", false)
--------------------------------------------------------------------------------
function M:setLayerVisible(name, visible)
    for li, layer in ipairs(self.layers) do
        if layer.name == name then
            layer.visible = visible
            if _batches[li] then _batches[li].visible = visible end
            return
        end
    end
end

--------------------------------------------------------------------------------
-- M:rebuild()
-- Reloads all sprite batches after a runtime tile edit.
--   Map.layers[1].tiles[ row * Map.width + col + 1 ] = newGID
--   Map:rebuild()
--------------------------------------------------------------------------------
function M:rebuild()
    self:load()
end

--------------------------------------------------------------------------------
-- M:getTileProperty(gid, key) → value or nil
-- Returns the custom property value for a tile GID, or nil if not set.
--   local speed = Map:getTileProperty(gid, "speed")
--------------------------------------------------------------------------------
function M:getTileProperty(gid, key)
    local props = self.tileProperties and self.tileProperties[gid]
    if not props then return nil end
    for _, p in ipairs(props) do
        if p.key == key then return p.value end
    end
    return nil
end

--------------------------------------------------------------------------------
-- M:getObjectsByType(typeName) → array of objects
-- Returns all objects with the given type across all object layers.
-- Returns an empty table if none are found.
--   local coins = Map:getObjectsByType("coin")
--   for _, c in ipairs(coins) do spawnCoin(c.x, c.y) end
--------------------------------------------------------------------------------
function M:getObjectsByType(typeName)
    local result = {}
    for _, layer in ipairs(self.layers) do
        if layer.layerType == "object" and layer.objects then
            for _, obj in ipairs(layer.objects) do
                if obj.type == typeName then
                    table.insert(result, obj)
                end
            end
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- M:getObjectByName(name) → object or nil
-- Returns the first object with the given name, or nil if not found.
--   local exit = Map:getObjectByName("exit_door")
--   if exit then teleportPlayerTo(exit.x, exit.y) end
--------------------------------------------------------------------------------
function M:getObjectByName(name)
    for _, layer in ipairs(self.layers) do
        if layer.layerType == "object" and layer.objects then
            for _, obj in ipairs(layer.objects) do
                if obj.name == name then
                    return obj
                end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- M:worldToTile(wx, wy) → col, row
-- Converts a world pixel position to tile cell coordinates.
--   local col, row = Map:worldToTile(player.x, player.y)
--------------------------------------------------------------------------------
function M:worldToTile(wx, wy)
    local ox = self.originX or 0
    local oy = self.originY or 0
    local col = math.floor((wx - ox) / self.tileSize)
    local row = math.floor((wy - oy) / self.tileSize)
    return col, row
end

--------------------------------------------------------------------------------
-- M:tileToWorld(col, row) → wx, wy
-- Converts tile cell coordinates to world pixel position (top-left of cell).
--   local wx, wy = Map:tileToWorld(col, row)
--------------------------------------------------------------------------------
function M:tileToWorld(col, row)
    local ox = self.originX or 0
    local oy = self.originY or 0
    return col * self.tileSize + ox, row * self.tileSize + oy
end

--------------------------------------------------------------------------------
-- M:drawLayer(layerIndex, ox, oy, scale)
-- Draws a single layer by its 1-based index (ignores foreground flag).
--   Map:drawLayer(2, -camX, -camY)
--------------------------------------------------------------------------------
function M:drawLayer(layerIndex, ox, oy, scale)
    local entry = _batches[layerIndex]
    if not entry then return end
    ox    = (ox or 0) + (self.originX or 0)
    oy    = (oy or 0) + (self.originY or 0)
    scale = scale or 1
    local r, g, b, a = love.graphics.getColor()
    love.graphics.push()
    love.graphics.scale(scale, scale)
    local sox = ox / scale
    local soy = oy / scale
    love.graphics.setColor(r, g, b, a * (entry.opacity or 1))
    for _, batch in ipairs(entry.batches) do
        love.graphics.draw(batch.batch, sox, soy)
    end
    local animLayer = _animTiles[layerIndex]
    if animLayer then
        for _, at in ipairs(animLayer) do
            local st  = _animState[at.sourceGID]
            local gid = st and st.currentGID or at.sourceGID
            local q   = _quads[gid]
            local ti  = math.floor(gid / GID_STRIDE) + 1
            if q and _images[ti] then
                local sx = at.flipH and -1 or 1
                local sy = at.flipV and -1 or 1
                local fx = at.flipH and self.tileSize or 0
                local fy = at.flipV and self.tileSize or 0
                love.graphics.draw(_images[ti], q, sox + at.x + fx, soy + at.y + fy, 0, sx, sy)
            end
        end
    end
    local flipLayer = _flipTiles[layerIndex]
    if flipLayer then
        for _, ft in ipairs(flipLayer) do
            local q = _quads[ft.gid]
            if q and _images[ft.ti] then
                local sx = ft.flipH and -1 or 1
                local sy = ft.flipV and -1 or 1
                local fx = ft.flipH and self.tileSize or 0
                local fy = ft.flipV and self.tileSize or 0
                love.graphics.draw(_images[ft.ti], q, sox + ft.x + fx, soy + ft.y + fy, 0, sx, sy)
            end
        end
    end
    love.graphics.pop()
    love.graphics.setColor(r, g, b, a)
end

--------------------------------------------------------------------------------
-- M:forEachTile(layerIndex, fn)
-- Iterates over every non-empty tile in a layer, calling fn(col, row, gid).
--   Map:forEachTile(1, function(col, row, gid)
--       if Map:getTileProperty(gid, "damage") then ... end
--   end)
--------------------------------------------------------------------------------
function M:forEachTile(layerIndex, fn)
    local layer = self.layers[layerIndex]
    if not layer or not layer.tiles then return end
    for idx, gid in ipairs(layer.tiles) do
        if gid >= 0 then
            local col = (idx - 1) % self.width
            local row = math.floor((idx - 1) / self.width)
            fn(col, row, gid)
        end
    end
end

--------------------------------------------------------------------------------
-- M.debug
-- Set to true to enable M:drawDebug() overlays.
--   Map.debug = true
--------------------------------------------------------------------------------
M.debug = false

--------------------------------------------------------------------------------
-- M:drawDebug([ox, oy, scale])
-- When M.debug is true, draws:
--   • Semi-transparent red rectangles over every solid (collision) tile.
--   • Colored outlines + labels for every object on object layers.
-- Call after Map:draw() in love.draw().
--
--   function love.draw()
--       Map:draw(-camX, -camY)
--       Map:drawDebug(-camX, -camY)
--   end
--------------------------------------------------------------------------------
function M:drawDebug(ox, oy, scale)
    if not self.debug then return end
    ox    = (ox or 0) + (self.originX or 0)
    oy    = (oy or 0) + (self.originY or 0)
    scale = scale or 1
    local ts  = self.tileSize * scale
    local sox = ox
    local soy = oy
    local r, g, b, a = love.graphics.getColor()

    -- Solid collision tiles (red fill + outline)
    if self.collision then
        love.graphics.setColor(1, 0.15, 0.15, 0.35)
        for idx, v in ipairs(self.collision) do
            if v == 1 then
                local col = (idx - 1) % self.width
                local row = math.floor((idx - 1) / self.width)
                love.graphics.rectangle("fill",
                    sox + col * ts, soy + row * ts, ts, ts)
            end
        end
        love.graphics.setColor(1, 0.2, 0.2, 0.7)
        for idx, v in ipairs(self.collision) do
            if v == 1 then
                local col = (idx - 1) % self.width
                local row = math.floor((idx - 1) / self.width)
                love.graphics.rectangle("line",
                    sox + col * ts, soy + row * ts, ts, ts)
            end
        end
    end

    -- Object layers
    local typeColors = {
        spawn   = { 0.2, 1.0, 0.4 },
        trigger = { 0.2, 0.6, 1.0 },
        npc     = { 1.0, 0.8, 0.1 },
    }
    local defaultColor = { 0.9, 0.5, 1.0 }

    for _, layer in ipairs(self.layers) do
        if layer.layerType == "object" and layer.visible and layer.objects then
            for _, obj in ipairs(layer.objects) do
                local c = typeColors[obj.type] or defaultColor
                local rx = sox + obj.x * ts
                local ry = soy + obj.y * ts
                local rw = obj.w * ts
                local rh = obj.h * ts

                love.graphics.setColor(c[1], c[2], c[3], 0.18)
                love.graphics.rectangle("fill", rx, ry, rw, rh)
                love.graphics.setColor(c[1], c[2], c[3], 0.9)
                love.graphics.rectangle("line", rx, ry, rw, rh)

                -- Label (name + type), unscaled font
                love.graphics.setColor(1, 1, 1, 0.95)
                local label = obj.name ~= "" and (obj.name .. " [" .. obj.type .. "]") or obj.type
                love.graphics.print(label, rx + 3, ry + 2, 0, 1 / scale, 1 / scale)
            end
        end
    end

    love.graphics.setColor(r, g, b, a)
end

return M
"""
    }
}
