-- WindEnergyUnleashed Shared Core Logic
-- Defines constants, shared functions, loads sandbox options, etc.

WindEnergy = WindEnergy or {}
WindEnergy.DEBUG = true -- Set to false for release
WindEnergy.VERSION = "0.1.0" -- Mod version

function WindEnergy.log(message, ...)
    if WindEnergy.DEBUG then
        if #{...} > 0 then
            print("[WindEnergyUnleashed] " .. string.format(tostring(message), ...))
        else
            print("[WindEnergyUnleashed] " .. tostring(message))
        end
    end
end

function WindEnergy.error(message, ...)
    if #{...} > 0 then
        print("[WindEnergyUnleashed ERROR] " .. string.format(tostring(message), ...))
    else
        print("[WindEnergyUnleashed ERROR] " .. tostring(message))
    end
end

function WindEnergy.warn(message, ...)
    if #{...} > 0 then
        print("[WindEnergyUnleashed WARNING] " .. string.format(tostring(message), ...))
    else
        print("[WindEnergyUnleashed WARNING] " .. tostring(message))
    end
end


-- Load Sandbox Options on Game Start
function WindEnergy.LoadSandboxOptions()
    local sandbox = SandboxVars.WindEnergy
    WindEnergy.Options = {
        Enabled = sandbox.Enabled,
        PowerMultiplier = sandbox.PowerMultiplier,
        CraftingDifficulty = sandbox.CraftingDifficulty, -- 1=Easy, 2=Normal, 3=Hard
        WindVariability = sandbox.WindVariability,
        AdvancedPartRarity = sandbox.AdvancedPartRarity -- 1=VeryRare, 2=Rare, 3=Common
    }
    -- Log loaded options manually
    WindEnergy.log("Sandbox Options Loaded:")
    for k, v in pairs(WindEnergy.Options) do
        WindEnergy.log("  - " .. tostring(k) .. ": " .. tostring(v))
    end
end

-- WindSystem data (speed, direction) is managed server-side using ClimateManager.
-- This table can be used for shared constants or functions related to wind if needed later.
WindEnergy.WindSystem = {}

--- ===========================================================================
--- ModData Keys (Constants)
--- ===========================================================================
WindEnergy.ModDataKeys = {
    IsWindTurbine = "isWindTurbine", -- boolean: Identifies the object as a turbine
    TurbineData = "WindEnergyData", -- table: Container for all turbine-specific data
    TypeName = "typeName", -- string: Key from WindEnergy.TurbineTypes
    BladeType = "bladeType", -- string: Key from WindEnergy.BladeTypes
    Condition = "condition", -- number: Current condition (0-100 or 0-maxCondition)
    PowerOutput = "powerOutput", -- number: Current power generation (Watts)
    WindDirection = "windDirection", -- number: Current wind direction affecting the turbine (degrees)
    ConnectedPB = "connectedPB", -- table: {x=number, y=number, z=number} Coordinates of connected ISAPowerBank
    UniqueID = "uniqueId" -- string/number: A unique identifier (may not be needed if using object refs)
}

--- ===========================================================================
--- Turbine Definitions
--- ===========================================================================
-- maxPowerOutput: Max power output (Watts) at ratedSpeed under ideal conditions (100% condition, best blades).
-- cutInSpeed: Minimum wind speed (kph) to start generating power.
-- ratedSpeed: Wind speed (kph) at which maxPowerOutput is achieved.
-- cutOutSpeed: Maximum wind speed (kph) before shutdown for safety.
-- powerCurveExponent: Affects how quickly power ramps up between cutIn and rated speeds (e.g., 2 for quadratic, 3 for cubic).
-- placeableItem: The item type used to place this turbine (e.g., "WindEnergy.SmallWoodenTurbineItem").
-- objectSprite: The base name for the IsoObject's sprite (e.g., "WindEnergy_SmallTurbine"). Animations might append suffixes.
-- conditionMax: Maximum condition points for this turbine type.
WindEnergy.TurbineTypes = {
    SmallWooden = {
        key = "SmallWooden", -- Added for easier reference
        name = "Small Wooden Turbine",
        maxPowerOutput = 1500, -- Watts
        cutInSpeed = 10,  -- kph
        ratedSpeed = 40,  -- kph
        cutOutSpeed = 70, -- kph
        powerCurveExponent = 2.5,
        placeableItem = "WindEnergy.SmallWoodenTurbine", -- Matches item definition
        objectSprite = "WindEnergy_SmallTurbine_0", -- Placeholder base sprite
        conditionMax = 100,
        defaultBladeType = "MakeshiftWood" -- Default blades when placed
    },
    LargeMetal = {
        key = "LargeMetal", -- Added for easier reference
        name = "Large Metal Turbine",
        maxPowerOutput = 5000, -- Watts
        cutInSpeed = 12,  -- kph
        ratedSpeed = 45,  -- kph
        cutOutSpeed = 80, -- kph
        powerCurveExponent = 2.8,
        placeableItem = "WindEnergy.LargeMetalTurbine", -- Matches item definition
        objectSprite = "WindEnergy_LargeTurbine_0", -- Placeholder base sprite
        conditionMax = 150,
        defaultBladeType = "MetalSheet" -- Default blades when placed
    },
    AdvancedComposite = { -- Added based on user feedback
        key = "AdvancedComposite",
        name = "Advanced Composite Turbine",
        maxPowerOutput = 8000, -- Watts (Higher output)
        cutInSpeed = 10,  -- kph (Slightly lower cut-in)
        ratedSpeed = 50,  -- kph (Higher rated speed)
        cutOutSpeed = 90, -- kph (Higher cut-out)
        powerCurveExponent = 3.0, -- More aggressive curve
        placeableItem = "WindEnergy.AdvancedCompositeTurbine", -- Assumed item name
        objectSprite = "WindEnergy_AdvancedTurbine_0", -- Placeholder base sprite
        conditionMax = 200, -- Higher durability
        defaultBladeType = "AdvancedComposite" -- Uses the best blades by default
    }
}

--- ===========================================================================
--- Blade Definitions
--- ===========================================================================
-- efficiencyModifier: Multiplier applied to the turbine's power output (1.0 = baseline).
-- durabilityFactor: Multiplier affecting how quickly the turbine condition degrades (1.0 = baseline, >1 means faster degradation, <1 means slower).
-- itemType: The item type corresponding to these blades (e.g., "WindEnergy.WoodenTurbineBlades").
WindEnergy.BladeTypes = {
    MakeshiftWood = {
        key = "MakeshiftWood",
        name = "Makeshift Wooden Blades",
        efficiencyModifier = 0.6,
        durabilityFactor = 1.5,
        itemType = "WindEnergy.MakeshiftWoodenBlades" -- Assumed item name
    },
    CarvedWood = {
        key = "CarvedWood",
        name = "Carved Wooden Blades",
        efficiencyModifier = 0.8,
        durabilityFactor = 1.2,
        itemType = "WindEnergy.CarvedWoodenBlades" -- Assumed item name
    },
    MetalSheet = {
        key = "MetalSheet",
        name = "Sheet Metal Blades",
        efficiencyModifier = 0.9,
        durabilityFactor = 0.9,
        itemType = "WindEnergy.MetalSheetBlades" -- Assumed item name
    },
    AdvancedComposite = {
        key = "AdvancedComposite",
        name = "Advanced Composite Blades",
        efficiencyModifier = 1.1,
        durabilityFactor = 0.7,
        itemType = "WindEnergy.AdvancedCompositeBlades" -- Assumed item name
    }
    -- Add more types later
}

--- ===========================================================================
--- Utility Functions (Shared)
--- ===========================================================================
WindEnergy.Utils = WindEnergy.Utils or {}

-- Converts wind angle (degrees, 0=N, 90=E, 180=S, 270=W) to IsoDirection (0-7)
-- Note: IsoDirections are N=0, NE=1, E=2, SE=3, S=4, SW=5, W=6, NW=7
function WindEnergy.Utils.WindAngleToDirection(angle)
    local normalizedAngle = angle % 360
    if normalizedAngle < 0 then normalizedAngle = normalizedAngle + 360 end

    -- Adjust angle so 0 degrees aligns roughly with IsoDirection North (index 0)
    -- Iso North is roughly between 337.5 and 22.5 degrees.
    local adjustedAngle = normalizedAngle + 22.5
    local segment = math.floor((adjustedAngle % 360) / 45)
    return IsoDirections.fromIndex(segment)
end

-- Helper to get turbine definition from an object
function WindEnergy.Utils.GetTurbineDefinition(obj)
    if not obj then return nil end
    local modData = obj:getModData()
    if not modData or not modData[WindEnergy.ModDataKeys.IsWindTurbine] then return nil end
    local turbineData = modData[WindEnergy.ModDataKeys.TurbineData]
    if not turbineData then return nil end
    local typeName = turbineData[WindEnergy.ModDataKeys.TypeName]
    return WindEnergy.TurbineTypes[typeName]
end

-- Helper to get blade definition from an object
function WindEnergy.Utils.GetBladeDefinition(obj)
    if not obj then return nil end
    local modData = obj:getModData()
    if not modData or not modData[WindEnergy.ModDataKeys.IsWindTurbine] then return nil end
    local turbineData = modData[WindEnergy.ModDataKeys.TurbineData]
    if not turbineData then return nil end
    local bladeTypeName = turbineData[WindEnergy.ModDataKeys.BladeType]
    return WindEnergy.BladeTypes[bladeTypeName]
end


-- WindEnergy.log("Core Shared Loaded v" .. WindEnergy.VERSION) -- Moved to Init file

-- Hook into game loading
-- Events.OnGameStart.Add(WindEnergy.LoadSandboxOptions) -- Moved to Init file

return WindEnergy -- Add this line