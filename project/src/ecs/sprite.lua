-- Copyright 2026 Natalie Baker -- AGPLv3 --

local arlu = require("lib.arlu")

---@class Sprite
---@field size Vec2
---@field tint [number, number, number, number]
---@field texId integer
local Sprite = {
    ID = arlu.CId.register("Sprite", {uid = "019e72db-c999-712b-9b50-5236e8e6d3db"})
}
Sprite.__index = Sprite

---@param size Vec2
---@param tint [number, number, number, number]
---@param texId integer
---@return Sprite
function Sprite.new(size, tint, texId)
    return setmetatable(
        {size=size, tint=tint, texId=texId},
        Sprite
    )
end

return Sprite
