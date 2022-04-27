%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.math_cmp import is_le, is_nn
from starkware.cairo.common.math import signed_div_rem

from contracts.szudzik import random_felt
from contracts.fixed_point_numbers import (
    Math64x61_assert64x61 as assert64x61,
    Math64x61_fromFelt as from_felt,
    Math64x61_add as add,
    Math64x61_sub as sub,
    Math64x61_mul as mul,
    Math64x61_div as div,
    Math64x61_pow as pow,
    Math64x61_sqrt as sqrt,
    Math64x61_ONE as ONE,
    Math64x61_floor as floor,
    Math64x61_FRACT_PART as FRACT_PART,
    Math64x61_BOUND as BOUND
)

#using Point = (x : felt, y : felt)

# sqrt(3) in 64.61 fixed-point format
const SQRT3 = 3993837248401023412

# 1/2 in 64.61 fixed-point format
const HALF = 1152921504606846976

# 1/6 in 64.61 fixed-point format
const ONE_SIXTH = 384307168202282325

# 3 in 64.61 fixed-point format
const THREE = 6917529027641081856

# 2 in 64.61 fixed-point format
const TWO = 4611686018427387904

# 70 in 64.61 fixed-point format
const SEVENTY = 161409010644958576640

func grad2{range_check_ptr}() -> (gradient_table : felt*):
    let (gradient_address) = get_label_location(gradients)
    let gradient_table = cast(gradient_address, felt*)
    return (gradient_table)

    gradients:
    dw ONE
    dw ONE

    dw -ONE
    dw ONE

    dw ONE
    dw -ONE

    dw -ONE
    dw -ONE

    dw ONE
    dw 0

    dw -ONE
    dw 0

    dw ONE
    dw 0

    dw -ONE
    dw 0

    dw 0
    dw ONE

    dw 0
    dw -ONE

    dw 0
    dw ONE

    dw 0
    dw -ONE
end

func dot{range_check_ptr}(grad_x: felt, grad_y: felt, x: felt, y: felt)->(res: felt):
    let (val_x) = mul(grad_x, x)
    let (val_y) = mul(grad_y, y)
    let (res) = add(val_x, val_y)
    return (res)
end

func contribution{range_check_ptr}(t: felt, grad_x: felt, grad_y: felt, x: felt, y: felt) -> (res: felt):
    alloc_locals
    local res
    let (temp) = is_nn(t)
    if temp == 1:
        let (t_4) = pow(t, 4)
        let (d) = dot(grad_x, grad_y, x, y)
        let (m) = mul(t_4, d)
        return (m)
    else:
        return (0)
    end
end

func compute_t{range_check_ptr}(x: felt, y: felt) -> (t: felt):
    let (x_2) = mul(x, y)
    let (y_2) = mul(y, y)
    tempvar t = HALF - x_2 - y_2
    return (t)
end

@view
func noise{range_check_ptr}(x: felt, y: felt) -> (noise: felt):
    alloc_locals

    # Switch to 64.61 fixed-point format
    let (x_64x61) = from_felt(x)
    let (y_64x61) = from_felt(y)

    # skew input space
    let (subF) = sub(SQRT3, ONE)
    let (F) = mul(HALF, subF)
    let (addS) = add(x_64x61, y_64x61)
    let (s) = mul(addS, F)
    let (i) = floor(x + s)
    let (j) = floor(y + s)
    local i = i
    local j = j

    let (subG) = sub(THREE, SQRT3)
    let (G) = mul(subG, ONE_SIXTH)
    let (addt) = add(i, j)
    let (t) = mul(G, addt)
    let (X0) = sub(i, t)
    let (Y0) = sub(j, t)
    let (x0) = sub(x, X0)
    let (y0) = sub(y, Y0)

    # determine which simplex we are in
    local i1
    local j1

    let (temp) = is_le(x0, y0)
    if temp == 1:
        assert i1 = 0
        assert j1 = ONE
    else:
        assert i1 = ONE
        assert j1 = 0
    end

    let (x1) = sub(x0, i1)
    let (x1) = add(x1, G)
    let (y1) = sub(y0, j1)
    let (y1) = add(y0, G)
    let (g2) = mul(TWO, G)
    let (x2) = sub(x0, ONE)
    let (x2) = add(x2, g2)
    let (y2) = sub(y0, ONE)
    let (y2) = add(y2, g2)

    # random gradient
    let (gradient_table) = grad2()

    let (g0) = random_felt(i, j, 1, 0, 12)
    let (g1) = random_felt(i1, j, 1, 0, 12)
    let (g2) = random_felt(i, j1, 1, 0, 12)

    tempvar g0_x = gradient_table[g0*2]
    tempvar g0_y = gradient_table[g0*2+1]
    tempvar g1_x = gradient_table[g1*2]
    tempvar g1_y = gradient_table[g1*2+1]
    tempvar g2_x = gradient_table[g2*2]
    tempvar g2_y = gradient_table[g2*2+1]

    # contribution from the three corners
    let (t0) = compute_t(x0, y0)
    let (t1) = compute_t(x1, y1)
    let (t2) = compute_t(x2, y2)

    let (n0) = contribution(t0, g0_x, g0_y, x0, y0)
    let (n1) = contribution(t1, g1_x, g1_y, x1, y1)
    let (n2) = contribution(t2, g2_x, g2_y, x2, y2)

    # return final value
    let (noise) = add(n0, n1)
    let (noise) = add(noise, n2)
    let (noise) = mul(noise, SEVENTY)
    return (noise)
end