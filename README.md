# Minetest Mod: nplib
/nplib/ is a node persistance library. It stores certain nodes inside a per-world database to operate on them
even if the terrain is not loaded by the Minetest core.
License: LGPL 2.1
## How to use
Note: This guide is for mod developers, not for end users.
### Registering nodes
For a node to be recognized by /nplib/, you need to add it to the following group:
*save_in_nodedb = 1,*
By using this group, you are *required* to operate on the node by *only* using the functions provided by nplib,
or to call nplib.update(pos) after every operation you do with the node while it's loaded.
### Working with persistent nodes
/nplib/ provides some alternate functions to default minetest API functions:
*nplib.get_node(pos)*:
  Returns {name="<node name>", param2="<param2>"} of the node at <pos>. 
  Returns ignore when the node is neither persistent nor loaded.
*nplib.get_node_or_nil(pos)*:
  returns {name="<node name>", param2="<param2>"} of the node at <pos>, returns nil when not found.
*nplib.swap_node(pos, node)*: 
  places the node specified by <node> at <pos>.
### Notes
- Operating nplib.swap_node() on nodes which are not a member of the save_in_nodedb group might not work as expected,
  however, the call always causes minetest.swap_node() to be executed.
- nplib is not able to store and/or handle param1 values
### The LBM
/nplib/ defines an LBM that replaces every node by its current representation in the node database, and adds nodes
that are missing to the database.
###/nplib_sync_ndb
This command can be used to synchronise the nplib node database and the map.
In most cases such inconsistencies occur when someone deleted save_in_nodedb nodes using worldedit.
Then some 'ghost nodes' lie around in the node database. Executing the command checks all loaded
nodes against their database counterpart and removes those that have been removed from the world.
