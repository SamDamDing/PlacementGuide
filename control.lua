-- -----------------------------------------------------------------------------
-- CONSTANTS

local PG_GUIDE_ITEM_NAME = "pg-guide"
local DEFAULT_MIN_GUIDE_MARGIN = 3

local unsupported_entity_types = {
    ["artillery-wagon"] = true,
    ["car"] = true,
    ["cargo-wagon"] = true,
    ["fluid-wagon"] = true,
    ["locomotive"] = true,
    ["spidertron"] = true,
    ["tank"] = true,
    ["spidertron"] = true
}

-- -----------------------------------------------------------------------------
-- UTILITY FUNCTIONS

-- Ensure `global` and its subtables are properly initialized
local function ensure_global_initialized()
    global = global or {}
    global.players = global.players or {}
end

-- Fetch player-specific settings
local function get_player_setting(player, setting_name, default_value)
    local setting = settings.get_player_settings(player)[setting_name]
    return setting and setting.value or default_value
end

-- Get the minimum guide margin from settings
local function get_min_guide_margin(player)
    return get_player_setting(player, "placement-guide-min-guide-margin", DEFAULT_MIN_GUIDE_MARGIN)
end

-- Fetch dimensions of an area
local function get_dimensions(area)
    return {
        height = math.abs(area.right_bottom.y - area.left_top.y),
        width = math.abs(area.right_bottom.x - area.left_top.x)
    }
end

-- Check the player's cursor stack for a valid item or ghost
local function check_stack(player)
    local cursor_stack = player.cursor_stack
    local cursor_ghost = player.cursor_ghost
    if cursor_stack and cursor_stack.valid_for_read then
        if cursor_stack.name == PG_GUIDE_ITEM_NAME then
            local icon = cursor_stack.preview_icons[1]
            if icon then
                return icon.signal.name, true
            else
                player.clear_cursor()
            end
        else
            return cursor_stack.name
        end
    elseif cursor_ghost then
        return cursor_ghost.name, false, true
    end
    return nil
end

-- Set the label for the cursor stack
local function set_label(player, item_name, is_ghost)
    local count = player.get_main_inventory().get_item_count(item_name)
    player.cursor_stack.label = is_ghost and "[img=utility/ghost_cursor]" or tostring(count)
    return count
end

-- Set up the guide blueprint
local function setup_guide(player, item_name, entity_prototype, orientation, is_ghost)
    local min_margin = get_min_guide_margin(player)
    local dimensions = get_dimensions(entity_prototype.selection_box)
    local cursor_stack = player.cursor_stack

    cursor_stack.set_stack{name = PG_GUIDE_ITEM_NAME}
	
	local position
    local guide_margin
	if orientation == 0 then
      guide_margin = math.max(dimensions.width, min_margin)
      position = {(dimensions.width + (guide_margin * 2) / 2) - (dimensions.width / 2), dimensions.height / 2}
    elseif orientation == 1 then
      guide_margin = math.max(dimensions.height, min_margin)
      position = {dimensions.width / 2, (dimensions.height + (guide_margin * 2) / 2) - (dimensions.height / 2)}
    end
    

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

-- Check if positions are different
local function positions_different(pos1, pos2)
    return pos1.x ~= pos2.x or pos1.y ~= pos2.y
end

-- -----------------------------------------------------------------------------
-- EVENT HANDLERS

script.on_init(function()
    ensure_global_initialized()
end)

script.on_event(defines.events.on_player_created, function(e)
    ensure_global_initialized()
    global.players[e.player_index] = {
        building = false,
        is_ghost = false,
        last_error_position = {x = 0, y = 0},
        orientation = 0
    }
end)

script.on_event(defines.events.on_player_removed, function(e)
    ensure_global_initialized()
    global.players[e.player_index] = nil
end)

script.on_event("pg-activate-guide", function(e)
    ensure_global_initialized()

    local player = game.get_player(e.player_index)
    local player_table = global.players[e.player_index] or {
        building = false,
        is_ghost = false,
        last_error_position = {x = 0, y = 0},
        orientation = 0
    }

    global.players[e.player_index] = player_table

    local item_name, is_guide, is_ghost = check_stack(player)
    if not item_name then return end

    local item_prototype = prototypes.item[item_name]
    if not item_prototype or not item_prototype.place_result then
        player.print({"placement-guide.error-no-placeable-entity", item_name})
        return
    end

    if is_guide then
        player.clear_cursor()
        player_table.orientation = math.abs(player_table.orientation - 1)
        setup_guide(player, item_name, item_prototype.place_result, player_table.orientation, player_table.is_ghost)
    else
        setup_guide(player, item_name, item_prototype.place_result, 0, is_ghost)
        player_table.is_ghost = is_ghost
        player_table.orientation = 0
    end
end)

script.on_event(defines.events.on_pre_build, function(e)
    ensure_global_initialized()

    if e.shift_build then return end

    local player = game.get_player(e.player_index)
    local _, is_guide = check_stack(player)
    if is_guide then
        global.players[e.player_index] = global.players[e.player_index] or {
            building = false,
            is_ghost = false,
            last_error_position = {x = 0, y = 0},
            orientation = 0
        }
        global.players[e.player_index].building = true
    end
end)

script.on_event(defines.events.on_built_entity, function(e)
    ensure_global_initialized()

    if not e.entity then
        game.print({"placement-guide.error-no-entity-created"})
        return
    end

    local entity = e.entity
    local player = game.get_player(e.player_index)
    local player_table = global.players[e.player_index]

    if not player_table then return end

    ---if entity.name == "entity-ghost" then
    ---    game.print({"placement-guide.ghost-placed", entity.ghost_name or "unknown"})
    ---    return
    ---end

    if player_table.building then
        player_table.building = false

        local item_name = check_stack(player)
        if not item_name then return end

        local required_count
        local prototype = prototypes.entity[entity.name]
        if prototype and prototype.items_to_place_this then
            for _, stack in ipairs(prototype.items_to_place_this) do
                if stack.name == item_name then
                    required_count = stack.count
                    break
                end
            end
        end

        if not required_count then return end

        local main_inventory = player.get_main_inventory()
        local item_count = main_inventory.get_item_count(item_name)
        if item_count >= required_count then
            main_inventory.remove{name = item_name, count = required_count}
        end
    end
end)

script.on_event(defines.events.on_player_main_inventory_changed, function(e)
    ensure_global_initialized()

    local player = game.get_player(e.player_index)
    local player_table = global.players[e.player_index] or {
        building = false,
        is_ghost = false,
        last_error_position = {x = 0, y = 0},
        orientation = 0
    }

    global.players[e.player_index] = player_table

    local item_name, is_guide = check_stack(player)
    if is_guide and not player_table.is_ghost then
        local new_count = set_label(player, item_name)
        if new_count == 0 then
            player.clear_cursor()
        end
    end
end)
