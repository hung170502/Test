--[[
    Merge ESP targets from multiple data sources.
]]

local DataCollector = {}

function DataCollector.create(deps)
    local Config = deps.Config
    local EggData = deps.EggData
    local TreadmillData = deps.TreadmillData
    local TrapData = deps.TrapData

    local function collect()
        local results = {}

        local treadmill = TreadmillData.Collect()
        if treadmill then
            table.insert(results, treadmill)
        end

        for _, trap in ipairs(TrapData.Collect()) do
            table.insert(results, trap)
        end

        for _, egg in ipairs(EggData.Collect()) do
            if not Config or not Config.Runtime or Config.Runtime.showEggs ~= false then
                table.insert(results, egg)
            end
        end

        return results
    end

    return {
        Collect = collect,
    }
end

return DataCollector
