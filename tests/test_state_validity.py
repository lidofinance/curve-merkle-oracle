import pytest

WEEK = 86400 * 7


@pytest.fixture(scope="module", autouse=True)
def setup(alice, state_oracle, holder, block, serialized_block, serialized_proofs, web3):
    assert block["hash"] == web3.keccak(serialized_block).hex()

    state_oracle.set_eth_blockhash(block["number"], block["hash"], {"from": alice})
    state_oracle.submit_state(holder, serialized_block, serialized_proofs, {"from": alice})


def test_valid_properties(block, chain, holder, state_oracle, voting_escrow):
    timestamp = chain.time()

    expected_balance = voting_escrow.balanceOf(holder, timestamp, block_identifier=block["number"])
    oracle_balance = state_oracle.balanceOf(holder, timestamp)

    assert expected_balance == oracle_balance

    expected_totalSupply = voting_escrow.totalSupply(timestamp, block_identifier=block["number"])
    oracle_totalSupply = state_oracle.totalSupply(timestamp)
    last_point = state_oracle.point_history(state_oracle.epoch())

    if (timestamp // WEEK * WEEK) - (last_point["ts"] // WEEK * WEEK) > 8:
        # when we don't go past the bounds of the slope_changes state
        # we want the totalSupply to be greater than the expected totalSupply
        # incentives users to update the oracle
        assert expected_totalSupply < oracle_totalSupply
    else:
        # within the bounds of 2 months, we should have state match exactly
        assert expected_totalSupply == oracle_totalSupply
