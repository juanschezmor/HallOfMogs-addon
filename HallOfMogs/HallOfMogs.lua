local EXPORT_SLOTS = {
  { slotName = "HEADSLOT", inventorySlotID = INVSLOT_HEAD or 1, outfitSlots = { 0 } },
  { slotName = "SHOULDERSLOT", inventorySlotID = INVSLOT_SHOULDER or 3, outfitSlots = { 1, 2 } },
  { slotName = "BACKSLOT", inventorySlotID = INVSLOT_BACK or 15, outfitSlots = { 3 } },
  { slotName = "CHESTSLOT", inventorySlotID = INVSLOT_CHEST or 5, outfitSlots = { 4 } },
  { slotName = "SHIRTSLOT", inventorySlotID = INVSLOT_BODY or 4, outfitSlots = { 6 } },
  { slotName = "TABARDSLOT", inventorySlotID = INVSLOT_TABARD or 19, outfitSlots = { 5 } },
  { slotName = "WRISTSLOT", inventorySlotID = INVSLOT_WRIST or 9, outfitSlots = { 7 } },
  { slotName = "HANDSSLOT", inventorySlotID = INVSLOT_HAND or 10, outfitSlots = { 8 } },
  { slotName = "WAISTSLOT", inventorySlotID = INVSLOT_WAIST or 6, outfitSlots = { 9 } },
  { slotName = "LEGSSLOT", inventorySlotID = INVSLOT_LEGS or 7, outfitSlots = { 10 } },
  { slotName = "FEETSLOT", inventorySlotID = INVSLOT_FEET or 8, outfitSlots = { 11 } },
  { slotName = "MAINHANDSLOT", inventorySlotID = INVSLOT_MAINHAND or 16, outfitSlots = { 12 } },
  { slotName = "SECONDARYHANDSLOT", inventorySlotID = INVSLOT_OFFHAND or 17, outfitSlots = { 13 } },
}

local CLASS_ARMOR_TYPES = {
  [1] = "plate", -- Warrior
  [2] = "plate", -- Paladin
  [3] = "mail", -- Hunter
  [4] = "leather", -- Rogue
  [5] = "cloth", -- Priest
  [6] = "plate", -- Death Knight
  [7] = "mail", -- Shaman
  [8] = "cloth", -- Mage
  [9] = "cloth", -- Warlock
  [10] = "leather", -- Monk
  [11] = "leather", -- Druid
  [12] = "leather", -- Demon Hunter
  [13] = "mail", -- Evoker
}

local HIDDEN_PLACEHOLDER_ITEM_IDS = {
  TABARDSLOT = {
    [142504] = true, -- Hidden Tabard
  },
}

local exportFrame
local createExportFrame
local playerModelScene
local getOutfitAppearanceItemID
local DRESS_UP_FRAME_MODEL_SCENE_ID = 596
local EXPORT_SCENE_WARMUP_DELAY_SECONDS = 0.15
local EXPORT_FRAME_SUBTITLE =
  "This exports your visible player appearance first. If WoW does not expose it cleanly, it falls back to transmog APIs and finally the equipped item."
local exportRenderRequestID = 0

local function loadBlizzardAddon(name)
  if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, name)
    return
  end

  if UIParentLoadAddOn then
    pcall(UIParentLoadAddOn, name)
  end
end

local function ensureTransmogSupport()
  if TransmogUtil and TransmogUtil.CreateTransmogLocation then
    loadBlizzardAddon("Blizzard_Transmog")
    return
  end

  loadBlizzardAddon("Blizzard_Collections")
  loadBlizzardAddon("Blizzard_InspectUI")
  loadBlizzardAddon("Blizzard_Transmog")
end

local function urlEncode(value)
  if not value or value == "" then
    return ""
  end

  return (value:gsub("([^%w%-_%.~])", function(character)
    return string.format("%%%02X", string.byte(character))
  end))
end

local function getBodyType()
  local sex = UnitSex("player")

  if sex == 3 then
    return "feminine"
  end

  if sex == 2 then
    return "masculine"
  end

  return ""
end

local function getArmorType(classID)
  return CLASS_ARMOR_TYPES[classID] or ""
end

local function normalizeHiddenPlaceholderItemID(slot, itemID)
  if type(itemID) ~= "number" or itemID <= 0 then
    return itemID
  end

  local hiddenItemIDs = slot and HIDDEN_PLACEHOLDER_ITEM_IDS[slot.slotName]
  if hiddenItemIDs and hiddenItemIDs[itemID] then
    return 0
  end

  return itemID
end

local function ensurePlayerModelScene()
  ensureTransmogSupport()

  if not playerModelScene then
    local ok, modelScene = pcall(CreateFrame, "ModelScene", nil, UIParent, "ModelSceneMixinTemplate")
    if not ok or not modelScene then
      return nil
    end

    modelScene:SetSize(1, 1)
    modelScene:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    modelScene:Hide()
    playerModelScene = modelScene
  end

  return playerModelScene
end

local function preparePlayerActor()
  local modelScene = ensurePlayerModelScene()
  if not modelScene then
    return nil
  end

  if modelScene.ClearScene then
    modelScene:ClearScene()
  end

  if modelScene.ReleaseAllActors then
    modelScene:ReleaseAllActors()
  end

  if modelScene.TransitionToModelSceneID then
    modelScene:TransitionToModelSceneID(
      DRESS_UP_FRAME_MODEL_SCENE_ID,
      CAMERA_TRANSITION_TYPE_IMMEDIATE,
      CAMERA_MODIFICATION_TYPE_DISCARD,
      true
    )
  end

  if SetupPlayerForModelScene then
    local _, inAlternateForm = C_PlayerInfo and C_PlayerInfo.GetAlternateFormInfo and C_PlayerInfo.GetAlternateFormInfo()
    local useNativeForm = not inAlternateForm
    local sheatheWeapons = false
    local autoDress = true
    local hideWeapons = false
    SetupPlayerForModelScene(modelScene, nil, nil, sheatheWeapons, autoDress, hideWeapons, useNativeForm)
  end

  if modelScene.GetPlayerActor then
    return modelScene:GetPlayerActor()
  end

  return nil
end

local function getPlayerActor()
  local modelScene = ensurePlayerModelScene()
  if modelScene and modelScene.GetPlayerActor then
    return modelScene:GetPlayerActor()
  end

  return nil
end

local function extractItemIDFromLink(itemLink)
  if type(itemLink) ~= "string" or itemLink == "" then
    return nil
  end

  local itemID = itemLink:match("item:(%d+)")
  if itemID then
    return tonumber(itemID)
  end

  return nil
end

local function getSourceItemID(sourceID)
  if not sourceID or sourceID == 0 then
    return nil
  end

  if C_TransmogCollection and C_TransmogCollection.GetAppearanceSourceInfo then
    local ok, infoOrCategory, _, _, _, _, legacyItemLink = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
    if ok then
      if type(infoOrCategory) == "table" then
        if infoOrCategory.isHideVisual then
          return 0
        end

        if C_TransmogCollection.IsAppearanceHiddenVisual and infoOrCategory.itemAppearanceID then
          local hiddenOk, isHiddenAppearance = pcall(C_TransmogCollection.IsAppearanceHiddenVisual, infoOrCategory.itemAppearanceID)
          if hiddenOk and isHiddenAppearance then
            return 0
          end
        end

        local itemID = extractItemIDFromLink(infoOrCategory.itemLink)
        if itemID and itemID > 0 then
          return itemID
        end
      else
        local itemID = extractItemIDFromLink(legacyItemLink)
        if itemID and itemID > 0 then
          return itemID
        end
      end
    end
  end

  if C_TransmogCollection and C_TransmogCollection.GetSourceItemID then
    local ok, itemID = pcall(C_TransmogCollection.GetSourceItemID, sourceID)
    if ok and itemID and itemID > 0 then
      return itemID
    end
  end

  if C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
    local ok, sourceInfo = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
    if ok and type(sourceInfo) == "table" then
      if sourceInfo.isHideVisual then
        return 0
      end

      if sourceInfo.itemID and sourceInfo.itemID > 0 then
        return sourceInfo.itemID
      end
    end
  end

  return nil
end

local function getAppearanceItemID(appearanceID)
  if type(appearanceID) ~= "number" or appearanceID <= 0 then
    return nil
  end

  if C_TransmogCollection and C_TransmogCollection.IsAppearanceHiddenVisual then
    local hiddenOk, isHiddenAppearance = pcall(C_TransmogCollection.IsAppearanceHiddenVisual, appearanceID)
    if hiddenOk and isHiddenAppearance then
      return 0
    end
  end

  if C_TransmogCollection and C_TransmogCollection.GetAllAppearanceSources then
    local ok, sourceIDs = pcall(C_TransmogCollection.GetAllAppearanceSources, appearanceID)
    if ok and type(sourceIDs) == "table" then
      for _, sourceID in ipairs(sourceIDs) do
        local itemID = getSourceItemID(sourceID)
        if itemID == 0 then
          return 0
        end

        if itemID and itemID > 0 then
          return itemID
        end
      end
    end
  end

  return nil
end

local function extractSourceID(value)
  if type(value) == "number" then
    if value > 0 then
      return value
    end

    return nil
  end

  if type(value) ~= "table" then
    return nil
  end

  local appliedSourceID = value.appliedSourceID
  if type(appliedSourceID) == "number" and appliedSourceID > 0 then
    return appliedSourceID
  end

  local selectedSourceID = value.selectedSourceID
  if type(selectedSourceID) == "number" and selectedSourceID > 0 then
    return selectedSourceID
  end

  local baseSourceID = value.baseSourceID
  if type(baseSourceID) == "number" and baseSourceID > 0 then
    return baseSourceID
  end

  local sourceID = value.sourceID
  if type(sourceID) == "number" and sourceID > 0 then
    return sourceID
  end

  for _, nestedValue in pairs(value) do
    local nestedSourceID = extractSourceID(nestedValue)
    if nestedSourceID then
      return nestedSourceID
    end
  end

  return nil
end

local function getTransmogLocation(slotName)
  ensureTransmogSupport()

  if not (TransmogUtil and Enum and Enum.TransmogType) then
    return nil
  end

  return TransmogUtil.CreateTransmogLocation(slotName, Enum.TransmogType.Appearance, false)
end

local function resolveActorAppearanceItemID(playerActor, slot)
  if not playerActor or not playerActor.GetItemTransmogInfo then
    return nil, nil
  end

  local ok, itemTransmogInfo = pcall(playerActor.GetItemTransmogInfo, playerActor, slot.inventorySlotID)
  if not ok or type(itemTransmogInfo) ~= "table" then
    return nil, nil
  end

  local actorItemID = itemTransmogInfo.itemID
  local sourceID = extractSourceID(itemTransmogInfo)
  local sourceItemID = getSourceItemID(sourceID)
  if sourceItemID == 0 then
    return 0, itemTransmogInfo, actorItemID, sourceID, sourceItemID, nil, nil, "source-hidden"
  end

  if sourceItemID and sourceItemID > 0 then
    return sourceItemID, itemTransmogInfo, actorItemID, sourceID, sourceItemID, nil, nil, "source"
  end

  local appearanceID = itemTransmogInfo.appearanceID
  local appearanceItemID = nil
  if type(appearanceID) == "number" and appearanceID > 0 then
    appearanceItemID = getAppearanceItemID(appearanceID)
    if appearanceItemID == 0 then
      return 0, itemTransmogInfo, actorItemID, sourceID, sourceItemID, appearanceID, appearanceItemID, "appearance-hidden"
    end

    if appearanceItemID and appearanceItemID > 0 then
      return appearanceItemID, itemTransmogInfo, actorItemID, sourceID, sourceItemID, appearanceID, appearanceItemID, "appearance"
    end
  end

  if type(actorItemID) == "number" and actorItemID > 0 then
    return actorItemID, itemTransmogInfo, actorItemID, sourceID, sourceItemID, appearanceID, appearanceItemID, "item"
  end

  return nil, itemTransmogInfo, actorItemID, sourceID, sourceItemID, appearanceID, appearanceItemID, "none"
end

local function getActorAppearanceItemID(slot)
  local playerActor = getPlayerActor()
  if not playerActor then
    return nil, nil
  end

  local itemID, itemTransmogInfo = resolveActorAppearanceItemID(playerActor, slot)
  return itemID, itemTransmogInfo
end

local function inspectActorAppearanceItemID(slot)
  local playerActor = getPlayerActor()
  local itemID, itemTransmogInfo, actorItemID, sourceID, sourceItemID, appearanceID, appearanceItemID, resolution =
    resolveActorAppearanceItemID(playerActor, slot)

  return {
    actorItemID = actorItemID,
    appearanceID = appearanceID,
    appearanceItemID = appearanceItemID,
    itemID = itemID,
    itemTransmogInfo = itemTransmogInfo,
    resolution = resolution or "none",
    sourceID = sourceID,
    sourceItemID = sourceItemID,
  }
end

local function getAppliedTransmogSource(slot)
  local transmogLocation = getTransmogLocation(slot.slotName)
  local locationData = transmogLocation and transmogLocation.GetData and transmogLocation:GetData() or transmogLocation
  local isTransmogrified = false

  if C_Transmog and C_Transmog.GetSlotInfo and transmogLocation then
    local ok, slotIsTransmogrified, _, _, _, _, _, isHideVisual = pcall(C_Transmog.GetSlotInfo, transmogLocation)
    if ok then
      isTransmogrified = slotIsTransmogrified and true or false
      if isHideVisual then
        return nil, true, isTransmogrified
      end
    end
  end

  if C_Transmog and C_Transmog.GetSlotVisualInfo then
    local callVariants = {
      locationData,
    }

    for _, variant in ipairs(callVariants) do
      if variant ~= nil then
        local ok, visualInfoOrBaseSourceID, _, appliedSourceID, _, _, _, _, isHideVisual = pcall(C_Transmog.GetSlotVisualInfo, variant)
        if ok then
          if type(visualInfoOrBaseSourceID) == "table" then
            local visualInfo = visualInfoOrBaseSourceID
            if visualInfo.isHideVisual then
              return nil, true, isTransmogrified
            end

            local resolvedSourceID = extractSourceID(visualInfo)
            if resolvedSourceID then
              return resolvedSourceID, false, isTransmogrified
            end
          else
            if isHideVisual then
              return nil, true, isTransmogrified
            end

            local resolvedSourceID = extractSourceID(appliedSourceID)
            if resolvedSourceID then
              return resolvedSourceID, false, isTransmogrified
            end
          end
        end
      end
    end
  end

  if TransmogUtil and TransmogUtil.GetInfoForEquippedSlot and transmogLocation then
    local ok, slotInfo = pcall(TransmogUtil.GetInfoForEquippedSlot, transmogLocation)
    if ok then
      local appliedSourceID = extractSourceID(slotInfo)
      if appliedSourceID then
        return appliedSourceID, false, isTransmogrified
      end
    end
  end

  return nil, false, isTransmogrified
end

local function getVisibleItemIDForSlot(slot)
  local actorItemID = normalizeHiddenPlaceholderItemID(slot, getActorAppearanceItemID(slot))
  if actorItemID == 0 then
    return 0
  end

  if actorItemID and actorItemID > 0 then
    return actorItemID
  end

  local appliedSourceID, isHidden, isTransmogrified = getAppliedTransmogSource(slot)
  if isHidden then
    return 0
  end

  local transmogItemID = normalizeHiddenPlaceholderItemID(slot, getSourceItemID(appliedSourceID))
  if transmogItemID == 0 then
    return 0
  end

  if transmogItemID and transmogItemID > 0 then
    return transmogItemID
  end

  local outfitItemID = normalizeHiddenPlaceholderItemID(slot, getOutfitAppearanceItemID(slot))
  if outfitItemID == 0 then
    return 0
  end

  if outfitItemID and outfitItemID > 0 then
    return outfitItemID
  end

  if isTransmogrified then
    return 0
  end

  local equippedItemID = GetInventoryItemID("player", slot.inventorySlotID)
  if equippedItemID and equippedItemID > 0 then
    return equippedItemID
  end

  return 0
end

local function buildExportCode(usePreparedActor)
  if not usePreparedActor then
    preparePlayerActor()
  end

  local _, _, classID = UnitClass("player")
  local _, _, raceID = UnitRace("player")
  local bodyType = getBodyType()
  local armorType = getArmorType(classID)
  local characterName = urlEncode(UnitName("player") or "")
  local slotValues = {}

  for _, slot in ipairs(EXPORT_SLOTS) do
    slotValues[#slotValues + 1] = tostring(getVisibleItemIDForSlot(slot))
  end

  return string.format(
    "v2|%d|%d|%s|%s|%s|%s",
    classID or 0,
    raceID or 0,
    bodyType,
    armorType,
    characterName,
    table.concat(slotValues, ",")
  )
end

local function getArrayLength(value)
  if type(value) ~= "table" then
    return 0
  end

  local length = 0
  while value[length + 1] ~= nil do
    length = length + 1
  end

  if length > 0 then
    return length
  end

  for key in pairs(value) do
    if type(key) == "number" and key > length and key % 1 == 0 then
      length = key
    end
  end

  return length
end

local function valueToString(value, depth, seen)
  depth = depth or 0
  seen = seen or {}
  local valueType = type(value)
  if valueType == "nil" then
    return "nil"
  end

  if valueType == "boolean" or valueType == "number" then
    return tostring(value)
  end

  if valueType == "string" then
    if value == "" then
      return '""'
    end

    return value
  end

  if valueType ~= "table" then
    return "<" .. valueType .. ">"
  end

  if seen[value] then
    return "<cycle>"
  end

  if depth >= 2 then
    return "<table>"
  end

  seen[value] = true

  local parts = {}
  local visitedKeys = {}
  local maxArrayIndex = getArrayLength(value)

  if maxArrayIndex > 0 then
    for index = 1, maxArrayIndex do
      visitedKeys[index] = true
      parts[#parts + 1] = "[" .. index .. "]=" .. valueToString(value[index], depth + 1, seen)
    end
  end

  local entries = {}
  for key, fieldValue in pairs(value) do
    if not visitedKeys[key] then
      entries[#entries + 1] = {
        key = key,
        label = tostring(key),
        fieldType = type(fieldValue),
      }
    end
  end

  table.sort(entries, function(a, b)
    return a.label < b.label
  end)

  for _, entry in ipairs(entries) do
    local fieldValue = value[entry.key]
    if fieldValue ~= nil then
      if entry.fieldType == "string" or entry.fieldType == "number" or entry.fieldType == "boolean" then
        parts[#parts + 1] = entry.label .. "=" .. tostring(fieldValue)
      elseif entry.fieldType == "table" then
        parts[#parts + 1] = entry.label .. "=" .. valueToString(fieldValue, depth + 1, seen)
      else
        parts[#parts + 1] = entry.label .. "=<" .. entry.fieldType .. ">"
      end
    end
  end

  seen[value] = nil

  if #parts == 0 then
    return "{}"
  end

  return "{" .. table.concat(parts, ", ") .. "}"
end

local function firstSourceValue(sourceValues)
  if type(sourceValues) ~= "table" then
    return nil
  end

  local maxArrayIndex = getArrayLength(sourceValues)
  for index = 1, maxArrayIndex do
    local sourceValue = sourceValues[index]
    if sourceValue ~= nil then
      return sourceValue
    end
  end

  for _, sourceValue in pairs(sourceValues) do
    return sourceValue
  end

  return nil
end

local function debugSourceValues(sourceValues)
  if type(sourceValues) ~= "table" then
    return valueToString(sourceValues)
  end

  local maxArrayIndex = getArrayLength(sourceValues)
  if maxArrayIndex == 0 then
    return valueToString(sourceValues)
  end

  local parts = {}
  for index = 1, maxArrayIndex do
    parts[#parts + 1] = "[" .. index .. "]=" .. valueToString(sourceValues[index])
  end

  return table.concat(parts, ", ")
end

local function collectCallResults(callable, ...)
  if not callable then
    return nil
  end

  return { pcall(callable, ...) }
end

local function describeCallResults(results)
  if not results then
    return "unavailable"
  end

  if not results[1] then
    return "error=" .. tostring(results[2])
  end

  local parts = {}
  for index = 2, #results do
    parts[#parts + 1] = valueToString(results[index])
  end

  if #parts == 0 then
    return "ok"
  end

  return table.concat(parts, " | ")
end

getOutfitAppearanceItemID = function(slot)
  ensureTransmogSupport()

  if not C_TransmogOutfitInfo then
    return nil, nil, nil
  end

  local activeOutfitID = C_TransmogOutfitInfo.GetActiveOutfitID and C_TransmogOutfitInfo.GetActiveOutfitID()
  if type(activeOutfitID) ~= "number" then
    return nil, nil, nil
  end

  for _, outfitSlot in ipairs(slot.outfitSlots or {}) do
    local ok, sourceIDs = pcall(C_TransmogOutfitInfo.GetSourceIDsForSlot, activeOutfitID, outfitSlot)
    if ok and type(sourceIDs) == "table" then
      local firstValue = firstSourceValue(sourceIDs)
      if firstValue ~= nil and getArrayLength(sourceIDs) == 0 then
        local sourceID = extractSourceID(firstValue) or firstValue
        local itemID = getSourceItemID(sourceID)
        if itemID == 0 then
          return 0, activeOutfitID, outfitSlot
        end

        if itemID and itemID > 0 then
          return itemID, activeOutfitID, outfitSlot
        end
      end

      for index = 1, getArrayLength(sourceIDs) do
        local sourceValue = sourceIDs[index]
        local sourceID = extractSourceID(sourceValue) or sourceValue
        local itemID = getSourceItemID(sourceID)
        if itemID == 0 then
          return 0, activeOutfitID, outfitSlot
        end

        if itemID and itemID > 0 then
          return itemID, activeOutfitID, outfitSlot
        end
      end
    end
  end

  return nil, activeOutfitID, nil
end

local function buildDebugDump(usePreparedActor)
  if not usePreparedActor then
    preparePlayerActor()
  end

  local lines = {
    "Hall of Mogs debug",
    "export=" .. buildExportCode(true),
    "",
  }

  for _, slot in ipairs(EXPORT_SLOTS) do
    local transmogLocation = getTransmogLocation(slot.slotName)
    local locationData = transmogLocation and transmogLocation.GetData and transmogLocation:GetData() or transmogLocation
    local slotInfoResults = collectCallResults(C_Transmog and C_Transmog.GetSlotInfo, transmogLocation)
    local visualInfoBySlotIDResults = collectCallResults(C_Transmog and C_Transmog.GetSlotVisualInfo, slot.inventorySlotID)
    local visualInfoByLocationResults = collectCallResults(C_Transmog and C_Transmog.GetSlotVisualInfo, locationData)
    local equippedInfoResults = collectCallResults(TransmogUtil and TransmogUtil.GetInfoForEquippedSlot, transmogLocation)
    local outfitActiveResults = collectCallResults(C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetActiveOutfitID)
    local activeOutfitID = C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetActiveOutfitID and C_TransmogOutfitInfo.GetActiveOutfitID()
    local outfitSourceResults = {}
    for _, outfitSlot in ipairs(slot.outfitSlots or {}) do
      local getSourceIDsForSlot = C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetSourceIDsForSlot
      if getSourceIDsForSlot then
        local ok, sourceIDs = pcall(getSourceIDsForSlot, activeOutfitID, outfitSlot)
        if ok then
          outfitSourceResults[#outfitSourceResults + 1] = string.format("%d:%s", outfitSlot, debugSourceValues(sourceIDs))
        else
          outfitSourceResults[#outfitSourceResults + 1] = string.format("%d:error=%s", outfitSlot, tostring(sourceIDs))
        end
      else
        outfitSourceResults[#outfitSourceResults + 1] = string.format("%d:unavailable", outfitSlot)
      end
    end
    local actorInspection = inspectActorAppearanceItemID(slot)
    local rawActorItemID = actorInspection.itemID
    local actorItemID = normalizeHiddenPlaceholderItemID(slot, rawActorItemID)
    local outfitItemID = normalizeHiddenPlaceholderItemID(slot, getOutfitAppearanceItemID(slot))
    local playerActor = getPlayerActor()
    local modelTransmogInfoResults = collectCallResults(playerActor and playerActor.GetItemTransmogInfo, playerActor, slot.inventorySlotID)
    local appliedSourceID, isHidden, isTransmogrified = getAppliedTransmogSource(slot)
    local resolvedItemID = getSourceItemID(appliedSourceID)
    local equippedItemID = GetInventoryItemID("player", slot.inventorySlotID)
    local exportedItemID = getVisibleItemIDForSlot(slot)

    lines[#lines + 1] = string.format("%s (%d)", slot.slotName, slot.inventorySlotID)
    lines[#lines + 1] = "  equippedItemID=" .. tostring(equippedItemID or 0)
    lines[#lines + 1] = "  isTransmogrified=" .. tostring(isTransmogrified)
    lines[#lines + 1] = "  isHidden=" .. tostring(isHidden)
    lines[#lines + 1] = "  appliedSourceID=" .. tostring(appliedSourceID or 0)
    lines[#lines + 1] = "  resolvedItemID=" .. tostring(resolvedItemID or 0)
    lines[#lines + 1] = "  rawActorItemID=" .. tostring(rawActorItemID or 0)
    lines[#lines + 1] = "  actorResolution=" .. tostring(actorInspection.resolution)
    lines[#lines + 1] = "  actorItemTransmogInfo.itemID=" .. tostring(actorInspection.actorItemID or 0)
    lines[#lines + 1] = "  actorSourceID=" .. tostring(actorInspection.sourceID or 0)
    lines[#lines + 1] = "  actorSourceItemID=" .. tostring(actorInspection.sourceItemID or 0)
    lines[#lines + 1] = "  actorAppearanceID=" .. tostring(actorInspection.appearanceID or 0)
    lines[#lines + 1] = "  actorAppearanceItemID=" .. tostring(actorInspection.appearanceItemID or 0)
    lines[#lines + 1] = "  actorItemID=" .. tostring(actorItemID or 0)
    lines[#lines + 1] = "  outfitItemID=" .. tostring(outfitItemID or 0)
    lines[#lines + 1] = "  exportedItemID=" .. tostring(exportedItemID or 0)
    lines[#lines + 1] = "  C_TransmogOutfitInfo.GetActiveOutfitID=" .. describeCallResults(outfitActiveResults)
    lines[#lines + 1] = "  manualOutfitSlots=" .. table.concat(slot.outfitSlots or {}, ",")
    lines[#lines + 1] = "  C_TransmogOutfitInfo.GetSourceIDsForSlot=" .. table.concat(outfitSourceResults, " || ")
    lines[#lines + 1] = "  PlayerActor:GetItemTransmogInfo=" .. describeCallResults(modelTransmogInfoResults)
    lines[#lines + 1] = "  GetSlotInfo=" .. describeCallResults(slotInfoResults)
    lines[#lines + 1] = "  GetSlotVisualInfo(slotID)=" .. describeCallResults(visualInfoBySlotIDResults)
    lines[#lines + 1] = "  GetSlotVisualInfo(locationData)=" .. describeCallResults(visualInfoByLocationResults)
    lines[#lines + 1] = "  GetInfoForEquippedSlot=" .. describeCallResults(equippedInfoResults)
    lines[#lines + 1] = ""
  end

  return table.concat(lines, "\n")
end

local function populateFrame(title, subtitleText, content, refreshAction)
  local frame = createExportFrame()
  frame.TitleText:SetText(title)
  frame.subtitle:SetText(subtitleText)
  frame.refreshAction = refreshAction
  frame.editBox:SetText(content)
  frame.editBox:HighlightText()
  frame.editBox:SetFocus()
  frame:Show()
end

createExportFrame = function()
  if exportFrame then
    return exportFrame
  end

  local frame = CreateFrame("Frame", "HallOfMogsExportFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(760, 220)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:Hide()

  frame.TitleText:SetText("Hall of Mogs Export")

  local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", 16, -32)
  subtitle:SetPoint("TOPRIGHT", -16, -32)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText(EXPORT_FRAME_SUBTITLE)

  local scrollFrame = CreateFrame("ScrollFrame", "HallOfMogsExportScrollFrame", frame, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 16, -56)
  scrollFrame:SetPoint("BOTTOMRIGHT", -32, 48)

  local editBox = CreateFrame("EditBox", nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetSize(680, 112)
  editBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    frame:Hide()
  end)

  scrollFrame:SetScrollChild(editBox)

  local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshButton:SetSize(100, 24)
  refreshButton:SetPoint("BOTTOMRIGHT", -120, 16)
  refreshButton:SetText("Refresh")

  local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeButton:SetSize(100, 24)
  closeButton:SetPoint("BOTTOMRIGHT", -16, 16)
  closeButton:SetText("Close")

  refreshButton:SetScript("OnClick", function()
    if frame.refreshAction then
      frame.refreshAction()
    end
  end)

  closeButton:SetScript("OnClick", function()
    frame:Hide()
  end)

  frame.editBox = editBox
  frame.subtitle = subtitle
  exportFrame = frame
  return frame
end

local function showPreparedFrame(title, subtitleText, loadingText, contentBuilder, refreshAction)
  exportRenderRequestID = exportRenderRequestID + 1
  local requestID = exportRenderRequestID

  populateFrame(title, subtitleText, loadingText, refreshAction)
  preparePlayerActor()

  local function renderPreparedContent()
    if requestID ~= exportRenderRequestID then
      return
    end

    populateFrame(title, subtitleText, contentBuilder(true), refreshAction)
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(EXPORT_SCENE_WARMUP_DELAY_SECONDS, renderPreparedContent)
    return
  end

  renderPreparedContent()
end

local function showExportFrame()
  showPreparedFrame(
    "Hall of Mogs Export",
    EXPORT_FRAME_SUBTITLE,
    "Preparing visible appearance...",
    buildExportCode,
    showExportFrame
  )
end

local function showDebugFrame()
  showPreparedFrame(
    "Hall of Mogs Debug",
    "Use this dump to inspect what Blizzard returns for every transmog slot.",
    "Preparing debug dump...",
    buildDebugDump,
    showDebugFrame
  )
end

SLASH_HALLOFMOGS1 = "/hom"
SLASH_HALLOFMOGS2 = "/hallofmogs"
SLASH_HALLOFMOGS3 = "/mogcode"
SlashCmdList.HALLOFMOGS = showExportFrame

SLASH_HALLOFMOGSDEBUG1 = "/homdebug"
SlashCmdList.HALLOFMOGSDEBUG = showDebugFrame
