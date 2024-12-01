data:extend{
  {
    type = "blueprint",
    name = "pg-guide",
    icons = {
      {icon = "__base__/graphics/icons/blueprint.png", icon_size = 64, icon_mipmaps = 4, tint = {r = 1, g = 0.5, b = 1}}
    },
    stack_size = 1,
    flags = {"not-stackable", "only-in-cursor"},
    draw_label_for_cursor_render = true,
    selection_color = {0, 1, 0}, -- Green for selection
    alt_selection_color = {1, 0, 0}, -- Red for alt-selection
    select = { -- Specifies primary selection behavior
      mode = {"any-entity"}, -- Selects any entity
      cursor_box_type = "entity", -- Cursor box for entities
      border_color = {r = 0, g = 1, b = 0, a = 1} -- Green border
    },
    alt_select = { -- Specifies alternate selection behavior
      mode = {"any-tile", "any-entity"}, -- Selects tiles and entities
      cursor_box_type = "blueprint-snap-rectangle", -- Cursor box for tiles
      border_color = {r = 1, g = 0, b = 0, a = 1} -- Red border
    },
    always_include_tiles = false, -- Tiles are not always included
    mouse_cursor = "selection-tool-cursor", -- Default cursor
    skip_fog_of_war = false -- Tool respects fog of war
  },
  {
    type = "custom-input",
    name = "pg-activate-guide",
    key_sequence = "CONTROL + G"
  }
}
