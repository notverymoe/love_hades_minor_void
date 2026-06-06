-- Copyright 2026 Natalie Baker -- MIT --

---@type table<string, number>
local spans = {}

---@type table<string, number[]>
local durations = {}

local reportTicks = 0

local function spanStart(name)
    local now = love.timer.getTime()
    spans[name] = now
end

local function spanStop(name)
    local now = love.timer.getTime()

    local start = spans[name]
    local duration = now - start

    local t = durations[name] or {}
    durations[name] = t
    t[1] = (t[1] or 0) + duration
end

local function spanReport(rate, maxSamples)
    maxSamples = maxSamples or 100
    reportTicks = reportTicks + 1

    -- Start new samples
    for _,t in pairs(durations) do
        table.insert(t, 1, 0)
        t[maxSamples+1] = nil
    end

    if reportTicks % rate == 0 then


        local padLen = 0

        ---@type [string, number][]
        local avg = {}
        for k,t in pairs(durations) do
            local v = 0
            for i=2,#t do v = v + t[i] end
            v = v/(#t-1)
            table.insert(avg, {k, v})
            padLen = math.max(padLen, k:len())
        end

        table.sort(avg, function(a, b)
            return a[2] > b[2]
        end)

        print("--------------------------------------------------------------------------------")
        for _,entry in ipairs(avg) do
            local k,v = unpack(entry)
            local padAmount = padLen - k:len()
            local p = (" "):rep(padAmount)
            print(k..p.." | "..tostring(math.ceil(v*1000000)).."us")
        end
        print("--------------------------------------------------------------------------------")
    end
end

return {
    start  = spanStart,
    stop   = spanStop,
    report = spanReport,
}