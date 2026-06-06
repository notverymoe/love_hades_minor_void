-- Copyright 2026 Natalie Baker -- AGPLv3 --

---@alias SLookupData [any, number, number, number, number]

local LOOKUP_SHIFT  = 2^26
local LOOKUP_OFFSET = LOOKUP_SHIFT/2

local function encodeLookup(x, y)
    return ((y + LOOKUP_OFFSET)*LOOKUP_SHIFT) + (x + LOOKUP_SHIFT)
end

---@class SLookup
---@field _extract fun(v: any): number
---@field _lookup table<number, [any, number, number, number, number, number]>
---@field _scale number
---@field _data table<any, number[]>
local SLookup = {}
SLookup.__index = SLookup

---@param cellSize number
---@param extract fun(id: any): number
---@return SLookup
function SLookup.new(cellSize, extract)
    return setmetatable({_extract=extract, _scale=1/cellSize, _lookup={}, _data={}}, SLookup)
end

---@param self SLookup
---@param id any
---@param min Vec2
---@param max Vec2
function SLookup.set(self, id, min, max)
    local minX = math.floor(min.x*self._scale)
    local minY = math.floor(min.y*self._scale)
    local maxX = math.floor(max.x*self._scale)
    local maxY = math.floor(max.y*self._scale)
    self:_set(id, minX, minY, maxX, maxY)
end

---@param self SLookup
---@param id any
function SLookup.remove(self, id)
    local uid = self._extract(id)
    if self._lookup[uid] ~= nil then
        local eid, _, eMinX, eMinY, eMaxX, eMaxY = unpack(self._lookup[uid])
        if eid ~= id then error("UID-ID Mismatch") end
        self:_removeData(uid, eMinX, eMinY, eMaxX, eMaxY)
    end
    self._lookup[uid] = nil
end

---@param self SLookup
---@param min Vec2
---@param max Vec2
---@return table<number, any>
function SLookup.get(self, min, max)
    local minX = math.floor(min.x*self._scale)
    local minY = math.floor(min.y*self._scale)
    local maxX = math.floor(max.x*self._scale)
    local maxY = math.floor(max.y*self._scale)
    local ids = {}
    for x=minX,maxX do
        for y=minY,maxY do
            local cell = self._data[encodeLookup(x, y)]
            if cell ~= nil then
                for uid,_ in pairs(cell) do
                    ids[uid] = self._lookup[uid][1]
                end
            end
        end
    end
    return ids
end

---@param self SLookup
---@param uid number
---@param minX integer
---@param minY integer
---@param maxX integer
---@param maxY integer
function SLookup._removeData(self, uid, minX, minY, maxX, maxY)
    for x=minX,maxX do
        for y=minY,maxY do
            local idx = encodeLookup(x, y)
            self._data[idx][uid] = nil
        end
    end
end

---@param self SLookup
---@param uid number
---@param minX integer
---@param minY integer
---@param maxX integer
---@param maxY integer
function SLookup._setData(self, uid, minX, minY, maxX, maxY)
    for x=minX,maxX do
        for y=minY,maxY do
            local idx = encodeLookup(x, y)
            self._data[idx] = self._data[idx] or {}
            self._data[idx][uid] = uid
        end
    end
end

---@param self SLookup
---@param id   any
---@param minX integer
---@param minY integer
---@param maxX integer
---@param maxY integer
function SLookup._set(self, id, minX, minY, maxX, maxY)
    local uid = self._extract(id)
    if self._lookup[uid] ~= nil then
        local eid, _, eMinX, eMinY, eMaxX, eMaxY = unpack(self._lookup[uid])
        if eid ~= id then error("UID-ID Mismatch") end
        self:_removeData(uid, eMinX, eMinY, eMaxX, eMaxY)
    end
    self._lookup[uid] = {id, uid, minX, minY, maxX, maxY}
    self:_setData(uid, minX, minY, maxX, maxY)
end

return SLookup
