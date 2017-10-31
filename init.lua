--nplib: Node persistence library
--Originally a part of advtrains
-- For certain reasons, advtrains still keeps duplicate code of this mod with slight changes.

--nodedb.lua
--database of all nodes that have 'save_in_nodedb' field set to true in node definition

local mstore = minetest.get_mod_storage()

--serialization format:
--(2byte z) (2byte y) (2byte x) (2byte contentid)
--contentid := (14bit nodeid, 2bit param2)

local function int_to_bytes(i)
	local x=i+32768--clip to positive integers
	local cH = math.floor(x /           256) % 256;
	local cL = math.floor(x                ) % 256;
	return(string.char(cH, cL));
end
local function bytes_to_int(bytes)
	local t={string.byte(bytes,1,-1)}
	local n = 
		t[1] *           256 +
		t[2]
    return n-32768
end
local function l2b(x)
	return x%4
end
local function u14b(x)
	return math.floor(x/4)
end
local ndb={}

--local variables for performance
local ndb_nodeids={}
local ndb_nodes={}

local function ndbget(x,y,z)
	local ny=ndb_nodes[y]
	if ny then
		local nx=ny[x]
		if nx then
			return nx[z]
		end
	end
	return nil
end
local function ndbset(x,y,z,v)
	if not ndb_nodes[y] then
		ndb_nodes[y]={}
	end
	if not ndb_nodes[y][x] then
		ndb_nodes[y][x]={}
	end
	ndb_nodes[y][x][z]=v
end

local path = minetest.get_worldpath().."/nplib_ndb"

local file, err = io.open(path, "r")
if not file then
	minetest.log("error", "Couldn't load the node database: "..( err or "Unknown Error"))
	load_from_avt=true
	minetest.log("error", "Trying file: "..path_compat)
	file, err = io.open(path_compat, "r")
	if not file then
		minetest.log("error", "Couldn't load the node database from compatibility file: "..( err or "Unknown Error"))
	end
end
if file then
	local cnt=0
	local hst_z=file:read(2)
	local hst_y=file:read(2)
	local hst_x=file:read(2)
	local cid=file:read(2)
	while hst_z and hst_y and hst_x and cid and #hst_z==2 and #hst_y==2 and #hst_x==2 and #cid==2 do
		ndbset(bytes_to_int(hst_x), bytes_to_int(hst_y), bytes_to_int(hst_z), bytes_to_int(cid))
		cnt=cnt+1
		hst_z=file:read(2)
		hst_y=file:read(2)
		hst_x=file:read(2)
		cid=file:read(2)
	end
	minetest.log("action", "[nplib] nodedb: read"..cnt.."nodes.")
	file:close()
	local mstorek = minetest.deserialize(mstore:get_string("nodeids"))
	if mstorek and not load_from_avt then then
		ndb_nodeids = mstorek
	else
		minetest.log("error", "[nplib] Could not load the node id's from the mod storage. To prevent a huge mess, the node database will be cleared.")
		ndb_nodes={}
		ndb_nodeids={}
	end
end


function ndb.save_data()
	local file, err = io.open(path, "w")
	if not file then
		minetest.log("error", "Couldn't save the node database: "..( err or "Unknown Error"))
	else
		for y, ny in pairs(ndb_nodes) do
			for x, nx in pairs(ny) do
				for z, cid in pairs(nx) do
					file:write(int_to_bytes(z))
					file:write(int_to_bytes(y))
					file:write(int_to_bytes(x))
					file:write(int_to_bytes(cid))
				end
			end
		end
		file:close()
	end
	mstore:set_string("nodeids", minetest.serialize(ndb_nodeids))
end

--function to get node.
function ndb.get_node_or_nil(pos)
	-- FIX for bug found on linuxworks server:
	-- a loaded node might get read before the LBM has updated its state, resulting in wrongly set signals and switches
	-- -> Using the saved node prioritarily.
	local node = ndb.get_node_raw(pos)
	if node then
		return node
	else
		--try reading the node from the map
		return minetest.get_node_or_nil(pos)
	end
end
function ndb.get_node(pos)
	local n=ndb.get_node_or_nil(pos)
	if not n then
		return {name="ignore", param2=0}
	end
	return n
end
function ndb.get_node_raw(pos)
	local cid=ndbget(pos.x, pos.y, pos.z)
	if cid then
		local nodeid = ndb_nodeids[u14b(cid)]
		if nodeid then
			return {name=nodeid, param2 = l2b(cid)}
		end
	end
	return nil
end


function ndb.swap_node(pos, node)
	minetest.swap_node(pos, node)
	ndb.update(pos, node)
end

function ndb.update(pos, pnode)
	local node = pnode or minetest.get_node_or_nil(pos)
	if not node or node.name=="ignore" then return end
	if minetest.registered_nodes[node.name] and minetest.registered_nodes[node.name].groups.save_in_nodedb then
		local nid
		for tnid, nname in pairs(ndb_nodeids) do
			if nname==node.name then
				nid=tnid
			end
		end
		if not nid then
			nid=#ndb_nodeids+1
			ndb_nodeids[nid]=node.name
		end
		ndbset(pos.x, pos.y, pos.z, (nid * 4) + (l2b(node.param2 or 0)) )
	else
		--at this position there is no longer a node that needs to be tracked.
		ndbset(pos.x, pos.y, pos.z, nil)
	end
end

function ndb.clear(pos)
	ndbset(pos.x, pos.y, pos.z, nil)
end

ndb.run_lbm = function(pos, node)
	return advtrains.pcall(function()
		local cid=ndbget(pos.x, pos.y, pos.z)
		if cid then
			--if in database, detect changes and apply.
			local nodeid = ndb_nodeids[u14b(cid)]
			local param2 = l2b(cid)
			if not nodeid then
				--something went wrong
				minetest.log("warning", "[nplib] Node Database corruption, couldn't determine node to set at "..minetest.pos_to_string(pos))
				ndb.update(pos, node)
			else
				if (nodeid~=node.name or param2~=node.param2) then
					minetest.swap_node(pos, {name=nodeid, param2 = param2})
					local ndef=minetest.registered_nodes[nodeid]
					if ndef and ndef.on_updated_from_nodedb then
						ndef.on_updated_from_nodedb(pos, node)
					end
					return true
				end
			end
		else
			--if not in database, take it.
			minetest.log("action", "[nplib] Node Database: "..minetest.pos_to_string(pos).." was not found in the database, have you used worldedit?")
			ndb.update(pos, node)
		end
		return false
	end)
end


minetest.register_lbm({
        name = "nplib:nodedb_on_load_update",
        nodenames = {"group:save_in_nodedb"},
        run_at_every_load = true,
        run_on_every_load = true,
        action = ndb.run_lbm,
        interval=30,
        chance=1,
    })

--used when restoring stuff after a crash
ndb.restore_all = function()
	minetest.log("action", "Updating the map from the nodedb, this may take a while")
	local cnt=0
	for y, ny in pairs(ndb_nodes) do
		for x, nx in pairs(ny) do
			for z, _ in pairs(nx) do
				local pos={x=x, y=y, z=z}
				local node=minetest.get_node_or_nil(pos)
				if node then
					local ori_ndef=minetest.registered_nodes[node.name]
					local ndbnode=ndb.get_node_raw(pos)
					if ori_ndef and ori_ndef.groups.save_in_nodedb then --check if this node has been worldedited, and don't replace then
						if (ndbnode.name~=node.name or ndbnode.param2~=node.param2) then
							minetest.swap_node(pos, ndbnode)
							minetest.log("action", "Replaced "..node.name.." @"..minetest.pos_to_string(pos).." with "..ndbnode.name)
						end
					else
						ndb.clear(pos)
						minetest.log("action", "Found ghost node (former"..ndbnode.name..") @"..minetest.pos_to_string(pos)..", deleting")
					end
				end
			end
		end
	end
end
    
minetest.register_on_dignode(function(pos, oldnode, digger)
	ndb.clear(pos)
end)

function ndb.get_nodes()
	return ndb_nodes
end
function ndb.get_nodeids()
	return ndb_nodeids
end


nplib=ndb

local ptime=0

minetest.register_chatcommand("nplib_sync_ndb",
	{
        params = "", -- Short parameter description
        description = "Synchronize node database and map. Useful after using WorldEdit", -- Full description
        privs = {worldedit=true}, -- Require the "privs" privilege to run
        func = function(name, param)
			return advtrains.pcall(function()
				if not minetest.check_player_privs(name, {server=true}) and os.time() < ptime+30 then
					return false, "Please wait at least 30s from the previous execution of /nplib_sync_ndb!"
				end
				ndb.restore_all()
				ptime=os.time()
				return true
			end)
        end,
    })

