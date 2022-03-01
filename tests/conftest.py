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


@pytest.fixture
def alice(accounts):
    return accounts[0]


@pytest.fixture
def state_oracle(alice, VotingEscrowStateOracle):
    return VotingEscrowStateOracle.deploy(ZERO_ADDRESS, {"from": alice})


@pytest.fixture(autouse=True)
def isolation(module_isolation, fn_isolation):
    pass


@pytest.fixture
def block_number():
    for block_n in np.linspace(11863283, 14297900, dtype=int).tolist():
        yield block_n


@pytest.fixture
def serialize_block():
    def _serialize_block(block):
        block_header = [
            HexBytes("0x") if isinstance((v := block[k]), int) and v == 0 else HexBytes(v)
            for k in BLOCK_HEADER
            if k in block
        ]
        return rlp.encode(block_header)

    return _serialize_block


@pytest.fixture
def serialize_proofs():
    def _serialize_proofs(proofs):
        account_proof = list(map(rlp.decode, map(HexBytes, proofs["accountProof"])))
        storage_proofs = [
            list(map(rlp.decode, map(HexBytes, proof["proof"]))) for proof in proofs["storageProof"]
        ]
        return rlp.encode([account_proof, *storage_proofs])

    return _serialize_proofs
