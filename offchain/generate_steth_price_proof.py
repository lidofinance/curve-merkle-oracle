import math
import argparse
import json
import sys
import os

from ethereum import block, messages, transactions, utils
from web3 import Web3
import requests
import rlp

from state_proof import request_block_header, request_account_proof


def main():
    parser = argparse.ArgumentParser(
        description="Patricia Merkle Trie Proof Generating Tool",
        formatter_class=argparse.RawTextHelpFormatter)

    parser.add_argument("-b", "--block-number",
        default="latest",
        help="Block number")

    parser.add_argument("-r", "--rpc",
        default="http://localhost:8545",
        help="URL of a full node RPC endpoint, e.g. http://localhost:8545")

    args = parser.parse_args()

    w3 = Web3(Web3.HTTPProvider(args.rpc))
    oracle_contract = get_oracle_contract('0x602C71e4DAC47a042Ee7f46E0aee17F94A3bA0B6', w3)
    params = oracle_contract.functions.getProofParams().call()

    (block_header, pool_acct_proof, steth_acct_proof, pool_storage_proofs, steth_storage_proofs) = \
        generate_proof_data(
            rpc_endpoint=args.rpc,
            block_number=args.block_number,
            pool_address=params[0],
            steth_address=params[1],
            pool_slots=params[2:4],
            steth_slots=params[4:11],
        )

    header_blob = rlp.encode(block_header)

    proofs_blob = rlp.encode(
        [pool_acct_proof, steth_acct_proof] +
        pool_storage_proofs +
        steth_storage_proofs
    )

    print(f"\nBlock number: {block_header.number}\n")
    print("Header:\n")
    print(f"0x{header_blob.hex()}\n")
    print("Proof:\n")
    print(f"0x{proofs_blob.hex()}\n")

    exit(0)


def get_oracle_contract(address, w3):
    dir = os.path.dirname(__file__)
    interface_path = os.path.join(dir, '../interfaces/StableSwapStateOracle.json')
    with open(interface_path) as abi_file:
        abi = json.load(abi_file)
        return w3.eth.contract(address=address, abi=abi)


def generate_proof_data(
    rpc_endpoint,
    block_number,
    pool_address,
    steth_address,
    pool_slots,
    steth_slots,
):
    block_number = \
        block_number if block_number == "latest" or block_number == "earliest" \
        else hex(int(block_number))

    block_header = request_block_header(
        rpc_endpoint=rpc_endpoint,
        block_number=block_number,
    )

    (pool_acct_proof, pool_storage_proofs) = request_account_proof(
        rpc_endpoint=rpc_endpoint,
        block_number=block_header.number,
        address=pool_address,
        slots=pool_slots,
    )

    (steth_acct_proof, steth_storage_proofs) = request_account_proof(
        rpc_endpoint=rpc_endpoint,
        block_number=block_header.number,
        address=steth_address,
        slots=steth_slots,
    )

    return (
        block_header,
        pool_acct_proof,
        steth_acct_proof,
        pool_storage_proofs,
        steth_storage_proofs,
    )


if __name__ == "__main__":
    main()
