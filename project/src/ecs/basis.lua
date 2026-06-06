-- Copyright 2026 Natalie Baker -- AGPLv3 --

local v2d = require("lib.shrimpvec")
local arlu = require("lib.arlu")
local lovely = require("lib.lovely")

---@class Basis
---@field origin   Vec2
---@field rotation Vec2
---@field scale    number
local Basis = {
    ID = arlu.CId.register("Basis", {uid = "05e8f80f-ae16-4334-a3a4-8ca12920f83b"})
}
Basis.__index = Basis

---@param origin   Vec2?
---@param rotation (Vec2 | number)?
---@param scale    number?
---@return Basis
function Basis.new(origin, rotation, scale)
    origin   = origin or v2d()
    if type(rotation) == "number" then rotation = v2d.newRotation(rotation) end
    rotation = rotation or v2d(1,0)
    scale    = scale or 1
    return setmetatable({origin=origin:clone(), rotation=rotation, scale=scale}, Basis)
end

---@param self Basis
---@param dst love.Transform?
---@return love.Transform
function Basis.copyTransformTo(self, dst)
    dst = dst or love.math.newTransform()
    return dst:setMatrix(lovely.math.trsMatrixFromRot(self.origin.x, self.origin.y, self.rotation.x, self.rotation.y, self.scale))
end

---@param self Basis
---@param dst love.Transform?
---@return love.Transform
function Basis.copyViewTransformTo(self, dst)
    dst = dst or love.math.newTransform()
    return dst:setMatrix(lovely.math.viewTRSMatrixFromRot(self.origin.x, self.origin.y, self.rotation.x, self.rotation.y, self.scale))
end

return Basis
