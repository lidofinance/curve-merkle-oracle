import json

import numpy as np
import pytest
import rlp
from brownie import ZERO_ADDRESS
from hexbytes import HexBytes

# https://github.com/ethereum/go-ethereum/blob/master/core/types/block.go#L69
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


# account fixtures


@pytest.fixture(scope="module")
def alice(accounts):
    return accounts[0]


# contract fixtures


@pytest.fixture(scope="module")
def state_sender(alice, StateSender):
    return StateSender.deploy({"from": alice})


@pytest.fixture(scope="module")
def state_oracle(alice, VotingEscrowStateOracle):
    return VotingEscrowStateOracle.deploy(ZERO_ADDRESS, {"from": alice})


# parameterized fixtures


@pytest.fixture(scope="module", params=BLOCK_NUMBERS)
def block_number(request):
    return request.param


@pytest.fixture(scope="module", params=HOLDERS)
def holder(request):
    return request.param


@pytest.fixture(scope="module")
def block(block_number):
    with open(f"tests/data/block_{block_number}/block.json") as f:
        return json.load(f)


@pytest.fixture(scope="module")
def serialized_block(block, serialize_block):
    return serialize_block(block)


@pytest.fixture(scope="module")
def proofs(block_number, holder):
    with open(f"tests/data/block_{block_number}/proofs_{holder}.json") as f:
        return json.load(f)


@pytest.fixture(scope="module")
def serialized_proofs(proofs, serialize_proofs):
    return serialize_proofs(proofs)


# forked fixture


@pytest.fixture(scope="module")
def voting_escrow(Contract):
    return Contract("0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2")


# isolation fixture


@pytest.fixture(autouse=True)
def isolation(module_isolation, fn_isolation):
    pass


# helper function fixtures


@pytest.fixture(scope="session")
def serialize_block():
    """Helper function to rlp serialize a block header"""

    def _serialize_block(block):
        block_header = [
            HexBytes("0x") if isinstance((v := block[k]), int) and v == 0 else HexBytes(v)
            for k in BLOCK_HEADER
            if k in block
        ]
        return rlp.encode(block_header)

    return _serialize_block


@pytest.fixture(scope="session")
def serialize_proofs():
    """Helper function to rlp serialize a proof generated via web3.eth.get_proof"""

    def _serialize_proofs(proofs):
        account_proof = list(map(rlp.decode, map(HexBytes, proofs["accountProof"])))
        storage_proofs = [
            list(map(rlp.decode, map(HexBytes, proof["proof"]))) for proof in proofs["storageProof"]
        ]
        return rlp.encode([account_proof, *storage_proofs])

    return _serialize_proofs
