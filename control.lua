-- -----------------------------------------------------------------------------
-- UTILITIES

-- Initialize `global` and `global.players` if they are not already
local function ensure_global_initialized()
    global = global or {}
    global.players = global.players or {}
end

-- Unsupported entity types for the guide
local unsupported_entity_types = {
    ["artillery-wagon"] = true,
    ["car"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["locomotive"] = true,
    ["spidertron"] = true,
    ["tank"] = true
}

-- Get the item currently in the cursor stack or ghost
local function check_stack(player)
    local cursor_stack = player.cursor_stack
    local cursor_ghost = player.cursor_ghost

    if cursor_stack and cursor_stack.valid_for_read then
        if cursor_stack.name == "pg-guide" and cursor_stack.preview_icons[1] then
            return cursor_stack.preview_icons[1].signal.name, true
        end
        return cursor_stack.name
    elseif cursor_ghost then
        return cursor_ghost.name, false, true
    end

    return nil
end

-- Set the label on the cursor stack
local function set_label(player, item_name, is_ghost)
    local count = player.get_main_inventory().get_item_count(item_name)
    player.cursor_stack.label = is_ghost and "[img=utility/ghost_cursor]" or tostring(count)
    return count
end

-- Get dimensions from a bounding box
local function get_dimensions(area)
    return {
        height = math.abs(area.right_bottom.y - area.left_top.y),
        width = math.abs(area.right_bottom.x - area.left_top.x)
    }
end

-- Get the minimum guide margin from player settings
local function get_min_guide_margin(player)
    return settings.get_player_settings(player)["placement-guide-min-guide-margin"].value
end

-- Setup the guide blueprint
local function setup_guide(player, item_name, entity_prototype, orientation, is_ghost)
    local min_margin = get_min_guide_margin(player)
    local dimensions = get_dimensions(entity_prototype.selection_box)
    local cursor_stack = player.cursor_stack

    cursor_stack.set_stack{name = "pg-guide"}
    local guide_margin = math.max(orientation == 0 and dimensions.width or dimensions.height, min_margin)
    local position = orientation == 0
        and {x = (dimensions.width + guide_margin * 2) / 2 - dimensions.width / 2, y = dimensions.height / 2}
        or {x = dimensions.width / 2, y = (dimensions.height + guide_margin * 2) / 2 - dimensions.height / 2}

    cursor_stack.set_blueprint_entities{
        {entity_number = 1, name = entity_prototype.name, position = position}
    }

    cursor_stack.blueprint_snap_to_grid = {
        x = dimensions.width + (guide_margin * (orientation == 0 and 2 or 0)),
        y = dimensions.height + (guide_margin * (orientation == 1 and 2 or 0))
    }

    cursor_stack.preview_icons = {{signal = {type = "item", name = item_name}, index = 1}}
    set_label(player, item_name, is_ghost)
end

-- -----------------------------------------------------------------------------
-- EVENT HANDLERS

-- Initialize global tables on mod load
script.on_init(function()
    ensure_global_initialized()
    for _, player in pairs(game.players) do
        global.players[player.index] = {
            building = false,
            is_ghost = false,
            last_error_position = {x = 0, y = 0},
            orientation = 0
        }
    end
end)

-- Handle guide activation
script.on_event("pg-activate-guide", function(e)
    ensure_global_initialized()
    local player = game.get_player(e.player_index)
    local player_table = global.players[e.player_index] or {
        building = false,
        is_ghost = false,
        last_error_position = {x = 0, y = 0},
        orientation = 0
    }

    local item_name, is_guide, is_ghost = check_stack(player)
    if item_name then
        local item_prototype = prototypes.item[item_name]
        if not item_prototype then
            player.print("Error: Item prototype not found for " .. item_name)
            return
        end

        local entity_prototype = item_prototype.place_result
        if not entity_prototype then
            player.print("Error: No placeable entity for item " .. item_name)
            return
        end

        player.clear_cursor()
        player_table.orientation = is_guide and math.abs(player_table.orientation - 1) or 0
        setup_guide(player, item_name, entity_prototype, player_table.orientation, is_ghost)
        player_table.is_ghost = is_ghost
    end

    global.players[e.player_index] = player_table
end)

-- Handle pre-build actions
script.on_event(defines.events.on_pre_build, function(e)
    ensure_global_initialized()
    if e.shift_build then return end

    local player = game.get_player(e.player_index)
    local _, is_guide = check_stack(player)
    if is_guide then
        global.players[e.player_index] = global.players[e.player_index] or {}
        global.players[e.player_index].building = true
    end
end)

-- Handle built entities
script.on_event(defines.events.on_built_entity, function(e)
    ensure_global_initialized()

    local player = game.get_player(e.player_index)
    local player_table = global.players[e.player_index]
    if not player_table or not e.entity then return end

    -- Handle ghost entities
    --if e.entity.name == "entity-ghost" then
    --    game.print("Placed ghost for: " .. (e.entity.ghost_name or "unknown"))
    --    return
    --end

    -- Handle actual entities
    if player_table.building then
        player_table.building = false
        local item_name = check_stack(player)
        if not item_name then return end

        local required_count = nil
        local prototype = prototypes.entity[e.entity.name]
        if prototype and prototype.items_to_place_this then
            for _, stack in ipairs(prototype.items_to_place_this) do
                if stack.name == item_name then
                    required_count = stack.count
                    break
                end
            end
        end

        if required_count and player.get_main_inventory().get_item_count(item_name) >= required_count then
            player.get_main_inventory().remove{name = item_name, count = required_count}
        end
    end
end)

-- Handle inventory changes
script.on_event(defines.events.on_player_main_inventory_changed, function(e)
    ensure_global_initialized()
    local player = game.get_player(e.player_index)
    local player_table = global.players[e.player_index] or {}

    local item_name, is_guide = check_stack(player)
    if is_guide and not player_table.is_ghost then
        if set_label(player, item_name) == 0 then
            player.clear_cursor()
        end
    end
end)

-- Handle player creation
script.on_event(defines.events.on_player_created, function(e)
    ensure_global_initialized()
    global.players[e.player_index] = {
        building = false,
        is_ghost = false,
        last_error_position = {x = 0, y = 0},
        orientation = 0
    }
end)

-- Handle player removal
script.on_event(defines.events.on_player_removed, function(e)
    ensure_global_initialized()
    global.players[e.player_index] = nil
end)
