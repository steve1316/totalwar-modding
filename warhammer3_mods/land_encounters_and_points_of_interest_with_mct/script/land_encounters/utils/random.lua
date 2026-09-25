--- Side-effect module that publishes random-number / shuffle utility globals used across the mod.

math.randomseed(os.time())
math.random(); math.random(); math.random() -- warm up the RNG after seeding

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
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end


--- Returns a random integer in [min_num, max_num] (defaults 1..100). Safe in multiplayer. Used in place of cm:random_number
--- which has quirky behavior. Returns 0 for invalid inputs.
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
	
	return math.random(min_num, max_num)
end
