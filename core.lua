-- TODO: Add optional sound alert, chat alert for wishlist,favorites,custom in itemref, loot, lootroll
-- 
ItemHints = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceDB-2.0", "AceEvent-2.0", "AceHook-2.1", "FuBarPlugin-2.0")
local D = AceLibrary("Dewdrop-2.0")
local DF = AceLibrary("Deformat-2.0")
local T = AceLibrary("Tablet-2.0")
local gratuity = AceLibrary("Gratuity-2.0")
local L = AceLibrary("AceLocale-2.2"):new("ItemHints")

ItemHints.hexColorQuality = {}
for i=-1,6 do
  ItemHints.hexColorQuality[ITEM_QUALITY_COLORS[i].hex] = i
end

local empty = {}
local defaults = {
  Active = true,
  WishList = true,
  GearSet = true,
  Favorite = false,
  Custom = true,
  CustomItems = {},
}
ItemHints._optDeps = {
  GearSet  = {"ItemRack", "Outfitter"},
  WishList = {"AtlasLoot"},
  Favorite = {"pfQuest"},
}
ItemHints.ItemRack_Update = {
  {fn="ItemRack_Sets_Save_OnClick"}, 
  {fn="ItemRack_Sets_Remove_OnClick"}
}
ItemHints.Outfitter_Update = {
  {fn="OutfitterNameOutfit_Done"}, 
  {fn="Outfitter_AddOutfit"},
  {fn="Outfitter_DeleteOutfit"},
  {fn="Outfitter_RebuildSelectedOutfit"}
}
ItemHints.AtlasLoot_Update = {
  {fn="AtlasLoot_AddToWishlist"}, 
  {fn="AtlasLoot_DeleteFromWishList"}
}
ItemHints.pfQuest_Update = {
  {f="pfQuestBrowser",s="OnHide"}
}
ItemHints._wishlist = {}
ItemHints._gearsets = {}
ItemHints._favorites = {}
local options  = {
  type = "group",
  handler = ItemHints,
  args =
  {
    Active =
    {
      name = L["Active"],
      desc = L["Activate/Suspend 'Item Hints'"],
      type = "toggle",
      get  = "GetActiveStatusOption",
      set  = "SetActiveStatusOption",
      order = 1,
    },
    WishList =
    {
      name = L["WishList"],
      desc = L["Show WishList Hint (requires AtlasLoot)"],
      type = "toggle",
      get  = "GetWishListOption",
      set  = "SetWishListOption",
      hidden = function() return not ItemHints.db.char.Active end,
      order = 2,
    },
    GearSet = 
    {
      name = L["GearSet"],
      desc = L["Show GearSet Hint (requires ItemRack or Outfitter)"],
      type = "toggle",
      get  = "GetGearSetOption",
      set  = "SetGearSetOption",
      hidden = function() return not ItemHints.db.char.Active end,
      order = 3,
    },
    Favorite = 
    {
      name = L["Favorite"],
      desc = L["Show Favorite Hint (requires pfQuest)"],
      type = "toggle",
      get  = "GetFavoriteOption",
      set  = "SetFavoriteOption",
      hidden = function() return not ItemHints.db.char.Active end,
      order = 4,    
    },
    Custom = {
      type = "group",
      handler = ItemHints,
      name = L["Custom"],
      desc = L["Manage Custom Hints"],
      order = 5,
      hidden = function() return not ItemHints.db.char.Active end,
      args = {
        Enable = {
          name = L["Enable"],
          desc = L["Show Custom Hint"],
          type = "toggle",
          get  = "GetCustomOption",
          set  = "SetCustomOption",
          order = 51,
        },
        Add = {
          name = L["Add"],
          desc = L["Add item to Custom"],
          type = "text",
          get  = false,
          set  = "AddToCustom",
          usage = "<itemname>",
          order = 52,
          hidden = function() return not ItemHints.db.char.Custom end,
        },
        Remove = {
          name = L["Remove"],
          desc = L["Remove item from Custom"],
          type = "text",
          get = false,
          set = "RemoveFromCustom",
          usage = "<itemname>",
          validate = empty,
          order = 53,
          hidden = function() return not ItemHints.db.char.Custom end,
        },
      },
    },    
  },
}

---------
-- FuBar
---------
ItemHints.hasIcon = "Interface\\Icons\\INV_ValentinesCard01"
ItemHints.title = L["Item Hints"]
ItemHints.defaultMinimapPosition = 265
ItemHints.defaultPosition = "RIGHT"
ItemHints.cannotDetachTooltip = true
ItemHints.tooltipHiddenWhenEmpty = false
ItemHints.hideWithoutStandby = true
ItemHints.independentProfile = true

function ItemHints:OnInitialize() -- ADDON_LOADED (1)
  self:RegisterDB("ItemHintsDB")
  self:RegisterDefaults("char", defaults )
  self:RegisterChatCommand( { "/itmh", "/itemhint" }, options )
  self.OnMenuRequest = options
  if not FuBar then
    self.OnMenuRequest.args.hide.guiName = L["Hide minimap icon"]
    self.OnMenuRequest.args.hide.desc = L["Hide minimap icon"]
  end 
end

function ItemHints:OnEnable() -- PLAYER_LOGIN (2)
  self.extratip = (self.extratip) or CreateFrame("GameTooltip","ItemHint_tooltip",UIParent,"GameTooltipTemplate")
  -- catch loading of optional dependencies
  self:RegisterEvent("ADDON_LOADED")
  -- hook SetItemRef to add hints to chat links
  self:Hook("SetItemRef")
  -- hook tooltip to add our hints
  self:TipHook()

  self:OptDepInit()

  self:refreshOptions()
end

function ItemHints:OnDisable()
  self:UnregisterAllEvents()
  self:UnhookAll()
end

function ItemHints:OnTooltipUpdate()
  local hint = L["Right-click for Options"]
  T:SetHint(hint)
end

function ItemHints:OnTextUpdate()
  self:SetText(L["Item Hints"])
end

function ItemHints:OnClick()

end

function ItemHints:ItemID(item)
  local itemID,found,_,itemString,is,il
  if (type(item)=="number") then
    itemID = tonumber(item)
  end
  if (type(item)=="string") then
    found,_,is = string.find(item,"^item:(%d+):.+")
    if (found) then 
      itemID = tonumber(is) 
    else
      found,_,il = string.find(item,"^|c%x+|Hitem:(%d+):.+")
      if (found) then
        itemID = tonumber(il)
      end
    end
  end
  if (itemID) then
    return itemID
  end
end

function ItemHints:ItemInfo(item)
  local link_found, _, itemColor, itemString, itemName = string.find(item, "^(|c%x+)|H(.+)|h(%[.+%])")
  local itemQuality = self.hexColorQuality[itemColor] or -1
  if link_found then
    return itemName, itemString, itemQuality, itemColor
  end
end

ItemHints._itemCache = setmetatable({},{mode="v"})
function ItemHints:SearchCache(item)
  if self._itemCache[item] then
    return item, self._itemCache[item][1], self._itemCache[item][2], self._itemCache[item][3] 
  end
  for i=34424,1,-1 do
    local itemName, itemString, itemQuality, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(i)
    if itemName then 
      self._itemCache[itemName] = {itemString, itemQuality, ITEM_QUALITY_COLORS[itemQuality].hex} 
    end
    if self._itemCache[item] then
      return item, self._itemCache[item][1], self._itemCache[item][2], self._itemCache[item][3]
    end
  end
end

function ItemHints:AddDataToTooltip(tooltip,itemlink,itemstring)
  if not self.db.char.Active then return end
  local itemID, itemString, _
  local lineCount = 0
  if itemlink then
    _, itemString = self:ItemInfo(itemlink)
    itemID = self:ItemID(itemString)
  elseif itemstring then
    itemID = self:ItemID(itemstring)
    itemString = itemstring
  end
  if not (itemID and itemString) then return end
  ItemHints.extratip:ClearLines()
  ItemHints.extratip:SetOwner(tooltip,"ANCHOR_TOPLEFT", 0, 5)
  local hint
  if self.db.char.WishList and type(self.WishList)=="function" then
    if self._wishlist[itemID] then
      if not hint then
        hint = string.format(L["|cffFF8C00Hint: %s"],L["|cffFF69B4WishList|r"])
        lineCount = lineCount + 1
      end
    end
  end
  if self.db.char.Favorite and type(self.Favorite)=="function" then
    if self._favorites[itemID] then
      if not hint then
        hint = string.format(L["|cffFF8C00Hint: %s"],L["|cff00FFFFFavorite|r"])
        lineCount = lineCount + 1
      else
        hint = string.format("%s, %s",hint,L["|cff00FFFFFavorite|r"])
      end
    end
  end
  if self.db.char.Custom and self:tableCount(self.db.char.CustomItems) > 0 then
    local hashID = tostring(itemID)
    if self.db.char.CustomItems[hashID] then
      if not hint then
        hint = string.format(L["|cffFF8C00Hint: %s"],L["|cffDC143CCustom|r"])
        lineCount = lineCount + 1
      else
        hint = string.format("%s, %s",hint,L["|cffDC143CCustom|r"])
      end
    end
  end
  if (hint) then
    ItemHints.extratip:AddLine(hint)
  end
  if self.db.char.GearSet and type(self.GearSet)=="function" then
    if self._gearsets[itemString] then
      ItemHints.extratip:AddLine(string.format(L["|cffFF8C00GearSets:|r %s"], self._gearsets[itemString]))
      lineCount = lineCount + 1
    end
  end
  if lineCount > 0 then
    ItemHints.extratip:Show()
  end
end

function ItemHints:SetItemRef(link, name, button)
  self.hooks["SetItemRef"](link, name, button)
  if (link and name and ItemRefTooltip) then
    if (strsub(link, 1, 4) == "item") then
      if (ItemRefTooltip:IsVisible()) then
        if (not DressUpFrame:IsVisible()) then
          self:AddDataToTooltip(ItemRefTooltip, link)
        end
      end
    end
  end
end

function ItemHints:TipHook()
  self:SecureHook(GameTooltip, "SetHyperlink", function(this, itemstring)
    ItemHints:AddDataToTooltip(GameTooltip, nil, itemstring)
  end)
  self:SecureHook(GameTooltip, "SetBagItem", function(this, bag, slot)
    local itemLink = GetContainerItemLink(bag, slot)
    if (itemLink) then
      ItemHints:AddDataToTooltip(GameTooltip, itemLink)
    end
  end
  )
  self:SecureHook(GameTooltip, "SetLootItem", function(this, slot)
    ItemHints:AddDataToTooltip(GameTooltip, GetLootSlotLink(slot))
  end
  )
  self:SecureHook(GameTooltip, "SetLootRollItem", function(this, id)
    ItemHints:AddDataToTooltip(GameTooltip, GetLootRollItemLink(id))
  end
  )
  self:SecureHook(GameTooltip, "SetAuctionItem", function(this, type, index)
    ItemHints:AddDataToTooltip(GameTooltip, GetAuctionItemLink(type, index))
  end
  )
  self:SecureHook(GameTooltip, "SetMerchantItem", function(this, id) 
    ItemHints:AddDataToTooltip(GameTooltip, GetMerchantItemLink(id))
  end
  )
  self:SecureHook(GameTooltip, "SetQuestItem", function(this, type, id)
    ItemHints:AddDataToTooltip(GameTooltip, GetQuestItemLink(type, id))
  end
  )
  self:SecureHook(GameTooltip, "SetQuestLogItem", function(this, type, id)
    ItemHints:AddDataToTooltip(GameTooltip, GetQuestLogItemLink(type, id))
  end
  )
  self:SecureHook(GameTooltip, "SetInventoryItem", function(this, unit, slot, nameOnly)
    if unit == "player" and slot > 39 then -- bank item slot
      local itemLink = GetInventoryItemLink("player",slot)
      if (itemLink) then
        ItemHints:AddDataToTooltip(GameTooltip, itemLink)
      end
    end
  end
  )
  self:HookScript(GameTooltip, "OnHide", function()
    if ItemHints.extratip:IsVisible() then ItemHints.extratip:Hide() end
    self.hooks[GameTooltip]["OnHide"]()
  end
  )
  self:HookScript(ItemRefTooltip, "OnHide", function()
    if ItemHints.extratip:IsVisible() then ItemHints.extratip:Hide() end
    self.hooks[ItemRefTooltip]["OnHide"]()
  end
  )
  if (AtlasLootTooltip) then
    self:SecureHook(AtlasLootTooltip, "SetHyperlink", function(this, itemstring)
      ItemHints:AddDataToTooltip(AtlasLootTooltip,nil,itemstring)
    end)
    self:HookScript(AtlasLootTooltip, "OnHide", function()
      if ItemHints.extratip:IsVisible() then ItemHints.extratip:Hide() end
      self.hooks[AtlasLootTooltip]["OnHide"]()
    end)
  end
end

function ItemHints:inTable(tableName, searchString)
  if not searchString then return false end
  for key, value in pairs(tableName) do
    if string.lower(value) == string.lower(searchString) then
      return key
    end
  end
  return nil
end

function ItemHints:tableCount(tableName)
  local count = 0
  for k,v in pairs(tableName) do
    count = count + 1
  end
  return count
end

function ItemHints:wipeTable(tab)
  for k,v in pairs(tab) do
    tab[k]=nil
  end
  for i,v in ipairs(tab) do
    tab[i]=nil
  end
  table.setn(tab,0)
end

function ItemHints:refreshOptions()
  options.args.Custom.args.Remove.validate = self.db.char.CustomItems
end

function ItemHints:GetActiveStatusOption()
  return self.db.char.Active
end
function ItemHints:SetActiveStatusOption(newStatus)
  self.db.char.Active = newStatus
end
function ItemHints:GetWishListOption()
  return self.db.char.WishList
end
function ItemHints:SetWishListOption(newOption)
  self.db.char.WishList = newOption
end
function ItemHints:GetGearSetOption()
  return self.db.char.GearSet
end
function ItemHints:SetGearSetOption(newOption)
  self.db.char.GearSet = newOption
end
function ItemHints:GetFavoriteOption()
  return self.db.char.Favorite
end
function ItemHints:SetFavoriteOption(newOption)
  self.db.char.Favorite = newOption
end
function ItemHints:GetCustomOption()
  return self.db.char.Custom
end
function ItemHints:SetCustomOption(newOption)
  self.db.char.Custom = newOption
end
function ItemHints:AddToCustom(item)
  local itemName, itemString, itemQuality, itemColor = self:SearchCache(item)
  if (itemName and itemString) then
    local itemID = self:ItemID(itemString)
    if itemID then
      local hashID = tostring(itemID)
      if not self.db.char.CustomItems[hashID] then
        self.db.char.CustomItems[hashID] = string.format("%s%s|r",itemColor,itemName)
        self:refreshOptions()
      end      
    end
  end
end
function ItemHints:RemoveFromCustom(item)
  if self.db.char.CustomItems[item] then
    self.db.char.CustomItems[item] = nil
    self:refreshOptions()
  end
end

function ItemHints:OptDepInit()
  for cat, addons in pairs(self._optDeps) do
    if not self[cat] then
      for _,addon in ipairs(addons) do
        if (IsAddOnLoaded(addon)) then
          self[cat] = self[addon]
          if self.db.char[cat] then self[cat]() end
          local hooks = self[string.format("%s_Update",addon)]
          for _,hook in ipairs(hooks) do
            if hook.fn then
              self:SecureHook(hook.fn,self[cat])
            elseif hook.f then
              local frame = getglobal(hook.f)
              self:HookScript(frame, hook.s, self[cat])
            end
          end
          break
        end
      end
    end
  end
end

function ItemHints.ItemRack()
  local self = ItemHints
  self:wipeTable(self._gearsets)
  local profile_name = string.format("%s of %s",(UnitName("player")),(GetRealmName()))
  if Rack_User[profile_name] and Rack_User[profile_name].Sets then
    for setname, set in pairs(Rack_User[profile_name].Sets) do
      if string.find(setname, "^Rack%-") or string.find(setname, "^ItemRack") then
        -- system sets, ignore
      else
        -- user sets
        for slot,item in pairs(set) do
          if type(slot)=="number" and item.id~=0 then
            local itemstring = string.format("item:%s:0",item.id)
            if self._gearsets[itemstring] then
              self._gearsets[itemstring] = string.format("%s, %s", self._gearsets[itemstring], setname)
            else
              self._gearsets[itemstring] = setname
            end
          end
        end
      end
    end
  end
end

function ItemHints.Outfitter()
  local self = ItemHints
  self:wipeTable(self._gearsets)
  -- Partial, Accessory, Special, Complete
  if gOutfitter_Settings and gOutfitter_Settings.Outfits then
    for cat, outfits in pairs(gOutfitter_Settings.Outfits) do
      if table.getn(outfits) > 0 then
        for _,outfit in ipairs(outfits) do
          if self:tableCount(outfit.Items) > 0 then
            local outfitName = outfit.Name
            for slot, item in pairs(outfit.Items) do
              local itemstring = string.format("item:%s:%s:%s:0",item.Code,item.SubCode,item.EnchantCode)
              if self._gearsets[itemstring] then
                self._gearsets[itemstring] = string.format("%s, %s", self._gearsets[itemstring], outfitName)
              else
                self._gearsets[itemstring] = outfitName
              end            
            end
          end
        end
      end
    end
  end
end

function ItemHints.AtlasLoot()
  local self = ItemHints
  self:wipeTable(self._wishlist)
  if AtlasLootCharDB and AtlasLootCharDB.WishList then
    for _,item in ipairs(AtlasLootCharDB.WishList) do
      self._wishlist[item[1]] = true
    end
  end
end

function ItemHints.pfQuest()
  local self = ItemHints
  self:wipeTable(self._favorites)
  if pfBrowser_fav and pfBrowser_fav.items then
    for itemid, _ in pairs(pfBrowser_fav.items) do
      self._favorites[itemid] = true
    end
  end 
end

function ItemHints:ADDON_LOADED()
  self:OptDepInit()
  if (pfUI) and pfUI.api and pfUI.api.CreateBackdrop and pfUI_config and pfUI_config.tooltip and pfUI_config.tooltip.alpha then
    pfUI.api.CreateBackdrop(ItemHints.extratip,nil,nil,pfUI_config.tooltip.alpha)
  end
end