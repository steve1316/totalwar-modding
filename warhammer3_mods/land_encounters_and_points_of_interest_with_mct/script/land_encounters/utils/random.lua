--- Side-effect module that publishes random-number / shuffle utility globals used across the mod.
--- Every roll goes through `random_number`: the game's synced generator in multiplayer, Lua's clock-seeded one in single player.

--- Builds a 1..n array and returns it shuffled.
--- @param length_of_an_array number Size of the array to build before shuffling.
--- @returns table A shuffled array containing the integers 1..length_of_an_array.
function randomic_length_shuffle(length_of_an_array)
    local arr = {}
    for i=1, length_of_an_array do
        table.insert(arr, i)
    end
    return randomic_shuffle(arr)
end


--- Fisher-Yates in-place shuffle. Source: https://gist.github.com/Uradamus/10323382.
--- @param tbl table The array to shuffle in place.
--- @returns table The same table reference, now shuffled.
function randomic_shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = random_number(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end


--- Returns a random integer in [min_num, max_num] (defaults 1..100), and guards cm:random_number's quirks. Returns 0 for invalid inputs.
--- Multiplayer uses cm:random_number, which is synced across clients. Single player uses `math.random`, which the game seeds from the clock
--- at startup, so a reloaded save rolls new numbers rather than replaying the saved generator's.
--- @param max_num number Upper bound inclusive. Defaults to 100 when nil.
--- @param min_num number Lower bound inclusive. Defaults to 1 when nil.
--- @returns number A random integer in the range, or 0 on invalid input.
function random_number(max_num, min_num)
	if max_num == nil then
		max_num = 100
	end
	
	if min_num == nil then
		min_num = 1
	end
	
	if not (type(max_num) == "number") or math.floor(max_num) < max_num then
		return 0
	end
	
	if max_num == min_num then
		return max_num
	end
	
	if min_num == 1 and max_num < min_num then
		return 0
	end
	
	if not (type(min_num) == "number") or min_num >= max_num or math.floor(min_num) < min_num then
		return 0
	end
	
	--- Only an explicit false counts as single player, so anything unsure keeps the synced generator.
	if cm:is_multiplayer() == false then
		return math.random(min_num, max_num)
	end
	return cm:random_number(max_num, min_num)
end


--- Returns a random integer in [min_num, max_num], swapping a reversed range. Reads like `math.random(min, max)` but is multiplayer-safe.
--- @param min_num number One end of the range, inclusive.
--- @param max_num number The other end of the range, inclusive.
--- @returns number A random integer between the two ends.
function random_range(min_num, max_num)
	if min_num > max_num then
		min_num, max_num = max_num, min_num
	end
	return random_number(max_num, min_num)
end


--- Returns true with the given percent chance. Multiplayer-safe replacement for `math.random() < p`.
--- @param percent number The chance of returning true, from 0 to 100.
--- @returns boolean True when the roll lands inside the chance.
function random_chance(percent)
	return random_number(100) <= percent
end
