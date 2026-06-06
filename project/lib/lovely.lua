-- Copyright 2026 Natalie Baker -- MIT --

local v2d = require("lib.shrimpvec")

---@class Lovely
local lovely = {}
lovely.graphics = {}
lovely.math = {}

--=============================================================================
--#region Graphics 
--=============================================================================

--- Runs an isolated randerpass, pushing all graphical state, resetting and then
--- restoring the previous graphical state to create proper isolation.
---@param action fun()
function lovely.graphics.isolate(action)
    love.graphics.push("all")
    love.graphics.reset()
    action()
    love.graphics.pop()
end

---@type love.Transform[]
local viewTransformStack = {love.math.newTransform()}

---@type integer
local viewTransformHead = 1

---@overload fun(e1_1: number, e1_2: number, e1_3: number, e1_4: number, e2_1: number, e2_2: number, e2_3: number, e2_4: number, e3_1: number, e3_2, e3_3: number, e3_4: number, e4_1: number, e4_2: number, e4_3: number, e4_4: number)
---@overload fun(layout: love.MatrixLayout, e1_1: number, e1_2: number, e1_3: number, e1_4: number, e2_1: number, e2_2: number, e2_3: number, e2_4: number, e3_1: number, e3_2: number, e3_3: number, e3_4: number, e4_1: number, e4_2: number, e4_3: number, e4_4: number):love.Transform
---@overload fun(layout: love.MatrixLayout, matrix: table):love.Transform
---@overload fun(layout: love.MatrixLayout, matrix: table):love.Transform
function lovely.graphics.replaceView(...)
    viewTransformStack[viewTransformHead]:setMatrix(...)
end

---@return love.Transform
function lovely.graphics.getView()
    return viewTransformStack[viewTransformHead]
end

---@param shader love.Shader?
---@param transform love.Transform?
function lovely.graphics.sendView(shader, transform)
    (shader or love.graphics.getShader()):send(
        "ViewMatrix",
        transform or viewTransformStack[viewTransformHead]
    )
end

function lovely.graphics.replaceTransformWithView()
    love.graphics.replaceTransform(lovely.graphics.getView())
end

function lovely.graphics.resetTransform()
    love.graphics.replaceTransform(love.math.newTransform())
end

local love_graphics_push = love.graphics.push
love.graphics.push = function(...)
    viewTransformHead = viewTransformHead+1
    viewTransformStack[viewTransformHead] = viewTransformStack[viewTransformHead] or love.math.newTransform()
    viewTransformStack[viewTransformHead]:setMatrix(viewTransformStack[viewTransformHead-1]:getMatrix())
    love_graphics_push(...)
end

local love_graphics_pop = love.graphics.pop
love.graphics.pop = function(...)
    love_graphics_pop(...)
    viewTransformHead = math.max(viewTransformHead-1, 1)
end

--=============================================================================
--#endregion Graphics 
--=============================================================================

--=============================================================================
--#region Math 
--=============================================================================

---------------------------------------
--#region Ortho Projection
---------------------------------------

---Returns a default love2d orthogonal projection matrix.
---Properties: X-right, Y-down, Top-Left Origin, ZRange of (-10,10)
---@param w any
---@param h any
---@return number, number, number, number, number, number, number, number, number, number, number, number, number, number, number, number
function lovely.math.orthoProjectionDefault(w, h)
    return lovely.math.orthoProjectionComplex(0, w, h, 0, -10, 10)
end

---Createa a new orthogonal projection matrix from a size and normalized origin point
---@param width  number size of the x-axis to compress into NDC, negative flips axis
---@param height number size of the y-axis to compress into NDC, negative flips axis
---@param depth  number? size of the z-axis to compress into NDC, negative flips axis, defaults to 20 (love2d default)
---@param xOriginNorm number? center point on the x-axis to map into NDC, normalized by width to 0-1, defaults to 0.5 (not love2d-ish)
---@param yOriginNorm number? center point on the y-axis to map into NDC, normalized by height to 0-1, defaults to 0.5 (not love2d-ish)
---@param zOriginNorm number? center point on the z-axis to map into NDC, normalized by depth to 0-1, defaults to 0.5 (love2d default)
---@return number, number, number, number, number, number, number, number, number, number, number, number, number, number, number, number
function lovely.math.orthoProjection(
    width,
    height,
    depth,
    xOriginNorm,
    yOriginNorm,
    zOriginNorm
)
    local sx =  2.0/width
    local sy = -2.0/height        --- Love2D-ish negates Y
    local sz = -2.0/(depth or 20) --- OpenGL-ish negates Z

    local tx = 2*(xOriginNorm or 0.5) - 1
    local ty = 2*(yOriginNorm or 0.5) - 1
    local tz = 2*(zOriginNorm or 0.5) - 1

    return sx,  0,  0, tx,
            0, sy,  0, ty,
            0,  0, sz, tz,
            0,  0,  0,  1
end

---Creates a new orthogonal projection matrix as 16 return values, in
---row-major order. Ideal for passing to `lovely.graphics.replaceMatrixProjection`
---
---@param left   number The left-most position to map to NDC left
---@param right  number The right-most position to map to NDC right
---@param bottom number The bottom-most position to map to NDC bottom
---@param top    number The top-most position to map to NDC top
---@param near   number The left-most position to map to NDC near (love defaults to -10)
---@param far    number The left-most position to map to NDC far (love defaults to 10)
---@return number, number, number, number, number, number, number, number, number, number, number, number, number, number, number, number
function lovely.math.orthoProjectionComplex(left, right, bottom, top, near, far)
    local sx =  2.0/(right - left  )
    local sy =  2.0/(  top - bottom)
    local sz = -2.0/(  far - near  ) --- OpenGL-ish negates Z

    local tx = -((right + left  )/(right - left  ))
    local ty = -((  top + bottom)/(  top - bottom))
    local tz = -((  far + near  )/(  far - near  ))

    return sx,  0,  0, tx,
            0, sy,  0, ty,
            0,  0, sz, tz,
            0,  0,  0,  1
end

---------------------------------------
--#endregion Ortho Projection
---------------------------------------

---@param x number
---@param y number
---@param a number
---@param s number
---@return number, number, number, number, number, number, number, number, number, number, number, number, number, number, number, number
function lovely.math.trsMatrix(x, y, a, s)
    return lovely.math.trsMatrixFromRot(
        x,
        y,
        a and math.cos(a),
        a and math.sin(a),
        s
    )
end

---@param x number
---@param y number
---@param rc number
---@param rs number
---@param s number
---@return number, number, number, number, number, number, number, number, number, number, number, number, number, number, number, number
function lovely.math.trsMatrixFromRot(x, y, rc, rs, s)
    rc = rc or 1
    rs = rs or 0
    s  =  s or 1
    return s*rc, -s*rs,  0,  x,
           s*rs,  s*rc,  0,  y,
              0,     0,  1,  0,
              0,     0,  0,  1
end

---@param x number
---@param y number
---@param a number
---@param s number
function lovely.math.viewTRSMatrix(x, y, a, s)
    return lovely.math.viewTRSMatrixFromRot(
        x,
        y,
        a and math.cos(a),
        a and math.sin(a),
        s
    )
end

---@param x number
---@param y number
---@param rc number
---@param rs number
---@param s number
function lovely.math.viewTRSMatrixFromRot(x, y, rc, rs, s)
    rc =  (rc or 1)
    rs = -(rs or 0)
    s  =    s or 1
    return
        s*rc, -s*rs, 0, -s*(x*rc - y*rs),
        s*rs,  s*rc, 0, -s*(x*rs + y*rc),
        0,    0,     1, 0,
        0,    0,     0, 1
end

---@param x number
---@param y number
---@param a number
---@param vW number
---@param vH number
---@param pW number
---@param pH number
---@param contains boolean
---@return number, number, number, number, number, number, number, number, number, number, number, number, number, number, number, number
function lovely.math.viewMatrix(x, y, a, vW, vH, pW, pH, contains)
    local s = contains and math.min(pW/vW, pH/vH) or math.max(pW/vW, pH/vH)
    return lovely.math.viewTRSMatrix(x, y, a, s)
end

---Checks for an overlap between two AABBs
---@param minA Vec2 min point of aabb 1
---@param maxA Vec2 max point of aabb 1
---@param minB Vec2 min point of aabb 2
---@param maxB Vec2 max point of aabb 2
---@return boolean
function lovely.math.aabbOverlap(minA, maxA, minB, maxB)
    return minA <= maxB and maxA >= minB
end

---Checks for an overlap between two AABBs
---@param midA Vec2 middle point of aabb 1
---@param hsize Vec2 | number half size of aabb 1
---@param minB Vec2 min point of aabb 2
---@param maxB Vec2 max point of aabb 2
---@return boolean
function lovely.math.aabbOverlapMid(midA, hsize, minB, maxB)
    return ((midA-hsize) <= maxB) and ((midA+hsize) >= minB)
end

--=============================================================================
--#endregion Math
--=============================================================================

return lovely