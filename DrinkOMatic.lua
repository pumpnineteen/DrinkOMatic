local addonName, DM = ...
local DMH = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")

-- Initialize localization
local L = LibStub("AceLocale-3.0"):GetLocale("DrinkOMatic")
-- local NL = LibStub("AceLocale-3.0"):GetLocale("GatheringTooltipNodes")

local AceGUI = LibStub("AceGUI-3.0")
local LibBagUtils = LibStub("LibBagUtils-1.0")


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
    3823,   -- Lesser Invisibility Potion
    9172,   -- Invisibility Potion
    12190,  -- Dreamless Sleep Potion
    20002,  -- Greater Dreamless Sleep Potion
    4366,  -- Target Dummy
    4392,  -- Advanced Target Dummy
    16023,  -- Masterwork Target Dummy
}

local druid_exception_names = {}
for _, itemID in ipairs(druid_exceptions) do
    local itemName = GetItemInfoInstant(itemID)
    if itemName then
        druid_exception_names[itemName] = true
    else
        -- print("Item not found: ", itemID)
    end
end


-- print("We are classical: ", IsClassicWow())

local itemCategories = {}

DOM_Buttons = {}
DOM_BEAR = "BEAR"
DOM_CAT = "CAT"
DOM_MOONKIN = "MOONKIN"
DOM_ReturnToForm = DOM_BEAR
DOM_DRUID = false

local DEBUG_SHOWMACROTEXT = false
local DEBUG = false

local drinks
local conjured_drinks
local healing_potions
local mana_potions
local specific_healing_potions
local specific_mana_potions
local mana_gems
local healthstones
local scrolls
local foods
local other_consumables

local function get_tables()
    if IsClassicWow() or IsTBCWow() then
        drinks = tbc_drinks
        conjured_drinks = tbc_conjured_drinks
        healing_potions = tbc_healing_potions
        mana_potions = tbc_mana_potions
        specific_healing_potions = tbc_specific_healing_potions
        specific_mana_potions = tbc_specific_mana_potions
        healthstones = tbc_healthstones
        scrolls = tbc_scrolls
        foods = tbc_foods
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
    addUnorderedCategory(scrolls, "Scroll")
    addUnorderedCategory(foods, "Food")
    addUnorderedCategory(other_consumables, "Other")
end

DOM_savedPositions = DOM_savedPositions or {} -- Table to store button positions

local function saveButtonPosition(button)
    local point, relativeTo, relativePoint, xOffs, yOffs = button:GetPoint()
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

local bestConsumables = { 
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
        other = {},
    }

-- Find the best healing potion in your bags
local function GetBestConsumables()
    -- print("Finding consumables...")
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
        other = {},
    }
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(itemID)
                local itemData = itemCategories[itemID]
                if itemData then
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


local function createDrinkButton(keybind, itemNames, buttonName, altItemNames)
    -- print("CreateDrinkButton... ", itemName, buttonName)
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

    local itemName = (itemNames and itemNames[1]) or nil -- Use the first item name for the button
    local altItemName = (altItemNames and altItemNames[1]) or nil -- Use the first item name for the button

    itemName = itemName or altItemName or nil
    
    if not itemName then return end

    if DEBUG_SHOWMACROTEXT then
        print("Creating button: ", buttonName, " for item: ", itemName, " alt:", altItemName)
        print("\n" .. macrotext)
    end

    -- print(macrotext)

    -- Create a secure action button
    local button = DOM_Buttons[buttonName] or CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
    button.itemName = itemName
    DOM_Buttons[buttonName] = button
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", macrotext)
    
    -- Restore saved position or default to center
    if DOM_savedPositions[buttonName] then
        button:SetPoint(unpack(DOM_savedPositions[buttonName]))
    else
        button:SetPoint("CENTER")
    end

    button:SetSize(32, 32)
    
    -- Set the button texture and icon
    local itemTexture = GetItemIcon(itemName)
    local itemID = GetItemInfoInstant(itemName)

    local altTexture = nil
    local altItemID = nil
    if altItemName then
        altTexture = GetItemIcon(altItemName)
        altItemID = GetItemInfoInstant(altItemName)
    end

    local buttonTexture = button.buttonTexture
    if not buttonTexture then
        buttonTexture = button:CreateTexture(nil, "ARTWORK")
        button.buttonTexture = buttonTexture
    end

    if altTexture then
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
    end)
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Create and set the count text
    local count = button.count
    if not count then
        count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        button.count = count
    end
    
    local function setStackText(item, altitem)
        local _item = altitem or item
        if IsControlKeyDown() then
            _item = item
        end
        local itemCount = GetItemCount(_item, false, true)
        button.count:SetText(itemCount)
    end

    setStackText(itemName, altItemName)

    -- Update the item count after the macro runs
    button:HookScript("OnClick", function()
        setStackText(itemName, altItemName)
    end)

    button:RegisterEvent("MODIFIER_STATE_CHANGED")
    button:RegisterEvent("PLAYER_REGEN_ENABLED")
    button:RegisterEvent("BAG_UPDATE_COOLDOWN")

    button:SetScript("OnEvent", function(self, event, key, state)
        -- if InCombatLockdown() then return end
        if event == "PLAYER_REGEN_ENABLED" or event == "MODIFIER_STATE_CHANGED" then
            if IsControlKeyDown() then
                -- Alt is pressed
                button.buttonTexture:SetTexture(itemTexture)
                setStackText(itemTexture)

            else
                -- Alt is released
                if altItemName then
                    button.buttonTexture:SetTexture(itemTexture)
                    setStackText(itemName)
                end
            end
        end
    end)

    -- Create and set the cooldown frame
    local cooldown = button.cooldown
    if not cooldown then
        cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetSwipeColor(0, 0, 0, 0)
        cooldown:SetAllPoints()
        button.cooldown = cooldown
    end


    -- Update the cooldown frame when events occur
    button:SetScript("OnEvent", function(self, event)
        if event == "BAG_UPDATE_COOLDOWN" or event == "PLAYER_REGEN_ENABLED" then
            local start, duration, enable = C_Container.GetItemCooldown(itemID)
            CooldownFrame_Set(button.cooldown, start, duration, enable)
            button.cooldown:SetSwipeColor(0, 0, 0, 0)
        elseif event == "MODIFIER_STATE_CHANGED" then
            -- if InCombatLockdown() then return end
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
    end)


    button:Show()

    -- Make button movable out of combat
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveButtonPosition(self)
    end)

    if keybind then
        -- Assign a key bind to the button
        SetBindingClick(keybind, button:GetName())

        -- Save the bindings
        SaveBindings(GetCurrentBindingSet())
    end
end

local function createDruidPotButton(keybind, itemNames, buttonName, altItemNames)
    local itemName = (itemNames and itemNames[1]) or nil -- Use the first item name for the button
    local altItemName = (altItemNames and altItemNames[1]) or nil -- Use the first item name for the button

    itemName = itemName or altItemName or nil
    
    if not itemName then return end

    if druid_exception_names[itemName] then
        return createDrinkButton(keybind, itemNames, buttonName, altItemNames)
    end
    if not (IsSpellKnown(direBearFormSpellID) or IsSpellKnown(bearFormSpellID) or IsSpellKnown(catFormSpellID) or IsSpellKnown(moonkinSpellID)) then
        return createDrinkButton(keybind, itemNames, buttonName, altItemNames)
    end

    -- print("CreateDruidDrinkButton... ", itemName, buttonName)
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
    macrotext = macrotext .. "/stopmacro [mod:alt] " .. "\n" ..
                             "/cast " .. getFormName()

    if DEBUG_SHOWMACROTEXT then
        print("Creating button: ", buttonName, " for item: ", itemName)
        print(itemNames)
        for _, item in ipairs(itemNames) do
            print(item)
        end
        print("\n" .. macrotext)
    end
    -- print(macrotext)

    -- Create a secure action button
    local button = DOM_Buttons[buttonName] or CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
    button.itemName = itemName
    DOM_Buttons[buttonName] = button
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", macrotext)
    
    -- Restore saved position or default to center
    if DOM_savedPositions[buttonName] then
        button:SetPoint(unpack(DOM_savedPositions[buttonName]))
    else
        button:SetPoint("CENTER")
    end

    button:SetSize(32, 32)
    
    -- Set the button texture and icon
    local itemTexture = GetItemIcon(itemName)
    local itemID = GetItemInfoInstant(itemName)

    local altTexture = nil
    local altItemID = nil

    if altItemName then
        altTexture = GetItemIcon(altItemName)
        altItemID = GetItemInfoInstant(altItemName)
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
    end)
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Create and set the count text
    local count = button.count
    if not count then
        count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        button.count = count
    end
    
    local function setStackText(item, altitem)
        local _item = altitem or item
        if IsControlKeyDown() then
            _item = item
        end
        local itemCount = GetItemCount(_item, false, true)
        button.count:SetText(itemCount)
    end

    setStackText(itemName, altItemName)

    -- Update the item count after the macro runs
    button:HookScript("OnClick", function()
        setStackText(itemName, altItemName)
    end)

    -- Handle modifier key state to change the texture
    button:RegisterEvent("MODIFIER_STATE_CHANGED")
    button:RegisterEvent("PLAYER_REGEN_ENABLED")
    button:RegisterEvent("BAG_UPDATE_COOLDOWN")
    button:SetScript("OnEvent", function(self, event, key, state)
        if event == "BAG_UPDATE_COOLDOWN" or event == "PLAYER_REGEN_ENABLED" then
            local start, duration, enable = C_Container.GetItemCooldown(itemID)
            CooldownFrame_Set(button.cooldown, start, duration, enable)
        end
        if event == "MODIFIER_STATE_CHANGED" then
            if IsAltKeyDown() then
                button.form:Hide()
            else
                button.form:Show()
            end
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
        -- if InCombatLockdown() then return end
        if event == "PLAYER_REGEN_ENABLED" or event == "MODIFIER_STATE_CHANGED" then
            button.buttonTexture:SetTexture(itemTexture)
            setStackText(itemName, altItemName)
        end
    end
    )

    -- Create and set the cooldown frame
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetSwipeColor(0, 0, 0, 0)
    button.cooldown:SetAllPoints()
    local start, duration, enable = C_Container.GetItemCooldown(itemID)
    CooldownFrame_Set(button.cooldown, start, duration, enable)

    button:Show()

    -- Make button movable out of combat
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveButtonPosition(self)
    end)

    if keybind then
        -- Assign a key bind to the button
        SetBindingClick(keybind, button:GetName())

        -- Save the bindings
        SaveBindings(GetCurrentBindingSet())
    end
end


local lastPickConsumablesTime = 0
local cooldownPeriod = 2 -- seconds

local function amIaDruid()
    if IsClassicWow() then
        local _, class = UnitClass("player")
        return class == "DRUID"
    end
    return false
end

local function clearButtons()
    if InCombatLockdown() then return end
    for buttonName, button in pairs(DOM_Buttons) do
        if button.itemName then 
            local itemCount = GetItemCount(button.itemName, false, false)
            if itemCount == 0 then
                button:Hide()
                button:UnregisterAllEvents()
                button:SetParent(nil)
                button = nil
                DOM_Buttons.buttonName = nil
            end
        end
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

    if DEBUG then
        for _, itemName in ipairs(sorted_drinks) do
            print("Sorted drink: " .. itemName)
        end
        for _, itemName in ipairs(sorted_conjured_drinks) do
            print("Sorted conjured drink: " .. itemName)
        end
    end

    return sorted_drinks, sorted_conjured_drinks, sorted_healing_potions, sorted_specific_healing_potions, sorted_mana_potions, sorted_specific_mana_potions, sorted_healthstones, sorted_mana_gems
end


local function createButtons()
    if InCombatLockdown() then return end
    clearButtons()
    -- print("Creating buttons...")
    -- Create a button for the best drink

    local sorted_drinks, sorted_conjured_drinks, sorted_healing_potions, sorted_specific_healing_potions, sorted_mana_potions, sorted_specific_mana_potions, sorted_healthstones, sorted_mana_gems = sortConsumables()
    
    if sorted_drinks or sorted_conjured_drinks then
            createDrinkButton(nil, sorted_drinks, "DrinkOMaticDrinkButton", sorted_conjured_drinks)
    end

    if sorted_healing_potions or sorted_specific_healing_potions then
        if DOM_DRUID then
            createDruidPotButton(nil, sorted_healing_potions, "DrinkOMaticHealingPotionButton", sorted_specific_healing_potions)
        else
            createDrinkButton(nil, sorted_healing_potions, "DrinkOMaticHealingPotionButton", sorted_specific_healing_potions)
        end
    end

    if sorted_mana_potions or sorted_specific_mana_potions then
        if DOM_DRUID then
            createDruidPotButton(nil, sorted_mana_potions, "DrinkOMaticManaPotionButton", sorted_specific_mana_potions)
        else
            createDrinkButton(nil, sorted_mana_potions, "DrinkOMaticManaPotionButton", sorted_specific_mana_potions)
        end
    end

    if sorted_healthstones then
        if DOM_DRUID then
            createDruidPotButton(nil, sorted_healthstones, "DrinkOMaticHealthStoneButton")
        else
            createDrinkButton(nil, sorted_healthstones, "DrinkOMaticHealthStoneButton")
        end
        
    end

    if sorted_mana_gems then
        createDrinkButton(nil, sorted_mana_gems, "DrinkOMaticManaGemButton")
    end

    if bestConsumables.scrolls then
        for _, itemName in ipairs(bestConsumables.scrolls) do
            createDrinkButton(nil, {itemName}, "DrinkOMaticScrollButton" .. itemName)
        end
    end

    if bestConsumables.foods then
        for _, itemName in ipairs(bestConsumables.foods) do
            createDrinkButton(nil, {itemName}, "DrinkOMaticFoodButton" .. itemName)
        end
    end

    if bestConsumables.other then
        for _, itemName in ipairs(bestConsumables.other) do
            if DOM_DRUID then
                createDruidPotButton(nil, {itemName}, "DrinkOMaticCombatPotionButton" .. itemName)
            else
                createDrinkButton(nil, {itemName}, "DrinkOMaticCombatPotionButton" .. itemName)
            end
        end
    end
end

local function selectForm()
    if not DOM_DRUID then return end
    -- Create the parent frame
    local frameWidth = 96
    local frameHeight = 32
    local buttonSize = 32

    local frame = DOM_Buttons["MyShapeshiftFrame"] or CreateFrame("Frame", "MyShapeshiftFrame", UIParent)
    DOM_Buttons["MyShapeshiftFrame"] = frame

    frame:SetSize(frameWidth, frameHeight)
    frame:Show()
    frame:SetMovable(true)

    if DOM_savedPositions["MyShapeshiftFrame"] then
        frame:SetPoint(unpack(DOM_savedPositions["MyShapeshiftFrame"]))
    else
        frame:SetPoint("CENTER")
    end

    -- Create buttons
    local buttons = {}

    -- Function to create a button
    local function createButton(iconTexture, spellID)
        if not spellID then return end
        local name = "Form" .. spellID
        local button = DOM_Buttons[name] or CreateFrame("Button", name, frame)
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

        buttons[spellID] = button
        DOM_Buttons[name] = button
        return button
    end

    -- Function to desaturate all buttons except the clicked one
    local function desaturateAll(exceptButton)
        for _, button in pairs(buttons) do
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
            createButtons()
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
            createButtons()
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
            createButtons()
        end)
    end

    -- Initial desaturation setup
    local bearID = getBearID()
    if bearID and buttons[bearID] then
        desaturateAll(buttons[bearID])
    else
        desaturateAll(buttons, nil)
    end

end


local function ThrottledPickConsumables()
    local currentTime = GetTime()
    if (currentTime - lastPickConsumablesTime) < cooldownPeriod then return end
    
    bestConsumables = GetBestConsumables()
    if bestConsumables.conjuredDrink then
        -- print("Best conjured: " .. bestConsumables.conjuredDrink.name)
    end
    if bestConsumables.drink and bestConsumables.drink.name then
        -- print("Best drink: " .. bestConsumables.drink.name)
    end
    lastPickConsumablesTime = currentTime

    createButtons()

end


function DOM_Initialize(self)
    -- Only subscribe to inventory updates once we're in the world
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_LEAVING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA") -- Event for entering an instance or new area
    self:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND") -- Event for entering a battleground
    print("DOM initialized...")
end



function DOM_OnEvent(self, event, arg1, arg2)
    if ( event == "PLAYER_ENTERING_WORLD" ) then

        selectForm()

		self:RegisterEvent("BAG_UPDATE")
		if (InCombatLockdown()) then
			DOM_PickFoodQueued = true
		else
            C_Timer.After(10, ThrottledPickConsumables)
		end
		return;

	elseif ( event == "PLAYER_LEAVING_WORLD" ) then

		self:UnregisterEvent("BAG_UPDATE")

	elseif (event == "BAG_UPDATE" ) then

		if (arg1 < 0 or arg1 > 4) then return; end	-- don't bother looking in keyring, bank, etc for food
		if (DOM_IsSpecialBag(arg1)) then return; end	-- don't look in bags that can't hold food, either

		DOM_PickFoodQueued = true
        ThrottledPickConsumables()
    end
end


function DrinkOMatic_OnLoad(self)
    DOM_Initialize(self)
    DOM_DRUID = amIaDruid()
    get_tables()
    makeCategoriesTable()
    -- SLASH_DRINKOMATIC1 = "/drinkomatic"
    -- SlashCmdList["DRINKOMATIC"] = UseBestDrink
end

