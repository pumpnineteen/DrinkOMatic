local addonName, DOM = ...
DOM = LibStub("AceAddon-3.0"):NewAddon(DOM, "AceConsole-3.0", "AceEvent-3.0")

-- Initialize localization
local L = LibStub("AceLocale-3.0"):GetLocale("DrinkOMatic")
-- local NL = LibStub("AceLocale-3.0"):GetLocale("GatheringTooltipNodes")

local AceGUI = LibStub("AceGUI-3.0")
local LibBagUtils = LibStub("LibBagUtils-1.0")
local LibKeyBound = LibStub("LibKeyBound-1.0", true)
-- local LAB = LibStub("LibActionButton-1.0")

local CE = LibStub("AceAddon-3.0"):GetAddon("Cooldown_Edge")

local LDB = LibStub("LibDataBroker-1.1", true)
local dataObject = LDB:NewDataObject("Drink-o-Matic", {
    type = "launcher", -- Common types include "launcher", "data source", or "stat"
    text = "DoM", -- Text to display in compatible broker addons
    icon = "Interface\\Icons\\INV_Potion_04", -- Path to your icon asset
    OnClick = function(clickedFrame, button)
        if button == "LeftButton" then

        elseif button == "RightButton" then
            if IsShiftKeyDown() then
                LibKeyBound:Toggle()
            else
                DOM:ToggleEditMode()
            end
            -- print("Right-click action triggered!")
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Drink-o-Matic", 1, 1, 1) -- Tooltip title
        -- tooltip:AddLine("Left-click: Open settings", 0.8, 0.8, 0.8) -- Tooltip instructions
        tooltip:AddLine("Shift-Right-click: Toggle keybinding mode", 0.8, 0.8, 0.8)
        tooltip:AddLine("Right-click: Edit mode", 0.8, 0.8, 0.8) -- Tooltip instructions
    end,
})



-- Expansion determination code from LibBagUtils.lua
local WOW_PROJECT_ID = _G.WOW_PROJECT_ID
local WOW_PROJECT_CLASSIC = _G.WOW_PROJECT_CLASSIC
local WOW_PROJECT_BURNING_CRUSADE_CLASSIC = _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC
local WOW_PROJECT_WRATH_CLASSIC = _G.WOW_PROJECT_WRATH_CLASSIC
local WOW_PROJECT_CATACLYSM_CLASSIC = _G.WOW_PROJECT_CATACLYSM_CLASSIC
local WOW_PROJECT_MAINLINE = _G.WOW_PROJECT_MAINLINE
local LE_EXPANSION_LEVEL_CURRENT = _G.LE_EXPANSION_LEVEL_CURRENT
local LE_EXPANSION_BURNING_CRUSADE =_G.LE_EXPANSION_BURNING_CRUSADE
local LE_EXPANSION_WRATH_OF_THE_LICH_KING = _G.LE_EXPANSION_WRATH_OF_THE_LICH_KING
local LE_EXPANSION_CATACLYSM = _G.LE_EXPANSION_CATACLYSM

DOM_savedPositions = DOM_savedPositions or {} -- Table to store button positions
DOM_RealNames = DOM_RealNames or {} 
DOM_BoundToNames = DOM_BoundToNames or {}

DOM.editMode = false
DOM.updateNeeded = false
DOM.maxButtons = 12 -- Maximum number of buttons
DOM.buttonSize = 32 -- Size of the buttons
DOM.itemIDMap = {} -- Table to store item IDs
DOM.dropBaseName = "DOMButton" -- Base name for drop target buttons
DOM.keyBoundClickButton = "LeftButton" -- Default click button for keybindings
DOM.creatingButton = {} -- Button creation lock
DOM.buffToButton = {} -- Table to store auras linked to active buttons

local defaultButtonConfig = {
	outOfRangeColoring = "button",
	tooltip = "enabled",
	showGrid = false,
	colors = {
		range = { 0.8, 0.1, 0.1 },
		mana = { 0.5, 0.5, 1.0 }
	},
	hideElements = {
		macro = false,
		hotkey = false,
		equipped = false,
	},
	keyBoundTarget = false,
	clickOnDown = false,
	flyoutDirection = "UP",
}

local DEBUG_SHOWMACROTEXT = false
local DEBUG = false

local function debugmsg(...)
    if DEBUG then
        local args = {...}
        local output = "DEBUG: "
        for i, v in ipairs(args) do
            output = output .. tostring(v) .. " "
        end
        print(output)
    end
end

local function IsOnCooldown(start, duration)
    return not (start == 0 and duration == 0)
end

function DOM:CreateFrame()
    DOM.header = CreateFrame("Frame", "DOM_header", UIParent, "SecureHandlerStateTemplate")
    DOM.drop   = CreateFrame("Frame", "DOM_drop", UIParent, "SecureHandlerStateTemplate")
    DOM.header:Show()
end

local function IsPointInside(frame, x, y)
    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()

    return (x >= left and x <= right) and (y >= bottom and y <= top)
end


local function IsClassicWow() --luacheck: ignore 212
    return WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
end

local function IsTBCWow() --luacheck: ignore 212
    return WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_BURNING_CRUSADE
end

local function IsWrathWow() --luacheck: ignore 212
    return WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_WRATH_OF_THE_LICH_KING
end

local function IsCataWow() --luacheck: ignore 212
    return WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC and LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CATACLYSM
end

local function IsRetailWow() --luacheck: ignore 212
    return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

local druid_exceptions = {
    [3823] = true,   -- Lesser Invisibility Potion
    [9172] = true,   -- Invisibility Potion
    [12190] = true,  -- Dreamless Sleep Potion
    [20002] = true,  -- Greater Dreamless Sleep Potion
    [4366] = true,  -- Target Dummy
    [4392] = true,  -- Advanced Target Dummy
    [16023] = true,  -- Masterwork Target Dummy
    [13506] = true,  -- Flask of Petrification > You turn to stone, protecting you from all physical attacks and spells for 1 min, but during that time you cannot attack, move or cast spells. Counts as both a Battle and Guardian elixir.
    -- [18297] = true,  -- Thornling Seed > Plants a Thornling which attracts nearby enemies.
    [184937] = true,  -- Chronoboon Displacer > Alters the fabric of time, suspending beneficial world effects from dragonslaying, Dire Maul, Zul'Gurub, and Felwood.
    [184938] = true,  -- Supercharged Chronoboon Displacer > Restores your suspended world effects.
    [8529] = true,  -- Noggenfogger Elixir > Drink Me.
    [8546] = true,  -- Powerful Smelling Salts > Brings a dead player back to life with 15% of their health and mana.  Cannot be used when in combat.
}

local TwoWayMap = {}
TwoWayMap.__index = TwoWayMap

-- this doesn't work in wow, since __pairs was introduced in lua 5.2
-- TwoWayMap.__pairs = function(self)
--     return pairs(self.forward)
-- end

-- Constructor now accepts optional forward and reverse tables.
function TwoWayMap:new(forward, reverse, forwardName, reverseName)
    local obj = {
        forward = forward or {},
        reverse = reverse or {},
        forwardName = forwardName,
        reverseName = reverseName,
    }
    setmetatable(obj, self)
    debugmsg(obj.forward == forward)  -- Should output true
    debugmsg(obj.reverse == reverse)  -- Should output true
    -- Add dynamic method names for forward and reverse retrieval
    obj:addDynamicGetters()
    return obj
end

function TwoWayMap:pairs()
    return pairs(self.forward)
end

function TwoWayMap:addDynamicGetters()
    if self.forwardName and self.forwardName ~= "GetForward" then
        self[self.forwardName] = function(self, key)
            return self:GetForward(key)
        end
    end
    if self.reverseName and self.reverseName ~= "GetReverse" then
        self[self.reverseName] = function(self, value)
            return self:GetReverse(value)
        end
    end
end


-- Optional method to replace the forward and reverse tables at any time.
function TwoWayMap:SetTables(newForward, newReverse)
    self.forward = newForward or {}
    self.reverse = newReverse or {}
end

function TwoWayMap:Set(key, value)
    -- Remove any existing mapping for key or value.
    local currentValue = self.forward[key]
    if currentValue then
        self.reverse[currentValue] = nil
    end
    local currentKey = self.reverse[value]
    if currentKey then
        self.forward[currentKey] = nil
    end

    -- Set the new mapping both ways.
    self.forward[key] = value
    self.reverse[value] = key
end

function TwoWayMap:GetForward(key)
    return self.forward[key]
end

function TwoWayMap:GetReverse(value)
    return self.reverse[value]
end

function TwoWayMap:RemoveByKey(key)
    local value = self.forward[key]
    if value then
        self.forward[key] = nil
        self.reverse[value] = nil
    end
end

function TwoWayMap:RemoveByValue(value)
    local key = self.reverse[value]
    if key then
        self.reverse[value] = nil
        self.forward[key] = nil
    end
end

function TwoWayMap:Get(key)
    -- Check if the key exists in the forward table.
    local value = self.forward[key]
    if value ~= nil then
        return value
    end

    -- If not, check in the reverse table.
    return self.reverse[key]
end


-- -- Usage example:

-- -- Option 1: Start with empty tables.
-- local map = TwoWayMap:new()
-- map:set("drinkButton1", "dropTarget5")
-- print("Forward mapping:", map:getForward("drinkButton1"))  -- outputs "dropTarget5"
-- print("Reverse mapping:", map:getReverse("dropTarget5"))     -- outputs "drinkButton1"

-- -- Option 2: Provide custom forward and reverse tables.
-- local customForward = { initButton = "initDrop" }
-- local customReverse = { initDrop = "initButton" }
-- local map2 = TwoWayMap:new(customForward, customReverse)
-- print("Forward mapping:", map2:getForward("initButton"))  -- outputs "initDrop"
-- print("Reverse mapping:", map2:getReverse("initDrop"))      -- outputs "initButton"

-- -- Later, you can reset the tables if needed.
-- map2:setTables({ newStart = "newDrop" }, { newDrop = "newStart" })
-- print("Updated forward mapping:", map2:getForward("newStart"))  -- "newDrop"

-- -- Get value from either mapping.
-- print("Any mapping:", map2:get("newStart"))  -- outputs "newDrop"


-- print("We are classical: ", IsClassicWow())

local itemCategories = {}

DOM.Buttons = {}
DOM_BEAR = "BEAR"
DOM_CAT = "CAT"
DOM_MOONKIN = "MOONKIN"
DOM_ReturnToForm = DOM_BEAR
DOM_DRUID = false

local drinks
local conjured_drinks
local healing_potions
local mana_potions
local specific_healing_potions
local specific_mana_potions
local mana_gems
local healthstones
local scrolls
local nb_foods
local conjured_nb_foods
local percent_foods
local foods
local alcohol
local other_consumables
local buff_map

local function get_tables()
    if IsClassicWow() or IsTBCWow() then
        buff_map = tbc_consumables
        drinks = tbc_drinks
        conjured_drinks = tbc_conjured_drinks
        healing_potions = tbc_healing_potions
        mana_potions = tbc_mana_potions
        specific_healing_potions = tbc_specific_healing_potions
        specific_mana_potions = tbc_specific_mana_potions
        healthstones = tbc_healthstones
        scrolls = tbc_scrolls
        nb_foods = tbc_nonbuff_foods
        conjured_nb_foods = tbc_conjured_nonbuff_foods
        percent_foods = tbc_percent_nonbuff_foods
        foods = tbc_foods
        alcohol = tbc_alcohol
        other_consumables = tbc_other_consumables
    end
end


local function addOrderedCategory(itemList, category, subcategory)
    for rank, itemID in ipairs(itemList) do
        itemCategories[itemID] = {
            category = category,
            rank = rank
        }
        if subcategory then
            itemCategories[itemID].subcategory = subcategory
        end
    end
end

local function addUnorderedCategory(itemList, category)
    for _, item in ipairs(itemList) do
        if type(item) == "number" then
            itemCategories[item] = {
                category = category,
                rank = 1
            }
        elseif type(item) == "table" then
            for subCategory, subItems in pairs(item) do
                addOrderedCategory(subItems, category, subCategory)
            end
        else
            print("Unknown item type: ", item, type(item))
        end    
    end
end

local function makeCategoriesTable()
    addOrderedCategory(drinks, "Drink")
    addOrderedCategory(conjured_drinks, "ConjuredDrink")
    addOrderedCategory(healing_potions, "HealingPotion")
    addOrderedCategory(mana_potions, "ManaPotion")
    addOrderedCategory(specific_healing_potions, "SpecificHealingPotion")
    addOrderedCategory(specific_mana_potions, "SpecificManaPotion")
    addOrderedCategory(healthstones, "HealthStone")
    addOrderedCategory(nb_foods, "NonbuffFood")
    addOrderedCategory(conjured_nb_foods, "ConjuredNonbuffFood")
    addOrderedCategory(percent_foods, "PercentFood")
    addOrderedCategory(alcohol, "Alcohol")
    addUnorderedCategory(scrolls, "Scroll")
    addUnorderedCategory(foods, "Food")
    addUnorderedCategory(other_consumables, "Other")
end

local function saveButtonPosition(button)
    local point, relativeTo, relativePoint, xOffs, yOffs = button:GetPoint()
    debugmsg("Saving position for button: ", button:GetName(), point, relativeTo, relativePoint, xOffs, yOffs)
    DOM_savedPositions[button:GetName()] = { point, relativeTo, relativePoint, xOffs, yOffs }
    -- print(button:GetName(), point, relativeTo, relativePoint, xOffs, yOffs)
end


function DOM_IsSpecialBag(bagNum)
    -- First check basic constraints
    if bagNum > 4 then return true end
    if bagNum == 0 then return false end -- Backpack is always valid
    
    -- Get bag info using LibBagUtils
    local bagType = LibBagUtils:GetContainerFamily(bagNum)
    if not bagType then 
        return true -- If we can't get info, assume it's special
    end 
    
    return bagType ~= 0
end

local bestConsumables = {} 

local function resetBestConsumables()
    bestConsumables = { 
        healingPotion = {}, 
        manaPotion = {},
        specificHealing = {},
        specificMana = {}, 
        healthStone = {}, 
        drink = {},
        conjuredDrink = {},
        manaGem = {},
        scrolls = {},
        foods = {},
        nb_foods = {},
        conjured_nb_foods = {},
        percent_foods = {},
        alcohol = {},
        other = {},
    }
end


-- Find the best healing potion in your bags
local function GetBestConsumables()
    -- print("Finding consumables...")
    resetBestConsumables()

    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemID)
                local itemData = itemCategories[itemID]
                if itemData then
                    DOM.itemIDMap[itemName] = itemID
                    if itemID < 10 then
                        print("ItemID is less than 10: ", itemID, itemName)
                    end
                    local category = itemData.category
                    local rank = itemData.rank
                    -- print("Found consumable:", itemName, "in category:", category, "with rank:", rank)

                    if category == "ConjuredDrink" then
                        bestConsumables.conjuredDrink[itemName] = rank
                    elseif category == "Drink" then
                        bestConsumables.drink[itemName] = rank 
                    elseif category == "HealingPotion" then
                        bestConsumables.healingPotion[itemName] = rank
                    elseif category == "SpecificHealingPotion" then
                        bestConsumables.specificHealing[itemName] = rank
                    elseif category == "ManaPotion" then
                        bestConsumables.manaPotion[itemName] = rank
                    elseif category == "SpecificManaPotion" then
                        bestConsumables.specificMana[itemName] = rank
                    elseif category == "HealthStone" then
                        bestConsumables.healthStone[itemName] = rank
                    elseif category == "ManaGem" then
                        bestConsumables.manaGem[itemName] = rank
                    elseif category == "NonbuffFood" then
                        bestConsumables.nb_foods[itemName] = rank
                    elseif category == "ConjuredNonbuffFood" then
                        bestConsumables.conjured_nb_foods[itemName] = rank
                    elseif category == "PercentFood" then
                        bestConsumables.percent_foods[itemName] = rank
                    elseif category == "Alcohol" then
                        bestConsumables.alcohol[itemName] = rank
                    elseif category == "Scroll" then
                        table.insert(bestConsumables.scrolls, itemName)
                    elseif category == "Food" then
                        table.insert(bestConsumables.foods, itemName)
                    elseif category == "Other" then
                        table.insert(bestConsumables.other, itemName)
                    end
                end
            end
        end
    end
    return bestConsumables
end

local catFormSpellID = 768
local bearFormSpellID = 5487
local direBearFormSpellID = 9634
local moonkinSpellID = 24858

local function isDire()
    return IsSpellKnown(direBearFormSpellID)
end

local function getBearID()
    if isDire() then
        return direBearFormSpellID
    end
    return bearFormSpellID
end

local function getBearName()
    if isDire() then
        return GetSpellInfo(direBearFormSpellID)
    end
    return GetSpellInfo(bearFormSpellID)
end

local function getFormName()
    if DOM_ReturnToForm == DOM_BEAR then
        return getBearName()
    elseif DOM_ReturnToForm == DOM_CAT then
        return GetSpellInfo(catFormSpellID)
    elseif DOM_ReturnToForm == DOM_MOONKIN then
        return GetSpellInfo(moonkinSpellID)
    else
        print("Unknown form: ", DOM_ReturnToForm)
        return getBearName()
    end
end

local function getFormID()
    if DOM_ReturnToForm == DOM_BEAR then
        return getBearID()
    elseif DOM_ReturnToForm == DOM_CAT then
        return catFormSpellID
    elseif DOM_ReturnToForm == DOM_MOONKIN then
        return moonkinSpellID
    else
        print("Unknown form: ", DOM_ReturnToForm)
        return getBearID()
    end
end
local function debug_macrotext(buttonName, itemName, itemNames, macrotext)
    print("Creating button: ", buttonName, " for item: ", itemName)
    print(itemNames)
    for _, item in ipairs(itemNames) do
        print(item)
    end
    print("\n" .. macrotext)
end

local function is_druid_button(tryDruid, itemID)
    local useDruid = tryDruid
    if tryDruid then
        -- print("tryDruid", itemID, itemID and druid_exceptions[itemID])
        if itemID and druid_exceptions[itemID] then
            useDruid = false
        end
        if not (IsSpellKnown(direBearFormSpellID) or 
                IsSpellKnown(bearFormSpellID) or 
                IsSpellKnown(catFormSpellID) or 
                IsSpellKnown(moonkinSpellID)) then
            useDruid = false
        end
    end

    debugmsg("druid:", useDruid, tryDruid, itemID)

    return useDruid
end

local function build_macrotext(itemNames, altItemNames, useDruid)
    local macrotext = ""
    if altItemNames then
        for _, item in ipairs(altItemNames) do
            macrotext = macrotext .. "/use [nomod:ctrl] " .. item .. "\n"
        end
    end
    if itemNames then
        for _, item in ipairs(itemNames) do
            macrotext = macrotext .. "/use " .. item .. "\n"
        end
    end

    if useDruid then
        macrotext = macrotext .. "/stopmacro [mod:alt]\n" .. "/cast " .. getFormName()
    end

    return macrotext
end

local function setKeybindText(button)
    if not button.isBoundButton then return end
    local key = (button.GetHotkey  and button:GetHotkey()) or nil

    if key then 
        local keybindtext = button.keybindtext or button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        keybindtext:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2) 
        keybindtext:SetText(key)
        keybindtext:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        keybindtext:Show()

        button.keybindtext = keybindtext
        debugmsg("Keybind text set for", button:GetName(), ":", key , button.keybindtext:GetText())
    end
end

function DOM:UpdateDragCoordinates()
    if self.draggedButton and self.draggedButton:IsDragging() then
        local x, y = self.draggedButton:GetCenter()
        debugmsg("Dragging coordinates: ", x, y)
        -- Fire a custom event "DraggingUpdate" with the coordinates.
        self.callbacks:Fire("DraggingUpdate", x, y)
    end
end

function DOM:StopDragUpdates()
    local updateNeeded = false
    if self.dragUpdateTicker then
        self.dragUpdateTicker:Cancel()
        self.dragUpdateTicker = nil
    end
    -- print(self.draggedButton and self.draggedButton:GetName(), self.dropTarget and self.dropTarget:GetName())
    if self.draggedButton and self.dropTarget then
        self.buttonNameMap:Set(self.dropTarget:GetName(), self.draggedButton:GetName())
        updateNeeded = true
        
        saveButtonPosition(self.draggedButton)
        saveButtonPosition(self.dropTarget)

        DOM:DestroyButton(self.draggedButton)
        DOM:SetDropOverlay_noOverlap(self.dropTarget)
    end
    self.draggedButton = nil
    self.dropTarget = nil
    if updateNeeded then
        -- print("Requesting update...")
        DOM:ExitEditMode()
        self:createButtons()
        DOM.EnterEditMode()
    end
end

function DOM:SetDropOverlay_overlap(button)
    button.overlay:SetColorTexture(1, 0.5, 0, 0.5)  -- Highlighted color (orange)
    debugmsg("Coordinates overlap with", button:GetName())
    DOM.dropTarget = button
end

function DOM:SetDropOverlay_noOverlap(button)
    button.overlay:SetColorTexture(0, 1, 0, 0.5)
end

function DOM:CheckDropTargetOverlap(x, y)
    -- Loop through all drop targets using dropBaseName
    for i = 1, DOM.maxButtons do
        local buttonName = DOM.dropBaseName .. i  -- Use dropBaseName here
        local dropTarget = DOM.Buttons[buttonName]
        if dropTarget then
            if IsPointInside(dropTarget, x, y) then
                -- Overlap detected: change the overlay appearance
                DOM:SetDropOverlay_overlap(dropTarget)
            end
        else
            -- No overlap: reset to default overlay color (green)
            DOM:SetDropOverlay_noOverlap(dropTarget)
            if DOM.dropTarget and DOM.dropTarget == dropTarget then
                DOM.dropTarget = nil
            end
        end
    end
end

function DOM:ButtonSetPoint(button, buttonName)
    if DOM_savedPositions[buttonName] and #DOM_savedPositions[buttonName] > 1 then
        button:SetPoint(unpack(DOM_savedPositions[buttonName]))
    else
        button:SetPoint("CENTER")
    end
end

function DOM:ButtonRegisterAuras(actualButtonName, itemNames)
    for _, item in ipairs(itemNames) do
        local itemID = DOM:GetItemID(item)
        if itemID and buff_map[itemID] then
            local buffs = buff_map[itemID].buffs or {}
            for _, buff in ipairs(buffs) do
                if not DOM.buffToButton[buff] then DOM.buffToButton[buff] = {} end
                table.insert(DOM.buffToButton[buff], actualButtonName)
            end
        end
    end
end

-- function DOM:ButtonHasActiveAura(button)
--     if not button.hasAura then return false end
--     for _,active in pairs(button.hasAura) do
--         if active then return true end
--     end
--     return false
-- end

function DOM:GetItemID(itemName)
    local itemID = itemName and DOM.itemIDMap[itemName] or nil
    return itemID
end

local function createDrinkButton(buttonID, tryDruid, itemNames, buttonName, altItemNames)
    if DOM.creatingButton[buttonName] then return end
    DOM.creatingButton[buttonName] = true
    local itemName = (itemNames and itemNames[1]) or nil    -- Use the first item from itemNames
    local altItemName = (altItemNames and altItemNames[1]) or nil  -- Use the first item from altItemNames
    itemName = itemName or altItemName or nil
    if not itemName then 
        return 
    end

    local itemID = DOM:GetItemID(itemName)

    local useDruid = is_druid_button(tryDruid, itemID)

    local macrotext = build_macrotext(itemNames, altItemNames, useDruid)

    if DEBUG_SHOWMACROTEXT then
        debug_macrotext(buttonName, itemName, itemNames, macrotext)
    end

    --  LAB:CreateButton(buttonID, buttonName, DOM_header, defaultButtonConfig)  
    -- CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
    local isBoundButton = false
    local actualButtonName = buttonName
    if DOM.buttonNameMap:Get(buttonName) then
        actualButtonName = DOM.buttonNameMap:Get(buttonName)
        isBoundButton = true
        debugmsg("Found button: ", buttonName, DOM.buttonNameMap:GetBoundToName(buttonName), DOM.buttonNameMap:GetRealName(buttonName))
    end

    if isBoundButton then
        debugmsg("Creating Bound Button: ", buttonName, " for item: ", itemName, " with actual name: ", actualButtonName, " isBoundButton: ", isBoundButton)
    end
   
    local button = DOM.Buttons[actualButtonName] or  CreateFrame("Button", actualButtonName, UIParent, "SecureActionButtonTemplate, BackdropTemplate")
    -- local button = DOM.Buttons[actualButtonName] or  LAB:CreateButton(buttonID, actualButtonName, DOM.header)
    -- print("DrinkButton:" , button)
    button.itemName = itemName
    button.itemID = itemID
    button.altItemName = altItemName
    button.isBoundButton = isBoundButton
    button.realButtonName = buttonName
    button.cooldownProgress = false
    button.itemDepleted = false
    button.altItemDepleted = false
    button.itemIndex = 1
    button.altItemIndex = 1
    button.isPinned = false
    button.isDesaturated = false
    button.lastBAG_UPDATE_COOLDOWN = GetTime()
    button.isDesaturated = false 
    button.hasAura = button.hasAura or false

    if not altItemNames then 
        button.altItemDepleted = true
    else
        local itemCount = (altItemNames[1] and GetItemCount(altItemNames[1], false, true)) or 0
        if itemCount == 0 then
            button.altItemDepleted = true
        end 
    end

    if not itemNames then
        button.itemDepleted = true
    else
        local itemCount = (itemNames[1] and GetItemCount(itemNames[1], false, true)) or 0
        if itemCount == 0 then
            button.itemDepleted = true
        end
    end

    DOM.Buttons[actualButtonName] = button

    if not button.altItemDepleted then
        DOM:ButtonRegisterAuras(actualButtonName, altItemNames)
    end

    if not button.itemDepleted then
        DOM:ButtonRegisterAuras(actualButtonName, itemNames)
    end
    
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", macrotext)
    
    -- Restore saved position or default to center
    if DOM_savedPositions[actualButtonName] then
        DOM:ButtonSetPoint(button, actualButtonName)
    elseif isBoundButton then
        DOM:ButtonSetPoint(button, buttonName)
    else
        button:SetPoint("CENTER")
    end

    button:SetSize(DOM.buttonSize, DOM.buttonSize)
    
    -- Set the button texture and icon
    local itemTexture = GetItemIcon(itemName)

    local altTexture = nil
    local altItemID = nil

    if altItemName then
        altTexture = GetItemIcon(altItemName)
        altItemID = DOM:GetItemID(altItemName)
    end

    local buttonTexture = button.buttonTexture
    if not buttonTexture then
        buttonTexture = button:CreateTexture(nil, "ARTWORK")
        button.buttonTexture = buttonTexture
    end

    if  altItemName then
        buttonTexture:SetTexture(altTexture)
    elseif itemTexture then
        buttonTexture:SetTexture(itemTexture)
    else
        buttonTexture:SetTexture("Interface\\ICONS\\INV_Drink_01")
    end

    buttonTexture:SetSize(32, 32)
    buttonTexture:SetPoint("CENTER")
    buttonTexture:Show()
    button.buttonTexture = buttonTexture

    if useDruid then
        local form = button.form
        if not form then
            form = button:CreateTexture(nil, "OVERLAY")
            button.form = form
        end

        form:SetTexture(GetSpellTexture(getFormID()))
        form:SetSize(12, 12)
        form:SetPoint("TOPRIGHT")
        form:Show()
        button.form = form
    end

    -- Set up the tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        
        if IsControlKeyDown() then
            -- print("Control: ", itemName)
            GameTooltip:SetHyperlink("item:" .. GetItemInfoInstant(itemName))
        else
            if altItemName then
                GameTooltip:SetHyperlink("item:" .. GetItemInfoInstant(altItemName))
            else
                GameTooltip:SetHyperlink("item:" .. GetItemInfoInstant(itemName))
            end
        end
        
        GameTooltip:Show()

        -- print("Bound:", self.isBoundButton, LibKeyBound)
        if self.isBoundButton then
            if LibKeyBound then
                debugmsg("KeyBound: ", actualButtonName, " is bound to: ", self:GetHotkey())
                LibKeyBound:Set(self)
            end
        end

    end)

    -- Create and set the count text
    local count = button.count
    local countFrame = button.countFrame or CreateFrame("Frame", nil, button)
    if not count then
        countFrame:SetFrameLevel(1000)
        count = countFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        button.count = count
        button.countFrame = countFrame
    end
    
    local function setStackText()
        local item = altItemName or itemName
        local isAltItem = true
        if not altItemName then
            isAltItem = false
        end
        if IsControlKeyDown() then
            item = itemName
            isAltItem = false
        end
        local itemCount = GetItemCount(item, false, true)
        button.count:SetText(itemCount)
        return itemCount, isAltItem
    end

    function button:setStatus()
        if IsControlKeyDown() then
            button.buttonTexture:SetTexture(itemTexture)
            setStackText(itemName, altItemName)
        else
            if altItemName then
                button.buttonTexture:SetTexture(altTexture)
                setStackText(itemName, altItemName)
            else
                button.buttonTexture:SetTexture(itemTexture)
                setStackText(itemName, altItemName)
            end
        end
    end

    setStackText()

    local function handleDepteltion(isAltItem)
        -- TODO: implement item depletion logic
    end

    -- Update the item count after the macro runs
    if not button.stackHook then
        button.stackHook = true
        button:HookScript("OnClick", function()
            local itemCount, isAltItem = setStackText()
        end)
    end

    -- Handle modifier key state to change the texture
    button:RegisterEvent("MODIFIER_STATE_CHANGED")
    button:RegisterEvent("PLAYER_REGEN_ENABLED")
    button:RegisterEvent("BAG_UPDATE_COOLDOWN")
    button:SetScript("OnEvent", function(self, event, key, state)
        local time = GetTime()
        if event == "BAG_UPDATE_COOLDOWN" and time - button.lastBAG_UPDATE_COOLDOWN < 0.5 then return end
        
        -- if actualButtonName == "DrinkOMaticCombatPotionButtonMagic Dust" then
        --     print("Event triggered:", event, button.cooldownStarted, button.cooldownProgress)
        -- end

        if event == "BAG_UPDATE_COOLDOWN" then
            button.lastBAG_UPDATE_COOLDOWN = time
            button.cooldownProgress = DOM:UpdateCooldown(self)
            if button.cooldownProgress then
                button:AddOnUpdate()
            end
        end
        if event == "MODIFIER_STATE_CHANGED" then
            if useDruid then 
                if IsAltKeyDown() then
                    button.form:Hide()
                else
                    button.form:Show()
                end
            end
            button:setStatus()
            if DOM.creatingButton[buttonName] then
                print(buttonName,"is still being created, or didn't finish creation properly!")
            end
        end
        -- if InCombatLockdown() then return end
        if event == "PLAYER_REGEN_ENABLED" then
            button:setStatus()
        end
    end
    )

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    function button:AddOnUpdate()
        if self.cooldownProgress then
            button:SetScript("OnUpdate", function(self)
                if self.itemID then
                    if self.cooldownProgress then
                        local start, duration, enable = C_Container.GetItemCooldown(self.itemID)
                        self.cooldownProgress = IsOnCooldown(start, duration)
                    end
                    if not self.cooldownProgress then
                        if self.isDesaturated then
                            self.buttonTexture:SetDesaturated(false)
                            self.isDesaturated = false
                            self.cooldownStarted = false
                            self:SetScript("OnUpdate", nil)
                        end
                    end 
                end
                
            end)
        end
    end

    -- Create and set the cooldown frame
    if not button.cooldown then
        button.cooldown = button.cooldown or CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.cooldown:SetSwipeColor(0, 0, 0, 0)
        button.cooldown:SetAllPoints()
        if CE then
            button.cooldown:SetSwipeTexture(CE.CIRCLE_RED)
            button.cooldown:SetSwipeColor(1,1,1,1)
            button.cooldown.noTextureOverride = true
        end
    end
    
    if itemID then
        local start, duration, enable = C_Container.GetItemCooldown(itemID)
        button.cooldownProgress = IsOnCooldown(start, duration)
        if button.cooldownProgress then
            CooldownFrame_Set(button.cooldown, start, duration, enable, false, 1.0)
            button:AddOnUpdate()
        end
    end

    
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    
    DOM:AddButtonScripts(button)   

    if isBoundButton then
        debugmsg(">> Adding Binding Text to: ", button:GetName(), " with key: ", button:GetHotkey())
        setKeybindText(button)
    end

    -- button:SetParent(DOM.header)
    button:Show()
    -- button:SetAttribute("statehidden", nil)
    -- button:UpdateAction()

    DOM.creatingButton[buttonName] = nil
end

function DOM:NormalButtonDrag(button)
    button:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
            if DOM.editMode then
                DOM.draggedButton = self
                DOM.dragUpdateTicker = C_Timer.NewTicker(0.1, function() DOM:UpdateDragCoordinates() end)
            end

        end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveButtonPosition(self)
        DOM:StopDragUpdates()

    end)
end

function DOM:BoundButtonDrag(button)
    button:SetMovable(false)

    button:SetScript("OnDragStart", function(self)
        if DOM.editMode then
            if not InCombatLockdown() then
                self:StartMoving()
            end
        end
    end)

    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveButtonPosition(self)
    end)
end

function DOM:BoundButtonEditMode(button)
    debugmsg("Adding EditMode: ", button:GetName())
    function button:EnterEditMode()
        if InCombatLockdown() then return end
        debugmsg("Entering edit mode for: ", button:GetName())

        button:SetMovable(true)
        local overlay = self.overlay or button:CreateTexture(nil, "OVERLAY")
        overlay:SetAllPoints()
        overlay:SetColorTexture(0, 1, 0, 0.4)  -- Green, 50% opacity
        button.overlay = overlay

        button.overlay:Show()
    end

    function button:ExitEditMode()
        button:SetMovable(false)
        if button.overlay then
            button.overlay:Hide()
        end
    end

    function button:ToggleEditMode()
        if DOM.editMode then
            button:ExitEditMode()
        else
            button:EnterEditMode()
        end
    end
end

-- LibActionButton-1.0
local function getKeys(binding, keys)
	keys = keys or ""
	for i = 1, select("#", GetBindingKey(binding)) do
		local hotKey = select(i, GetBindingKey(binding))
		if keys ~= "" then
			keys = keys .. ", "
		end
		keys = keys .. GetBindingText(hotKey)
	end
	return keys
end

local function getKeybindName(button)
    local name = ("CLICK %s:%s"):format(button:GetName(), DOM.keyBoundClickButton)
    return name
end

function DOM:AddKeyboundScritps(button)
    debugmsg("Adding keybound scripts to: ", button:GetName())

    function button:GetHotkey()
        local name = getKeybindName(button)
        local key = GetBindingKey(name)
        if key then
            return LibKeyBound and LibKeyBound:ToShortKey(key) or key
        end
    end

    function button:SetKey(key)
        SetBindingClick(key, self:GetName(), DOM.keyBoundClickButton)
        setKeybindText(button)   
    end

    function button:ClearBindings()
        self.currentBinding = nil
        if self.keybindtext then
            self.keybindtext:SetText("")
            self.keybindtext:Hide()
        end
        local binding = getKeybindName(button)
        while GetBindingKey(binding) do
            SetBinding(GetBindingKey(binding), nil)
        end

    end

    function button:GetBindings()
        local keys
        keys = getKeys(getKeybindName(button), keys)
        
        self.currentBinding = keys
        return keys
    end

    function button:GetActionName()
        if not button.itemName then
            return button:GetName()
        end
        if button.altItemName then
            return format("DrinkButton: %s , alt: %s", button.itemName, button.altItemName)
        end
        return format("DrinkButton: %s", button.itemName)
    end

    debugmsg("Keybound scripts added to: ", button:GetName(), " with key: ", button:GetHotkey())
end

function DOM:AddButtonScripts(button)
    local isBoundButton = button.isBoundButton or false

    if isBoundButton then
        DOM:BoundButtonDrag(button)
        DOM:BoundButtonEditMode(button)
        DOM:AddKeyboundScritps(button)
    else 
        DOM:NormalButtonDrag(button)
    end
end

function DOM:EnterEditMode()
    if InCombatLockdown() then 
        print("Cannot enter edit mode while in combat.")    
        return 
    end
    if DOM.editMode then 
        print("Already in edit mode.")
        return 
    end

    if DEBUG then
        for k,v in DOM.buttonNameMap:pairs() do
            print("name map: ", k , " <-> ", v)
        end
    end

    debugmsg(DOM.buttonNameMap.forward == DOM_BoundToNames)  -- Should output true
    debugmsg(DOM.buttonNameMap.reverse == DOM_RealNames)    -- Should output true


    DOM.editMode = true
    DOM:CreateKeyButtons()
    for i = 1, DOM.maxButtons do
        local buttonName = DOM.dropBaseName .. i
        if DOM.buttonNameMap:Get(buttonName) then
            local name = buttonName
            if not DOM.Buttons[name] then
                name = DOM.buttonNameMap:Get(buttonName)
            end
            DOM.Buttons[name]:EnterEditMode()
        else
            local dropTarget = DOM.Buttons[buttonName]

            -- Enable the green overlay and make the drop target movable
            local overlay = dropTarget.overlay or dropTarget:CreateTexture(nil, "OVERLAY")
            overlay:SetAllPoints()
            overlay:SetColorTexture(0, 1, 0, 0.4)  -- Green, 40% opacity
            dropTarget.overlay = overlay

            dropTarget.overlay:Show()

            dropTarget:EnableMouse(true)
            dropTarget:SetMovable(true)
        end
    end
end

function DOM:DestroyButton(button)
    if not button then return end
    local buttonName = button:GetName()

    button:UnregisterAllEvents()  -- Unregister events to prevent lingering references
    button:SetParent(nil)         -- Remove parent reference
    button:ClearAllPoints()       -- Clear anchors
    button:EnableMouse(false)     -- Disable interaction
    button:Hide()                 -- Ensure it's hidden from view
    
    DOM.Buttons[buttonName] = nil     -- Remove reference from DOM.Buttons
    button = nil                  -- Remove local reference, allowing Lua's garbage collector to clean up

end

function DOM:ExitEditMode()
    DOM.editMode = false
    for i = 1, DOM.maxButtons do
        local buttonName = DOM.dropBaseName .. i
        if DOM.buttonNameMap:Get(buttonName) then
            local name = buttonName
            if not DOM.Buttons[name] then
                name = DOM.buttonNameMap:Get(buttonName)
            end
            if DOM.Buttons[name].ExitEditMode then
                DOM.Buttons[name]:ExitEditMode()
            end
        else
            local dropTarget = DOM.Buttons[buttonName]
            -- print("Handling exit edit mode for", buttonName, dropTarget and dropTarget:GetName())
            if dropTarget then
                -- Hide overlay
                if dropTarget.overlay then
                    dropTarget.overlay:Hide()
                end

                -- If the drop target has no child button, remove it
                if not dropTarget.childButton then
                    DOM:DestroyButton(dropTarget)
                else
                    -- Disable mouse interaction and movement for used drop targets
                    dropTarget:SetMovable(false)
                    dropTarget:EnableMouse(false)
                end
            end
        end
    end
end

function DOM:ToggleEditMode()
    if DOM.editMode then
        DOM:ExitEditMode()
    else
        DOM:EnterEditMode()
        
    end
end

function DOM:CreateKeyButtons()
    if not DOM.editMode then return end

    for i=1, DOM.maxButtons do
        local buttonName = DOM.dropBaseName .. i
        if not DOM.Buttons[buttonName] then
            DOM:CreateDropTarget(buttonName, i)
        end
    end
end

function DOM:CreateDropTarget(buttonName, buttonNum)
    buttonNum = buttonNum or 1
    local buttonPos = buttonNum - 1
    -- CreateFrame("Button", buttonName, UIParent, "UIPanelButtonTemplate,BackdropTemplate")
    -- LAB:CreateButton(buttonName, buttonName, DOM_drop) 
    local dropTarget = CreateFrame("Button", buttonName, UIParent, "BackdropTemplate")
    dropTarget.isBoundButton = true

    DOM.Buttons[buttonName] = dropTarget
    
    dropTarget:SetSize(DOM.buttonSize, DOM.buttonSize)

    -- if DOM_savedPositions[buttonName] then
    --     DOM:ButtonSetPoint(dropTarget, buttonName)
    -- else
    local row = math.floor(DOM.maxButtons / 12)
    local col  = buttonPos % 12
    local offsetX = (col - 6) * DOM.buttonSize
    local offsetY = row * DOM.buttonSize
    dropTarget:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    -- end

    dropTarget:SetText(tostring(buttonNum))
    dropTarget:EnableMouse(true)

    -- Optional: Visual feedback when hovering over drop target.
    dropTarget:SetScript("OnEnter", function(self)
        self:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background" })
        if LibKeyBound then
            -- print("KeyBound: ", buttonName, " is bound to: ", self:GetHotkey())
            LibKeyBound:Set(self)
        end
    end)

    dropTarget:SetScript("OnLeave", function(self)
        self:SetBackdrop(nil)
    end)

    dropTarget:RegisterForDrag("LeftButton")

    dropTarget:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        dropTarget:StartMoving()
    end)
    dropTarget:SetScript("OnDragStop", function(self)
        dropTarget:StopMovingOrSizing()
        saveButtonPosition(dropTarget)
    end)

    DOM:AddKeyboundScritps(dropTarget)

    -- Make button movable out of combat
    dropTarget:SetMovable(DOM.editMode)
    dropTarget:RegisterForDrag("LeftButton")
    dropTarget:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    dropTarget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveButtonPosition(self)
    end)

    dropTarget:RegisterEvent("PLAYER_REGEN_ENABLED")
    dropTarget:SetScript("OnEvent", function(self, event, key, state)

    end
    )
    

end


local lastPickConsumablesTime = 0
local lastBagUpdate = 0
local bagUpdateCooldown = 0.1
local cooldownPeriod = 0.1 -- seconds

local function amIaDruid()
    if IsClassicWow() then
        local _, class = UnitClass("player")
        return class == "DRUID"
    end
    return false
end

local function clearButtons()
    if InCombatLockdown() then return end
    local buttonsToRemove = {}
    -- First identify buttons to remove
    for buttonName, button in pairs(DOM.Buttons) do
        if button.itemName and not button.isPinned then
            local itemCount = GetItemCount(button.itemName, false, false)
            if itemCount == 0 and not button.isPinned and not button.hasAura then
                buttonsToRemove[buttonName] = button
            end
        end
    end
    -- Then remove them
    for buttonName, button in pairs(buttonsToRemove) do
        DOM:DestroyButton(button)
    end
end

local function _sortTable(table_to_sort)
    local _table = {}
    for itemName, rank in pairs(table_to_sort) do
        table.insert(_table, { name = itemName, rank = rank })
    end
    table.sort(_table, function(a, b) return a.rank < b.rank end)
    local sorted_table = {}
    for _, item in ipairs(_table) do
        table.insert(sorted_table, item.name)
    end
    return sorted_table

end

local function sortConsumables()
    local sorted_drinks = _sortTable(bestConsumables.drink)
    local sorted_conjured_drinks = _sortTable(bestConsumables.conjuredDrink)
    local sorted_healing_potions = _sortTable(bestConsumables.healingPotion)
    local sorted_specific_healing_potions = _sortTable(bestConsumables.specificHealing)
    local sorted_mana_potions = _sortTable(bestConsumables.manaPotion)
    local sorted_specific_mana_potions = _sortTable(bestConsumables.specificMana)
    local sorted_healthstones = _sortTable(bestConsumables.healthStone)
    local sorted_mana_gems = _sortTable(bestConsumables.manaGem)
    local sorted_nb_foods = _sortTable(bestConsumables.nb_foods)
    local sorted_conjured_nb_foods = _sortTable(bestConsumables.conjured_nb_foods)
    local sorted_percent_foods = _sortTable(bestConsumables.percent_foods)
    local sorted_alcohol = _sortTable(bestConsumables.alcohol)

    if DEBUG then
        for _, itemName in ipairs(sorted_drinks) do
            debugmsg("Sorted drink: " .. itemName)
        end
        for _, itemName in ipairs(sorted_conjured_drinks) do
            debugmsg("Sorted conjured drink: " .. itemName)
        end
    end

    return sorted_drinks, sorted_conjured_drinks, sorted_healing_potions, sorted_specific_healing_potions, sorted_mana_potions, sorted_specific_mana_potions, sorted_healthstones, sorted_mana_gems, sorted_nb_foods, sorted_conjured_nb_foods, sorted_percent_foods, sorted_alcohol
end


function DOM:createButtons()
    if InCombatLockdown() then return end
    if DOM.runningButtonCreation then return end
    DOM.runningButtonCreation = true
    
    -- Save current buttons that need to be cleared
    clearButtons()
    DOM.buffToButton = {}
    
    -- Rest of button creation logic
    local sorted_drinks, sorted_conjured_drinks, sorted_healing_potions, sorted_specific_healing_potions, sorted_mana_potions, sorted_specific_mana_potions, sorted_healthstones, sorted_mana_gems, sorted_nb_foods, sorted_conjured_nb_foods, sorted_percent_foods, sorted_alcohol = sortConsumables()
    
    if sorted_drinks or sorted_conjured_drinks then
            createDrinkButton(1, false, sorted_drinks, "DrinkOMaticDrinkButton", sorted_conjured_drinks)
    end

    if sorted_healing_potions or sorted_specific_healing_potions then
        createDrinkButton(2, DOM_DRUID, sorted_healing_potions, "DrinkOMaticHealingPotionButton", sorted_specific_healing_potions)
    end

    if sorted_nb_foods or sorted_conjured_nb_foods then
        createDrinkButton(1, false, sorted_nb_foods, "DrinkOMaticEatButton", sorted_conjured_nb_foods)
    end

    if sorted_percent_foods then
        createDrinkButton(1, false, sorted_percent_foods, "DrinkOMaticPEatButton")
    end

    if sorted_alcohol then
        createDrinkButton(1, false, sorted_alcohol, "DrinkOMaticDrunkButton")
    end

    if sorted_mana_potions or sorted_specific_mana_potions then
        createDrinkButton(3, DOM_DRUID, sorted_mana_potions, "DrinkOMaticManaPotionButton", sorted_specific_mana_potions)
    end

    if sorted_healthstones then
        createDrinkButton(4, DOM_DRUID, sorted_healthstones, "DrinkOMaticHealthStoneButton")
  
    end

    if sorted_mana_gems then
        createDrinkButton(5, false, sorted_mana_gems, "DrinkOMaticManaGemButton")
    end

    if bestConsumables.scrolls then
        for _, itemName in ipairs(bestConsumables.scrolls) do
            createDrinkButton(DOM.itemIDMap[itemName], false, {itemName}, "DrinkOMaticScrollButton" .. itemName)
        end
    end

    if bestConsumables.foods then
        for _, itemName in ipairs(bestConsumables.foods) do
            createDrinkButton(DOM.itemIDMap[itemName], false, {itemName}, "DrinkOMaticFoodButton" .. itemName)
        end
    end

    if bestConsumables.other then
        for _, itemName in ipairs(bestConsumables.other) do
            createDrinkButton(DOM.itemIDMap[itemName], DOM_DRUID, {itemName}, "DrinkOMaticCombatPotionButton" .. itemName)
        end
    end

    DOM:UpdateAuras()

    if not InCombatLockdown() then
        DOM.updateNeeded = false
    end  
    DOM.runningButtonCreation = false
end

local function selectForm()
    if not DOM_DRUID then return end
    -- Create the parent frame
    local frameWidth = 96
    local frameHeight = 32
    local buttonSize = 32

    local frame = DOM.Buttons["MyShapeshiftFrame"] or CreateFrame("Frame", "MyShapeshiftFrame", UIParent)
    DOM.Buttons["MyShapeshiftFrame"] = frame

    frame:SetSize(frameWidth, frameHeight)
    frame:Show()
    frame:SetMovable(true)

    if DOM_savedPositions["MyShapeshiftFrame"] then
        frame:SetPoint(unpack(DOM_savedPositions["MyShapeshiftFrame"]))
    else
        frame:SetPoint("CENTER")
    end

    if frame.buttons then
        for k, button in pairs(frame.buttons) do
        DOM:DestroyButton(button)
        frame.buttons[k] = nil
        end
    end

    -- Create buttons
    frame.buttons =  frame.buttons or {}

    -- Interface\\ICONS\\9XP_Sigil_Ardenweald01
    -- Function to create a button
    local function createButton(iconTexture, spellID)
        if not spellID then return end
        local name = "Form" .. spellID
        local button = DOM.Buttons[name] or CreateFrame("Button", name, frame)
        button.spellID = spellID
        button:SetSize(buttonSize, buttonSize)
        button:SetNormalTexture(iconTexture)
        
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(spellID)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        button.frame = frame
        -- Enable mouse interaction and dragging
        button:EnableMouse(true)
        button:SetMovable(true)
        button:RegisterForDrag("LeftButton")

        button:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            self.frame:StartMoving()
        end)
        button:SetScript("OnDragStop", function(self)
            self.frame:StopMovingOrSizing()
            saveButtonPosition(frame)
        end)

        -- Create border
        local border = button.border
        if not border then
            border = button:CreateTexture(nil, "BACKGROUND")
        end
        border:SetSize(buttonSize, buttonSize + 4)
        border:SetPoint("CENTER")
        border:SetColorTexture(1, 0.84, 0, 1) -- Yellow border color
        border:Hide()
        button.border = border

        button:RegisterEvent("MODIFIER_STATE_CHANGED")
        button:SetScript("OnEvent", function(self, event, key, state)
            if InCombatLockdown() then return end
            if event == "MODIFIER_STATE_CHANGED" then
                if IsAltKeyDown() then
                    button.border:Hide()
                    button:GetNormalTexture():SetDesaturated(true)
                else
                    if button.spellID == getFormID() then
                        button.border:Show()
                        button:GetNormalTexture():SetDesaturated(false)
                    else
                        button.border:Hide()
                        button:GetNormalTexture():SetDesaturated(true)
                    end
                end
            end
        end)

        frame.buttons[spellID] = button
        DOM.Buttons[name] = button
        return button
    end

    -- Function to desaturate all buttons except the clicked one
    local function desaturateAll(exceptButton)
        for _, button in pairs(frame.buttons) do
            if button == exceptButton then
                button:GetNormalTexture():SetDesaturated(false)
                button.border:Show()
            else
                button:GetNormalTexture():SetDesaturated(true)
                button.border:Hide()
            end
        end
    end

    local bearButton = nil
    local catButton = nil
    local moonkinButton = nil
    -- Check for Dire Bear Form or Bear Form
    local bearSpellID = IsSpellKnown(direBearFormSpellID) and direBearFormSpellID or IsSpellKnown(bearFormSpellID) and bearFormSpellID or nil
    if bearSpellID then
        bearButton = createButton(GetSpellTexture(bearSpellID), bearSpellID)
        bearButton:SetPoint("LEFT", frame, "LEFT", 0, 0)
        bearButton:SetScript("OnClick", function(self)
            if InCombatLockdown() then return end
            desaturateAll(self)
            DOM_ReturnToForm = DOM_BEAR
            -- print(DOM_ReturnToForm)
            DOM:createButtons()
        end)
    end

    -- Check for Cat Form
    if IsSpellKnown(catFormSpellID) then
        catButton = createButton(GetSpellTexture(catFormSpellID), catFormSpellID)
        catButton:SetPoint("LEFT", (bearButton or frame), "RIGHT", 0, 0)
        catButton:SetScript("OnClick", function(self)
            if InCombatLockdown() then return end
            desaturateAll(self)
            DOM_ReturnToForm = DOM_CAT
            -- print(DOM_ReturnToForm)
            DOM:createButtons()
        end)
    end

    -- Check for Moonkin Form
    if IsSpellKnown(moonkinSpellID) then
        moonkinButton = createButton(GetSpellTexture(moonkinSpellID), moonkinSpellID)
        moonkinButton:SetPoint("LEFT", (catButton or bearButton or frame), "RIGHT", 0, 0)
        moonkinButton:SetScript("OnClick", function(self)
            if InCombatLockdown() then return end
            desaturateAll(self)
            DOM_ReturnToForm = DOM_MOONKIN
            -- print(DOM_ReturnToForm)
            DOM:createButtons()
        end)
    end

    -- Initial desaturation setup
    local bearID = getBearID()
    if bearID and frame.buttons[bearID] then
        desaturateAll(frame.buttons[bearID])
    else
        desaturateAll(frame.buttons, nil)
    end

end


local function ThrottledPickConsumables()
    local currentTime = GetTime()
    if (currentTime - lastPickConsumablesTime) < cooldownPeriod then return end
    if InCombatLockdown() then return end
    
    bestConsumables = GetBestConsumables()

    lastPickConsumablesTime = currentTime

    DOM:createButtons()

end

function DOM:UpdateCooldown(button)
    if not button.itemName then return false end
    local itemID = DOM:GetItemID(button.itemName)
    if itemID then
        local start, duration, enable = C_Container.GetItemCooldown(itemID)
        local onCooldown = IsOnCooldown(start, duration)
        if onCooldown then
            if not button.isDesaturated then
                button.buttonTexture:SetDesaturated(true)
                button.isDesaturated = true
            end
            if not button.cooldownStarted then
                button.cooldownStarted = true
		        CooldownFrame_Set(button.cooldown, start, duration, enable)
            end
            return true
        else
            button.buttonTexture:SetDesaturated(false)
            button.isDesaturated = false
            button.cooldownStarted = false
        end
    end
    return false 
end

local update_cooldowns_progress = false
function DOM:UpdateCooldowns()
    if not update_cooldowns_progress then
        update_cooldowns_progress = true
        for actualButtonName, button in pairs(DOM.Buttons) do
            DOM:UpdateCooldown(button)
        end
        update_cooldowns_progress = false
    end
end

function DOM:UpdateAuras()
    -- 1. Build a table of active auras, keyed by buffID (spellId)
    local activeAuras = {}
    local i = 1
    while true do
        local name, icon, count, debuffType, duration, expirationTime, 
              unitCaster, isStealable, nameplateShowPersonal, spellId = UnitAura("player", i)
        if not name then break end

        -- Only consider auras with a valid duration of at least 1 second and a valid spellId
        if duration and duration >= 1 and spellId then
            activeAuras[spellId] = {
                name = name,
                icon = icon,
                duration = duration,
                expirationTime = expirationTime,
                startTime = expirationTime - duration,
                spellId = spellId,
                -- Optional: add an explicit 'priority' field here if needed.
                priority = nil,
            }
        end
        i = i + 1
    end

    -- 2. Group the active auras by button using DOM.buffToButton (buffID -> buttonName)
    local buttonAuras = {}
    for buffID, buttonNames in pairs(self.buffToButton) do
        local auraData = activeAuras[buffID]
        if auraData then
            for _, buttonName in ipairs(buttonNames) do
                if not buttonAuras[buttonName] then
                    buttonAuras[buttonName] = {}
                end
                table.insert(buttonAuras[buttonName], auraData)
            end
        end
    end

    -- 3. For each button, select the highest priority aura and update the display.
    for buttonName, auraList in pairs(buttonAuras) do
        local buttonFrame = self.Buttons and self.Buttons[buttonName]
        if buttonFrame then
            -- Sort the auras so that the highest priority one comes first.
            table.sort(auraList, function(a, b)
                if a.priority and b.priority then
                    return a.priority > b.priority
                elseif a.priority then
                    return true
                elseif b.priority then
                    return false
                else
                    return a.duration < b.duration
                end
            end)

            local highestAura = auraList[1]
            if highestAura then
                -- Create or update the aura icon texture.
                if not buttonFrame.auraTexture then
                    buttonFrame.auraTexture = buttonFrame:CreateTexture(nil, "OVERLAY")
                    buttonFrame.auraTexture:SetAllPoints(buttonFrame)
                end
                buttonFrame.auraTexture:SetTexture(highestAura.icon)
                buttonFrame.auraTexture:Show()

                -- Create or update the cooldown overlay.
                if not buttonFrame.auraCooldown then
                    buttonFrame.auraCooldown = CreateFrame("Cooldown", nil, buttonFrame, "CooldownFrameTemplate")
                    buttonFrame.auraCooldown:SetAllPoints(buttonFrame)
                    if CE then
                        buttonFrame.auraCooldown:SetSwipeTexture(CE.CIRCLE_GREEN)
                        buttonFrame.auraCooldown:SetSwipeColor(1,1,1,1)
                        buttonFrame.auraCooldown.noTextureOverride = true
                    end
                end
                CooldownFrame_Set(buttonFrame.auraCooldown, highestAura.startTime, highestAura.duration, true)
                buttonFrame.auraCooldown:Show()
                buttonFrame.hasAura = true
            end
        end
    end

    -- 4. For any buttons that have no active auras, clear/hide any previous aura display.
    if self.Buttons then
        for buttonName, buttonFrame in pairs(self.Buttons) do
            if not buttonAuras[buttonName] then
                if buttonFrame.auraTexture then
                    buttonFrame.auraTexture:Hide()
                    buttonFrame.auraTexture:SetTexture(nil)
                    buttonFrame.hasAura = false
                end
                if buttonFrame.auraCooldown then
                    buttonFrame.auraCooldown:Hide()
                end
            end
        end
    end
end

function DOM_Initialize(self)
    -- Only subscribe to inventory updates once we're in the world
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_LEAVING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA") -- Event for entering an instance or new area
    self:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND") -- Event for entering a battleground
    self:RegisterEvent("PLAYER_REGEN_ENABLED") -- Event for entering an arena
    -- self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    self:RegisterEvent("LEARNED_SPELL_IN_TAB")
    self:RegisterEvent("UNIT_AURA")
end



function DOM_OnEvent(self, event, arg1, arg2)
    if ( event == "PLAYER_ENTERING_WORLD" ) then

        selectForm()

		self:RegisterEvent("BAG_UPDATE")
		if (InCombatLockdown()) then

		else
            C_Timer.After(10, ThrottledPickConsumables)
		end
		return;

	elseif ( event == "PLAYER_LEAVING_WORLD" ) then

		self:UnregisterEvent("BAG_UPDATE")

	elseif (event == "BAG_UPDATE" ) then
		if (arg1 < 0 or arg1 > 4) then return end	-- don't bother looking in keyring, bank, etc for food
		if (DOM_IsSpecialBag(arg1)) then return end	-- don't look in bags that can't hold food, either
        
        DOM.updateNeeded = true

        ThrottledPickConsumables()

        if not InCombatLockdown() then
            DOM:createButtons()
        end

    elseif (event == "PLAYER_REGEN_ENABLED") then
        if DOM.updateNeeded then
            DOM:createButtons()
        end

    elseif (event == "UNIT_AURA" and arg1 == "player") then
        DOM:UpdateAuras()

    elseif (event == "LEARNED_SPELL_IN_TAB") then
        selectForm()
    end
end

-- function DOM:OnEnable(first)
--     print("DrinkOMatic enabling...", first)
-- 	-- LibKeyBound.RegisterCallback(self, "LIBKEYBOUND_ENABLED")
-- 	-- LibKeyBound.RegisterCallback(self, "LIBKEYBOUND_DISABLED")
-- 	-- LibKeyBound.RegisterCallback(self, "LIBKEYBOUND_MODE_COLOR_CHANGED")
-- end

function DOM:OnInitialize()
    DOM.callbacks = DOM.callbacks or LibStub("CallbackHandler-1.0"):New(DOM)

    DOM.buttonNameMap = TwoWayMap:new(DOM_BoundToNames, DOM_RealNames, "GetBoundToName", "GetRealName")

    DOM:CreateFrame()
    DOM_DRUID = amIaDruid()
    get_tables()
    makeCategoriesTable()

    local name = "Drink-o-Matic"
    _G["BINDING_HEADER_DOMHEAD"] = name
    for k=1,12 do
        _G[("BINDING_NAME_CLICK DOMButton%d:Keybind"):format(k)] = ("%s %s"):format(name, L["Button %s"]:format(k))

        -- _G[("BINDING_NAME_CLICK DOMButton%d"):format(k)] = ("%s %s"):format(name, L["Button %s"]:format(k))
    end

end

function DOM:PrintButtonNames()
    for name, _ in pairs (DOM.Buttons) do
        print(name)
    end
end

function DOM:OnEnable()
    print("DrinkOMatic is enabled...")
    
    DOM:RegisterCallback("DraggingUpdate", function(event, x, y)
        debugmsg("DraggingUpdate event received! X:", x, "Y:", y)
        DOM:CheckDropTargetOverlap(x, y)
    end)

    if CE then
        print("Cooldown Edge addon detected!")
    else
        print("Cooldown Edge addon not found, skipping enhancements.")
    end

end

local function showDomHelp()
    print("Usage: /dom <option>")
    print("Available options:")
    print("  kb    - Toggle keybind mode")
    print("  edit  - Toggle edit mode")
end

function DrinkOMatic_OnLoad(self)
    DOM_Initialize(self)
    
    SLASH_DOM1 = "/dom"
    SlashCmdList["DOM"] = function(msg)
        local cmd = (msg or ""):match("^%s*(.-)%s*$")

        if cmd == "" then
            showDomHelp()
        elseif cmd == "kb" then
            print("Toggling keybind mode")
            LibKeyBound:Toggle()
        elseif cmd == "edit" then
            print("Toggling edit mode")
            DOM:ToggleEditMode()
        elseif cmd == "list" then
            DOM:PrintButtonNames()
        else
            print("Unknown command: " .. cmd)
            showDomHelp()
        end
    end
end


