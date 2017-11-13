--nplib: Node persistence library
--Originally a part of advtrains
-- For certain reasons, advtrains still keeps duplicate code of this mod with slight changes.

--nodedb.lua
--database of all nodes that have 'save_in_nodedb' field set to true in node definition

local mstore = minetest.get_mod_storage()

--serialization format:
--(2byte z) (2byte y) (2byte x) (2byte contentid) (1byte param2)

local function int_to_bytes(i)
	local x=i+32768--clip to positive integers
	local cH = math.floor(x /           256) % 256;
	local cL = math.floor(x                ) % 256;
	return(string.char(cH, cL));
end
local function int_to_single_byte(i)
	local x=i
	local cL = math.floor(x                ) % 256;
	return(string.char(cL));
end
local function bytes_to_int(bytes)
	local t={string.byte(bytes,1,-1)}
	local n = 
		t[1] *           256 +
		t[2]
    return n-32768
end
local function single_byte_to_int(bytes)
	local t={string.byte(bytes,1,-1)}
	local n = 
		t[1]
    return n
end
local ndb={}

--local variables for performance
local ndb_nodeids={}
local ndb_nodecid={}
local ndb_nodepar={}

local ndb_nodemeta={}

local function ndbget(t,x,y,z)
	local ny=t[y]
	if ny then
		local nx=ny[x]
		if nx then
			return nx[z]
		end
	end
	return nil
end
local function ndbset(t,x,y,z,v)
	if not t[y] then
		t[y]={}
	end
	if not t[y][x] then
		t[y][x]={}
	end
	t[y][x][z]=v
end

local path = minetest.get_worldpath().."/nplib_ndb"

local file, err = io.open(path, "r")
if not file then
	minetest.log("error", "Couldn't load the node database: "..( err or "Unknown Error"))
end
if file then
	local cnt=0
	local hst_z=file:read(2)
	local hst_y=file:read(2)
	local hst_x=file:read(2)
	local cid=file:read(2)
	local par=file:read(1)
	while hst_z and hst_y and hst_x and cid and #hst_z==2 and #hst_y==2 and #hst_x==2 and #cid==2 do
		ndbset(ndb_nodecid, bytes_to_int(hst_x), bytes_to_int(hst_y), bytes_to_int(hst_z), bytes_to_int(cid))
		ndbset(ndb_nodepar, bytes_to_int(hst_x), bytes_to_int(hst_y), bytes_to_int(hst_z), single_byte_to_int(par))
		cnt=cnt+1
		hst_z=file:read(2)
		hst_y=file:read(2)
		hst_x=file:read(2)
		cid=file:read(2)
		par=file:read(1)
	end
	minetest.log("action", "[nplib] nodedb: read"..cnt.."nodes.")
	file:close()
	local mstorek = minetest.deserialize(mstore:get_string("data"))
	if mstorek and mstorek.version==1 then
		ndb_nodeids = mstorek.ids
		ndb_meta = mstorek.meta
	else
		minetest.log("error", "[nplib] Could not load the node ids and/or metadata from the mod storage (unreadable, unsupported version a.s.o.)")
		minetest.log("error", "[nplib] To prevent a huge mess, the node database will be cleared.")
		ndb_nodes={}
		ndb_nodeids={}
	end
end


function ndb.save_data()
	local file, err = io.open(path, "w")
	local par
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
					par=ndbget(ndb_nodepar, x, y, z) or 0
					file:write(int_to_single_byte(par))
				end
			end
		end
		file:close()
	end
	local tmp = {
		version = 1,
		ids = ndb_nodeids,
		meta = ndb_nodemeta,
	}
	mstore:set_string("data", minetest.serialize(tmp))
end

--function to get node.
function ndb.get_node_or_nil(pos)
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
	local cid=ndbget(ndb_nodecid, pos.x, pos.y, pos.z)
	if cid then
		local nodeid = ndb_nodeids[cid]
		if nodeid then
			local par=ndbget(ndb_nodepar, pos.x, pos.y, pos.z)
			return {name=nodeid, param2 = par}
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
		ndbset(ndb_nodecid, pos.x, pos.y, pos.z, nid)
		ndbset(ndb_nodepar, pos.x, pos.y, pos.z, node.param2)
	else
		--at this position there is no longer a node that needs to be tracked.
		ndb.clear(pos)
	end
end

function ndb.clear(pos)
	ndbset(ndb_nodecid, pos.x, pos.y, pos.z, nil)
	ndbset(ndb_nodepar, pos.x, pos.y, pos.z, nil)
end

ndb.run_lbm = function(pos, node)
	local cid=ndbget(ndb_nodecid, pos.x, pos.y, pos.z)
	if cid then
		--if in database, detect changes and apply.
		local nodeid = ndb_nodeids[cid]
		local param2 = ndbget(ndb_nodepar, pos.x, pos.y, pos.z)
		if not nodeid or not param2 then
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

--- METADATA

local pts = minetest.pos_to_string

function ndb.get_meta(pos)
	local p = pts(pos)
	return ndb_nodemeta[p]
end

function ndb.set_meta(pos, meta)
	local p = pts(pos)
	ndb_nodemeta[p] = meta
end



minetest.register_chatcommand("nplib_sync_ndb",
	{
        params = "", -- Short parameter description
        description = "Synchronize node database and map. Useful after using WorldEdit", -- Full description
        privs = {worldedit=true}, -- Require the "privs" privilege to run
        func = function(name, param)
			if not minetest.check_player_privs(name, {server=true}) and os.time() < ptime+30 then
				return false, "Please wait at least 30s from the previous execution of /nplib_sync_ndb!"
			end
			ndb.restore_all()
			ptime=os.time()
			return true
        end,
    })

