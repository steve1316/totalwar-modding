math.randomseed(os.time()) -- random initialize
math.random(); math.random(); math.random() -- warming up

--- @function randomic_length_shuffle
--- @desc Given a length creates an array with the elements of that length and and shuffles them
--- @return table random a disordered table
function randomic_length_shuffle(length_of_an_array)
    local arr = {}
    for i=1, length_of_an_array do
        table.insert(arr, i)
    end
    return randomic_shuffle(arr)
end


-- Fisher-Yates shuffle
-- Randomly shuffles an array so that its members are disordered
-- https://gist.github.com/Uradamus/10323382
-- param tbl: Array
function randomic_shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end


--- @function random_number
--- @desc Have taken it from outside campaign manager for avoiding the weird behaviour of cm. Assembles and returns a random integer between 1 and 100, or other supplied values. The result returned is inclusive of the supplied max/min. This is safe to use in multiplayer scripts.
--- @p [opt=100] integer max, Maximum value of returned random number.
--- @p [opt=1] integer min, Minimum value of returned random number.
--- @return number random number
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
