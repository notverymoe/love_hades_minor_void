-- Copyright 2026 Natalie Baker -- AGPLv3 --

local v2d = require("lib.shrimpvec")

-------------------------------------------------------------------------------
--#region OccluderShape
-------------------------------------------------------------------------------

---@alias LFX.OccluderShape {pnts: Vec2[], dirs: Vec2[], lens: number[], radius: number}

---@class LFX.OccluderShapeModule
local OccluderShape = {}
OccluderShape.__index = OccluderShape

---Creates a new occluder shape which calculates and caches
---important variables for use in occluder creation.
---@param points Vec2[] Points making up a closed polygon (first/last should not be the same)
---@return LFX.OccluderShape
function OccluderShape.fromPoints(points)
    local pnts = {}
    local dirs = {}
    local lens = {}
    local radius = 0
    for i=1,#points do
        local a = points[i]
        local b = points[i+1] or points[1]
        local d = b - a
        local dLen = d:length()
        radius = math.max(radius, dLen)
        table.insert(pnts, a     )
        table.insert(dirs, d/dLen)
        table.insert(lens, dLen  )
    end
    return {pnts=pnts, dirs=dirs, lens=lens, radius=radius}
end

-------------------------------------------------------------------------------
--#endregion OccluderShape
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--#region Occluder
-------------------------------------------------------------------------------

---@class LFX.Occluder
---@field _height number
---@field _count integer
---@field _radius number
---@field _buffer love.Buffer
local Occluder = {}
Occluder.__index = Occluder

---Draws the occluder, sending the buffer
---and occluder height to the shader
---@param self LFX.Occluder
function Occluder.draw(self)
    love.graphics.getShader():send("ShadowSegments", self._buffer)
    love.graphics.getShader():send("CasterHeight",   self._height)
    love.graphics.drawFromShader("triangles", 2*3*self._count)
end

--- Creates a new occluder from a list of verticies and a transform
---@param height number
---@param points Vec2[]
---@return LFX.Occluder
function Occluder.fromPoints(height, points)
    return Occluder.fromShape(height, OccluderShape.fromPoints(points))
end

--- Creates a new occluder from a shape and a transform
---@param height number
---@param shape LFX.OccluderShape
---@return LFX.Occluder
function Occluder.fromShape(height, shape)
    return Occluder._fromShapeRaw(height, shape.pnts, shape.dirs, shape.lens, shape.radius)
end

-------------------
--#region Internal
-------------------

---Creates a new occluder from the given segments, radius and height.
---Typically not to be used directly.
---@param segments number[][]
---@param radius number
---@param height number
---@return LFX.Occluder
function Occluder._new(segments, radius, height)
    local buffer = love.graphics.newBuffer({
        {name="pntA", format="floatvec2"},
        {name="pntB", format="floatvec2"},

        {name="dir1", format="floatvec2"},
        {name="dir2", format="floatvec2"},
        {name="dir3", format="floatvec2"},

        {name="len1", format="float"    },
        {name="len2", format="float"    },
        {name="len3", format="float"    },
    }, segments, {debugname="shadow_volume_buffer", shaderstorage=true})

    return setmetatable({
        _buffer=buffer,
        _count=#segments,
        _radius=radius,
        _height=height,
    }, Occluder)
end

--- Turns a shape into segments (pre-transformed) and
--- adds them to the `segments` array
---@param segments number[][]?
---@param pnts Vec2[]
---@param dirs Vec2[]
---@param lens number[]
---@param origin Vec2?
---@param angle number?
---@param scale number?
---@return number[][]
function Occluder._addShapeToSegments(segments, pnts, dirs, lens, origin, angle, scale)
    origin = origin or v2d(0,0)
    local rotation = v2d.newRotation(angle or 0)
    scale = scale or 1

    ---@param point Vec2
    ---@return Vec2
    local function transformPoint(point)
        return origin + (scale*point):rotatedByVec(rotation)
    end

    ---@param point Vec2
    ---@return Vec2
    local function transformDir(point)
        return point:rotatedByVec(rotation)
    end

    segments = segments or {}
    for i=1,#pnts do
        local a = transformPoint(pnts[i])
        local b = transformPoint(pnts[i+1] or pnts[1])

        local d1 = transformDir(dirs[i-1] or dirs[#dirs])
        local d2 = transformDir(dirs[i])
        local d3 = transformDir(dirs[i+1] or dirs[1])

        local l1 = scale*(lens[i-1] or lens[#lens])
        local l2 = scale*(lens[i])
        local l3 = scale*(lens[i+1] or lens[1])

        table.insert(segments, {a.x, a.y, b.x, b.y, d1.x, d1.y, d2.x, d2.y, d3.x, d3.y, l1, l2, l3})
    end
    return segments
end

--- Creates a new occluder from a shape and a transform
---@param height number
---@param pnts Vec2[]
---@param dirs Vec2[]
---@param lens number[]
---@param radius number
---@return LFX.Occluder
function Occluder._fromShapeRaw(height, pnts, dirs, lens, radius)
    return Occluder._new(
        Occluder._addShapeToSegments(nil, pnts, dirs, lens),
        radius,
        height
    )
end

-------------------
--#endregion Internal
-------------------

-------------------------------------------------------------------------------
--#endregion Occluder
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--#region OccluderBuilder
-------------------------------------------------------------------------------

---@alias LFX.OccluderVertex [number, number, number, number, number, number, number, number, number]

---@class LFX.OccluderBuilder
---@field _segments number[][]
---@field _radius number
local OccluderBuilder = {}
OccluderBuilder.__index = OccluderBuilder

---Create a new occluder builder.
---@return LFX.OccluderBuilder
function OccluderBuilder.new()
    return setmetatable({_segments = {}, _radius=0}, OccluderBuilder)
end

---Adds a OccluderShape or Polygon to the currently building
---occluder, applying any transformation provided to the data.
---@param self LFX.OccluderBuilder
---@param shape LFX.OccluderShape | Vec2[] The shape to add, either a precomputed `OccluderShape` or a list of points forming a polygon
---@param origin Vec2? The origin / offset to apply to the shape
---@param angle number? The rotation to appy to the shape
---@param scale number? The scale to apply to the shape
---@return self
function OccluderBuilder.add(self, shape, origin, angle, scale)
    origin = origin or v2d(0,0)
    angle  = angle or 0
    scale  = scale or 1
    if getmetatable(shape) ~= OccluderShape then shape = OccluderShape.fromPoints(shape) end
    Occluder._addShapeToSegments(
        self._segments,
        shape.pnts,
        shape.dirs,
        shape.lens,
        origin,
        angle,
        scale
    )
    self._radius = math.max(self._radius, origin:length() + scale*shape.radius)
    return self
end

---Adds a box to the occluder centered on the given location
---@param self LFX.OccluderBuilder
---@param size Vec2
---@param origin Vec2?
---@param angle number?
---@param scale number?
---@return LFX.OccluderBuilder
function OccluderBuilder.addBox(self, size, origin, angle, scale)
    local hsize = size*0.5
    return self:add(
        {
            v2d(-hsize.x, -hsize.y),
            v2d(-hsize.x,  hsize.y),
            v2d( hsize.x,  hsize.y),
            v2d( hsize.x, -hsize.y),
        },
        origin,
        angle,
        scale
    )
end

---Create an Occluder from the stored verticies and given transform.
---Can be called multiple times, and accept new occluders.
---@param self LFX.OccluderBuilder
---@param height number
---@return LFX.Occluder
function OccluderBuilder.build(self, height)
    return Occluder._new(self._segments, self._radius, height)
end

-------------------------------------------------------------------------------
--#endregion OccluderBuilder
-------------------------------------------------------------------------------

return {
    OccluderBuilder = OccluderBuilder,
    OccluderShape   = OccluderShape,
    Occluder        = Occluder,
}
