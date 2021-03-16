import math
import json

from ethereum import block, utils
import requests
import rlp


def request_block_header(rpc_endpoint, block_number):
    r = requests.post(rpc_endpoint, json={
        "jsonrpc": "2.0",
        "method": "eth_getBlockByNumber",
        "params": [block_number, True],
        "id": 1,
    })

    r.raise_for_status()
    block_dict = r.json()["result"]

    header = block.BlockHeader(
        normalize_bytes(block_dict["parentHash"]),
        normalize_bytes(block_dict["sha3Uncles"]),
        utils.normalize_address(block_dict["miner"]),
        normalize_bytes(block_dict["stateRoot"]),
        normalize_bytes(block_dict["transactionsRoot"]),
        normalize_bytes(block_dict["receiptsRoot"]),
        utils.bytes_to_int(normalize_bytes(block_dict["logsBloom"])),
        utils.parse_as_int(block_dict["difficulty"]),
        utils.parse_as_int(block_dict["number"]),
        utils.parse_as_int(block_dict["gasLimit"]),
        utils.parse_as_int(block_dict["gasUsed"]),
        utils.parse_as_int(block_dict["timestamp"]),
        normalize_bytes(block_dict["extraData"]),
        normalize_bytes(block_dict["mixHash"]),
        normalize_bytes(block_dict["nonce"]),
    )

    if normalize_bytes(block_dict["hash"]) != header.hash:
        raise ValueError(
            """Blockhash does not match.
            Received invalid block header? {} vs {}""".format(
                str(normalize_bytes(block_dict["hash"])),
                str(b.hash)))

    return header


def request_account_proof(rpc_endpoint, block_number, address, slots):
    hex_slots = [to_0x_string(s) for s in slots]

    r = requests.post(rpc_endpoint, json={
        "jsonrpc": "2.0",
        "method": "eth_getProof",
        "params": [address.lower(), hex_slots, to_0x_string(block_number)],
        "id": 1,
    })

    r.raise_for_status()
    result = r.json()["result"]

    account_proof = decode_rpc_proof(result["accountProof"])
    storage_proofs = [
        decode_rpc_proof(slot_data["proof"]) for slot_data in result["storageProof"]
    ]

    return (account_proof, storage_proofs)


def decode_rpc_proof(proof_data):
    return [rlp.decode(utils.decode_hex(node)) for node in proof_data]


def normalize_bytes(hash):
    if isinstance(hash, str):
        if hash.startswith("0x"):
            hash = hash[2:]
        if len(hash) % 2 != 0:
            hash = "0" + hash
        return utils.decode_hex(hash)
    elif isinstance(hash, int):
        return hash.to_bytes(length=(math.ceil(hash.bit_length() / 8)),
            byteorder="big",
            signed=False)


def to_0x_string(v):
    if isinstance(v, bytes):
        return "0x" + v.hex()
    if isinstance(v, str):
        return v if v.startswith("0x") else hex(int(v))
    return hex(v)
