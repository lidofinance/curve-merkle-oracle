import json
from collections import defaultdict
from functools import lru_cache

import numpy as np
import rlp
from brownie import ZERO_ADDRESS, Contract, VotingEscrowStateOracle, accounts, chain
from hexbytes import HexBytes
from hypothesis.strategies import sampled_from

BLOCK_HEADER = (
    "parentHash",
    "sha3Uncles",
    "miner",
    "stateRoot",
    "transactionsRoot",
    "receiptsRoot",
    "logsBloom",
    "difficulty",
    "number",
    "gasLimit",
    "gasUsed",
    "timestamp",
    "extraData",
    "mixHash",
    "nonce",
    "baseFeePerGas",  # added by EIP-1559 and is ignored in legacy headers
)

BLOCK_NUMBERS = np.linspace(11863283, 14297900, num=15, dtype=int).tolist()

HOLDERS = [
    "0x7a16ff8270133f063aab6c9977183d9e72835428",
    "0xf89501b77b2fa6329f94f5a05fe84cebb5c8b1a0",
    "0x9b44473e223f8a3c047ad86f387b80402536b029",
    "0x431e81e5dfb5a24541b5ff8762bdef3f32f96354",
    "0x425d16b0e08a28a3ff9e4404ae99d78c0a076c5a",
    "0x32d03db62e464c9168e41028ffa6e9a05d8c6451",
    "0xb18fbfe3d34fdc227eb4508cde437412b6233121",
    "0x394a16eea604fbd86b0b45184b2d790c83a950e3",
    "0xc72aed14386158960d0e93fecb83642e68482e4b",
    "0x9c5083dd4838e120dbeac44c052179692aa5dac5",
]

WEEK = 86400 * 7


@lru_cache
def load_block(block_number):
    with open(f"tests/data/block_{block_number}/block.json") as f:
        return json.load(f)


@lru_cache
def load_proofs(block_number, holder):
    with open(f"tests/data/block_{block_number}/proofs_{holder}.json") as f:
        return json.load(f)


def serialize_block(block):
    block_header = [
        HexBytes("0x") if isinstance((v := block[k]), int) and v == 0 else HexBytes(v)
        for k in BLOCK_HEADER
        if k in block
    ]
    return rlp.encode(block_header)


def serialize_proofs(proofs):
    account_proof = list(map(rlp.decode, map(HexBytes, proofs["accountProof"])))
    storage_proofs = [
        list(map(rlp.decode, map(HexBytes, proof["proof"]))) for proof in proofs["storageProof"]
    ]
    return rlp.encode([account_proof, *storage_proofs])


class StateMachine:

    st_block_number = sampled_from(BLOCK_NUMBERS)
    st_holder = sampled_from(HOLDERS)

    def __init__(cls, serialize_block, serialize_proofs):
        cls.ve = Contract("0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2")
        cls.so = VotingEscrowStateOracle.deploy(ZERO_ADDRESS, {"from": accounts[0]})

    def setup(self):
        # user => last (most recent) block which a proof was submitted
        self.last_block_number = defaultdict(int)

    def rule_submit_proof(self, st_block_number, st_holder):
        if st_block_number > self.last_block_number[st_holder]:
            self.last_block_number[st_holder] = st_block_number

        serialized_block = serialize_block(load_block(st_block_number))
        serialized_proofs = serialize_proofs(load_proofs(st_block_number, st_holder))

        self.so.submit_state(st_holder, serialized_block, serialized_proofs, {"from": accounts[0]})

    def invariant_balance_of(self):
        if len(self.last_block_number) == 0:
            return

        timestamp = chain.time()

        for holder in HOLDERS:
            value = self.so.balanceOf(holder, timestamp)

            if (last_block_number := self.last_block_number) != 0:
                # we get the result of `balanceOf` at last_block_number bc that is the state we are
                # verifying we match
                expected = self.ve.balanceOf(holder, timestamp, block_identifier=last_block_number)
                assert value == expected
            else:
                # no proof has been submitted
                assert value == 0

    def invariant_total_supply(self):
        if len(self.last_block_number) == 0:
            # if no proofs have been submitted we can return
            return

        timestamp = chain.time()
        # get the last block a proof was submitted for
        last_block_number = max(self.last_block_number.values())
        # last point stored in our state oracle
        last_point = self.so.point_history(self.so.epoch())

        expected = self.ve.totalSupply(timestamp, block_identifier=last_block_number)
        value = self.so.totalSupply(timestamp)
        if (timestamp // WEEK * WEEK) - (last_point["ts"] // WEEK * WEEK) > 8:
            # a submitted proof bundles 8 weeks worth of slope changes
            # which are used for calculating totalSupply, if `timestamp` is
            # greater than 8 weeks since the last point that was submitted
            # then the state oracle will return an inflated totalSupply
            # forcing users to submit new proofs (otherwise they'll be dilluted)
            assert expected < value
        else:
            assert expected == value


def test_state_machine(state_machine, serialize_block, serialize_proofs):
    state_machine(StateMachine, serialize_block, serialize_proofs)
