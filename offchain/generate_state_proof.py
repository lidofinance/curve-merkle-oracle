import math
import argparse
import json
import sys
from typing import List, Tuple

from ethereum import block, messages, transactions, utils
import pprint
import requests
import rlp
from trie import HexaryTrie
from trie.constants import (
    BLANK_NODE,
    BLANK_NODE_HASH,
    NODE_TYPE_BLANK,
    NODE_TYPE_LEAF,
    NODE_TYPE_EXTENSION,
    NODE_TYPE_BRANCH,
    BLANK_HASH,
)
from trie.utils.nodes import *
from trie.utils.nibbles import encode_nibbles, decode_nibbles, bytes_to_nibbles


def generate_account_proof(rpc_endpoint, block_number, address, slots):
    block_number = \
        block_number if block_number == "latest" or block_number == "earliest" \
        else hex(int(block_number))

    block_header = request_block_header(rpc_endpoint, block_number)
    proof_json = request_account_proof(rpc_endpoint, hex(block_header.number), address, slots)

    account_proof = decode_rpc_proof(proof_json["accountProof"])

    storage_proofs = [
        decode_rpc_proof(slot_data["proof"]) for slot_data in proof_json["storageProof"]
    ]

    header_blob = rlp.encode(block_header)
    proof_blob = rlp.encode([account_proof, storage_proofs])

    return (block_header.number, header_blob, proof_blob)


def decode_rpc_proof(proof_data):
    return [rlp.decode(utils.decode_hex(node)) for node in proof_data]


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
    hex_slots = [s if s.startswith("0x") else hex(int(s)) for s in slots]

    r = requests.post(rpc_endpoint, json={
        "jsonrpc": "2.0",
        "method": "eth_getProof",
        "params": [address.lower(), hex_slots, block_number],
        "id": 1,
    })

    r.raise_for_status()
    return r.json()["result"]

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


def main():
    parser = argparse.ArgumentParser(
        description="Patricia Merkle Trie Proof Generating Tool",
        formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument("-b", "--block-number",
        default="latest",
        help="Block number")

    parser.add_argument("-r", "--rpc", required=True,
        default="",
        help="URL of web3 RPC endpoint, e.g. http://localhost:8545")

    parser.add_argument("-a", "--address", required=True,
        default="",
        help="Account address")

    parser.add_argument("-s", "--slot-positions", nargs="*",
        help="Positions of storage slots to prove")

    args = parser.parse_args()

    (block_number, header_blob, proof_blob) = generate_account_proof(
        args.rpc,
        args.block_number,
        args.address,
        args.slot_positions
    )

    print(f"\nBlock number: {block_number}\n")
    print("Header:\n")
    print(f"0x{header_blob.hex()}\n")
    print("Proof:\n")
    print(f"0x{proof_blob.hex()}\n")

    exit(0)


if __name__ == "__main__":
    main()
