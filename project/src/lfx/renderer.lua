-- Copyright 2026 Natalie Baker -- AGPLv3 --

local v2d = require("lib.shrimpvec")
local lovely = require("lib.lovely")

--[[
Renderer Scene
    Canvas
    | Albedo | RGBA8    |           | Albedo RGB, Emissive           | 
    | Normal | RG11B10f | Spare B10 | Normal XY, Height              |
    | BRDF   | RGBA8    | Spare A8  | Occlusion, Roughness, Metallic | 
]]

---@class LFX.RendererTargets
---@field gAlbedo   love.Canvas
---@field gNormal   love.Canvas
---@field gMaterial love.Canvas
---@field gShadow   love.Canvas
---@field hdrAccum  love.Canvas
---@field expAvgs   love.Canvas[]
---@field expPrev   love.Canvas
---@field expNext   love.Canvas
---@field sdrFinal  love.Canvas

---@class LFX.Renderer
---@field _projection love.Transform
---@field _size       [number, number]
---@field _rt         LFX.RendererTargets
---@field _viewMin    Vec2
---@field _viewMax    Vec2
---@field _viewTransform love.Transform
local Renderer = {}
Renderer.__index = Renderer

Renderer.SHADERS = {}
Renderer.SHADERS.PBRGeometry   = love.graphics.newShader("src/lfx/shaders/pbr_geometry.glsl")
Renderer.SHADERS.PBRLightPoint = love.graphics.newShader("src/lfx/shaders/pbr_light_point.glsl")
Renderer.SHADERS.ShadowVol     = love.graphics.newShader("src/lfx/shaders/shadow_volume.glsl")
Renderer.SHADERS.Tonemap       = love.graphics.newShader("src/lfx/shaders/tonemap.glsl")
Renderer.SHADERS.Exposure      = love.graphics.newShader("src/lfx/shaders/exposure.glsl")
Renderer.SHADERS.Luminance     = love.graphics.newShader("src/lfx/shaders/luminance.glsl")
Renderer.SHADERS.Blit          = love.graphics.newShader("src/lfx/shaders/blit.glsl")

---Creates a new renderer with the given render scale, target width and target height
---@param scale number
---@param w number
---@param h number
---@return LFX.Renderer
function Renderer.new(scale, w, h)
    return setmetatable({
        _projection    = love.math.newTransform(lovely.math.orthoProjection(w, h)),
        _size          = {w,h},
        _rt            = Renderer._createRenderTargets(scale*w, scale*h, nil),
        _viewTransform = love.math.newTransform(),
        _viewMin       = v2d(),
        _viewMax       = v2d(),
    }, Renderer)
end

---Prepare to start rendering the scene, resizing if required. Sets up the
---camera view matrix.
---@param self LFX.Renderer
---@param scale number
---@param w number
---@param h number
---@param cameraOrigin Vec2
---@param cameraAngle  number
---@param cameraSize   Vec2
---@param cameraSizeContains boolean
function Renderer.start(self, scale, w, h, cameraOrigin, cameraAngle, cameraSize, cameraSizeContains)
    self:_resize(scale, w, h)

    -- Calculate view transform
    self._viewTransform:setMatrix(lovely.math.viewMatrix(
        cameraOrigin.x,
        cameraOrigin.y,
        cameraAngle,
        cameraSize.x,
        cameraSize.y,
        w,
        h,
        cameraSizeContains
    ))

    -- Calculate World AABB View Bounds
    local pvMatrix = self._projection:clone():apply(self._viewTransform):inverse()
    local viewA = v2d(pvMatrix:transformPoint(-1, -1))
    local viewB = v2d(pvMatrix:transformPoint( 1, -1))
    local viewC = v2d(pvMatrix:transformPoint(-1,  1))
    local viewD = v2d(pvMatrix:transformPoint( 1,  1))
    self._viewMin = viewA:min(viewB):min(viewC):min(viewD)
    self._viewMax = viewA:max(viewB):max(viewC):max(viewD)

    -- Setup vars
    lovely.graphics.replaceView(self._viewTransform:getMatrix())
    lovely.graphics.sendView(Renderer.SHADERS.PBRGeometry  )
    lovely.graphics.sendView(Renderer.SHADERS.PBRLightPoint)
    lovely.graphics.sendView(Renderer.SHADERS.ShadowVol    )

    -- Clear accum
    love.graphics.setCanvas(self._rt.hdrAccum)
    love.graphics.clear(0,0,0,0)

    return self._viewMin, self._viewMax
end

---Called to indicated the renderer is finished
---and to generate the final SDR image.
---@param self LFX.Renderer
function Renderer.finish(self)
    ------------------------------
    -- Manual to 1x1 mips
    ------------------------------

    -- Convert HDR scene to exposure values
    love.graphics.setCanvas(self._rt.expAvgs[1])
    love.graphics.setShader(Renderer.SHADERS.Luminance)
    Renderer.SHADERS.Luminance:send("TexAccum", self._rt.hdrAccum)
    love.graphics.drawFromShader("fan", 4)

    -- Downscale
    love.graphics.setShader(Renderer.SHADERS.Blit)
    for i=2,#self._rt.expAvgs do
        love.graphics.setCanvas(self._rt.expAvgs[i])
        Renderer.SHADERS.Blit:send("TexSource", self._rt.expAvgs[i-1])
        love.graphics.drawFromShader("fan", 4)
    end

    -- Calculate auto-exposure
    love.graphics.setCanvas(self._rt.expNext)
    love.graphics.setShader(Renderer.SHADERS.Exposure)

    Renderer.SHADERS.Exposure:send("TexExposureP",   self._rt.expPrev)
    Renderer.SHADERS.Exposure:send("TexExposureAvg", self._rt.expAvgs[#self._rt.expAvgs])

    Renderer.SHADERS.Exposure:send("DeltaTime", love.timer.getDelta())
    Renderer.SHADERS.Exposure:send("ExposureSpeed", 0.5)

    love.graphics.drawFromShader("fan", 4)

    -- Tonemap HDR -> SDR
    love.graphics.setCanvas(self._rt.sdrFinal)
    love.graphics.setShader(Renderer.SHADERS.Tonemap)

    Renderer.SHADERS.Tonemap:send("TexExposure", self._rt.expNext)
    Renderer.SHADERS.Tonemap:send("TexAccum", self._rt.hdrAccum)
    Renderer.SHADERS.Tonemap:send("MidtoneAdjustment", 1)

    love.graphics.drawFromShader("fan", 4)

    love.graphics.setCanvas()
    love.graphics.setShader()

    -- Swap exposure buffers
    local tmp = self._rt.expPrev
    self._rt.expPrev = self._rt.expNext
    self._rt.expNext = tmp
end

---Starts the opaque pass. You can only have one opaque pass. It
---must be rendered before transparent objects and lights are rendered.
---
---The opaque pass outputs to 3 targets:
--- - Albedo  
---   - The colour data of a surface (RGBA)
--- - Material 
---   - The material data of a surface 
---     - RGB = Occlusion, Roughness, Metalness
--- - Normal   
---   - Floating-point RGB
---     - RG = The X and Y normal components (Reconstructed Z)
---     - B  = Height  
---
---@param self LFX.Renderer
---@param atlas LFX.TexAtlas?
function Renderer.startPassOpaque(self, atlas)
    love.graphics.setCanvas({self._rt.gAlbedo, self._rt.gMaterial, self._rt.gNormal, depth=false})
    love.graphics.clear(true, true, true)
    love.graphics.setShader(Renderer.SHADERS.PBRGeometry)
    love.graphics.setProjection(self._projection)
    if atlas then self:setPBRTexAtlas(atlas) end
end

---Sends the Atlas to the PBR shader
---@param self LFX.Renderer
---@param atlas LFX.TexAtlas
function Renderer.setPBRTexAtlas(self, atlas)
    love.graphics.getShader():send("TexAlbedo",   atlas.texAlbedo  )
    love.graphics.getShader():send("TexMaterial", atlas.texMaterial)
    love.graphics.getShader():send("TexNormal",   atlas.texNormal  )
end

---Sends the albedo Tint to the PBR shader
---@param self LFX.Renderer
---@param color [number, number, number] | [number, number, number, number]
function Renderer.setPBRAlbedoTint(self, color)
    love.graphics.getShader():send(
        "PBRAlbedoTint",
        { color[1], color[2], color[3], color[4] or 1 }
    )
end

---Sends the PBR Properties to the PBR shader
---@param self LFX.Renderer
---@param layer integer
---@param height number
---@param dispScale number
function Renderer.setPBRProperties(self, layer, height, dispScale)
    love.graphics.getShader():send(
        "PBRProperties",
        { layer, height, dispScale }
    )
end

---Called to indicate that the opaque pass has finished
function Renderer.endPassOpaque(self)

end

---Called to setup the lighting pass by sending the g-buffers 
---to the shader and setting up the accumulation texture for
---rendering. Should only be called once and all lights rendered.
function Renderer.startPassLight(self)
    Renderer.SHADERS.PBRLightPoint:send("TexShadow",   self._rt.gShadow  )
    Renderer.SHADERS.PBRLightPoint:send("TexAlbedo",   self._rt.gAlbedo  )
    Renderer.SHADERS.PBRLightPoint:send("TexMaterial", self._rt.gMaterial)
    Renderer.SHADERS.PBRLightPoint:send("TexNormal",   self._rt.gNormal  )

    love.graphics.setCanvas(self._rt.hdrAccum)
    love.graphics.setProjection(self._projection)
    love.graphics.setBlendState("add", "one", "one")
end

---Called to indicate that the lighting pass has finished.
function Renderer.endPassLight(self)

end

---Checks the boundry of a light to see if it overlaps the view
---@param self LFX.Renderer
---@param lightOrigin Vec2
---@param lightRadius number
---@return boolean
---@return Vec2
---@return Vec2
function Renderer.checkLightBounds(self, lightOrigin, lightRadius)
    local lightMin = lightOrigin - lightRadius
    local lightMax = lightOrigin + lightRadius
    return lightMin <= self._viewMax and lightMax >= self._viewMin, lightMin, lightMax
end

---Starts the occluder sub-pass to populate shadows for a light.
---@param lightOrigin Vec2
---@param lightHeight number
---@param lightRadius number
function Renderer.startPassLightOccluders(self, lightOrigin, lightHeight, lightRadius)
    love.graphics.setShader(Renderer.SHADERS.ShadowVol)
    Renderer.SHADERS.ShadowVol:send("LightOrigin", {lightOrigin.x, lightOrigin.y, lightHeight})
    Renderer.SHADERS.ShadowVol:send("LightRadius", lightRadius)
    
    love.graphics.setCanvas({self._rt.gShadow, depth=true})
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setProjection(self._projection)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.clear(0,0,0,1,false,true)
end

---Called to indicate that the shadow sub-pass is complete
function Renderer.endPassLightOccluders(self)
    
end

---Draws a single light using the last occluder pass to provide shadows.
---@param lightOrigin Vec2
---@param lightHeight number
---@param lightRadius number
---@param lightColour [number, number, number]
function Renderer.drawLightPassLightPoint(self, lightOrigin, lightHeight, lightRadius, lightColour)
    love.graphics.setShader(Renderer.SHADERS.PBRLightPoint)
    Renderer.SHADERS.PBRLightPoint:send("LightPosition", {lightOrigin.x, lightOrigin.y, lightHeight})
    Renderer.SHADERS.PBRLightPoint:send("LightRadius",    lightRadius)
    Renderer.SHADERS.PBRLightPoint:send("LightColor",     lightColour)

    local lightRadiusSafe = math.min(lightRadius*1.02, lightRadius+0.02)
    love.graphics.rectangle(
        "fill",
        lightOrigin.x-lightRadiusSafe,
        lightOrigin.y-lightRadiusSafe,
        lightRadiusSafe*2,
        lightRadiusSafe*2
    )
end

---------------------------------------
--#region Internal
---------------------------------------

---Resizes the renderer to fit the new target.
---@param self LFX.Renderer
---@param scale number
---@param w number
---@param h number
function Renderer._resize(self, scale, w, h)
    self._projection:setMatrix(lovely.math.orthoProjection(w, h))
    self._size = {w, h}
    if w*scale == self._rt.hdrAccum:getWidth() and h*scale == self._rt.hdrAccum:getHeight() then
        return
    end
    self._rt = Renderer._createRenderTargets(scale*w, scale*h, self._rt)
end

---Creates all the downscaling levels necessary for 
---creating the 1x1 scene average luminance.
---@param w integer
---@param h integer
---@return love.Canvas[]
function Renderer._createExposureAveragingLevels(w, h)
    ---@type love.Canvas[]
    local expAvgs = {}
    local expAvgsCount = math.max(math.log(w, 2), math.log(h, 2))
    for expAvgLevel=1,expAvgsCount do
        local divisor = math.pow(2, expAvgLevel+1)
        local tex = love.graphics.newCanvas(
            math.max(math.ceil(w/divisor), 1),
            math.max(math.ceil(h/divisor), 1),
            {format="r16f", dpiscale=1, linear=true}
        )
        table.insert(expAvgs, tex)
    end
    return expAvgs
end

---Creates the render targets for the given resolution,
---resolution independant render targets are maintained
---if provided.
---@param w integer
---@param h integer
---@param prevTargets LFX.RendererTargets?
---@return LFX.RendererTargets
function Renderer._createRenderTargets(w, h, prevTargets)
    return {
        gAlbedo   = love.graphics.newCanvas(w, h, {format="rgba8",    dpiscale=1, linear=true}),
        gNormal   = love.graphics.newCanvas(w, h, {format="rg11b10f", dpiscale=1, linear=true}),
        gMaterial = love.graphics.newCanvas(w, h, {format="rgba8",    dpiscale=1, linear=true}),
        gShadow   = love.graphics.newCanvas(w, h, {format="rg16f",    dpiscale=1, linear=true}),
        hdrAccum  = love.graphics.newCanvas(w, h, {format="rg11b10f", dpiscale=1, linear=true}),
        expAvgs   = Renderer._createExposureAveragingLevels(w, h),
        expPrev   = (prevTargets and prevTargets.expPrev) or love.graphics.newCanvas(1, 1, {format="r16f", dpiscale=1, linear=true}),
        expNext   = (prevTargets and prevTargets.expNext) or love.graphics.newCanvas(1, 1, {format="r16f", dpiscale=1, linear=true}),
        sdrFinal  = love.graphics.newCanvas(w, h, {format="srgba8",   dpiscale=1}),
    } --[[@as LFX.RendererTargets]]
end

---------------------------------------
--#endregion Internal
---------------------------------------

return {
    Renderer = Renderer,
}
