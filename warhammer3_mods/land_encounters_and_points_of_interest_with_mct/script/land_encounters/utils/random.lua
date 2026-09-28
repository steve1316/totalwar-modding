--- Side-effect module that publishes random-number / shuffle utility globals used across the mod.
--- Every roll goes through cm:random_number so all multiplayer clients draw the same numbers.

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


--- Returns a random integer in [min_num, max_num] (defaults 1..100). Wraps cm:random_number, which is synced across multiplayer
--- clients, and guards its quirks. Returns 0 for invalid inputs.
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
	
	return cm:random_number(max_num, min_num)
end


--- Returns true with the given percent chance. Multiplayer-safe replacement for `math.random() < p`.
--- @param percent number The chance of returning true, from 0 to 100.
--- @returns boolean True when the roll lands inside the chance.
function random_chance(percent)
	return random_number(100) <= percent
end
