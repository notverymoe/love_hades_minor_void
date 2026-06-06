-- Copyright 2026 Natalie Baker -- AGPLv3 --

---@class LFX.TexAtlas
---@field lookup table<string, integer>
---@field texAlbedo love.Texture
---@field texNormal love.Texture
---@field texMaterial love.Texture

---@class LFX.TexAtlasBuilder
---@field _lookup table<string, integer>
---@field _layersAlbedo   love.CompressedImageData[]
---@field _layersNormal   love.CompressedImageData[]
---@field _layersMaterial love.CompressedImageData[]
local TexAtlasBuilder = {}
TexAtlasBuilder.__index = TexAtlasBuilder

function TexAtlasBuilder.new()
    return setmetatable({
        _lookup={},
        _layersAlbedo={},
        _layersNormal={},
        _layersMaterial={}
    }, TexAtlasBuilder)
end

---Loads a texture from a directory of the given "kind"
---@param directory string The directory to load from
---@param kind      string The kind of texture to load ("tex_albedo" ie.)
---@param reference love.CompressedImageData? Reference image data to validate compatibility with
local function loadTexDataChecked(directory, kind, reference)
    local data = love.image.newCompressedData(directory..kind..".dds")

    local reqFormat = (reference or data):getFormat()
    local reqLevels = (reference or data):getMipmapCount()

    local loadedFormat = data:getFormat()
    local loadedLevels = data:getMipmapCount()

    if loadedFormat ~= reqFormat then
        error("Expected "..tostring(reqFormat).." format in "..kind.." but got "..loadedFormat.." for: "..directory)
    end

    if loadedLevels ~= reqLevels then
        error("Expected "..tostring(reqLevels).." mipmap levels in "..kind.." but got "..loadedLevels.." for: "..directory)
    end

    return data
end

---Loads all textures from a directory, textures of the same kind must have the
---same resolution, mipmap levels and compression format as those already loaded
---for those types.
---@param self LFX.TexAtlasBuilder
---@param directory string
---@return LFX.TexAtlasBuilder
function TexAtlasBuilder.loadAll(self, directory)
    for _,name in ipairs(love.filesystem.getDirectoryItems(directory)) do
        local path = directory..'/'..name
		local info = love.filesystem.getInfo(path)
        if info then
            if info.type == "directory" then
                self:load(name, path)
            end
        end
    end
    return self
end

---Loads a set of atlas textures, textures of the same kind must have the same
---resolution, mipmap levels and compression format as those already loaded for
---those types.
---@param self LFX.TexAtlasBuilder
---@param name string
---@param directory string
---@return integer
function TexAtlasBuilder.load(self, name, directory)
    -- Check if the texture is already loaded
    if self._lookup[name] ~= nil then
        error("Texture already loaded: "..name)
    end

    -- Check if we can alloc more (gpu textures start at 0)
    local idx = #self._layersAlbedo
    if idx >= 256 then
        error("Cannot load more than 256 textures")
    end

    -- Normalize directory end
    if directory:sub(-1) ~= "/" then
        directory = directory.."/"
    end

    -- Load data, check mip count and format
    local texAlbedo   = loadTexDataChecked(directory, "tex_albedo",   self._layersAlbedo[1])
    local texNormal   = loadTexDataChecked(directory, "tex_normal",   self._layersNormal[1])
    local texMaterial = loadTexDataChecked(directory, "tex_material", self._layersMaterial[1])

    -- Store data for build
    table.insert(self._layersAlbedo,   texAlbedo)
    table.insert(self._layersNormal,   texNormal)
    table.insert(self._layersMaterial, texMaterial)
    self._lookup[name] = idx

    return idx
end

---Attempts to build an atlas, returning nil if there are no textures loaded
---@param self LFX.TexAtlasBuilder
---@return LFX.TexAtlas
function TexAtlasBuilder.tryBuild(self)
    if #self._layersAlbedo == 0 then
        ---@diagnostic disable-next-line: return-type-mismatch
        return nil
    end
    return self:build()
end

---Builds texture arrays for all loaded textures by kind, copies the lookup and
---returns it as a TexAtlas.
---@param self LFX.TexAtlasBuilder
---@return LFX.TexAtlas
function TexAtlasBuilder.build(self)
    local texAlbedo   = love.graphics.newArrayImage(self._layersAlbedo,   {mipmaps=true, linear=false, dpiscale=1})
    local texNormal   = love.graphics.newArrayImage(self._layersNormal,   {mipmaps=true, linear=true,  dpiscale=1})
    local texMaterial = love.graphics.newArrayImage(self._layersMaterial, {mipmaps=true, linear=true,  dpiscale=1})
    local lookup = {}
    for k,v in pairs(self._lookup) do lookup[k] = v end
    return {lookup=lookup, texAlbedo=texAlbedo, texNormal=texNormal, texMaterial=texMaterial}
end

return {
    TexAtlasBuilder = TexAtlasBuilder
}
