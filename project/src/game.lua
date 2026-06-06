-- Copyright 2026 Natalie Baker -- AGPLv3 --

print(love.graphics.getRendererInfo())

local lovely = require("lib.lovely"   )
local v2d    = require("lib.shrimpvec")
local lfx    = require("src.lfx"      )
local arlu   = require("lib.arlu"     )

local Light    = require("src.ecs.light" )
local Basis    = require("src.ecs.basis" )
local Sprite   = require("src.ecs.sprite")
require("src.ecs.occluder") -- Decorate arlu with component id

---@param world arlu.World
---@param size number
---@param texId integer
local function initBoxes(world, size, texId)
    local hcount = 8

    local boxBuilder = lfx.OccluderBuilder.new():addBox(v2d(size, size))
    for x=-hcount,hcount do
        for y=-hcount,hcount do

            local i = x+hcount + (hcount*2+1)*(y+hcount)

            local r = 0.2 + 0.8*(i*37 % 10)/10
            local g = 0.2 + 0.8*(i*73 % 10)/10
            local b = 0.2 + 0.8*(i    % 10)/10

            world:spawn({
                [lfx.Occluder.ID] = boxBuilder:build(1.0),
                [      Sprite.ID] = Sprite.new(v2d(size,size), {r,g,b,1}, texId),
                [       Basis.ID] = Basis.new(2*size*v2d(x, y))
            })
        end
    end
end

local function initLights(world, count)
    local colours = {
        {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0},
        {1.0, 1.0, 0.0}, {1.0, 0.0, 1.0}, {0.0, 1.0, 1.0},
        {1.0, 0.5, 0.5}, {0.5, 1.0, 0.5}, {0.5, 0.5, 1.0},
        {1.0, 1.0, 0.5}, {1.0, 0.5, 1.0}, {0.5, 1.0, 1.0},
        {1.0, 1.0, 1.0},
    }

    local angle = 2*math.pi/count

    for i=1,count do
        local off   = i/count
        local dist  = 16 + 6*(math.cos(off+love.timer.getTime()))
        local dir = (i+off+love.timer.getTime())*angle

        world:spawn({
            [Light.ID] = Light.new(
                1.5,
                8 + (i*37 % 128)/128 * 12,
                (function()
                    local ra,ga,ba = unpack(colours[1+((   i-1) % #colours)])
                    local rb,gb,bb = unpack(colours[1+((73*i-1) % #colours)])
                    return {(2*ra + rb)*75, (2*ga + gb)*75, (2*ba + bb)*75}
                end)()
            ),
            [Basis.ID] = Basis.new(
                dist*v2d.newRotation(dir),
                0,
                1
            )
        })
    end
end

local world = arlu.World.new()
local projection = love.math.newTransform()
local playerEId

---@type table<string, LFX.TexAtlas>
local atlas = {}

function love.load()
    projection:setMatrix(lovely.math.orthoProjection(love.graphics.getPixelDimensions()))

    print("Loading low textures")
    atlas.lo = lfx.TexAtlasBuilder.new():loadAll("assets/materials/lo"):tryBuild()

    print("Loading med textures")
    atlas.md = lfx.TexAtlasBuilder.new():loadAll("assets/materials/md"):tryBuild()

    print("Loading high textures")
    atlas.hi = lfx.TexAtlasBuilder.new():loadAll("assets/materials/hi"):tryBuild()

    initBoxes(world, 2, atlas.md.lookup["copper"])
    initLights(world, 8)
    playerEId = world:spawn({
        --[ Light.ID] = Light.new(2, 15, {200,100,200}),
        [ Basis.ID] = Basis.new(v2d(0,0), 0, 1),
        [Sprite.ID] = Sprite.new(v2d(1, 1), {1,1,1}, atlas.md.lookup["player"])
    })
end

function love.resize(w, h)
    projection:setMatrix(lovely.math.orthoProjection(love.graphics.getPixelDimensions()))
end

local vSize = 8
function love.update(dt)
    local player = world:get(playerEId)
    if player then
        local d = v2d(0,0)
        if love.keyboard.isDown("w") then d.y = d.y - 1 end
        if love.keyboard.isDown("s") then d.y = d.y + 1 end
        if love.keyboard.isDown("a") then d.x = d.x - 1 end
        if love.keyboard.isDown("d") then d.x = d.x + 1 end
        if d:lengthSqr() > 0 then
            d = d:normalizeOrZero()
            local basis = player[Basis.ID] --[[@as Basis]]
            basis.origin   = basis.origin+ dt*3*d
            basis.rotation = d
        end

        local light = player[Light.ID] --[[@as Light]]
        if love.keyboard.isDown("q") then light.radius = math.max(  5, light.radius - 10*dt) end
        if love.keyboard.isDown("e") then light.radius = math.min(200, light.radius + 10*dt) end

        if love.keyboard.isDown("r") then light.height = math.max(0, light.height - dt) end
        if love.keyboard.isDown("f") then light.height = math.min(5, light.height + dt) end

        if love.keyboard.isDown("t") then 
            light.intensity[1] = math.max(1, light.intensity[1]/(1+3*dt)) 
            light.intensity[2] = math.max(1, light.intensity[2]/(1+3*dt)) 
            light.intensity[3] = math.max(1, light.intensity[3]/(1+3*dt)) 
        end
        if love.keyboard.isDown("g") then 
            light.intensity[1] = math.min(10000, light.intensity[1]*(1+3*dt)) 
            light.intensity[2] = math.min(10000, light.intensity[2]*(1+3*dt)) 
            light.intensity[3] = math.min(10000, light.intensity[3]*(1+3*dt)) 
        end

        if love.keyboard.isDown("x") then vSize = math.max(1,  vSize - 8*dt) end
        if love.keyboard.isDown("c") then vSize = math.min(60, vSize + 8*dt) end
    end

    local lights = world:query({[Light.ID]=1, [Basis.ID]=1}):collect(world)
    local numLights = #lights - 1
    local angle = 2*math.pi/numLights
    for i=1,#lights do
        if lights[i]:id() ~= playerEId then
            local off = i/numLights
            local basis = lights[i]:component(Basis.ID) --[[@as Basis]]
            basis.origin = (16 + 6*(math.cos(off+love.timer.getTime())))*v2d.newRotation((i+off+0.02*love.timer.getTime())*angle)
        end
    end

end

---@alias LightOccluder [LFX.Occluder, Basis]
---@alias GatheredLight [ LightOccluder[], Vec2, Vec2, Light, Basis ]

---@param renderer LFX.Renderer
---@return GatheredLight[]
local function gatherLightsAndOccluders(renderer)

    ---------------------------------------------------------------------------
    --- PERF
    ---------------------------------------------------------------------------
    --   We gather and associate occluders with lights, if the light is
    --   onscreen. This allows us to reduce the number of iterations
    --   required substantially.
    ---------------------------------------------------------------------------
    --   This should be further improved:
    --   - Temporal-Coherence
    --       - Store previous frame lights
    --       - Only re-run add/remove on lights and occluders that have moved
    --           - If light is not onscreen, mark dirty instead of recalc
    --   - Spatial-Partitioning
    --       - We should create a grid that lists entities in that grid
    --       - Cross reference with the occluder query based on the overlap
    --           of the light
    --       - Depending on render cost, this could save us a lot even
    --          without further filtering.
    ---------------------------------------------------------------------------
    
    ---@type GatheredLight[] 
    local lights = {}
    local lightAllMin
    local lightAllMax

    -- Determine onscreen lights
    for _,entity in world:query({[Light.ID]=1, [Basis.ID]=1}):iter(world) do
        local light = entity:component(Light.ID) --[[@as Light]]
        local basis = entity:component(Basis.ID) --[[@as Basis]]

        local draw, lightMin, lightMax = renderer:checkLightBounds(basis.origin, light.radius)
        if draw then
            table.insert(
                lights,
                {{}, lightMin, lightMax, light, basis} --[[@as GatheredLight ]]
            )
            lightAllMin = lightMin:min(lightAllMin or lightMin)
            lightAllMax= lightMax:max(lightAllMax or lightMax)
        end
    end

    -- Determine occluders that overlap with any onscreen light
    for _,occEntity in world:query({[lfx.Occluder.ID]=1, [Basis.ID]=1}):iter(world) do
        local occluder = occEntity:component(lfx.Occluder.ID) --[[@as LFX.Occluder]]
        local basis    = occEntity:component(Basis.ID) --[[@as Basis]]
        local entry    = {occluder, basis} --[[@as LightOccluder ]]
        -- If outside the total bounds, we can skip iterating against all of the onscreen lights
        if lovely.math.aabbOverlapMid(basis.origin, occluder._radius, lightAllMin, lightAllMax) then
            -- For each light, see if it overlaps and add it to the occluder list
            for i=1,#lights do
                local lightMin = lights[i][2]
                local lightMax = lights[i][3]
                if lovely.math.aabbOverlapMid(basis.origin, occluder._radius, lightMin, lightMax) then
                    table.insert(lights[i][1], entry)
                end
            end
        end
    end

    return lights
end

local RENDER_SCALE = 1
local renderer = lfx.Renderer.new(RENDER_SCALE, love.graphics.getPixelDimensions())
function love.draw()
    local w, h = love.graphics.getPixelDimensions()
    local player = world:get(playerEId)[Basis.ID] --[[@as Basis]]
    local viewMin, viewMax = renderer:start(RENDER_SCALE, w, h, player.origin, 0, v2d(vSize,vSize), true)

    -- Render scene
    lovely.graphics.isolate(function()
        renderer:startPassOpaque(atlas.md)

        renderer:setPBRProperties(atlas.md.lookup["concrete"], 0, 0.1)
        renderer:setPBRAlbedoTint({1,1,1})
        local floorTileSize = 2.5
        for x=math.floor(viewMin.x/floorTileSize),math.ceil(viewMax.x/floorTileSize) do
            for y=math.floor(viewMin.y/floorTileSize),math.ceil(viewMax.y/floorTileSize) do
                love.graphics.rectangle("fill", floorTileSize*x, floorTileSize*y, floorTileSize, floorTileSize)
            end
        end

        for _,entity in world:query({[Sprite.ID]=1, [Basis.ID]=1}):iter(world) do
            local sprite = entity:component(Sprite.ID) --[[@as Sprite]]
            local basis  = entity:component(Basis.ID) --[[@as Basis ]]
            local hsize  = sprite.size*0.5
            local sMin   = basis.origin - hsize
            local sMax   = basis.origin + hsize

            if lovely.math.aabbOverlap(sMin, sMax, viewMin, viewMax) then
                renderer:setPBRProperties(sprite.texId, 1, 0.1)
                renderer:setPBRAlbedoTint(sprite.tint)
                love.graphics.push()
                love.graphics.translate(basis.origin.x, basis.origin.y)
                love.graphics.rotate(math.atan2(basis.rotation.y, basis.rotation.x))
                love.graphics.rectangle("fill", -hsize.x, -hsize.y, sprite.size.x, sprite.size.y)
                love.graphics.pop()
            end
        end
        renderer:endPassOpaque()
    end)

    lovely.graphics.isolate(function()
        local lights = gatherLightsAndOccluders(renderer)
        local tmpTransform = love.math.newTransform()
        for _,entry in ipairs(lights) do
            local occluders, _, _, light, basis = unpack(entry)
            love.graphics.push()
            renderer:startPassLightOccluders(basis.origin, light.height, light.radius)
            for _,occEntity in ipairs(occluders) do
                local occluder = occEntity[1] --[[@as LFX.Occluder]]
                local basis    = occEntity[2] --[[@as Basis]]
                basis:copyTransformTo(tmpTransform)
                love.graphics.replaceTransform(tmpTransform)
                occluder:draw()
            end
            renderer:endPassLightOccluders()
            love.graphics.pop()
            
            renderer:startPassLight()
            renderer:drawLightPassLightPoint(basis.origin, light.height, light.radius, light.intensity)
            renderer:endPassLight()
        end
    end)

    local sdrFinal = renderer:finish()

    -- Display raw accum buffer
    love.graphics.setCanvas()
    love.graphics.clear(0,0,0)
    love.graphics.setProjection(projection)
    love.graphics.draw(sdrFinal, -w/2, -h/2, 0, 1/RENDER_SCALE)

    -- Draw FPS
    love.graphics.setColor(1,1,1)
    love.graphics.print("Current FPS: "..tostring(love.timer.getFPS( )), -w/2+10, -h/2+10)
end
