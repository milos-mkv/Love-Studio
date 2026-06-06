import Foundation

enum ProjectTemplate: String, CaseIterable, Identifiable {
    case empty          = "empty"
    case pixelArt       = "pixel-art"
    case platformer     = "platformer"
    case topDownRPG     = "top-down-rpg"
    case shmup          = "shmup"
    case physicsSandbox = "physics-sandbox"
    case visualNovel    = "visual-novel"
    case mobileGame     = "mobile-game"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .empty:          return "Empty Game"
        case .pixelArt:       return "Pixel-Art Game"
        case .platformer:     return "Platformer"
        case .topDownRPG:     return "Top-Down RPG"
        case .shmup:          return "Shoot 'em Up"
        case .physicsSandbox: return "Physics Sandbox"
        case .visualNovel:    return "Visual Novel"
        case .mobileGame:     return "Mobile Game"
        }
    }

    var description: String {
        switch self {
        case .empty:          return "Blank slate sa love.load/update/draw"
        case .pixelArt:       return "Virtual resolution, nearest-neighbor, fullscreen toggle"
        case .platformer:     return "Player, gravity, tilemap scaffold"
        case .topDownRPG:     return "Camera, NPC, map sistem"
        case .shmup:          return "Bullets, enemies, spawning, collision"
        case .physicsSandbox: return "Box2D tijela, joints, mouse drag"
        case .visualNovel:    return "Dialog sistem, scene manager, choices"
        case .mobileGame:     return "Endless runner, touch/tap kontrole, portrait 9:16"
        }
    }

    var icon: String {
        switch self {
        case .empty:          return "doc"
        case .pixelArt:       return "square.grid.2x2"
        case .platformer:     return "gamecontroller"
        case .topDownRPG:     return "map"
        case .shmup:          return "airplane"
        case .physicsSandbox: return "atom"
        case .visualNovel:    return "text.bubble.fill"
        case .mobileGame:     return "iphone"
        }
    }

    var windowSize: (width: Int, height: Int) {
        switch self {
        case .pixelArt:   return (640, 360)
        case .mobileGame: return (360, 640)
        default:          return (800, 600)
        }
    }

    var files: [(name: String, content: String)] {
        switch self {
        case .empty:
            return [("main.lua", Self.emptyMain)]
        case .pixelArt:
            return [("main.lua", Self.pixelArtMain)]
        case .platformer:
            return [("main.lua", Self.platformerMain), ("player.lua", Self.platformerPlayer), ("world.lua", Self.platformerWorld)]
        case .topDownRPG:
            return [("main.lua", Self.rpgMain), ("camera.lua", Self.rpgCamera), ("map.lua", Self.rpgMap)]
        case .shmup:
            return [("main.lua", Self.shmupMain), ("player.lua", Self.shmupPlayer), ("bullet.lua", Self.shmupBullet), ("enemy.lua", Self.shmupEnemy)]
        case .physicsSandbox:
            return [("main.lua", Self.physicsMain)]
        case .visualNovel:
            return [("main.lua", Self.vnMain), ("scene.lua", Self.vnScene), ("dialog.lua", Self.vnDialog), ("scenes", Self.vnScenesData)]
        case .mobileGame:
            return [("main.lua", Self.mobileMain), ("runner.lua", Self.mobileRunner), ("obstacle.lua", Self.mobileObstacle), ("ui.lua", Self.mobileUI)]
        }
    }
}

// MARK: - Template Sources

private extension ProjectTemplate {

    // MARK: Empty

    static let emptyMain = """
function love.load()
    -- Inicijalizacija
end

function love.update(dt)
    -- Update logika
end

function love.draw()
    -- Crtanje
    love.graphics.print("Hello, LÖVE!", 10, 10)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end
"""

    // MARK: Pixel Art

    static let pixelArtMain = """
-- Virtual resolution setup
local VWIDTH, VHEIGHT = 320, 180
local canvas
local scale

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    canvas = love.graphics.newCanvas(VWIDTH, VHEIGHT)
    recalcScale()
end

function recalcScale()
    local sw, sh = love.graphics.getDimensions()
    scale = math.min(sw / VWIDTH, sh / VHEIGHT)
end

function love.update(dt)
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.1, 0.1, 0.15)

    love.graphics.setColor(1, 0.4, 0.6)
    love.graphics.print("Pixel Art Mode!", 4, 4)

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    local sw, sh = love.graphics.getDimensions()
    local ox = (sw - VWIDTH * scale) / 2
    local oy = (sh - VHEIGHT * scale) / 2
    love.graphics.draw(canvas, ox, oy, 0, scale, scale)
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "f11" then
        local fs = love.window.getFullscreen()
        love.window.setFullscreen(not fs, "desktop")
        recalcScale()
    end
end

function love.resize(w, h)
    recalcScale()
end
"""

    // MARK: Platformer

    static let platformerMain = """
local Player = require("player")
local World  = require("world")

local player
local world

function love.load()
    world  = World.new()
    player = Player.new(100, 100)
end

function love.update(dt)
    player:update(dt, world)
end

function love.draw()
    world:draw()
    player:draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("WASD / Arrows — Move | Space — Jump | Esc — Quit", 8, 8)
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    player:keypressed(key)
end
"""

    static let platformerPlayer = """
local Player = {}
Player.__index = Player

local GRAVITY  = 800
local JUMP_VEL = -380
local SPEED    = 160
local W, H     = 24, 32

function Player.new(x, y)
    return setmetatable({ x=x, y=y, vx=0, vy=0, onGround=false }, Player)
end

function Player:update(dt, world)
    self.vx = 0
    if love.keyboard.isDown("left",  "a") then self.vx = -SPEED end
    if love.keyboard.isDown("right", "d") then self.vx =  SPEED end

    self.vy = self.vy + GRAVITY * dt
    self.x  = self.x + self.vx * dt
    self.y  = self.y + self.vy * dt
    self.onGround = false

    local floorY = world.floorY - H
    if self.y >= floorY then
        self.y = floorY
        self.vy = 0
        self.onGround = true
    end
end

function Player:keypressed(key)
    if (key == "space" or key == "up" or key == "w") and self.onGround then
        self.vy = JUMP_VEL
    end
end

function Player:draw()
    love.graphics.setColor(0.2, 0.6, 1)
    love.graphics.rectangle("fill", self.x, self.y, W, H)
    love.graphics.setColor(1, 1, 1)
end

return Player
"""

    static let platformerWorld = """
local World = {}
World.__index = World

function World.new()
    return setmetatable({ floorY = love.graphics.getHeight() - 40 }, World)
end

function World:draw()
    love.graphics.setColor(0.3, 0.7, 0.3)
    love.graphics.rectangle("fill", 0, self.floorY, love.graphics.getWidth(), 40)
    love.graphics.setColor(1, 1, 1)
end

return World
"""

    // MARK: Top-Down RPG

    static let rpgMain = """
local Camera = require("camera")
local Map    = require("map")

local camera
local map
local player = { x=200, y=200, speed=120, size=14 }

function love.load()
    map    = Map.new()
    camera = Camera.new()
end

function love.update(dt)
    if love.keyboard.isDown("left",  "a") then player.x = player.x - player.speed * dt end
    if love.keyboard.isDown("right", "d") then player.x = player.x + player.speed * dt end
    if love.keyboard.isDown("up",    "w") then player.y = player.y - player.speed * dt end
    if love.keyboard.isDown("down",  "s") then player.y = player.y + player.speed * dt end
    camera:follow(player.x, player.y, dt)
end

function love.draw()
    camera:attach()
        map:draw()
        love.graphics.setColor(0.2, 0.8, 0.4)
        local s = player.size
        love.graphics.rectangle("fill", player.x - s/2, player.y - s/2, s, s)
    camera:detach()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("WASD — Move | Esc — Quit", 8, 8)
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
end
"""

    static let rpgCamera = """
local Camera = {}
Camera.__index = Camera

local LERP = 5

function Camera.new()
    local sw, sh = love.graphics.getDimensions()
    return setmetatable({ x=0, y=0, sw=sw, sh=sh }, Camera)
end

function Camera:follow(tx, ty, dt)
    self.x = self.x + (tx - self.x) * LERP * dt
    self.y = self.y + (ty - self.y) * LERP * dt
end

function Camera:attach()
    love.graphics.push()
    love.graphics.translate(
        math.floor(self.sw / 2 - self.x),
        math.floor(self.sh / 2 - self.y)
    )
end

function Camera:detach()
    love.graphics.pop()
end

return Camera
"""

    static let rpgMap = """
local Map = {}
Map.__index = Map

local TILE = 32
local COLS = 20
local ROWS = 15

local data = {
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,2,2,2,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,2,0,2,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,2,2,2,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
}

local colors = {
    [0] = {0.3, 0.65, 0.3},
    [1] = {0.2, 0.4,  0.8},
    [2] = {0.6, 0.4,  0.2},
}

function Map.new()
    return setmetatable({}, Map)
end

function Map:draw()
    for i, tile in ipairs(data) do
        local col = (i-1) % COLS
        local row = math.floor((i-1) / COLS)
        local c = colors[tile] or {1,0,1}
        love.graphics.setColor(c)
        love.graphics.rectangle("fill", col*TILE, row*TILE, TILE-1, TILE-1)
    end
    love.graphics.setColor(1, 1, 1)
end

return Map
"""

    // MARK: Shoot 'em Up

    static let shmupMain = """
local Player = require("player")
local Bullet = require("bullet")
local Enemy  = require("enemy")

local player
local bullets = {}
local enemies = {}
local spawnTimer = 0
local SPAWN_INTERVAL = 1.5
local score = 0

function love.load()
    math.randomseed(os.time())
    player = Player.new()
end

function love.update(dt)
    player:update(dt, bullets)

    -- Spawn enemies
    spawnTimer = spawnTimer + dt
    if spawnTimer >= SPAWN_INTERVAL then
        spawnTimer = 0
        table.insert(enemies, Enemy.new())
    end

    -- Update bullets
    for i = #bullets, 1, -1 do
        bullets[i]:update(dt)
        if bullets[i].dead then table.remove(bullets, i) end
    end

    -- Update enemies
    for i = #enemies, 1, -1 do
        enemies[i]:update(dt)
        if enemies[i].dead then
            table.remove(enemies, i)
        end
    end

    -- Bullet <-> Enemy collision
    for bi = #bullets, 1, -1 do
        for ei = #enemies, 1, -1 do
            if bullets[bi] and not bullets[bi].dead and
               enemies[ei] and not enemies[ei].dead then
                if Bullet.hits(bullets[bi], enemies[ei]) then
                    bullets[bi].dead = true
                    enemies[ei].dead = true
                    score = score + 10
                end
            end
        end
    end
end

function love.draw()
    -- Background
    love.graphics.setColor(0.05, 0.05, 0.12)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

    player:draw()
    for _, b in ipairs(bullets) do b:draw() end
    for _, e in ipairs(enemies) do e:draw() end

    -- HUD
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Score: " .. score, 8, 8)
    love.graphics.print("WASD/Arrows — Move | Space — Shoot | Esc — Quit", 8, 28)
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
end
"""

    static let shmupPlayer = """
local Bullet = require("bullet")

local Player = {}
Player.__index = Player

local SPEED = 220
local SW, SH = love.graphics.getDimensions()
local W, H = 20, 28
local FIRE_RATE = 0.15

function Player.new()
    return setmetatable({
        x = SW / 2 - W / 2,
        y = SH - 80,
        fireTimer = 0
    }, Player)
end

function Player:update(dt, bullets)
    local sw, sh = love.graphics.getDimensions()
    if love.keyboard.isDown("left",  "a") then self.x = self.x - SPEED * dt end
    if love.keyboard.isDown("right", "d") then self.x = self.x + SPEED * dt end
    if love.keyboard.isDown("up",    "w") then self.y = self.y - SPEED * dt end
    if love.keyboard.isDown("down",  "s") then self.y = self.y + SPEED * dt end

    self.x = math.max(0, math.min(sw - W, self.x))
    self.y = math.max(0, math.min(sh - H, self.y))

    self.fireTimer = self.fireTimer + dt
    if love.keyboard.isDown("space") and self.fireTimer >= FIRE_RATE then
        self.fireTimer = 0
        table.insert(bullets, Bullet.new(self.x + W/2, self.y, -1))
    end
end

function Player:draw()
    love.graphics.setColor(0.3, 0.8, 1)
    love.graphics.polygon("fill",
        self.x + W/2, self.y,
        self.x,       self.y + H,
        self.x + W,   self.y + H
    )
end

return Player
"""

    static let shmupBullet = """
local Bullet = {}
Bullet.__index = Bullet

local SPEED = 420
local SIZE  = 5

function Bullet.new(x, y, dir)
    return setmetatable({ x=x, y=y, dir=dir or -1, dead=false }, Bullet)
end

function Bullet:update(dt)
    self.y = self.y + SPEED * self.dir * dt
    local _, sh = love.graphics.getDimensions()
    if self.y < -SIZE or self.y > sh + SIZE then
        self.dead = true
    end
end

function Bullet:draw()
    love.graphics.setColor(1, 1, 0.4)
    love.graphics.rectangle("fill", self.x - SIZE/2, self.y, SIZE, SIZE*2)
end

function Bullet.hits(bullet, target)
    local tw, th = target.w or 24, target.h or 24
    return bullet.x >= target.x and bullet.x <= target.x + tw
       and bullet.y >= target.y and bullet.y <= target.y + th
end

return Bullet
"""

    static let shmupEnemy = """
local Enemy = {}
Enemy.__index = Enemy

local SPEED = 90
local W, H  = 24, 20

function Enemy.new()
    local sw = love.graphics.getWidth()
    return setmetatable({
        x = math.random(0, sw - W),
        y = -H,
        w = W, h = H,
        dead = false
    }, Enemy)
end

function Enemy:update(dt)
    self.y = self.y + SPEED * dt
    local _, sh = love.graphics.getDimensions()
    if self.y > sh + H then self.dead = true end
end

function Enemy:draw()
    love.graphics.setColor(1, 0.3, 0.3)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
    love.graphics.setColor(1, 0.6, 0.1)
    love.graphics.rectangle("fill", self.x + 4, self.y + H, 4, 6)
    love.graphics.rectangle("fill", self.x + W - 8, self.y + H, 4, 6)
end

return Enemy
"""

    // MARK: Physics Sandbox

    static let physicsMain = """
-- Box2D Physics Sandbox
local world
local bodies = {}
local ground

local GRAVITY = 600
local grabbed = nil
local grabJoint = nil

function love.load()
    world = love.physics.newWorld(0, GRAVITY, true)

    -- Static ground
    local sw, sh = love.graphics.getDimensions()
    ground = {}
    ground.body = love.physics.newBody(world, sw/2, sh - 20, "static")
    ground.shape = love.physics.newRectangleShape(sw, 40)
    ground.fixture = love.physics.newFixture(ground.body, ground.shape, 1)

    -- Spawn a few starter boxes
    for i = 1, 5 do
        spawnBox(100 + i * 120, 200)
    end
end

function spawnBox(x, y, w, h)
    w = w or math.random(20, 60)
    h = h or math.random(20, 60)
    local b = {}
    b.body    = love.physics.newBody(world, x, y, "dynamic")
    b.shape   = love.physics.newRectangleShape(w, h)
    b.fixture = love.physics.newFixture(b.body, b.shape, 1)
    b.fixture:setRestitution(0.4)
    b.w, b.h = w, h
    b.r = math.random(0, 255) / 255
    b.g = math.random(0, 255) / 255
    b.b = math.random(0, 255) / 255
    table.insert(bodies, b)
end

function spawnCircle(x, y)
    local r = math.random(10, 30)
    local b = {}
    b.body    = love.physics.newBody(world, x, y, "dynamic")
    b.shape   = love.physics.newCircleShape(r)
    b.fixture = love.physics.newFixture(b.body, b.shape, 1)
    b.fixture:setRestitution(0.6)
    b.isCircle = true
    b.r = math.random(0, 255) / 255
    b.g = math.random(0, 255) / 255
    b.b = math.random(0, 255) / 255
    b.radius = r
    table.insert(bodies, b)
end

function love.update(dt)
    world:update(dt)

    -- Update grab joint mouse position
    if grabJoint then
        grabJoint:setTarget(love.mouse.getPosition())
    end
end

function love.draw()
    local sw, sh = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(0.12, 0.12, 0.16)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- Ground
    love.graphics.setColor(0.4, 0.4, 0.45)
    love.graphics.polygon("fill", ground.body:getWorldPoints(ground.shape:getPoints()))

    -- Bodies
    for _, b in ipairs(bodies) do
        love.graphics.setColor(b.r, b.g, b.b, 0.85)
        if b.isCircle then
            local x, y = b.body:getPosition()
            love.graphics.circle("fill", x, y, b.radius)
            love.graphics.setColor(1, 1, 1, 0.3)
            love.graphics.circle("line", x, y, b.radius)
        else
            love.graphics.polygon("fill", b.body:getWorldPoints(b.shape:getPoints()))
            love.graphics.setColor(1, 1, 1, 0.2)
            love.graphics.polygon("line", b.body:getWorldPoints(b.shape:getPoints()))
        end
    end

    -- HUD
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("LClick — spawn box  |  RClick — spawn circle  |  Hold LClick on body — drag  |  Esc — quit", 8, 8)
    love.graphics.print("Bodies: " .. #bodies, 8, 28)
end

function love.mousepressed(mx, my, button)
    if button == 1 then
        -- Check if clicking on existing body to grab
        for _, b in ipairs(bodies) do
            local bx, by = b.body:getPosition()
            local dist = math.sqrt((mx-bx)^2 + (my-by)^2)
            local threshold = b.isCircle and b.radius or math.max((b.w or 30), (b.h or 30)) * 0.8
            if dist < threshold then
                grabbed = b
                grabJoint = love.physics.newMouseJoint(b.body, mx, my)
                grabJoint:setMaxForce(b.body:getMass() * 1000)
                return
            end
        end
        -- Otherwise spawn new box
        spawnBox(mx, my)
    elseif button == 2 then
        spawnCircle(mx, my)
    end
end

function love.mousereleased(mx, my, button)
    if button == 1 and grabJoint then
        grabJoint:destroy()
        grabJoint = nil
        grabbed = nil
    end
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "r" then
        -- Reset
        for _, b in ipairs(bodies) do b.body:destroy() end
        bodies = {}
    end
end
"""

    // MARK: Visual Novel

    static let vnMain = """
local SceneManager = require("scene")

function love.load()
    SceneManager.load()
end

function love.update(dt)
    SceneManager.update(dt)
end

function love.draw()
    SceneManager.draw()
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    SceneManager.keypressed(key)
end

function love.mousepressed(mx, my, button)
    SceneManager.mousepressed(mx, my, button)
end
"""

    static let vnScene = """
local Dialog = require("dialog")

local SceneManager = {}

local scenes = require("scenes")
local currentScene = 1
local currentLine  = 1

function SceneManager.load()
    Dialog.load()
end

function SceneManager.update(dt)
    Dialog.update(dt)
end

function SceneManager.draw()
    local scene = scenes[currentScene]
    if not scene then return end

    local sw, sh = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(scene.bg or {0.1, 0.1, 0.2})
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    -- Character placeholder
    if scene.character then
        love.graphics.setColor(0.8, 0.7, 0.6)
        love.graphics.rectangle("fill", sw/2 - 60, sh/2 - 120, 120, 200)
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.printf(scene.character, sw/2 - 60, sh/2 + 85, 120, "center")
    end

    -- Dialog box
    local line = scene.lines and scene.lines[currentLine]
    if line then
        Dialog.draw(line.speaker, line.text)
    end
end

function SceneManager.keypressed(key)
    if key == "space" or key == "return" then
        SceneManager.advance()
    end
end

function SceneManager.mousepressed(mx, my, button)
    if button == 1 then
        SceneManager.advance()
    end
end

function SceneManager.advance()
    local scene = scenes[currentScene]
    if not scene then return end

    if Dialog.isAnimating() then
        Dialog.skip()
        return
    end

    currentLine = currentLine + 1
    if currentLine > #(scene.lines or {}) then
        currentLine = 1
        currentScene = currentScene + 1
        if currentScene > #scenes then
            love.event.quit()
        end
    else
        local line = scene.lines[currentLine]
        if line then Dialog.startLine(line.text) end
    end
end

return SceneManager
"""

    static let vnDialog = """
local Dialog = {}

local font
local displayText = ""
local fullText    = ""
local charTimer   = 0
local CHAR_SPEED  = 0.03  -- seconds per character
local animating   = false

function Dialog.load()
    font = love.graphics.newFont(16)
end

function Dialog.update(dt)
    if not animating then return end

    charTimer = charTimer + dt
    local charsToShow = math.floor(charTimer / CHAR_SPEED)

    if charsToShow >= #fullText then
        displayText = fullText
        animating   = false
    else
        displayText = string.sub(fullText, 1, charsToShow)
    end
end

function Dialog.startLine(text)
    fullText    = text
    displayText = ""
    charTimer   = 0
    animating   = true
end

function Dialog.skip()
    displayText = fullText
    animating   = false
end

function Dialog.isAnimating()
    return animating
end

function Dialog.draw(speaker, text)
    if not text then return end

    local sw, sh = love.graphics.getDimensions()
    local boxH   = 130
    local boxY   = sh - boxH - 20
    local pad    = 20

    -- Dialog box background
    love.graphics.setColor(0.05, 0.05, 0.1, 0.92)
    love.graphics.rectangle("fill", 20, boxY, sw - 40, boxH, 8, 8)
    love.graphics.setColor(0.6, 0.4, 0.8)
    love.graphics.rectangle("line", 20, boxY, sw - 40, boxH, 8, 8)

    -- Speaker name
    if speaker and speaker ~= "" then
        love.graphics.setColor(0.8, 0.6, 1)
        love.graphics.setFont(font)
        love.graphics.print(speaker, 40, boxY - 26)
    end

    -- Dialog text (typewriter effect)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font)
    love.graphics.printf(displayText, 40, boxY + pad, sw - 80)

    -- Advance hint
    if not Dialog.isAnimating() then
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.print("▶  Click or Space to continue", sw - 260, boxY + boxH - 28)
    end
end

return Dialog
"""

    static let vnScenesData = """
-- scenes.lua — define your story here
-- Each scene has: bg color, optional character name, and lines array
-- Each line has: speaker (string) and text (string)

return {
    {
        bg = {0.08, 0.06, 0.14},
        character = "Alex",
        lines = {
            { speaker = "Narrator", text = "It was a quiet evening. The kind that makes you feel like something is about to change." },
            { speaker = "Alex",     text = "I never expected to find a letter like this on my doorstep..." },
            { speaker = "Alex",     text = "Who could have left it here?" },
        }
    },
    {
        bg = {0.05, 0.10, 0.08},
        character = "Maya",
        lines = {
            { speaker = "Maya",     text = "You actually came. I wasn't sure you would." },
            { speaker = "Alex",     text = "How could I not? The letter said everything depended on it." },
            { speaker = "Maya",     text = "Then let me explain everything from the beginning..." },
        }
    },
    {
        bg = {0.14, 0.08, 0.06},
        character = nil,
        lines = {
            { speaker = "Narrator", text = "And so the story began — one that neither of them could have anticipated." },
            { speaker = "",         text = "[ End of demo. Edit scenes.lua to write your own story. ]" },
        }
    },
}
"""

    // MARK: Mobile Game — Endless Runner

    static let mobileMain = """
-- Mobile Endless Runner
-- Controls: tap screen (or Space/Up on desktop) to jump
-- Double-tap (or press twice) for double jump

local Runner   = require("runner")
local Obstacle = require("obstacle")
local UI       = require("ui")

local SW, SH = love.graphics.getDimensions()

-- Game state: "start", "playing", "dead"
local state       = "start"
local score       = 0
local hiScore     = 0
local scoreTimer  = 0

local runner
local obstacles   = {}
local spawnTimer  = 0
local spawnDelay  = 1.8
local speed       = 260   -- pixels/sec, increases over time

local GROUND_Y    = SH - 80

-- Parallax background layers
local bg = {
    { stars = {}, speed = 30  },
    { stars = {}, speed = 70  },
    { stars = {}, speed = 140 },
}

local function initBg()
    math.randomseed(os.time())
    for _, layer in ipairs(bg) do
        for _ = 1, 40 do
            table.insert(layer.stars, {
                x = math.random(0, SW),
                y = math.random(0, GROUND_Y - 20),
                r = math.random(1, 3) * 0.5,
            })
        end
    end
end

local function resetGame()
    runner    = Runner.new(SW, SH, GROUND_Y)
    obstacles = {}
    spawnTimer = 0
    spawnDelay = 1.8
    speed      = 260
    score      = 0
    scoreTimer = 0
end

function love.load()
    initBg()
    resetGame()
end

-- Input: jump on tap or key
local function tryJump()
    if state == "start" then
        state = "playing"
        runner:jump()
    elseif state == "playing" then
        runner:jump()
    elseif state == "dead" then
        resetGame()
        state = "playing"
    end
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "space" or key == "up" or key == "w" then tryJump() end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
    tryJump()
end

function love.mousepressed(x, y, button)
    if button == 1 then tryJump() end
end

function love.update(dt)
    if state ~= "playing" then return end

    -- Scroll background
    for _, layer in ipairs(bg) do
        for _, s in ipairs(layer.stars) do
            s.x = s.x - layer.speed * dt
            if s.x < 0 then s.x = SW end
        end
    end

    -- Increase difficulty over time
    speed      = speed + 18 * dt
    spawnDelay = math.max(0.7, spawnDelay - 0.012 * dt)
    scoreTimer = scoreTimer + dt
    if scoreTimer >= 0.1 then
        score = score + 1
        scoreTimer = 0
    end

    runner:update(dt)

    -- Spawn obstacles
    spawnTimer = spawnTimer + dt
    if spawnTimer >= spawnDelay then
        spawnTimer = 0
        table.insert(obstacles, Obstacle.new(SW, SH, GROUND_Y, speed))
    end

    -- Update & cull obstacles
    for i = #obstacles, 1, -1 do
        obstacles[i]:update(dt, speed)
        if obstacles[i].x + obstacles[i].w < 0 then
            table.remove(obstacles, i)
        end
    end

    -- Collision
    for _, obs in ipairs(obstacles) do
        if runner:hits(obs) then
            if score > hiScore then hiScore = score end
            state = "dead"
            break
        end
    end
end

function love.draw()
    local sw, sh = love.graphics.getDimensions()

    -- Sky gradient (two-rect approximation)
    love.graphics.setColor(0.05, 0.04, 0.14)
    love.graphics.rectangle("fill", 0, 0, sw, GROUND_Y)

    -- Parallax stars
    for li, layer in ipairs(bg) do
        local brightness = 0.3 + li * 0.2
        for _, s in ipairs(layer.stars) do
            love.graphics.setColor(brightness, brightness, brightness + 0.1)
            love.graphics.circle("fill", s.x, s.y, s.r)
        end
    end

    -- Ground
    love.graphics.setColor(0.18, 0.55, 0.34)
    love.graphics.rectangle("fill", 0, GROUND_Y, sw, sh - GROUND_Y)
    love.graphics.setColor(0.12, 0.42, 0.26)
    love.graphics.rectangle("fill", 0, GROUND_Y, sw, 6)

    -- Game objects
    for _, obs in ipairs(obstacles) do obs:draw() end
    runner:draw()

    -- UI overlay
    UI.draw(state, score, hiScore, sw, sh)
end
"""

    static let mobileRunner = """
-- runner.lua — the player character

local Runner = {}
Runner.__index = Runner

local GRAVITY     = 1400
local JUMP_VEL    = -580
local W, H        = 36, 52
local MAX_JUMPS   = 2   -- double jump allowed

function Runner.new(sw, sh, groundY)
    local r = setmetatable({}, Runner)
    r.x        = 80
    r.groundY  = groundY
    r.y        = groundY - H
    r.vy       = 0
    r.jumps    = 0
    r.w        = W
    r.h        = H
    -- Simple squash/stretch animation
    r.scaleY   = 1
    r.scaleVel = 0
    return r
end

function Runner:jump()
    if self.jumps < MAX_JUMPS then
        self.vy       = JUMP_VEL
        self.jumps    = self.jumps + 1
        self.scaleY   = 0.6
        self.scaleVel = 8
    end
end

function Runner:update(dt)
    self.vy = self.vy + GRAVITY * dt
    self.y  = self.y  + self.vy  * dt

    -- Land
    local floorY = self.groundY - self.h
    if self.y >= floorY then
        self.y     = floorY
        self.vy    = 0
        self.jumps = 0
        if self.scaleY < 1 then
            self.scaleY   = 1.3   -- squash on landing
            self.scaleVel = -6
        end
    end

    -- Animate squash/stretch back to 1
    self.scaleY = self.scaleY + self.scaleVel * dt
    if (self.scaleVel > 0 and self.scaleY > 1) or
       (self.scaleVel < 0 and self.scaleY < 1) then
        self.scaleY   = 1
        self.scaleVel = 0
    end
end

function Runner:hits(obs)
    local margin = 6
    local rx1 = self.x + margin
    local ry1 = self.y + margin
    local rx2 = self.x + self.w - margin
    local ry2 = self.y + self.h - margin
    local ox1 = obs.x + 2
    local oy1 = obs.y + 2
    local ox2 = obs.x + obs.w - 2
    local oy2 = obs.y + obs.h - 2
    return rx1 < ox2 and rx2 > ox1 and ry1 < oy2 and ry2 > oy1
end

function Runner:draw()
    local cx    = self.x + self.w / 2
    local cy    = self.y + self.h / 2
    local dh    = self.h * self.scaleY
    local dw    = self.w * (2 - self.scaleY)   -- inverse scale on X

    -- Body
    love.graphics.setColor(0.25, 0.72, 1)
    love.graphics.rectangle("fill",
        cx - dw / 2, cy - dh / 2, dw, dh, 6, 6)

    -- Eyes
    local eyeY  = cy - dh / 2 + dh * 0.22
    local eyeOX = dw * 0.22
    love.graphics.setColor(1, 1, 1)
    love.graphics.circle("fill", cx + eyeOX, eyeY, 5)
    love.graphics.setColor(0.05, 0.05, 0.15)
    love.graphics.circle("fill", cx + eyeOX + 1.5, eyeY, 2.5)

    -- Jump indicator dots (remaining jumps)
    for i = 1, MAX_JUMPS do
        local hasJump = i > self.jumps
        love.graphics.setColor(hasJump and {0.3, 0.9, 1} or {0.2, 0.2, 0.3})
        love.graphics.circle("fill", self.x + (i - 1) * 12, self.y - 10, 4)
    end

    love.graphics.setColor(1, 1, 1)
end

return Runner
"""

    static let mobileObstacle = """
-- obstacle.lua — randomly-shaped obstacles

local Obstacle = {}
Obstacle.__index = Obstacle

local TYPES = { "cactus", "spike", "block" }

function Obstacle.new(sw, sh, groundY, speed)
    local kind  = TYPES[math.random(#TYPES)]
    local w     = math.random(22, 38)
    local h     = math.random(30, 70)
    return setmetatable({
        x       = sw + 10,
        y       = groundY - h,
        w       = w,
        h       = h,
        kind    = kind,
        groundY = groundY,
    }, Obstacle)
end

function Obstacle:update(dt, speed)
    self.x = self.x - speed * dt
end

function Obstacle:draw()
    if self.kind == "cactus" then
        -- Trunk
        love.graphics.setColor(0.2, 0.65, 0.2)
        love.graphics.rectangle("fill", self.x + self.w * 0.3, self.y, self.w * 0.4, self.h, 3, 3)
        -- Arms
        local armH = self.h * 0.35
        love.graphics.rectangle("fill", self.x, self.y + self.h * 0.25, self.w * 0.35, self.h * 0.12, 2, 2)
        love.graphics.rectangle("fill", self.x, self.y + self.h * 0.13, self.w * 0.35, self.h * 0.12, 2, 2)
        love.graphics.rectangle("fill", self.x + self.w * 0.65, self.y + self.h * 0.35, self.w * 0.35, self.h * 0.12, 2, 2)
        love.graphics.rectangle("fill", self.x + self.w * 0.65, self.y + self.h * 0.23, self.w * 0.35, self.h * 0.12, 2, 2)

    elseif self.kind == "spike" then
        -- Row of triangles
        local cols  = math.max(1, math.floor(self.w / 18))
        local tw    = self.w / cols
        for i = 0, cols - 1 do
            local bx = self.x + i * tw
            love.graphics.setColor(0.8, 0.2, 0.3)
            love.graphics.polygon("fill",
                bx, self.groundY,
                bx + tw / 2, self.y,
                bx + tw, self.groundY)
            love.graphics.setColor(1, 0.4, 0.5)
            love.graphics.polygon("line",
                bx, self.groundY,
                bx + tw / 2, self.y,
                bx + tw, self.groundY)
        end

    else -- block
        love.graphics.setColor(0.6, 0.45, 0.25)
        love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 4, 4)
        -- Brick lines
        love.graphics.setColor(0.45, 0.32, 0.16)
        local rows = math.floor(self.h / 16)
        for r = 1, rows do
            love.graphics.rectangle("fill", self.x, self.y + r * 16 - 2, self.w, 3)
        end
        love.graphics.setColor(0.75, 0.58, 0.35)
        love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 4, 4)
    end

    love.graphics.setColor(1, 1, 1)
end

return Obstacle
"""

    static let mobileUI = """
-- ui.lua — HUD and overlay screens

local UI = {}

local function centeredText(text, y, sw, size, r, g, b)
    local font = love.graphics.newFont(size or 22)
    love.graphics.setFont(font)
    love.graphics.setColor(r or 1, g or 1, b or 1)
    love.graphics.printf(text, 0, y, sw, "center")
end

function UI.draw(state, score, hiScore, sw, sh)
    if state == "start" then
        -- Semi-transparent overlay
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, 0, sw, sh)

        centeredText("RUNNER",       sh * 0.28, sw, 46, 0.3, 0.85, 1)
        centeredText("Tap to start", sh * 0.52, sw, 22, 0.9, 0.9, 0.9)
        centeredText("Tap again to double jump", sh * 0.59, sw, 16, 0.6, 0.6, 0.6)

        if hiScore > 0 then
            centeredText("Best: " .. hiScore, sh * 0.70, sw, 18, 1, 0.85, 0.3)
        end

    elseif state == "playing" then
        -- Score top-center
        love.graphics.setColor(1, 1, 1, 0.9)
        local font = love.graphics.newFont(28)
        love.graphics.setFont(font)
        love.graphics.printf(tostring(score), 0, 22, sw, "center")

    elseif state == "dead" then
        love.graphics.setColor(0, 0, 0, 0.65)
        love.graphics.rectangle("fill", 0, 0, sw, sh)

        centeredText("GAME OVER",       sh * 0.30, sw, 40, 1, 0.35, 0.35)
        centeredText("Score: " .. score, sh * 0.44, sw, 26, 1, 1, 1)

        if score >= hiScore then
            centeredText("NEW BEST!", sh * 0.52, sw, 20, 1, 0.9, 0.2)
        else
            centeredText("Best: " .. hiScore, sh * 0.52, sw, 18, 0.8, 0.8, 0.6)
        end

        centeredText("Tap to play again", sh * 0.66, sw, 22, 0.7, 0.9, 1)
    end

    love.graphics.setColor(1, 1, 1)
end

return UI
"""
}
