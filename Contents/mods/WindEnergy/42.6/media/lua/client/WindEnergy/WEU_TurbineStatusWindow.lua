-- WindEnergyUnleashed Turbine Status Window

require "ISUI/ISCollapsableWindow"

WEU_TurbineStatusWindow = ISCollapsableWindow:derive("WEU_TurbineStatusWindow")

--[[*
 * Creates a new instance of the turbine status window.
 * @param x The x-coordinate of the window.
 * @param y The y-coordinate of the window.
 * @param width The width of the window.
 * @param height The height of the window.
 * @param turbineObj The IsoThumpable object representing the turbine.
]]
function WEU_TurbineStatusWindow:new(x, y, width, height, turbineObj)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = getText("IGUI_WEU_TurbineStatusTitle") -- Placeholder, will be translated
    o.resizable = false
    o.turbineObj = turbineObj
    o.infoText = nil -- RichTextPanel
    o:initialise()
    o:addToUIManager()
    o:setVisible(true)
    o:bringToTop()
    return o
end

--[[*
 * Creates the child UI elements for the window.
]]
function WEU_TurbineStatusWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    -- Rich Text Panel for displaying turbine info
    self.infoText = ISRichTextPanel:new(5, self:titleBarHeight() + 5, self.width - 10, self.height - self:titleBarHeight() - 10)
    self.infoText:initialise()
    self.infoText:setScrollHeight(self.height - self:titleBarHeight() - 10)
    self.infoText:setAnchorLeft(true)
    self.infoText:setAnchorRight(true)
    self.infoText:setAnchorTop(true)
    self.infoText:setAnchorBottom(true)
    self:addChild(self.infoText)

    -- TODO: Add buttons for future actions if needed
end

--[[*
 * Updates the window content. Called every frame.
]]
function WEU_TurbineStatusWindow:update()
    ISCollapsableWindow.update(self)

    if not self.turbineObj or not self.turbineObj:getObject() or self.turbineObj:getObject():getSquare() == nil then
        -- Turbine object is no longer valid, close the window
        self:close()
        return
    end

    local turbineData = self.turbineObj:getModData()
    if not turbineData then
        self:close() -- Close if no modData (shouldn't happen often)
        return
    end

    local text = ""
    local turbineType = turbineData.typeName or "Unknown"
    local currentPower = turbineData.currentPowerOutput or 0
    local currentWind = turbineData.currentWindSpeed or 0 -- Needs server to send this
    local condition = self.turbineObj:getCondition()
    local maxCondition = self.turbineObj:getMaxCondition()
    local conditionPercent = (condition / maxCondition) * 100
    local bladeType = turbineData.bladeType or "None"
    local connectedPB = turbineData.connectedPB

    -- Title/Type
    text = text .. "<CENTRE>" .. getText("IGUI_WEU_TurbineType") .. ": " .. turbineType .. "<LINE>"
    text = text .. "<LINE>" -- Extra space

    -- Power Output
    text = text .. "<LEFT>" .. getText("IGUI_WEU_PowerOutput") .. ": <RGB:1,1,0>" .. string.format("%.1f W", currentPower) .. "<RGB:1,1,1><LINE>"

    -- Wind Speed
    text = text .. "<LEFT>" .. getText("IGUI_WEU_WindSpeed") .. ": <RGB:0.8,0.8,1>" .. string.format("%.1f m/s", currentWind) .. "<RGB:1,1,1><LINE>" -- Assuming m/s

    -- Condition
    local r, g, b = ISHealthPanel.getConditionRGB(conditionPercent / 100)
    text = text .. "<LEFT>" .. getText("IGUI_WEU_Condition") .. ": <RGB:" .. r .. "," .. g .. "," .. b .. ">" .. string.format("%d%% (%d/%d)", math.floor(conditionPercent + 0.5), condition, maxCondition) .. "<RGB:1,1,1><LINE>"

    -- Blade Type
    text = text .. "<LEFT>" .. getText("IGUI_WEU_BladeType") .. ": " .. bladeType .. "<LINE>"

    -- Connected Power Bank
    if connectedPB and connectedPB.x then
        text = text .. "<LEFT>" .. getText("IGUI_WEU_ConnectedTo") .. ": ISA Power Bank @ " .. connectedPB.x .. "," .. connectedPB.y .. "," .. connectedPB.z .. "<LINE>"
    else
        text = text .. "<LEFT>" .. getText("IGUI_WEU_ConnectedTo") .. ": None<LINE>"
    end

    -- Set the text
    self.infoText:setText(text)
    self.infoText:paginate() -- Recalculate layout
end

--[[*
 * Renders the window.
]]
function WEU_TurbineStatusWindow:render()
    ISCollapsableWindow.render(self)
    -- Custom rendering if needed
end

--[[*
 * Closes the window and removes it from the UI manager.
]]
function WEU_TurbineStatusWindow:close()
    self:removeFromUIManager()
end

--[[*
 * Static function to open or focus the turbine status window for a specific turbine.
 * @param player The player object (usually getPlayer())
 * @param turbineObj The IsoThumpable object representing the turbine.
]]
function WEU_TurbineStatusWindow.OnOpenPanel(player, turbineObj)
    if not turbineObj then return end

    -- Check if a window for this specific turbine already exists
    local existingWindow = nil
    for i=0, UIManager.getWindows():size()-1 do
        local win = UIManager.getWindows():get(i)
        if instanceof(win, WEU_TurbineStatusWindow) and win.turbineObj == turbineObj then
            existingWindow = win
            break
        end
    end

    if existingWindow then
        -- Window exists, bring it to front and focus
        existingWindow:setVisible(true)
        existingWindow:bringToTop()
    else
        -- Create a new window
        local screenW = getCore():getScreenWidth()
        local screenH = getCore():getScreenHeight()
        local windowW = 300
        local windowH = 200
        local windowX = (screenW - windowW) / 2
        local windowY = (screenH - windowH) / 2
        local newWindow = WEU_TurbineStatusWindow:new(windowX, windowY, windowW, windowH, turbineObj)
        -- The 'new' function already adds it to the UI manager
    end
end

--[[*
 * Destructor equivalent.
]]
function WEU_TurbineStatusWindow:destroy()
    -- Clean up resources if necessary
end

-- Make sure the class is registered if needed by specific frameworks or contexts
-- Not typically required for basic ISUI elements unless doing advanced things.