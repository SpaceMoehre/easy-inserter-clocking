local mod_gui = require("mod-gui")

-- Persistent per-player preferences (chosen inserter + stack size). Factorio 2.0
-- renamed the saved `global` table to `storage`; `storage or global` resolves to
-- whichever exists -- the short-circuit means `global` is only read on 1.1, where
-- it is still the valid persisted table.
local function player_prefs(player)
    local root = storage or global
    root.eic = root.eic or {}
    root.eic.players = root.eic.players or {}
    local prefs = root.eic.players[player.index]
    if not prefs then
        prefs = {inserter = "fast-inserter", stack = 12}
        root.eic.players[player.index] = prefs
    end
    return prefs
end

-- Initialize the top-left toggle button
local function init_gui(player)
    local button_flow = mod_gui.get_button_flow(player)
    if not button_flow.eic_toggle_button then
        button_flow.add{
            type = "button",
            name = "eic_toggle_button",
            caption = "EIC",
            tooltip = {"eic.toggle-tooltip"}
        }
    end
end

script.on_init(function()
    for _, player in pairs(game.players) do
        init_gui(player)
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    init_gui(game.players[event.player_index])
end)

-- Toggle the main calculation window
local function toggle_main_frame(player)
    local frame_flow = mod_gui.get_frame_flow(player)
    if frame_flow.eic_main_frame then
        frame_flow.eic_main_frame.destroy()
    else
        local frame = frame_flow.add{
            type = "frame",
            name = "eic_main_frame",
            caption = {"eic.title"},
            direction = "vertical"
        }

        local prefs = player_prefs(player)

        local flow1 = frame.add{type = "flow", direction = "horizontal"}
        flow1.add{type = "label", caption = {"eic.target-item"}}
        flow1.add{type = "choose-elem-button", elem_type = "item", name = "eic_item_select"}

        local flow_ins = frame.add{type = "flow", direction = "horizontal"}
        flow_ins.add{type = "label", caption = {"eic.inserter"}}
        local inserter_select = flow_ins.add{
            type = "choose-elem-button",
            name = "eic_inserter_select",
            elem_type = "entity",
            elem_filters = {{filter = "type", type = "inserter"}},
        }
        inserter_select.elem_value = prefs.inserter -- restore the saved choice

        local flow2 = frame.add{type = "flow", direction = "horizontal"}
        flow2.add{type = "label", caption = {"eic.items-count"}}
        local count_input = flow2.add{type = "textfield", name = "eic_count_input", text = "1"}
        count_input.numeric = true
        count_input.allow_decimal = true

        local flow2b = frame.add{type = "flow", direction = "horizontal"}
        flow2b.add{type = "label", caption = {"eic.timeframe"}}
        local period_input = flow2b.add{type = "textfield", name = "eic_period_input", text = "0.5"}
        period_input.numeric = true
        period_input.allow_decimal = true

        local flow3 = frame.add{type = "flow", direction = "horizontal"}
        flow3.add{type = "label", caption = {"eic.stack-size"}}
        local stack_input = flow3.add{type = "textfield", name = "eic_stack_input", text = tostring(prefs.stack)}
        stack_input.numeric = true

        local flow4 = frame.add{type = "flow", direction = "horizontal"}
        flow4.add{type = "checkbox", name = "eic_belt_checkbox", caption = {"eic.pickup-from-belt"}, state = false}

        frame.add{type = "button", name = "eic_get_bp_button", caption = {"eic.create-blueprint"}}
    end
end

-- The clock is the same in both game versions: a constant combinator (+increment
-- per tick) feeds an arithmetic combinator doing `C % modulo` with its output
-- looped back to its own input, producing a sawtooth on signal-C. A decider emits
-- the chosen item signal while C <= decider_constant -- the inserter enable window.
-- Only the blueprint *encoding* differs between 1.1 and 2.0, so we branch on a
-- feature that only exists in 2.0 (the wire-connector enum) and build accordingly.

-- Factorio 2.0 encoding: per-entity `wires`, constant combinator `sections`,
-- decider `conditions`/`outputs`.
local function build_clock_entities_v2(item, increment, modulo, decider_constant, inserter, stack)
    local wc = defines.wire_connector_id
    return {
        { -- 1: constant combinator, source of the per-tick increment
            entity_number = 1,
            name = "constant-combinator",
            position = {x = 0, y = 0},
            control_behavior = {
                sections = {
                    sections = {
                        {
                            index = 1,
                            filters = {
                                {
                                    index = 1,
                                    type = "virtual",
                                    name = "signal-C",
                                    quality = "normal",
                                    comparator = "=",
                                    count = increment,
                                },
                            },
                        },
                    },
                },
            },
            wires = {
                {1, wc.circuit_green, 2, wc.combinator_input_green},
            },
        },
        { -- 2: arithmetic combinator, the looping `C % modulo` counter
            entity_number = 2,
            name = "arithmetic-combinator",
            position = {x = 1, y = 0},
            control_behavior = {
                arithmetic_conditions = {
                    first_signal = {type = "virtual", name = "signal-C"},
                    operation = "%",
                    second_constant = modulo,
                    output_signal = {type = "virtual", name = "signal-C"},
                },
            },
            wires = {
                -- output looped back to input (the counter), and output to the decider input
                {2, wc.combinator_output_green, 2, wc.combinator_input_green},
                {2, wc.combinator_output_green, 3, wc.combinator_input_green},
            },
        },
        { -- 3: decider combinator, emits the item signal during the enable window
            entity_number = 3,
            name = "decider-combinator",
            position = {x = 2, y = 0},
            control_behavior = {
                decider_conditions = {
                    conditions = {
                        {
                            first_signal = {type = "virtual", name = "signal-C"},
                            comparator = "<=",
                            constant = decider_constant,
                        },
                    },
                    outputs = {
                        {
                            signal = {type = "item", name = item},
                            copy_count_from_input = false,
                        },
                    },
                },
            },
        },
        { -- 4: the inserter, pre-wired to the decider output and gated on the item signal
            entity_number = 4,
            name = inserter,
            position = {x = 2, y = -2},
            override_stack_size = stack,
            control_behavior = {
                circuit_enabled = true,
                circuit_condition = {
                    first_signal = {type = "item", name = item},
                    comparator = ">",
                    constant = 0,
                },
            },
            wires = {
                {4, wc.circuit_green, 3, wc.combinator_output_green},
            },
        },
    }
end

-- Factorio 1.1 encoding: `connections` keyed by connection point with
-- {entity_id, circuit_id} targets (circuit_id 1 = input, 2 = output), flat
-- constant combinator `filters`, single `decider_conditions`.
local function build_clock_entities_v1(item, increment, modulo, decider_constant, inserter, stack)
    return {
        { -- 1: constant combinator, source of the per-tick increment
            entity_number = 1,
            name = "constant-combinator",
            position = {x = 0, y = 0},
            control_behavior = {
                filters = {
                    {signal = {type = "virtual", name = "signal-C"}, count = increment, index = 1},
                },
            },
            connections = {
                ["1"] = {green = {{entity_id = 2, circuit_id = 1}}},
            },
        },
        { -- 2: arithmetic combinator, the looping `C % modulo` counter
            entity_number = 2,
            name = "arithmetic-combinator",
            position = {x = 1, y = 0},
            control_behavior = {
                arithmetic_conditions = {
                    first_signal = {type = "virtual", name = "signal-C"},
                    operation = "%",
                    second_constant = modulo,
                    output_signal = {type = "virtual", name = "signal-C"},
                },
            },
            connections = {
                ["1"] = {green = {{entity_id = 1, circuit_id = 1}, {entity_id = 2, circuit_id = 2}}},
                ["2"] = {green = {{entity_id = 2, circuit_id = 1}, {entity_id = 3, circuit_id = 1}}},
            },
        },
        { -- 3: decider combinator, emits the item signal during the enable window
            entity_number = 3,
            name = "decider-combinator",
            position = {x = 2, y = 0},
            control_behavior = {
                decider_conditions = {
                    first_signal = {type = "virtual", name = "signal-C"},
                    comparator = "<=",
                    constant = decider_constant,
                    output_signal = {type = "item", name = item},
                    copy_count_from_input = false,
                },
            },
            connections = {
                ["1"] = {green = {{entity_id = 2, circuit_id = 2}}},
                ["2"] = {green = {{entity_id = 4, circuit_id = 1}}},
            },
        },
        { -- 4: the inserter, pre-wired to the decider output and gated on the item signal
            entity_number = 4,
            name = inserter,
            position = {x = 2, y = -2},
            override_stack_size = stack,
            control_behavior = {
                circuit_condition = {
                    first_signal = {type = "item", name = item},
                    comparator = ">",
                    constant = 0,
                },
            },
            connections = {
                ["1"] = {green = {{entity_id = 3, circuit_id = 2}}},
            },
        },
    }
end

-- defines.wire_connector_id only exists in Factorio 2.0+, so it tells the two
-- blueprint encodings apart at runtime.
local function build_clock_entities(item, increment, modulo, decider_constant, inserter, stack)
    if defines.wire_connector_id then
        return build_clock_entities_v2(item, increment, modulo, decider_constant, inserter, stack)
    else
        return build_clock_entities_v1(item, increment, modulo, decider_constant, inserter, stack)
    end
end

-- Find a named descendant; frame[name] only matches direct children, but our
-- inputs live inside per-row flows, so we have to recurse.
local function find_child(root, name)
    if root.name == name then return root end
    for _, child in pairs(root.children) do
        local found = find_child(child, name)
        if found then return found end
    end
end

-- Handle GUI clicks
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.players[event.player_index]
    local element = event.element

    if element.name == "eic_toggle_button" then
        toggle_main_frame(player)

    elseif element.name == "eic_get_bp_button" then
        local frame = element.parent

        local item_select = find_child(frame, "eic_item_select").elem_value
        local inserter_select = find_child(frame, "eic_inserter_select").elem_value
        local count_str = find_child(frame, "eic_count_input").text
        local period_str = find_child(frame, "eic_period_input").text
        local stack_str = find_child(frame, "eic_stack_input").text
        local is_belt = find_child(frame, "eic_belt_checkbox").state

        if not item_select then
            player.print({"gui-alert.missing-item"})
            return
        end

        if not inserter_select then
            player.print({"eic-msg.missing-inserter"})
            return
        end

        local count = tonumber(count_str)
        local period = tonumber(period_str)
        local stack = tonumber(stack_str)

        if not count or count <= 0 or not period or period <= 0 or not stack or stack <= 0 then
            player.print({"eic-msg.invalid-input"})
            return
        end
        stack = math.floor(stack)

        -- Remember this player's inserter + stack choice for next time
        local prefs = player_prefs(player)
        prefs.inserter = inserter_select
        prefs.stack = stack

        -- "count items every period seconds" -> items per second
        local rate = count / period

        -- The Math (fixed-point x100 for sub-tick precision on the rate)
        local increment = math.floor(rate * 100)
        local modulo = stack * 60 * 100

        -- Chest-to-chest only needs a 1-tick pulse to latch a swing. Belt pickup
        -- needs the inserter enabled long enough to fill its hand (~46 ticks).
        local active_ticks = is_belt and 46 or 1
        local decider_constant = active_ticks * increment

        -- If the enable window is as long as (or longer than) the whole clock period,
        -- the inserter would never switch off, so the clock can't throttle anything.
        if decider_constant >= modulo then
            player.print({"eic-msg.rate-too-high"})
            return
        end

        -- Construct the Blueprint in the player's cursor
        local cursor = player.cursor_stack
        if cursor and cursor.can_set_stack({name = "blueprint"}) then
            cursor.set_stack({name = "blueprint"})
            cursor.set_blueprint_entities(build_clock_entities(item_select, increment, modulo, decider_constant, inserter_select, stack))

            player.print({"eic-msg.generated", stack})
            toggle_main_frame(player) -- close the UI
        else
            player.print({"eic-msg.clear-cursor"})
        end
    end
end)

-- Persist preference changes immediately as the player makes them, so the choice
-- survives even if they close the window without generating a blueprint.
script.on_event(defines.events.on_gui_elem_changed, function(event)
    local element = event.element
    if element and element.valid and element.name == "eic_inserter_select" then
        player_prefs(game.players[event.player_index]).inserter = element.elem_value
    end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
    local element = event.element
    if element and element.valid and element.name == "eic_stack_input" then
        local n = tonumber(element.text)
        if n and n > 0 then
            player_prefs(game.players[event.player_index]).stack = math.floor(n)
        end
    end
end)
