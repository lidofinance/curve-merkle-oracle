# @version 0.2.8

interface StableSwap:
    def fee() -> uint256: view
    def A_precise() -> uint256: view


interface StateOracle:
    def getState() -> (uint256, uint256, uint256): view


STETH_POOL: constant(address) = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022
N_COINS: constant(int128) = 2
FEE_DENOMINATOR: constant(uint256) = 10 ** 10
A_PRECISION: constant(uint256) = 100


state_oracle: public(address)


@external
def __init__(_state_oracle: address):
    self.state_oracle = _state_oracle


@view
@external
def data_timestamp() -> uint256:
    return StateOracle(self.state_oracle).getState()[0]


@view
@internal
def _balances(_value: uint256 = 0) -> uint256[N_COINS]:
    ts: uint256 = 0
    balance0: uint256 = 0
    balance1: uint256 = 0
    (ts, balance0, balance1) = StateOracle(self.state_oracle).getState()
    return [balance0 - _value, balance1]


@view
@internal
def _fee() -> uint256:
    return StableSwap(STETH_POOL).fee()


@view
@internal
def _A() -> uint256:
    return StableSwap(STETH_POOL).A_precise()


# The following code has been copied with minor modifications from
# https://github.com/curvefi/curve-contract/blob/master/contracts/pools/steth/StableSwapSTETH.vy


@pure
@internal
def get_D(xp: uint256[N_COINS], amp: uint256) -> uint256:
    S: uint256 = 0
    Dprev: uint256 = 0

    for _x in xp:
        S += _x
    if S == 0:
        return 0

    D: uint256 = S
    Ann: uint256 = amp * N_COINS
    for _i in range(255):
        D_P: uint256 = D
        for _x in xp:
            D_P = D_P * D / (_x * N_COINS + 1)  # +1 is to prevent /0
        Dprev = D
        D = (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P)
        # Equality with the precision of 1
        if D > Dprev:
            if D - Dprev <= 1:
                return D
        else:
            if Dprev - D <= 1:
                return D
    # convergence typically occurs in 4 rounds or less, this should be unreachable!
    # if it does happen the pool is borked and LPs can withdraw via `remove_liquidity`
    raise


@view
@internal
def get_y(i: int128, j: int128, x: uint256, xp: uint256[N_COINS]) -> uint256:
    # x in the input is converted to the same price/precision

    assert i != j       # dev: same coin
    assert j >= 0       # dev: j below zero
    assert j < N_COINS  # dev: j above N_COINS

    # should be unreachable, but good for safety
    assert i >= 0
    assert i < N_COINS

    amp: uint256 = self._A()
    D: uint256 = self.get_D(xp, amp)
    Ann: uint256 = amp * N_COINS
    c: uint256 = D
    S_: uint256 = 0
    _x: uint256 = 0
    y_prev: uint256 = 0

    for _i in range(N_COINS):
        if _i == i:
            _x = x
        elif _i != j:
            _x = xp[_i]
        else:
            continue
        S_ += _x
        c = c * D / (_x * N_COINS)
    c = c * D * A_PRECISION / (Ann * N_COINS)
    b: uint256 = S_ + D * A_PRECISION / Ann  # - D
    y: uint256 = D
    for _i in range(255):
        y_prev = y
        y = (y*y + c) / (2 * y + b - D)
        # Equality with the precision of 1
        if y > y_prev:
            if y - y_prev <= 1:
                return y
        else:
            if y_prev - y <= 1:
                return y
    raise


@view
@external
def get_dy(i: int128, j: int128, dx: uint256) -> uint256:
    xp: uint256[N_COINS] = self._balances()
    x: uint256 = xp[i] + dx
    y: uint256 = self.get_y(i, j, x, xp)
    dy: uint256 = xp[j] - y - 1
    fee: uint256 = self._fee() * dy / FEE_DENOMINATOR
    return dy - fee


@view
@external
def A() -> uint256:
    return self._A() / A_PRECISION


@view
@external
def A_precise() -> uint256:
    return self._A()


@view
@external
def balances(i: uint256) -> uint256:
    return self._balances()[i]
