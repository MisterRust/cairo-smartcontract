%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.bool import TRUE, FALSE
from contracts.buildings import build_lumber_camp
from contracts.eykar import mint, conquer, move_convoy

@view
func test_build_lumber_camp_fail_on_water{
    syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*
}():
    alloc_locals
    %{ warp(0) %}
    mint('hello')
    %{ warp(1) %}
    move_convoy(1, 0, 0, 0, -1)
    %{ expect_revert("TRANSACTION_FAILED") %}
    conquer(1, 0, -1, 0)
    build_lumber_camp(1, 0, -1)
    return ()
end

@view
func test_build_lumber_camp_works_on_land{
    syscall_ptr : felt*, range_check_ptr, pedersen_ptr : HashBuiltin*
}():
    alloc_locals
    %{
        stop_prank_callable = start_prank(123)
        warp(0)
    %}
    mint('hello')
    %{ warp(1) %}
    move_convoy(1, 0, 0, 0, 3)
    %{ warp(3600) %}
    conquer(1, 0, 3, 0)
    build_lumber_camp(1, 0, 3)
    %{ stop_prank_callable() %}
    return ()
end
