require("script/land_encounters/utils/random")

local CHANCES_INDEX = 1

local STABILIZING_TURN = 120

local function calculate_filled_buckets_given_turn_number(number_of_levels, turn_number)
    local buckets = {}
    local total_chances_to_distribute = 100
    local equal_chance_of_event_happening = 100/number_of_levels
    local spillover_delta = (100 - equal_chance_of_event_happening) / STABILIZING_TURN

    -- turn_number | total chances | buckets [5]          | number_of_levels | spillover_delta | STABILIZING_TURN
    -- 1           | 100           | [100][0][0][0][0]    | 5                | 4               | 20
    -- 2           | 100           | [96][4][0][0][0]     | 5                | 4               | 20
    -- 3           | 100           | [92][8][0][0][0]     | 5                | 4               | 20
    -- 4           | 100           | [88][12][0][0][0]    | 5                | 4               | 20
    -- 5           | 100           | [84][16][0][0][0]    | 5                | 4               | 20
    -- 6           | 100           | [80][20][0][0][0]    | 5                | 4               | 20
    -- 7           | 100           | [76][20][4][0][0]    | 5                | 4               | 20
    local guiding_bucket_chances = total_chances_to_distribute - (turn_number - 1) * spillover_delta
    guiding_bucket_chances = math.max(equal_chance_of_event_happening, guiding_bucket_chances)
    buckets[1] = guiding_bucket_chances
    total_chances_to_distribute = total_chances_to_distribute - guiding_bucket_chances

    for bucket_index = 2, number_of_levels do
        local spilled_chances = math.min(equal_chance_of_event_happening, total_chances_to_distribute) 
        buckets[bucket_index] = spilled_chances
        total_chances_to_distribute = total_chances_to_distribute - spilled_chances
    end

    return buckets
end

local function compare_chances_of_event_happening(a,b)
    return a[CHANCES_INDEX] > b[CHANCES_INDEX]
end


--- @function randomize_chances_of_event_happening_considering_spillover_given_turn
--- @description using an spillover algorithm, slowly enable more complex events as turns pass
--- @param number_of_levels number the number of levels to consider for balancing the chances of an event happening 
--- @param turn_number number the current turn number in the user game
--- @return table RandomizedEvents a list of events randomized 
function randomize_chances_of_event_happening_considering_spillover_given_turn(number_of_levels, turn_number)
    --math.randomseed(100)
    local chance_of_event_of_level_happening = calculate_filled_buckets_given_turn_number(number_of_levels, turn_number)
    for i = 1, number_of_levels do
        local random_multiplier = cm:random_number()
        chance_of_event_of_level_happening[i] = { chance_of_event_of_level_happening[i] * random_multiplier, i }
    end
    table.sort(chance_of_event_of_level_happening, compare_chances_of_event_happening)
    return chance_of_event_of_level_happening
end

--[[
local x = randomize_chances_of_event_happening_considering_spillover_given_turn(5, 120)
print("sorted table =" .. tostring(#x))
for i = 1, #x do
  print("order[" .. tostring(i) .. "]= " .. tostring(x[i][2]))
end
]]--