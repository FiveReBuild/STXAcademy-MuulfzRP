local lang = vRP.lang
local cfg = module("cfg/inventory")

-- this module define the player inventory (lost after respawn, as wallet)

vRP.items = {}

-- define an inventory item (call this at server start) (parametric or plain text data)
-- idname: unique item name
-- name: display name or genfunction
-- description: item description (html) or genfunction
-- choices: menudata choices (see gui api) only as genfunction or nil
-- weight: weight or genfunction
--
-- genfunction are functions returning a correct value as: function(args) return value end
-- where args is a list of {base_idname,arg,arg,arg,...}
function vRP.defInventoryItem(idname, name, description, choices, weight,imgUrl, model)
    if weight == nil then
        weight = 0
    end
    if model == nil then
        model = 2491058022
    end

    local item = { name = name, description = description, choices = choices, weight = weight, img = imgUrl, model = model }

    vRP.items[idname] = item
end

-- give action
function ch_give(idname, player, choice)
    local user_id = vRP.getUserId(player)
    if user_id then
        -- get nearest player
        local nplayer = vRPclient.getNearestPlayer(player, 10)
        if nplayer then
            local nuser_id = vRP.getUserId(nplayer)
            if nuser_id then
                -- prompt number
                local amount = vRP.prompt(player, lang.inventory.give.prompt({ vRP.getInventoryItemAmount(user_id, idname) }), "")
                local amount = parseInt(amount)
                -- weight check
                local new_weight = vRP.getInventoryWeight(nuser_id) + vRP.getItemWeight(idname) * amount
                if new_weight <= vRP.getInventoryMaxWeight(nuser_id) then
                    if vRP.tryGetInventoryItem(user_id, idname, amount, true) then
                        vRP.giveInventoryItem(nuser_id, idname, amount, true)

                        vRPclient._playAnim(player, true, { { "mp_common", "givetake1_a", 1 } }, false)
                        vRPclient._playAnim(nplayer, true, { { "mp_common", "givetake2_a", 1 } }, false)
                    else
                        vRPclient._notify(player, lang.common.invalid_value())
                    end
                else
                    vRPclient._notify(player, lang.inventory.full())
                end
            else
                vRPclient._notify(player, lang.common.no_player_near())
            end
        else
            vRPclient._notify(player, lang.common.no_player_near())
        end
    end
end

-- trash action
function ch_trash(idname, player, choice)
    local user_id = vRP.getUserId(player)
    if user_id then
        -- prompt number
        local amount = vRP.prompt(player, lang.inventory.trash.prompt({ vRP.getInventoryItemAmount(user_id, idname) }), "")
        local amount = parseInt(amount)
        if vRP.tryGetInventoryItem(user_id, idname, amount, false) then
            vRPclient._notify(player, lang.inventory.trash.done({ vRP.getItemName(idname), amount }))
            vRPclient._playAnim(player, true, { { "pickup_object", "pickup_low", 1 } }, false)

            local x, y, z = vRPclient.getPosition(player)
            HudRP.createDrop(player, vRP.getItemModel(idname), x, y, z, idname, amount)
        else
            vRPclient._notify(player, lang.common.invalid_value())
        end
    end
end

function vRP.computeItemName(item, args)
    if type(item.name) == "string" then
        return item.name
    else
        return item.name(args)
    end
end

function vRP.computeItemDescription(item, args)
    if type(item.description) == "string" then
        return item.description
    else
        return item.description(args)
    end
end

function vRP.computeItemChoices(item, args)
    if item.choices ~= nil then
        return item.choices(args)
    else
        return {}
    end
end

function vRP.computeItemWeight(item, args)
    if type(item.weight) == "number" then
        return item.weight
    else
        return item.weight(args)
    end
end

function vRP.computeItemModel(item, args)
    local itemModelType = type(item.model)
    if itemModelType == "string" then
        return GetHashKey(item.model)
    elseif itemModelType == "function" then
        return item.model(args)
    else
        return item.model
    end
end

function vRP.parseItem(idname)
    return splitString(idname, "|")
end

-- return name, description, weight
function vRP.getItemDefinition(idname)
    local args = vRP.parseItem(idname)
    local item = vRP.items[args[1]]
    if item then
        return vRP.computeItemName(item, args), vRP.computeItemDescription(item, args), vRP.computeItemWeight(item, args)
    end

    return nil, nil, nil
end

function vRP.getItemName(idname)
    local args = vRP.parseItem(idname)
    local item = vRP.items[args[1]]
    if item then
        return vRP.computeItemName(item, args)
    end
    return args[1]
end

function vRP.getItemDescription(idname)
    local args = vRP.parseItem(idname)
    local item = vRP.items[args[1]]
    if item then
        return vRP.computeItemDescription(item, args)
    end
    return ""
end

function vRP.getItemChoices(idname)
    local args = vRP.parseItem(idname)
    local item = vRP.items[args[1]]
    local choices = {}
    if item then
        -- compute choices
        local cchoices = vRP.computeItemChoices(item, args)
        if cchoices then
            -- copy computed choices
            for k, v in pairs(cchoices) do
                choices[k] = v
            end
        end

        -- add give/trash choices
        choices[lang.inventory.give.title()] = { function(player, choice)
            ch_give(idname, player, choice)
        end, lang.inventory.give.description() }
        choices[lang.inventory.trash.title()] = { function(player, choice)
            ch_trash(idname, player, choice)
        end, lang.inventory.trash.description() }
    end

    return choices
end

function vRP.getItemWeight(idname)
    local args = vRP.parseItem(idname)
    local item = vRP.items[args[1]]
    if item then
        return vRP.computeItemWeight(item, args)
    end
    return 0
end

function vRP.getItemModel(idname)
    local args = vRP.parseItem(idname)
    local item = vRP.items[args[1]]
    if item then
        return vRP.computeItemModel(item, args)
    end
end

-- compute weight of a list of items (in inventory/chest format)
function vRP.computeItemsWeight(items)
    local weight = 0

    for k, v in pairs(items) do
        local iweight = vRP.getItemWeight(k)
        weight = weight + iweight * v.amount
    end

    return weight
end

-- add item to a connected user inventory
function vRP.giveInventoryItem(user_id, idname, amount, notify)
    if notify == nil then
        notify = true
    end -- notify by default

    local data = vRP.getUserDataTable(user_id)
    if data and amount > 0 then
        local entry = data.inventory[idname]
        if entry then
            -- add to entry
            entry.amount = entry.amount + amount
        else
            -- new entry
            data.inventory[idname] = { amount = amount }
        end

        -- notify
        if notify then
            local player = vRP.getUserSource(user_id)
            if player then
                vRPclient._notify(player, lang.inventory.give.received({ vRP.getItemName(idname), amount }))
            end
        end
    end
end

-- try to get item from a connected user inventory
function vRP.tryGetInventoryItem(user_id, idname, amount, notify)
    if notify == nil then
        notify = true
    end -- notify by default

    local data = vRP.getUserDataTable(user_id)
    if data and amount > 0 then
        local entry = data.inventory[idname]
        if entry and entry.amount >= amount then
            -- add to entry
            entry.amount = entry.amount - amount

            -- remove entry if <= 0
            if entry.amount <= 0 then
                data.inventory[idname] = nil
            end

            -- notify
            if notify then
                local player = vRP.getUserSource(user_id)
                if player then
                    vRPclient._notify(player, lang.inventory.give.given({ vRP.getItemName(idname), amount }))
                end
            end

            return true
        else
            -- notify
            if notify then
                local player = vRP.getUserSource(user_id)
                if player then
                    local entry_amount = 0
                    if entry then
                        entry_amount = entry.amount
                    end
                    vRPclient._notify(player, lang.inventory.missing({ vRP.getItemName(idname), amount - entry_amount }))
                end
            end
        end
    end

    return false
end

-- get item amount from a connected user inventory
function vRP.getInventoryItemAmount(user_id, idname)
    local data = vRP.getUserDataTable(user_id)
    if data and data.inventory then
        local entry = data.inventory[idname]
        if entry then
            return entry.amount
        end
    end

    return 0
end

-- get connected user inventory
-- return map of full idname => amount or nil 
function vRP.getInventory(user_id)
    local data = vRP.getUserDataTable(user_id)
    if data then
        return data.inventory
    end
end

-- return user inventory total weight
function vRP.getInventoryWeight(user_id)
    local data = vRP.getUserDataTable(user_id)
    if data and data.inventory then
        return vRP.computeItemsWeight(data.inventory)
    end

    return 0
end

-- return maximum weight of the user inventory
function vRP.getInventoryMaxWeight(user_id)
    return math.floor(vRP.expToLevel(vRP.getExp(user_id, "physical", "strength"))) * cfg.inventory_weight_per_strength
end

-- clear connected user inventory
function vRP.clearInventory(user_id)
    local data = vRP.getUserDataTable(user_id)
    if data then
        data.inventory = {}
    end
end

-- init inventory
AddEventHandler("vRP:playerJoin", function(user_id, source, name, last_login)
    local data = vRP.getUserDataTable(user_id)
    if not data.inventory then
        data.inventory = {}
    end
end)

