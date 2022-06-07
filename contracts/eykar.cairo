%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_block_timestamp
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.math import assert_le, abs_value
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc

from contracts.world import Plot, world, world_update, get_plot
from contracts.coordinates import spiral, get_distance
from contracts.colonies import Colony, colonies, get_colony, create_colony, redirect_colony
from contracts.convoys.library import (
    get_convoy_strength,
    convoy_can_access,
    contains_convoy,
    unsafe_move_convoy,
    convoy_meta,
    ConvoyMeta,
)
from contracts.convoys.factory import create_mint_convoy

#
# Colonies
#

@storage_var
func current_registration_id() -> (id : felt):
end

func _get_next_available_plot{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    n : felt
) -> (x : felt, y : felt, n : felt):
    let (x, y) = spiral(n, 16)
    let (plot) = world.read(x, y)
    if plot.owner == 0:
        return (x, y, n)
    else:
        return _get_next_available_plot(n + 1)
    end
end

@storage_var
func _player_colonies_storage(player : felt, index : felt) -> (colony_id : felt):
end

func _get_player_colonies{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    player : felt, colonies_index : felt
) -> (colonies_len : felt, found_colonies : felt*):
    alloc_locals
    let (colony_id) = _player_colonies_storage.read(player, colonies_index)

    if colony_id == 0:
        let (found_colonies) = alloc()
        return (0, found_colonies)
    end

    let (colonies_len, found_colonies) = _get_player_colonies(player, colonies_index + 1)
    let (colony : Colony) = colonies.read(colony_id - 1)
    let redirect : felt = colony.redirection

    if colony.redirection == colony_id:
        assert [found_colonies] = colony_id
        return (colonies_len + 1, found_colonies + 1)
    else:
        return (colonies_len, found_colonies)
    end
end

@view
func get_player_colonies{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    player : felt
) -> (colonies_len : felt, colonies : felt*):
    let (colonies_len, found_colonies) = _get_player_colonies(player, 0)
    return (colonies_len, found_colonies - colonies_len)
end

func _colonies_amount{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    player : felt, colonies_index : felt
) -> (amount : felt):
    let (colony) = _player_colonies_storage.read(player, colonies_index)
    if colony == 0:
        return (0)
    end
    let (remaining) = _colonies_amount(player, colonies_index + 1)
    return (1 + remaining)
end

func add_colony_to_player{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    player : felt, colony_id : felt
) -> ():
    let (id) = _colonies_amount(player, 0)
    _player_colonies_storage.write(player, id, colony_id)
    return ()
end

func _merge_util{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, x : felt, y : felt, n : felt
) -> (id : felt, plots_amount : felt):
    alloc_locals
    if n == 0:
        return (0, 0)
    end

    let (x_shift, y_shift) = spiral(n, 0)
    let (plot) = get_plot(x + x_shift, y + y_shift)
    let (colony) = get_colony(plot.owner)

    let (next_best_id, next_best_plots_amount) = _merge_util(owner, x, y, n - 1)
    if colony.owner != owner:
        return (next_best_id, next_best_plots_amount)
    end

    # if next_best_plots_amount > colony.plots_amount
    let (sup) = is_le(next_best_plots_amount, colony.plots_amount)
    if sup == 0:
        if colony.redirection != 0:
            redirect_colony(colony.redirection, next_best_id)
            tempvar syscall_ptr = syscall_ptr
            tempvar pedersen_ptr = pedersen_ptr
            tempvar range_check_ptr = range_check_ptr
        else:
            tempvar syscall_ptr = syscall_ptr
            tempvar pedersen_ptr = pedersen_ptr
            tempvar range_check_ptr = range_check_ptr
        end
        return (next_best_id, next_best_plots_amount)
    else:
        if next_best_id != 0:
            if colony.redirection != 0:
                redirect_colony(next_best_id, colony.redirection)
                tempvar syscall_ptr = syscall_ptr
                tempvar pedersen_ptr = pedersen_ptr
                tempvar range_check_ptr = range_check_ptr
            else:
                tempvar syscall_ptr = syscall_ptr
                tempvar pedersen_ptr = pedersen_ptr
                tempvar range_check_ptr = range_check_ptr
            end
        else:
            tempvar syscall_ptr = syscall_ptr
            tempvar pedersen_ptr = pedersen_ptr
            tempvar range_check_ptr = range_check_ptr
        end
        return (colony.redirection, colony.plots_amount)
    end
end

func merge{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, x : felt, y : felt
) -> (id : felt):
    # Merges colonies around a specific plot
    #
    # Parameters:
    #     owner (felt): The owner of the plot
    #     x (felt): The x coordinate of the plot
    #     y (felt): The y coordinate of the plot
    #
    # Returns:
    #     id (felt): The id of the redirected colony
    let (id, plots_amount) = _merge_util(owner, x, y, 9)
    return (id)
end

#
# Interactions
#

@external
func mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(name : felt):
    # Mints a plot on the next available location of the spawn spiral
    alloc_locals
    let (n) = current_registration_id.read()
    let (x, y, m) = _get_next_available_plot(n)
    current_registration_id.write(m + 1)

    let (player) = get_caller_address()
    let (colony_id) = merge(player, x, y)
    let (timestamp) = get_block_timestamp()
    if colony_id == 0:
        let (colony) = create_colony(name, player, x, y)
        add_colony_to_player(player, colony.redirection)
        world.write(x, y, Plot(owner=colony.redirection, structure=1))
    else:
        world.write(x, y, Plot(owner=colony_id, structure=1))
    end
    create_mint_convoy(player, x, y)
    world_update.emit(x, y)
    return ()
end

func assert_conquerable{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    convoy_id : felt, x : felt, y : felt, required_strength : felt, caller : felt
) -> ():
    # Asserts that the plot is conquerable by caller
    #
    # Parameters:
    #     convoy_id (felt): The id of the convoy
    #     x (felt): The x coordinate of the plot
    #     y (felt): The y coordinate of the plot
    #     required_strength (felt): The required strength
    #

    # Ensure the plot is not already owned
    let (plot : Plot) = world.read(x, y)
    assert plot.owner = 0

    # check caller is convoy owner
    let meta : ConvoyMeta = convoy_meta.read(convoy_id)
    assert meta.owner = caller

    # Check if the convoy is ready to be used
    let (timestamp : felt) = get_block_timestamp()
    assert_le(meta.availability, timestamp)

    # Check convoy strength is enough
    let (strength : felt) = get_convoy_strength(convoy_id)
    assert_le(required_strength, strength)

    return ()
end

@external
func expand{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    convoy_id : felt, source_x : felt, source_y : felt, target_x : felt, target_y : felt
):
    # Expands a colony using a convoy at destination
    #
    # Parameters:
    #     convoy_id (felt): The id of the convoy
    #     source_x (felt): The x coordinate of the plot to expand
    #     source_y (felt): The y coordinate of the plot to expand
    #     target_x (felt): The x coordinate of the plot to conquer
    #     target_y (felt): The y coordinate of the plot to conquer

    alloc_locals

    let (caller) = get_caller_address()

    # Check if the convoy is near the target
    let (found) = convoy_can_access(convoy_id, target_x, target_y)
    assert found = TRUE

    # check plot is conquerable
    assert_conquerable(convoy_id, target_x, target_y, 3, caller)

    # assert user owns source plot colony
    let (plot : Plot) = world.read(source_x, source_y)
    let colony_id : felt = plot.owner
    let (colony : Colony) = colonies.read(colony_id - 1)
    assert colony.owner = caller

    # move convoy from source to target (ensures the convoy is really on source)
    unsafe_move_convoy(convoy_id, source_x, source_y, target_x, target_y)

    # add plot to colony of source
    let (timestamp) = get_block_timestamp()
    world.write(target_x, target_y, Plot(owner=colony_id, structure=2))
    world_update.emit(target_x, target_y)
    return ()
end

@external
func conquer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    convoy_id : felt, x : felt, y : felt, name : felt
):
    # Conquers a plot using a convoy and create a new colony (or add the plot to an existing one)
    #
    # Parameters:
    #     convoy_id (felt): The id of the convoy
    #     x (felt): The x coordinate of the plot to conquer
    #     y (felt): The y coordinate of the plot to conquer
    #     name (felt): The name of the colony

    alloc_locals
    let (player) = get_caller_address()

    # check convoy is on this plot
    let (test) = contains_convoy(convoy_id, x, y)
    assert test = TRUE

    # check plot is conquerable
    assert_conquerable(convoy_id, x, y, 3, player)

    # create a new colony or add this plot to an existing colony
    let (colony_id) = merge(player, x, y)
    let (timestamp) = get_block_timestamp()
    if colony_id == 0:
        let (colony) = create_colony(name, player, x, y)
        add_colony_to_player(player, colony.redirection)
        world.write(x, y, Plot(owner=colony.redirection, structure=1))
    else:
        world.write(x, y, Plot(owner=colony_id, structure=1))
    end
    world_update.emit(x, y)
    return ()
end
