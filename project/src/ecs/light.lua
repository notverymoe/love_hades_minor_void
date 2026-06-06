-- Copyright 2026 Natalie Baker -- AGPLv3 --

local arlu = require("lib.arlu")

---@class Light
---@field height number
---@field radius number
---@field intensity [number, number, number]
local Light = {
    ID = arlu.CId.register("Basis", {uid = "019e7144-9a60-71d1-a6cf-866664106492"})
}
Light.__index = Light

---@param height number
---@param radius number
---@param intensity [number, number, number]
---@return Light
function Light.new(height, radius, intensity)
    return setmetatable(
        {height=height, radius=radius, intensity=intensity},
        Light
    )
end

return Light
