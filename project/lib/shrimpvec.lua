---------------
-- Shrimpvec --
---------------
-- Shrimpvec is a heavily modified version of Brinevector
--
-- -- Changelog --
--
-- 2026-05-25
-- - Add perpDot, signum, rotateByVec etc.
--
-- 2026-05-03
-- - Add perp function
-- - Add lt/gt functions
--
-- 2026-02-21
-- - Add point in box and point in circle functions
-- - Add abs and lerp functions
-- - Changed rotated to rotateBy, lengthSquared to lengthSqr
-- - Fix initialization logic with x/y defaults
--
-- 2026-02-20
-- - Remove some methods
-- - Add lua language server typings
-- - Add rudementry documentation
-- - Changed Vector to Vec2
--
-- 2026-02-16
-- - Make all operators component-wise and compatible with number
-- - Remove error checking
-- - Add version of normalize that doesn't check for a zero-length vector
-- - Add __DESCRIPTION, __VERSION and __LICENSE fields.
--
-----------------
-- Brinevector --
-----------------
-- Brinevector is a luajit ffi-accelerated vector library
--
-- -- Changelog --
--
-- 2202-08-22
-- hadamard product is now done with a default * operator
-- dot product is now done with Vector.dot
-- better error messages (thanks to Andrew Minnich)
--
-- 2018-09-25
-- added Vector.ceil and v.ceil
-- added Vector.clamp
-- changed float to double as per Mike Pall's advice
-- added Vector.floor
-- added fallback to table if luajit ffi is not detected (used for unit tests)
--

--- @class Vec2
--- @field x number
--- @field y number
--- @operator add:Vec2
--- @operator sub:Vec2
--- @operator mul:Vec2
--- @operator div:Vec2
--- @operator mod:Vec2
--- @operator unm:Vec2
local Vec2 = {
    __HOMEPAGE = 'https://github.com/notverymoe/love_libraries/',
    __DESCRIPTION = 'A luajit ffi-accelerated vector library, based on brinevector',
    __VERSION = '2026.05.03',
    __LICENSE = [[
        MIT License

        Copyright 2026 Natalie Baker (Modified Version)
        Copyright 2022 Brian Sarfati

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
    ]]
}

Vec2.__index = Vec2

-- Vectors cannot have additional properties
function Vec2.__newindex(t, k, v)
    error("Cannot assign a new property '" .. k .. "' to a Vec2", 2)
end

----------------------------------------------
-- Select FFI or Tables / Module __call new --
----------------------------------------------

--- @class ModuleVec2: Vec2
--- @operator call:Vec2

local ffi
local VECTORTYPE = "cdata"

if jit and jit.status() then
    ffi = require("ffi")
    local ShrimpVec_t = ffi.typeof[[struct {
            double x;
            double y;
    }]]
    ffi.metatype(ShrimpVec_t, Vec2)
    setmetatable(Vec2, {
        __call = function(t, x, y)
            x = x or 0
            if y == nil then y = x end
            return ShrimpVec_t(x, y)
        end
    })
else
    VECTORTYPE = "table"
    setmetatable(Vec2, {
        __call =function(t, x, y)
            x = x or 0
            if y == nil then y = x end
            return setmetatable({x, y}, Vec2)
        end
    })
end

-------------------
-- Internal Util -- 
-------------------

--- Unpacks if it's a vector, spreads if its a number
local function unpackOrSplat(v)
    if type(v) == "number" then
        return v, v
    else
        return v.x, v.y
    end
end

--- Clamps to the given min-max range
local function clamp(x, min, max)
    return math.min(math.max(min, x), max)
end

----------------
-- Operations --
----------------

--- Clones the given vector
--- @param v Vec2 Vector to clone
--- @return Vec2 _ The cloned vector
function Vec2.clone(v)
    return Vec2(v.x, v.y)
end

--- Unpacks the vector into its components
--- @param v Vec2 The vector to unpack
--- @return number, number _ (x, y)
function Vec2.unpack(v)
    return v.x, v.y
end

--- Returns the length of the given vector
--- @param v Vec2 The vector to calculate the length of
--- @return number _ The length of the vector
function Vec2.length(v)
    return math.sqrt(v.x*v.x + v.y*v.y)
end

--- Returns the square of the length of the vector
--- @param v Vec2 The vector to calculate the square of the length of
--- @return number _ The square of the length
function Vec2.lengthSqr(v)
    return v.x*v.x + v.y*v.y
end

-- Calculates the angle of the vector ccw from (1, 0) in radians.
--- @param v Vec2 The vector to calculate the angle of
--- @return number _ The angle in radians
function Vec2.angle(v)
    return math.atan2(v.y, v.x)
end

-- Finds the minimium component value
--- @param v Vec2 The vector to calculate the minimium component of
--- @return number _ The minimium component value
function Vec2.minComponent(v)
    return math.min(v.x, v.y)
end

-- Finds the maximum component value
--- @param v Vec2 The vector to calculate the maximum component of
--- @return number _ The maximum component value
function Vec2.maxComponent(v)
    return math.max(v.x, v.y)
end

--- Calculates the dot product of the two given vectors
--- @param v1 Vec2 A vector in the dot product
--- @param v2 Vec2 A vector in the dot product
--- @return number _ The dot product of the two given vectors
function Vec2.dot(v1, v2)
    return v1.x * v2.x + v1.y * v2.y
end

--- Calculates the perpendicular dot product of the two given vectors
--- Sometimes refered to as the 2D scalar cross product.
--- @param v1 Vec2 A vector in the dot product
--- @param v2 Vec2 A vector in the dot product
--- @return number _ The perpendicular dot product of the two given vectors
function Vec2.perpDot(v1, v2)
    return v1.x*v2.y - v1.y*v2.x
end

--- Calculates the unit normal of the given vector or returns 
--- a zero-length vector if the given vector is zero-length
--- @param v Vec2 The vector to calculate the unit normal of
--- @return Vec2 _ The normalized vector or a zero-length vector if the given vector was zero-length
function Vec2.normalizeOrZero(v)
    return Vec2.normalizeOr(v, Vec2(0,0))
end

--- Calculates the unit normal of the given vector or returns 
--- a default value if the given vector is zero-length
--- @generic T
--- @param v Vec2 The vector to calculate the unit normal of
--- @param r T The default to return in the case of a zero-length vector
--- @return Vec2 | T _ The normalized vector or a zero-length vector if the given vector was zero-length
function Vec2.normalizeOr(v, r)
    local lengthSqr = v:lengthSqr()
    if lengthSqr == 0 then
        return r
    else
        local lengthInv = 1/math.sqrt(lengthSqr)
        return Vec2(
            v.x * lengthInv,
            v.y * lengthInv
        )
    end
end

--- Calculates the unit normal of the given vector without checking
--- the length before division
--- @param v Vec2 The vector to calculate the unit normal of
--- @return Vec2 _ The normalized vector 
function Vec2.normalize(v)
    local lengthInv = 1/v:length()
    return Vec2(
        v.x * lengthInv,
        v.y * lengthInv
    )
end

--- Calculates the inverse of the vector, equivelent of (1/x, 1/y)
--- @param v Vec2 The vector to calculate the inverse of
--- @return Vec2 _ The inverse vector 
function Vec2.inverse(v)
    return Vec2(1 / v.x, 1 / v.y)
end

--- Calculates the absolute of the vector, equivelent of (abs(x), abs(y))
--- @param v Vec2 The vector to calculate the absolute of
--- @return Vec2 _ The absolute vector 
function Vec2.abs(v)
    return Vec2(math.abs(v.x), math.abs(v.y))
end

--- Calculates the signum of each component of the vector, equivelent of (signum(x), signum(y))
--- @param v Vec2 The vector to calculate the signs of
--- @return Vec2 _ The sign vector 
function Vec2.signum(v)
    return Vec2(
        v.x == 0 and 0 or math.abs(v.x)/v.x,
        v.y == 0 and 0 or math.abs(v.y)/v.y
    )
end

--- Calculates the component-wise floor of the vector
--- @param v Vec2 The vector to floor
--- @return Vec2 _ The floored vector
function Vec2.floor(v)
    return Vec2(math.floor(v.x), math.floor(v.y))
end

--- Calculates the component-wise round of the vector
--- @param v Vec2 The vector to croundil
--- @return Vec2 _ The rounded vector
function Vec2.round(v)
    return Vec2(math.ceil(v.x), math.ceil(v.y))
end

--- Calculates the component-wise ceil of the vector
--- @param v Vec2 The vector to ceil
--- @return Vec2 _ The ceiled vector
function Vec2.ceil(v)
    return Vec2(math.ceil(v.x), math.ceil(v.y))
end

--- Clamps the given vector between the range of the other given vectors
--- @param v Vec2 The vector to clamp the range of
--- @param min Vec2 The minimium bound ("bottom-left")
--- @param max Vec2 The maximium bound ("bottom-left")
--- @return Vec2 _ The clamped vector
function Vec2.clamp(v, min, max)
    return Vec2(
        clamp(v.x, min.x, max.x),
        clamp(v.y, min.y, max.y)
    )
end

--- Calculates the componnent wise minimium of the two given vectors
--- @param v1 Vec2 | number A vector calculate the component-wise minimium with (numbers are splatted (v1,v1))
--- @param v2 Vec2 | number A vector calculate the component-wise minimium with (numbers are splatted (v2,v2))
--- @return Vec2 _ The component-wise minimium of the vectors
function Vec2.min(v1, v2)
    local x1, y1 = unpackOrSplat(v1)
    local x2, y2 = unpackOrSplat(v2)
    return Vec2(
        math.min(x1, x2),
        math.min(y1, y2)
    )
end

--- Calculates the componnent wise maximium of the two given vectors
--- @param v1 Vec2 | number A vector calculate the component-wise minimium with (numbers are splatted (v1,v1))
--- @param v2 Vec2 | number A vector calculate the component-wise minimium with (numbers are splatted (v2,v2))
--- @return Vec2 _ The component-wise minimium of the vectors
function Vec2.max(v1, v2)
    local x1, y1 = unpackOrSplat(v1)
    local x2, y2 = unpackOrSplat(v2)
    return Vec2(
        math.max(x1, x2),
        math.max(y1, y2)
    )
end

--- Rotates the given vector by the given angle CCW
--- @param v Vec2 The vector to rotate
--- @param angle number The radians to rotate by
--- @return Vec2 _ The rotated vector
function Vec2.rotatedByAngle(v, angle)
    return v:rotatedByVec(Vec2.newRotation(angle))
end

--- Creates a vector that stores a rotation (cos, sin)
--- for faster transformation
--- @param angle number The radians to rotate by
--- @return Vec2
function Vec2.newRotation(angle)
    local cos = math.cos(angle)
    local sin = math.sin(angle)
    return Vec2(cos, sin)
end

--- Rotates the given vector by the rotation vector
--- encoded as (c, s), see `Vec2.newRotation`
--- @param v Vec2 The vector to rotate
--- @param angle Vec2 The vector containing the rotation transformation
--- @return Vec2 _ The rotated vector
function Vec2.rotatedByVec(v, angle)
    return Vec2(
        v.x * angle.x - v.y * angle.y,
        v.x * angle.y + v.y * angle.x
    )
end

--- Rotates the given vector by 90 degrees CW
--- @param v Vec2 The vector to rotate
--- @return Vec2 _ The rotated vector
function Vec2.perp(v)
    return Vec2(-v.y,  v.x)
end

--- Calculates the linear interpolation between two vectors with the given factor
--- @param v1 Vec2 The vector to lerp from
--- @param v2 Vec2 The vector to lerp to
--- @param t number The interpolation factor (0-1, typically)
--- @return Vec2 _ The lerped vector
function Vec2.lerp(v1, v2, t)
    return v1 + (v2 - v1)*t
end

--- Tests if the vector, as a point, is within the given rectangle's bounds
--- @param p Vec2 The point to test
--- @param r Vec2 The center point of the rectangle
--- @param hsz Vec2 The half-size of the rectangle
--- @return boolean _ If the provided point in inside the rectangle
function Vec2.isInRectangle(p, r, hsz)
    return math.abs(p.x - r.x) <= hsz.x and math.abs(p.y - r.y) <= hsz.y
end

--- Tests if the vector, as a point, is within the given circle's bounds
--- @param p Vec2 The point to test
--- @param c Vec2 The center point of the circle
--- @param r Vec2 The radius of the circle
--- @return boolean _ If the provided point in inside the circle
function Vec2.isInCircle(p, c, r)
    local dx = p.x - c.x
    local dy = p.y - c.y
    return dx*dx + dy*dy <= r*r
end

------------------------------
-- Operator Implementations --
------------------------------

--- Operator addition. Component-wise.
--- @param v1 Vec2
--- @param v2 Vec2 | number
--- @return Vec2
function Vec2.__add(v1, v2)
    local x1, y1 = unpackOrSplat(v1)
    local x2, y2 = unpackOrSplat(v2)
    return Vec2(
        x1 + x2,
        y1 + y2
    )
end

--- Operator subtraction. Component-wise.
--- @param v1 Vec2 | number
--- @param v2 Vec2 | number
--- @return Vec2
function Vec2.__sub(v1, v2)
    local x1, y1 = unpackOrSplat(v1)
    local x2, y2 = unpackOrSplat(v2)
    return Vec2(
        x1 - x2,
        y1 - y2
    )
end

--- Operator multiplication. Component-wise.
--- @param v1 Vec2 | number
--- @param v2 Vec2 | number
--- @return Vec2
function Vec2.__mul(v1, v2)
    local x1, y1 = unpackOrSplat(v1)
    local x2, y2 = unpackOrSplat(v2)
    return Vec2(
        x1 * x2,
        y1 * y2
    )
end

--- Operator division. Component-wise.
--- @param v1 Vec2 | number
--- @param v2 Vec2 | number
--- @return Vec2
function Vec2.__div(v1, v2)
    local x1, y1 = unpackOrSplat(v1)
    local x2, y2 = unpackOrSplat(v2)
    return Vec2(x1 / x2, y1 / y2)
end

--- Operator modulus. Component-wise.
--- @param v1 Vec2 | number
--- @param v2 Vec2 | number
--- @return Vec2
function Vec2.__mod(v1, v2)
    local x1, y1 = unpackOrSplat(v1)
    local x2, y2 = unpackOrSplat(v2)
    return Vec2(x1 % x2, y1 % y2)
end

--- Operator unary negate. Component-wise.
--- @param v Vec2
--- @return Vec2
function Vec2.__unm(v)
    return Vec2(-v.x, -v.y)
end

--- Operator equals. Component-wise.
--- @param v1 Vec2
--- @param v2 Vec2
--- @return boolean
function Vec2.__eq(v1, v2)
    return rawequal(v1, v2) or (rawequal(v1, nil) and rawequal(v2, nil) and v1.x == v2.x and v1.y == v2.y)
end

--- Operator less than. Component-wise.
--- @param v1 Vec2
--- @param v2 Vec2
--- @return boolean
function Vec2.__lt(v1, v2)
    return v1.x < v2.x and v1.y < v2.y
end

--- Operator less than/equal. Component-wise.
--- @param v1 Vec2
--- @param v2 Vec2
--- @return boolean
function Vec2.__le(v1, v2)
    return v1.x <= v2.x and v1.y <= v2.y
end

--- Operator greater than. Component-wise.
--- @param v1 Vec2
--- @param v2 Vec2
--- @return boolean
function Vec2.__gt(v1, v2)
    return v1.x > v2.x and v1.y > v2.y
end

--- Operator greater than/equal. Component-wise.
--- @param v1 Vec2
--- @param v2 Vec2
--- @return boolean
function Vec2.__ge(v1, v2)
    return v1.x >= v2.x and v1.y >= v2.y
end

--- Operator not equals. Component-wise.
--- @param v1 Vec2
--- @param v2 Vec2
--- @return boolean
function Vec2.__neq(v1, v2)
    return v1.x ~= v2.x or v1.y ~= v2.y
end

--- Operator string
--- @param t Vec2
--- @return string
function Vec2.__tostring(t)
    return string.format("Vec2{%.4f, %.4f}", t.x, t.y)
end

--- Operator concat (as strings)
--- @param str string
--- @param v Vec2
--- @return string
function Vec2.__concat(str, v)
    return tostring(str) .. tostring(v)
end

-- Type Check --

if ffi then
    --- Tests if the given argument is a vector from this module
    --- @param arg Vec2
    --- @return boolean
    function Vec2.isVec2(arg)
        return ffi.istype("shrimpvec", arg)
    end
else
    --- Tests if the given argument is a vector from this module
    --- @param arg Vec2
    --- @return boolean
    function Vec2.isVec2(arg)
        return not not (type(arg) == VECTORTYPE and arg.x and arg.y)
    end
end

----------------
-- Module End --
----------------

return Vec2 --[[@as ModuleVec2]]