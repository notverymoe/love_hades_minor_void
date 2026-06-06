-- Copyright 2026 Natalie Baker -- MIT --
-- arlu - A Lua Archetype-Based ECS & Scheduling Library --

--===========================================================================--
--#region Entities
--===========================================================================--

-------------------------------------------------------------------------------
--#region EId
-------------------------------------------------------------------------------

---EntityId
---@class arlu.EId
---@field index integer
---@field generation integer
local EId = {}
EId.__index = EId

if jit and jit.status() then
    local ffi = require("ffi")

    local EId_t = ffi.typeof[[struct { 
        uint32_t index; 
        uint32_t generation;
    }]]

    ffi.metatype(EId_t, EId)

    --- Create a new EntityId. 
    --- An index or generation of 0 is an "invalid" identifier.
    ---@param index      integer | nil Index of the identifier, defaults to 1
    ---@param generation integer | nil Generation of the identifier, defaults to 1
    ---@return arlu.EId
    function EId.new(index, generation)
        if index      == nil then index      = 1 end
        if generation == nil then generation = 1 end
        return EId_t(index, generation) --[[@as arlu.EId]]
    end
else
    -- NoFFI fallback, this won't be comfortable

    function EId.new(index, generation)
        if index      == nil then index      = 1 end
        if generation == nil then generation = 1 end
        return setmetatable({index = index, generation = generation} --[[@as arlu.EId]], EId)
    end
end

--- Gets the EntityId with the next generation
---@param id integer
---@return arlu.EId
function EId.withId(self, id)
    return EId.new(id, self.generation)
end

--- Gets the EntityId with the next generation
---@return arlu.EId
function EId.next(self)
    return EId.new(self.index, self.generation+1)
end

--- An index or generation of 0 is an "invalid" identifier.
---@return boolean
function EId.isValid(self)
    return self.index > 0 and self.generation > 0
end

---@param a arlu.EId
---@param b arlu.EId
---@return boolean
function EId.__eq(a, b)
    return a.index == b.index and a.generation == b.generation
end

-------------------------------------------------------------------------------
--#endregion EId
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--#region EntityAllocator
-------------------------------------------------------------------------------

---@class arlu.EntityAllocator
---@field _freelist arlu.EId[]
---@field _freecount integer
---@field _next integer
local EntityAllocator = {}
EntityAllocator.__index = EntityAllocator

---Creates a new EntityId allocator
---@return arlu.EntityAllocator
function EntityAllocator.new()
    return setmetatable(
        {_next = 0, _freelist = {}, _freecount = 0},
        EntityAllocator
    )
end

---Allocates a single new EntityId
---@param self arlu.EntityAllocator
---@return arlu.EId
function EntityAllocator.alloc(self)
    if self._freecount > 0 then
        self._freecount = self._freecount-1
        return table.remove(self._freelist, self._freecount+1)
    else
        self._next = self._next + 1
        return EId.new(self._next)
    end
end

---Checks if an id is probably allocated. Cannot confirm if
---a particular generation is allocated or not, because we
---don't track live genration indicies. So don't use this method
---in real code, only tests. This is potentially very slow.
---@param self arlu.EntityAllocator
---@param eId arlu.EId The identifier to free for reuse
function EntityAllocator._isProbablyAllocated(self, eId)
    if eId.index > self._next then return false end
    for idx=1,self._freecount do
        if self._freelist[idx].index == eId.index then
            return false
        end
    end
    return true
end

---Frees a single EntityId for reuse with a newer generation. Checks
---for a double-free, but does not check for a correct generation.
---Ensure only the latest generation is freed, otherwise generation
---reuse will occur! This is potentially very slow, prefer `freeUnchecked`
---when you have some external guarntee.
---@param self arlu.EntityAllocator
---@param eId arlu.EId
function EntityAllocator.freeSlow(self, eId)
    if not self:_isProbablyAllocated(eId) then
        error("Entity id already freed or could not have been allocated yet")
    end
    self:freeUnchecked(eId)
end

---Frees a single EntityId for reuse with a newer generation. Does
---not check for a double-free or the latest generation. Unsafe, but
---should be used in most cases relying on guantees from other
---sources (ie. associated data existing).
---@param self arlu.EntityAllocator
---@param eId arlu.EId
---@warning This method cannot verify if an id has been freed previously or is still valid
function EntityAllocator.freeUnchecked(self, eId)
    self._freecount = self._freecount + 1
    table.insert(self._freelist, self._freecount, eId:next())
end


-------------------------------------------------------------------------------
--#endregion EntityIdAllocator
-------------------------------------------------------------------------------

--===========================================================================--
--#endregion Entities
--===========================================================================--

--===========================================================================--
--#region Components
--===========================================================================--

------------------------------------------------------------------------------
--#region ComponentId
------------------------------------------------------------------------------

---ComponentId
---@class arlu.CId

---@class arlu.ModuleCId
---@field _next integer
---@field _data {name: string, uid: string}[]
---@field _lookup table<string, integer>
local CId = {
    _next   = 1,
    _data   = {},
    _lookup = {}
}

---Register a component
---@param name string Name of the component, should be unique or provide uid in options
---@param options { uid: string? }? Options to configure the registered component with
---@return arlu.CId
---@nodiscard
function CId.register(name, options)
    options = options or {}
    local uid = options.uid or name

    if CId._lookup[uid] ~= nil then
        error("Component with given UID already exists: "..tostring(uid))
    end

    local id = CId._next
    CId._next = CId._next + 1

    CId._lookup[uid] = id
    CId._data[id] = {name = name, uid = uid}

    return id --[[@as arlu.CId]]
end

---Gets the name of the given component ID
---@param id any
---@return string
---@nodiscard
function CId.nameOfId(id)
    return CId._data[id].name
end

---Gets the name of the given component UID
---@return string
---@nodiscard
function CId.nameOfUID(uid)
    local id = CId.fromUID(uid)
    return id and CId._data[id].name
end

---Gets the component ID of the given component UID
---@return string
---@nodiscard
function CId.toUID(id)
    local entry = CId._data[id]
    return entry and entry.uid
end

---Gets the component ID of the given component UID
---@return arlu.CId
---@nodiscard
function CId.fromUID(uid)
    return CId._lookup[uid] --[[@as arlu.CId]]
end

------------------------------------------------------------------------------
--#endregion ComponentId
------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--#region ComponentTable
-------------------------------------------------------------------------------

---@class arlu.ComponentTable
---@field _count integer
---@field _slots arlu.EId[]
---@field _data table<arlu.CId, any[]>
---@field _back integer[]
local ComponentTable = {}
ComponentTable.__index = ComponentTable

---Creates a new storage for EntityId-associated data
---@param columns arlu.ComponentSet
---@return arlu.ComponentTable
function ComponentTable.new(columns)
    local data = {}
    for cid,_ in pairs(columns) do
        data[cid] = {}
    end

    return setmetatable(
        {
            _count   = 0,
            _data    = data,
            _back    = {},
            _slots   = {},
        } --[[@as arlu.ComponentTable]],
        ComponentTable
    )
end

---@param self arlu.ComponentTable
---@param eId arlu.EId
---@param values table<arlu.CId, any> | nil
---@param force boolean?
---@return table<arlu.CId, any> | nil
function ComponentTable.set(self, eId, values, force)
    local existing = self:_getSlot(eId)
    if values == nil then
        if existing.index > 0 then
            if (not force) and (existing.generation ~= eId.generation) then
                error("Entity ID generation mismatch.")
            end
            return self:_remove(existing)
        else
            return nil
        end
    elseif (existing.index > 0) then
        if (not force) and (existing.generation ~= eId.generation) then
            error("Slot already contains a different generation, cannot reuse unless forced or removed first.")
        end
        return self:_set(eId, values, existing)
    else
        if (not force) and (existing.generation > eId.generation) then
            error("Slot previously used for a newer generation, cannot add older generation unless forced.")
        end
        return self:_add(eId, values)
    end
end

---@param eId arlu.EId
---@return table<arlu.CId, any> | nil
function ComponentTable.get(self, eId)
    local slot = self:_getSlot(eId)
    if (slot.index      <=              0) then return nil end
    if (slot.generation ~= eId.generation) then return nil end
    return self:getSlotDataAll(slot.index)
end

---@param cId arlu.CId
---@param eId arlu.EId
---@return any | nil
function ComponentTable.getComponent(self, cId, eId)
    local slot = self:_getSlot(eId)
    if (slot.index      <=              0) then return nil end
    if (slot.generation ~= eId.generation) then return nil end
    return self:getSlotData(cId, slot.index)
end

---@param eId arlu.EId
---@param init fun(): any
---@param force boolean?
---@return any
function ComponentTable.getOrSet(self, eId, init, force)
    return self:get(eId) or self:set(eId, init(), force)
end

---Gets the data in the given slot index
---@param slotIdx integer
---@return arlu.EId
function ComponentTable.getEntityIdForSlot(self, slotIdx)
    if slotIdx > self._count then
        error("Attempt to index out of bounds, slot idx not allocated")
    end
    local back = self._back[slotIdx]
    return self._slots[back]:withId(back)
end

---Gets the data in the given slot index
---@param slotIdx integer
---@return table<arlu.CId, any>
function ComponentTable.getSlotDataAll(self, slotIdx)
    if slotIdx > self._count then
        error("Attempt to index out of bounds, slot idx not allocated")
    end
    local slotData = {}
    for cid,data in pairs(self._data) do
        slotData[cid] = data[slotIdx]
    end
    return slotData
end

---Gets the data in the given slot index
---@param cId arlu.CId
---@param slotIdx integer
---@return any
function ComponentTable.getSlotData(self, cId, slotIdx)
    if slotIdx > self._count then
        error("Attempt to index out of bounds, slot idx not allocated")
    end
    local data = self._data[cId]
    return data and data[slotIdx]
end

---@param self arlu.ComponentTable
---@return fun(state: arlu.ComponentTable, key: arlu.EId): (arlu.EId, table<arlu.CId, any>), arlu.ComponentTable, any
function ComponentTable.iter(self)
    local slotIdx = 0
    return function(self, p)
        if slotIdx >= self._count then
            ---Iter needs to return nil
            ---@diagnostic disable-next-line: return-type-mismatch
            return nil, nil
        else
            slotIdx = slotIdx + 1
            local k = self:getEntityIdForSlot(slotIdx)
            local v = self:getSlotDataAll(slotIdx)
            return k, v
        end
    end, self, nil
end

---@param self arlu.ComponentTable
---@return integer
function ComponentTable.count(self)
    return self._count
end

---@param self arlu.ComponentTable
---@return arlu.ComponentSet
function ComponentTable.columns(self)
    return self._data
end

-----------------------------
--#region Internal 
-----------------------------

---@param eId arlu.EId
---@param values table<arlu.CId, any>
---@return table<arlu.CId, any>
function ComponentTable._add(self, eId, values)
    self._count = self._count + 1
    self._slots[eId.index] = EId.new(self._count, eId.generation)
    self._back[self._count] = eId.index
    for cid,data in pairs(self._data) do
        data[self._count] = values[cid]
    end
    return values
end

---@param eId arlu.EId The identifier to update the value of
---@param values table<arlu.CId, any>
---@param slot arlu.EId
---@return table<arlu.CId, any>
function ComponentTable._set(self, eId, values, slot)
    slot.generation = eId.generation
    for cid,data in pairs(self._data) do
        data[slot.index] = values[cid]
    end
    return values
end

---@param self arlu.ComponentTable
---@param slot arlu.EId
---@return table<arlu.CId, any> | nil
function ComponentTable._remove(self, slot)
    -- Check if it's already removed, no-op
    if (slot.index <= 0) then
        return nil
    end

    -- Move slot to end of data
    local slotValue = self:getSlotDataAll(slot.index)
    if slot.index ~= self._count then
        local endIndex = self._back[self._count]
        self._slots[endIndex].index = slot.index -- point end slot to vacated data index
        self._back[slot.index]      = endIndex   -- point back ref to vacated slot index
        for _,data in pairs(self._data) do
            data[slot.index] = data[self._count]  -- move data into slot
        end
        -- The original back ref can dangle, it's fine
    end

    -- Dealloc last slot
    slot.index = 0
    for _,data in pairs(self._data) do
        data[self._count] = nil
    end
    self._count = self._count - 1

    return slotValue
end

---@param self arlu.ComponentTable
---@param eId arlu.EId
---@return arlu.EId
function ComponentTable._getSlot(self, eId)
    return self._slots[eId.index] or EId.new(0,0)
end

-----------------------------
--#endregion Internal 
-----------------------------

-------------------------------------------------------------------------------
--#endregion ComponentTable
-------------------------------------------------------------------------------

--===========================================================================--
--#endregion Components
--===========================================================================--

--===========================================================================--
--#region ComponentSets
--===========================================================================--

------------------------------------------------------------------------------
--#region ComponentSet
------------------------------------------------------------------------------

---@alias arlu.ComponentSet table<arlu.CId, any>

---@class ModuleComponentSet
local ComponentSet = {}

---@param ... arlu.CId
---@return arlu.ComponentSet
function ComponentSet.from(...)
    return ComponentSet.fromArray({...})
end

---@param a arlu.CId[]
---@return arlu.ComponentSet
function ComponentSet.fromArray(a)
    local set = {}
    for _,k in ipairs(a) do set[k] = k end
    return set
end

--- Checks if all components listed in `a` exist in `b`
---@param a arlu.ComponentSet
---@param b arlu.ComponentSet
---@return boolean
---@nodiscard
function ComponentSet.all(a, b)
    for k,_ in pairs(a) do
        if b[k] == nil then
            return false
        end
    end
    return true
end

--- Checks if any component listed in `a` exists in `b`
---@param a arlu.ComponentSet
---@param b arlu.ComponentSet
---@return boolean
---@nodiscard
function ComponentSet.any(a, b)
    for k,_ in pairs(a) do
        if b[k] ~= nil then
            return true
        end
    end
    return false
end

--- Checks that `a`and `b` list exactly the same components
---@param a arlu.ComponentSet
---@param b arlu.ComponentSet
---@return boolean
---@nodiscard
function ComponentSet.exact(a, b)
    local count = 0

    --- Check keys in self exist in other table,
    --- and count number of keys in this container
    for k,_ in pairs(a) do
        if b[k] == nil then
            return false
        end
        count = count + 1
    end

    --- Ensure other table has same number of keys,
    --- if all of our keys existed in the other and
    --- we have the same number of keys, then we both
    --- have the same keys.
    for _ in pairs(b) do
        count = count - 1
    end

    return count == 0
end

------------------------------------------------------------------------------
--#endregion ComponentSet
------------------------------------------------------------------------------

------------------------------------------------------------------------------
--#region ComponentSetFilter
------------------------------------------------------------------------------

---@alias arlu.ComponentSetFilter {requires: arlu.ComponentSet, excludes: arlu.ComponentSet?} | arlu.ComponentSet

---@class arlu.ModuleComponentSetFilter
local ComponentSetFilter = {}

---@param requires arlu.CId[]
---@param excludes arlu.CId[]?
---@return arlu.ComponentSetFilter
function ComponentSetFilter.from(requires, excludes)
    if excludes == nil then
        return ComponentSet.fromArray(requires)
    else
        return {requires=ComponentSet.fromArray(requires), excludes=ComponentSet.fromArray(excludes)}
    end
end

---Returns the ComponentSet representing the included (required) components
---@param a arlu.ComponentSetFilter
---@return arlu.ComponentSet
---@nodiscard
function ComponentSetFilter.requires(a)
    return a.requires or a
end

---Returns the ComponentSet representing the excluded components
---@param a arlu.ComponentSetFilter
---@return arlu.ComponentSet
---@nodiscard
function ComponentSetFilter.excludes(a)
    return a.excludes or {}
end

---Checks if `a` will accept `b`
---@param a arlu.ComponentSetFilter filter
---@param b arlu.ComponentSet item
---@return boolean
---@nodiscard
function ComponentSetFilter.matches(a, b)
    return ComponentSet.all(ComponentSetFilter.requires(a), b) and
       not ComponentSet.any(ComponentSetFilter.excludes(a), b)
end

---Checks if `a` is eaxctly the same as `b`
---@param a arlu.ComponentSetFilter filter
---@param b arlu.ComponentSetFilter filter
---@return boolean
---@nodiscard
function ComponentSetFilter.exact(a, b)
    return ComponentSet.exact(
        ComponentSetFilter.requires(a),
        ComponentSetFilter.requires(b)
    ) and ComponentSet.exact(
        ComponentSetFilter.excludes(a),
        ComponentSetFilter.excludes(b)
    )
end

------------------------------------------------------------------------------
--#endregion ComponentSetFilter
------------------------------------------------------------------------------

------------------------------------------------------------------------------
--#region ComponentSetStorage
------------------------------------------------------------------------------

---@class arlu.ComponentSetStorage
---@field _next integer
---@field _groups table<arlu.CId, {key: arlu.ComponentSetFilter, idx: integer}[]>
---@field _data any[]
local ComponentSetStorage = {}
ComponentSetStorage.__index = ComponentSetStorage

function ComponentSetStorage.new()
    return setmetatable({_next = 1, _groups = {}, _data = {}}, ComponentSetStorage)
end

---Insert a new entry or replace an existing entry
---@param self arlu.ComponentSetStorage
---@param k arlu.ComponentSetFilter The composite key to associate with
---@param v any The value to associate with the composite key
---@return integer idx The data index inserted at
function ComponentSetStorage.insert(self, k, v)
    local idx = self:indexOf(k)
    if idx == nil then
        idx = self._next
        self._next = self._next + 1

        -- Add to lookup
        for part,_ in pairs(ComponentSetFilter.requires(k)) do
            local group = self._groups[part] or {}
            table.insert(group, {key=k, idx=idx})
            self._groups[part] = group
        end
    end

    self._data[idx] = v
    return idx
end

-- TODO
-- function ComponentSetStorage.remove(self, k)

-- end

---Finds all composite keys that match the given filter
---@param self arlu.ComponentSetStorage
---@param requires arlu.ComponentSet The list of components search with
---@param excludes arlu.ComponentSet? If provided, assumes filter is the required component set and creates a filter
---@return table<integer, any> results Pairs of data index and data that accepted the given component set
---@overload fun(self: arlu.ComponentSetStorage, filter: arlu.ComponentSetFilter): table<integer, any>
---@nodiscard
function ComponentSetStorage.filter(self, requires, excludes)
    local filter = requires
    if excludes ~= nil then
        filter = {requires=requires, excludes=excludes}
    end

    local found = {}
    for part,_ in pairs(ComponentSetFilter.requires(filter)) do
        local group = self._groups[part]
        if group ~= nil then
            for _,entry in ipairs(group) do
                if found[entry.idx] == nil and ComponentSetFilter.matches(filter, ComponentSetFilter.requires(entry.key)) then
                    found[entry.idx] = self._data[entry.idx]
                end
            end
        end
    end
    return found
end

---Finds all composite keys that accept the given components
---@param self arlu.ComponentSetStorage
---@param components arlu.ComponentSet The list of components search with
---@nodiscard
function ComponentSetStorage.query(self, components)
    local found = {}
    for part,_ in pairs(ComponentSetFilter.requires(components)) do
        local group = self._groups[part]
        if group ~= nil then
            for _,entry in ipairs(group) do
                if found[entry.idx] == nil and ComponentSetFilter.matches(entry.key, components) then
                    found[entry.idx] = self._data[entry.idx]
                end
            end
        end
    end
    return found
end

---Gets the data associated with the given key
---@param self arlu.ComponentSetStorage
---@param k arlu.ComponentSetFilter The composite key to lookup
---@return any data The data associated with the given composite key, or nil if it doesn't exist
---@nodiscard
function ComponentSetStorage.getByKey(self, k)
    local idx = self:indexOf(k)
    return idx and self:getByIdx(idx)
end

---Gets data by the raw index
---@param self arlu.ComponentSetStorage
---@param idx integer The index of the data to get
---@return any data The data stored at the given index, or nil if it doesn't exist
---@nodiscard
function ComponentSetStorage.getByIdx(self, idx)
    return self._data[idx]
end

---Finds the data index of the given key, or nil if it doesn't exist
---@param self arlu.ComponentSetStorage
---@param k arlu.ComponentSetFilter
---@return integer? index The data index of the key
---@nodiscard
function ComponentSetStorage.indexOf(self, k)
    --TODO OPT we could find the smallest group?
    for part,_ in pairs(ComponentSetFilter.requires(k)) do
        local group = self._groups[part]
        if group == nil then
            return nil -- If the group doesn't exist we don't store the key
        end
        for _,entry in ipairs(group) do
            if ComponentSetFilter.exact(k, entry.key) then
                return entry.idx
            end
        end
    end
    return nil
end

------------------------------------------------------------------------------
--#endregion ComponentSetStorage
------------------------------------------------------------------------------

--===========================================================================--
--#endregion ComponentSets
--===========================================================================--

--===========================================================================--
--#region Archetypes
--===========================================================================--

---ArchetypeId
---@class arlu.AId 

---QueryId
---@class arlu.QId 

------------------------------------------------------------------------------
--#region ArchetypeStorage
------------------------------------------------------------------------------

---@class arlu.ArchetypeStorage
---@field _archetypes arlu.ComponentSetStorage
---@field _queries    arlu.ComponentSetStorage
local ArchetypeStorage = {}
ArchetypeStorage.__index = ArchetypeStorage

---@return arlu.ArchetypeStorage
function ArchetypeStorage.new()
    return setmetatable({
        _archetypes = ComponentSetStorage.new(),
        _queries    = ComponentSetStorage.new()
    }, ArchetypeStorage)
end

---@param self arlu.ArchetypeStorage
---@param id arlu.AId
---@return arlu.ComponentTable
function ArchetypeStorage.getTableById(self, id)
    return self._archetypes:getByIdx(id --[[@as integer]]) --[[@as arlu.ComponentTable]]
end

---@param self arlu.ArchetypeStorage
---@param components arlu.ComponentSet
---@return arlu.ComponentTable
---@return arlu.AId
function ArchetypeStorage.getTable(self, components)
    local idx = self._archetypes:indexOf(components)
    return idx and self._archetypes:getByIdx(idx) --[[@as arlu.ComponentTable]], idx --[[@as arlu.AId]]
end

---@param self arlu.ArchetypeStorage
---@param components arlu.ComponentSet
---@return arlu.ComponentTable
---@return arlu.AId
function ArchetypeStorage.getOrCreateTable(self, components)
    local existing, idx = self:getTable(components)
    if existing == nil then
        existing = ComponentTable.new(components)
        idx = self._archetypes:insert(components, existing) --[[@as arlu.AId]]
        for _,data in pairs(self._queries:query(components)) do
            table.insert(data, idx)
        end
    end
    return existing, idx
end

---Run a query (cached) over all archetype component sets
---@param self arlu.ArchetypeStorage
---@param filter any The filter to run over the archetype component sets
---@param idCache arlu.QId? The cache index for the filter, faster if provided
---@return arlu.AId[] archetypes List of archetype ids that match the filter
---@return arlu.QId idCache The cache index associated with the given filter
function ArchetypeStorage.query(self, filter, idCache)
    if idCache == nil then
        idCache = self._queries:indexOf(filter) --[[@as arlu.QId?]]
    end
    if idCache == nil then
        idCache = self._queries:insert(filter, self:queryRaw(filter)) --[[@as arlu.QId]]
    end
    return self._queries:getByIdx(idCache --[[@as integer]]), idCache
end

---Run a query (uncached) over all archetype component sets
---@param self arlu.ArchetypeStorage
---@param filter arlu.ComponentSetFilter
---@return arlu.AId[]
function ArchetypeStorage.queryRaw(self, filter)
    local results = {}
    for idx,_ in pairs(self._archetypes:filter(filter)) do
        -- TODO OPT exclude zero-length archetypes we also need to make it so the
        --          cache is updated when archetypes are emptied or un-emptied.
        table.insert(results, idx)
    end
    return results
end

------------------------------------------------------------------------------
--#endregion ArchetypeStorage
------------------------------------------------------------------------------

--===========================================================================--
--#endregion Archetypes
--===========================================================================--

--===========================================================================--
--#region World
--===========================================================================--

------------------------------------------------------------------------------
--#region QueryEntity
------------------------------------------------------------------------------

---@class arlu.QueryEntity
---@field _archetype arlu.ComponentTable
---@field _entityRaw integer
local QueryEntity = {}
QueryEntity.__index = QueryEntity

---@param archetype arlu.ComponentTable?
---@param entityRaw integer?
---@return arlu.QueryEntity
function QueryEntity._new(archetype, entityRaw)
    return setmetatable({_archetype=archetype, _entityRaw=entityRaw}, QueryEntity)
end

---@param self arlu.QueryEntity
---@param archetype arlu.ComponentTable
---@param entitySlot integer
---@return arlu.QueryEntity
function QueryEntity._reset(self, archetype, entitySlot)
    self._archetype = archetype
    self._entityRaw = entitySlot
    return self
end

---@param self arlu.QueryEntity
---@return arlu.EId
function QueryEntity.id(self)
    return self._archetype:getEntityIdForSlot(self._entityRaw)
end

---@param self arlu.QueryEntity
---@param id arlu.CId
---@return any
function QueryEntity.component(self, id)
    return self._archetype:getSlotData(id, self._entityRaw)
end

---@param self arlu.QueryEntity
---@return arlu.ComponentSet
function QueryEntity.components(self)
    return self._archetype:getSlotDataAll(self._entityRaw)
end

------------------------------------------------------------------------------
--#endregion QueryEntity
------------------------------------------------------------------------------

------------------------------------------------------------------------------
--#region Query
------------------------------------------------------------------------------

---@class arlu.Query
---@field _id arlu.QId
local Query = {}
Query.__index = Query

function Query.new(id)
    return setmetatable({_id=id}, Query)
end

---@param self arlu.Query
---@param world arlu.World
---@return arlu.QueryEntity[]
function Query.collect(self, world)
    local archetypes,_ = world._storage:query(nil, self._id)
    local entities = {}
    for _,idArchetype in ipairs(archetypes) do
        local archetype = world._storage:getTableById(idArchetype)
        for i=1,archetype:count() do
            table.insert(entities, QueryEntity._new(archetype, i))
        end
    end
    return entities
end

---@class arlu.QueryIterState
---@field archetypes arlu.AId[]
---@field storage arlu.ArchetypeStorage

---@class arlu.QueryIterKey
---@field aCur arlu.ComponentTable
---@field aIdx integer
---@field eIdx integer
---@field eQur arlu.QueryEntity

---@param s arlu.QueryIterState
---@param k arlu.QueryIterKey
---@return arlu.QueryIterKey, arlu.QueryEntity
function Query._iterNext(s, k)
    k.eIdx = k.eIdx + 1
    while k.eIdx > k.aCur:count() do
        k.aIdx = k.aIdx + 1
        if k.aIdx > #s.archetypes then
            ---@diagnostic disable-next-line: return-type-mismatch
            return nil, nil
        end
        k.aCur = s.storage:getTableById(s.archetypes[k.aIdx])
        k.eIdx = 1
    end
    return k, k.eQur:_reset(k.aCur, k.eIdx)
end

---@param self arlu.Query
---@param world arlu.World
---@return (fun(s: arlu.QueryIterState, k: arlu.QueryIterKey): (arlu.QueryIterKey, arlu.QueryEntity)), arlu.QueryIterState, arlu.QueryIterKey
function Query.iter(self, world)
    local archetypes,_ = world._storage:query(nil, self._id)

    ---@type arlu.QueryIterState
    local state = {
        archetypes=archetypes,
        storage=world._storage
    }

    ---@type arlu.QueryIterKey
    local key = {
        aCur=world._storage:getTableById(archetypes[1]),
        aIdx=1,
        eIdx=0,
        eQur=QueryEntity._new()
    }

    return Query._iterNext, state, key
end

------------------------------------------------------------------------------
--#endregion Query
------------------------------------------------------------------------------

------------------------------------------------------------------------------
--#region SystemQuery
------------------------------------------------------------------------------

---Creates a system setup function that initializes
---a query from the world and passes it as userdata
---@param name string
---@param requires arlu.CId[]
---@param excludes arlu.CId[]
---@return fun(userdata: table, args: table)
function SystemQuery(name, requires, excludes)
    local filter = {
        requires=ComponentSet.fromArray(requires or {}),
        excludes=ComponentSet.fromArray(excludes or {})
    }
    return function(userdata, args)
        local world = args.world --[[@as arlu.World]]
        local query = world:query(filter)
        userdata[name] = query
    end
end

------------------------------------------------------------------------------
--#endregion SystemQuery
------------------------------------------------------------------------------

------------------------------------------------------------------------------
--#region World
------------------------------------------------------------------------------

---@class arlu.World
---@field _allocator arlu.EntityAllocator
---@field _storage arlu.ArchetypeStorage
---@field _archetypeLookup arlu.ComponentTable
local World = {}
World.__index = World

---@return arlu.World
function World.new()
    return setmetatable(
        {
            _allocator       = EntityAllocator.new(),
            _storage         = ArchetypeStorage.new(),
            _archetypeLookup = ComponentTable.new({1})
        },
        World
    )
end

---@param self arlu.World
---@param components arlu.ComponentSet
---@return arlu.EId
function World.spawn(self, components)
    local id = self._allocator:alloc()
    self:_entityArchetypeSet(id, components)
    return id
end

---@param self arlu.World
---@param eId arlu.EId
function World.destroy(self, eId)
    self:_entityArchetypeRemove(eId)
    self._allocator:freeUnchecked(eId)
end

---@param self arlu.World
---@param eId arlu.EId
---@param components arlu.ComponentSet
---@param replace boolean?
function World.attach(self, eId, components, replace)
    local existing = self:_entityArchetypeRemove(eId)
    if existing == nil then error("Archetype for entity does not exist.") end
    if replace then
        self:_entityArchetypeSet(eId, components)
    else
        for k,v in pairs(components) do existing[k] = v end
        self:_entityArchetypeSet(eId, existing)
    end
end

---@param self arlu.World
---@param eId arlu.EId
---@param components arlu.ComponentSet?
function World.detach(self, eId, components)
    local existing = self:_entityArchetypeRemove(eId) or {}
    if components == nil then
        self:_entityArchetypeSet(eId, {})
    else
        for k,_ in pairs(components) do existing[k] = nil end
        self:_entityArchetypeSet(eId, existing)
    end
end

---@param self arlu.World
---@param entity arlu.EId
---@param components arlu.ComponentSet
function World._entityArchetypeSet(self, entity, components)
    local archetype, id = self._storage:getOrCreateTable(components)
    archetype:set(entity, components)
    self._archetypeLookup:set(entity, {id})
end

---@param self arlu.World
---@param eId arlu.EId
function World._entityArchetypeRemove(self, eId)
    local archetype = self:_getEntityArchetype(eId)
    if not archetype then error("No archetype for entity") end
    self._archetypeLookup:set(eId, nil)
    return archetype:set(eId, nil)
end

---@param self arlu.World
---@param eId arlu.EId
---@return table<arlu.CId, any> | nil
function World.get(self, eId)
    local archetype = self:_getEntityArchetype(eId)
    return archetype and archetype:get(eId)
end

---@param self arlu.World
---@param cId arlu.CId
---@param eId arlu.EId
---@return any
function World.getComponent(self, cId, eId)
    local archetype = self:_getEntityArchetype(eId)
    return archetype and archetype:getComponent(cId, eId)
end

---@param self arlu.World
---@param filter arlu.ComponentSetFilter
---@return arlu.Query
function World.query(self, filter)
    local _,id = self._storage:query(filter, nil)
    return Query.new(id)
end

---@param self arlu.World
---@param eId arlu.EId
---@return arlu.ComponentTable | nil
function World._getEntityArchetype(self, eId)
    -- We're using 1 as a fixed-access cId since the lookup is not using regular components
    ---@diagnostic disable-next-line: param-type-mismatch
    local aId = self._archetypeLookup:getComponent(1, eId)
    return aId and self._storage:getTableById(aId)
end

------------------------------------------------------------------------------
--#endregion World
------------------------------------------------------------------------------

--===========================================================================--
--#endregion World
--===========================================================================--

--===========================================================================--
--#region Scheduling
--===========================================================================--

-------------------------------------------------------------------------------
--#region System
-------------------------------------------------------------------------------

---@alias FuncInvoke fun(systemData: table, invokeArgs: any, ...: any)
---@alias FuncInit fun(systemData: table, initArgs: any, params: any[])

---@class System
---@field name string
---@field paramList any[]
---@field systemData any
---@field _handleInvoke FuncInvoke
---@field _handleInit FuncInit?
---@field _dependencies {[System]: true}
---@field _dependencyCount integer
local System = {}
System.__index = System

---Create a new system
---@param name string
---@param handleInvoke FuncInvoke
---@param systemData table?
---@return System
function System.new(name, handleInvoke, systemData)
    return setmetatable({
        name = name,
        paramList = {},
        systemData = systemData or {},
        _handleInvoke = handleInvoke,
        _handleInit   = nil,
        _dependencies    = {},
        _dependencyCount = 0
    }, System)
end

---@param self System
---@param init FuncInit
---@return self
function System.withInit(self, init)
    self._init = init
    return self
end

---Adds a dependency that prevents this system running before the given system
---@param other System The system to run after
---@return System
function System.after(self, other)
    if not self._dependencies[other] then
        self._dependencies[other] = true
        self._dependencyCount = self._dependencyCount + 1
    end
    return self
end

---Initializes the system from the given init args
---@param self System
---@param initArgs any
function System._init(self, initArgs)
    if self._handleInit ~= nil then
        self._handleInit(self.systemData, initArgs, self.paramList)
    end
end

---Invokes the system from the given args
---@param self System
---@param invokeArgs any
function System._invoke(self, invokeArgs)
    self._handleInvoke(self.systemData, invokeArgs, unpack(self.paramList or {}))
end

-------------------------------------------------------------------------------
--#endregion System
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--#region Schedule
-------------------------------------------------------------------------------

---@class Schedule
---@field name string
---@field _systems System[]
---@field _hasInit boolean
local Schedule = {}
Schedule.__index = Schedule

---@param systems System[]
---@return Schedule
function Schedule.new(name, systems)
    return setmetatable({name = name, _systems = systems, _hasInit = false}, Schedule)
end

function Schedule.init(self, ...)
    if self._hasInit then
        error("Schedule is already initialized")
    end

    local initParams = {...}
    for _,system in pairs(self._systems) do
        system:_init(initParams)
    end
    self._hasInit = true
end

--- Runs every system in-order with the given arguments
---@param ... any
function Schedule.run(self, ...)
    local invokeParams = {...}
    for _,system in pairs(self._systems) do
        system:_invoke(invokeParams)
    end
end

-------------------------------------------------------------------------------
--#endregion Schedule
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--#region ScheduleBuilder
-------------------------------------------------------------------------------

---@class ScheduleBuilder
---@field name string
---@field _systems {[System]: number}
---@field _systemCount integer
local ScheduleBuilder = {}
ScheduleBuilder.__index = ScheduleBuilder

---Creates a new schedule builder
---@return ScheduleBuilder
function ScheduleBuilder.new(name)
    return setmetatable({name = name, _systems = {}, _systemCount = 0}, ScheduleBuilder)
end

---Adds a system to the schedule being built
---@param self ScheduleBuilder
---@param system System
---@return self
function ScheduleBuilder.add(self, system)
    if not self._systems[system] then
        self._systemCount     = self._systemCount + 1
        self._systems[system] = self._systemCount
    end
    return self
end

---Checks if a system has had all of it's "after" dependancies are resolved. 
---A system's dependancy is considered to be resolved if either the system
---it's ordered after is not being added to the schedule, or if the system
---has already been resolved previously. Obviously if a system has no dependancies
---then it's automatically resolved.
---
---@param systems {[System]: integer} All systems being added to the schedule
---@param resolved {[System]: true}[] Systems with their ordering resolved
---@param stage integer The current index being resolved, which is ignored for ordering
---@param system System The system to check if the dependancies have been resolved for
---@return boolean
local function areSystemDepsSatisfied(systems, resolved, stage, system)
    if (system._dependencyCount == 0) then
        return true
    end

    for dep,_ in pairs(system._dependencies) do
        -- If dependency is not in schedule at all, then it's satisfied
        if systems[dep] == nil then return true end

        local found = false
        for i = 1,stage-1 do
            if resolved[i][dep] ~= nil then
                found = true
                break
            end
        end
        if not found then return false end
    end
    return true
end

---Builds the schedule from the systems and their dependencies. The systems
---are first grouped into stages that ensure their dependencies were satisfied
---in a previous stage. Then within each group, they are sorted by insertion
---order to ensure deterministic system ordering.
---
---TODO CONDITION we store systems by-system. Is this going to break insertion 
---order guarntees in any way when we group systems into stages, since iteration
---order is not guarnteed? Hopefully not, but we should check...
---
---@return Schedule
function ScheduleBuilder.build(self)
    local pending = {} --[[@as {[System]: true}]]

    -- Initial
    for system,_ in pairs(self._systems) do
        pending[system] = true
    end

    -- Resolve remaining
    ---@type {[System]: integer}[]
    local resolved = { }
    local stage = 1
    local pendingCount = self._systemCount
    while pendingCount > 0 do
        local resolveCount = 0
        resolved[stage] = {}
        for system,_ in pairs(pending) do
            if areSystemDepsSatisfied(self._systems, resolved, stage, system) then
                resolved[stage][system] = self._systems[system]
                pending[system] = nil
                pendingCount = pendingCount - 1
                resolveCount = resolveCount + 1
            end
        end

        if resolveCount <= 0 then
            error("Could not resolve schedule with name: "..self.name)
        end

        stage = stage + 1
    end

    -- Final flattened ordering of stages
    ---@type System[]
    local orderedSystems = {}
    for _,group in pairs(resolved) do
        --TODO OPT Certainly some faster way to append these tables in-order

        ---@type {[integer]: {system: System, ordering: integer}}
        local sorting = {}
        for system,ordering in pairs(group) do
            table.insert(sorting, {system=system, ordering=ordering})
        end
        table.sort(sorting, function(a, b) return a.ordering < b.ordering end)

        for _,sortPair in ipairs(sorting) do
            table.insert(orderedSystems, sortPair.system)
        end
    end

    return Schedule.new(self.name, orderedSystems)
end

-------------------------------------------------------------------------------
--#endregion ScheduleBuilder
-------------------------------------------------------------------------------

--===========================================================================--
--#endregion Scheduling
--===========================================================================--

return {
    __HOMEPAGE    = 'https://github.com/notverymoe/love_libraries/',
    __DESCRIPTION = 'A simple archetype ECS library',
    __VERSION     = '2026.05.03',
    __LICENSE     = [[
        MIT License

        Copyright 2026 Natalie Baker

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
    ]],

    EId             = EId,             -- Tests: Initial
    EntityAllocator = EntityAllocator, -- Tests: Initial

    CId            = CId,            -- Tests: Initial
    ComponentTable = ComponentTable, -- Tests: Initial

    ComponentSet        = ComponentSet,        -- Tests: Initial
    ComponentSetFilter  = ComponentSetFilter,  -- Tests: Initial
    ComponentSetStorage = ComponentSetStorage, -- Tests: Initial

    ArchetypeStorage   = ArchetypeStorage,  -- Tests: Initial

    QueryEntity   = QueryEntity, -- Tests: TODO
    Query         = Query,       -- Tests: TODO
    World         = World,       -- Tests: Initial

    System          = System,          -- Tests: Initial
    Schedule        = Schedule,        -- Tests: Initial
    ScheduleBuilder = ScheduleBuilder, -- Tests: Initial

    SystemQuery = SystemQuery, -- Tests: TODO
}