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

BLOCK_NUMBERS = np.linspace(11863283, 14297900, dtype=int).tolist()

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
    "0x7e8b062d0693ee611ca197f3a5ca412559f4a2f5",
    "0x279a7dbfae376427ffac52fcb0883147d42165ff",
    "0x4bcc5ca6394971dde157dea794553d2b9de44b0f",
    "0xb01151b93b5783c252333ce0707d704d0bbdf5ec",
    "0xa5d223c176daab154a3134369d1c0478c5e6fecf",
    "0x39362b3ca91d40aff08ebccbdd121090f3bb3ef3",
    "0x9c02ac8a9e766a6e4f6987f5ea6aa91d70e932b9",
    "0xce2a3294f800b1bf9a907db3c7e377cf9486a456",
    "0xfbd50c82ea05d0d8b6b302317880060bc3086866",
    "0xc62eecc24cb6e84da2409e945ddcf7386118c57a",
    "0xd4a39d219adb43ab00739dc5d876d98fdf0121bf",
    "0x662353d1a53c88c85e546d7c4a72ce8fe1018e72",
    "0xc18406aa413b4d08c729e7312239c34e45c61197",
    "0x20017a30d3156d4005bda08c40acda0a6ae209b1",
    "0xe5350e927b904fdb4d2af55c566e269bb3df1941",
    "0xf96da4775776ea43c42795b116c7a6eccd6e71b5",
    "0xdedf3000d83bd3550d7d2080cc48a488c93a9442",
    "0x3ba21b6477f48273f41d241aa3722ffb9e07e247",
    "0x48fe56b756ef2717d1db4050ef648ad4b72f55b9",
    "0x78bc49be7bae5e0eec08780c86f0e8278b8b035b",
    "0x39415255619783a2e71fcf7d8f708a951d92e1b6",
    "0x7a8edc710ddeadddb0b539de83f3a306a621e823",
    "0x19ae3cf684087e2cb9cc2dd2b58c29f79f4e9d02",
    "0x0000a441fbb1fbaadf246539bf253a42abd31494",
    "0x018a82c70f689aeedb05cbc55631c5cfa807a25c",
    "0x903d12bf2c57a29f32365917c706ce0e1a84cce3",
    "0xd8ce0efcc3f2dd2ea0b1d7b9bd260a3987f7ad46",
    "0x6e26d91c264ab73a0062ccb5fb00becfab3acc6b",
    "0x8a473efb809b1c9ea7a4dd5cdd498e1fac54da14",
    "0x75c0c0591cdf9af7cb826a65ac213cff31916668",
    "0x8a7915b7727b0d198719864bfbf9c8e4caf9b21e",
    "0xe1acc251656c2964678a8843808dfc2bdf56da20",
    "0xa7b6f7f3e3aa2d9d33249e755f62d7e5ae19ef13",
    "0x41339d9825963515e5705df8d3b0ea98105ebb1c",
    "0x537bf75de19f3d229e3a9018ee1a23c0c9c7d39c",
    "0x1e5aebcfdc780da4fb506e93a0b398490fd94864",
    "0x1d5e65a087ebc3d03a294412e46ce5d6882969f4",
    "0x0c01383ecb25008d207025b405575f908c6167c4",
    "0xbce3e29641b2083716e023f0bb56635d3062c8c3",
    "0x3f47cb95efbc1a15113b6a405b7548421580967f",
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
