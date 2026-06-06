-- Copyright 2026 Natalie Baker -- AGPLv3 --

local function indentStr(level)
    return string.rep("    ", math.max(level, 0))
end

local function escapeStr(value)
    return string.gsub(value, "\n", "\\n")
end

local function toStr(value, dst, indent)
    indent = indent or 1
    dst = dst or ""

    local ty = type(value)
    if ty == "nil" then
        dst = dst.."nil"
    elseif ty == "number" then
        dst = dst..value
    elseif ty == "string" then
        dst = dst..'"'..escapeStr(value)..'"'
    elseif ty == "boolean" then
        if value then
            dst = dst.."true"
        else
            dst = dst.."false"
        end
    elseif ty == "table" then
        dst = dst.."{\n"

        local data = {}
        for k,v in pairs(value) do
            table.insert(data, {k, v})
        end
        table.sort(data, function(a, b) return a[1] < b[1] end)

        for _,p in ipairs(data) do
            local k,v = unpack(p)
            if type(k) == "string" then
                -- We dont verify if its a valid identifier
                dst = dst..indentStr(indent)..k..' = '
            else
                dst = dst..indentStr(indent)..'['
                dst = toStr(k, dst, indent+1)
                dst = dst..'] = '
            end
            dst = toStr(v, dst, indent+1)
            dst = dst..',\n'
        end
        dst = dst..indentStr(indent-1).."}"
    elseif ty == "function" then
        dst = dst.."<Cannot convert: "..value..">"
    elseif ty == "thread" then
        dst = dst.."<Cannot convert: "..value..">"
    elseif ty == "userdata" then
        dst = dst.."<Cannot convert: "..value..">"
    elseif ty == "cdata" then
        dst = dst..tostring(value)
    else 
        dst = dst.."<Cannot convert: "..ty..">"
    end
    
    return dst
end

return toStr