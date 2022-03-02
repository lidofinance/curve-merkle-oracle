import json
import os

import numpy as np
import requests
from brownie import ETH_ADDRESS, StateSender, convert, interface, web3
from eth_abi import decode_single
from web3.datastructures import AttributeDict

# Assign constants
ETHPLORER_API_KEY = os.getenv("ETHPLORER_API_KEY", "freekey")
MULTICALL = "0xeefBa1e63905eF1D7ACbA5a8513c70307C1cE441"
VOTING_ESCROW = "0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2"

# Query the addresses of the top 50 veCRV holders
resp = requests.get(
    f"https://api.ethplorer.io/getTopTokenHolders/{VOTING_ESCROW}",
    params={"apiKey": ETHPLORER_API_KEY, "limit": "10"},
)
assert resp.ok, "Failed to query top 50 veCRV holders"
holders = [holder["address"] for holder in resp.json()["holders"]]

# Assign list of block numbers to generate data for, starting from 11863283
block_numbers = np.linspace(11863283, 14297900, num=15, dtype=int).tolist()


class Web3Encoder(json.JSONEncoder):
    """JSON Encoder for special types"""

    def default(self, obj):
        if isinstance(obj, AttributeDict):
            return dict(obj)
        elif isinstance(obj, bytes):
            return obj.hex()
        else:
            return json.JSONEncoder.default(self, obj)


def main():
    multicall = interface.Multicall(MULTICALL)
    eth_call_kwargs = {
        "transaction": {
            "to": MULTICALL,
            "data": multicall.aggregate.encode_input(
                [(ETH_ADDRESS, "0x80dc72db" + "00" * 12 + holder[2:]) for holder in holders]
            ),
        },
        "state_override": {ETH_ADDRESS: {"code": StateSender._build["deployedBytecode"]}},
    }

    for block_number in block_numbers:
        # make necessary directory if it doesn't exist
        directory_path = f"tests/data/block_{block_number}"
        os.makedirs(directory_path, exist_ok=True)
        # store the block data
        with open(os.path.join(directory_path, "block.json"), "w") as f:
            json.dump(web3.eth.get_block(block_number), f, cls=Web3Encoder)

        # now need to generate the proofs that each of the holders will submit
        # first we calculate the slots we will need using the StateSender contract
        # since it doesn't exist we will use state_override + an archive node
        eth_call_kwargs.update(block_identifier=block_number)  # update the dictionary in-place
        _, encoded_array = multicall.aggregate.decode_output(web3.eth.call(**eth_call_kwargs))

        for holder, encoded_proof_args in zip(holders, encoded_array):
            proof_args = decode_single("(address,uint256[20],uint256)", encoded_proof_args)
            proofs = web3.eth.get_proof(convert.to_address(proof_args[0]), *proof_args[1:])

            with open(os.path.join(directory_path, f"proofs_{holder}.json"), "w") as f:
                json.dump(proofs, f, cls=Web3Encoder)
