# Curve StableSwap state oracle

This repo implements a trustless oracle of a Curve StableSwap pool using Merkle Patricia proofs
of Ethereum state.


## Playing with the code

Generate the proof:

```text
python3 offchain/generate_state_proof.py \
  --rpc http://host.docker.internal:9545 \
  --address 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022 \
  --slot-positions 0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6 \
                   0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf7 \
  --block-number 12020099
```

Submit the proof and read the state (inside brownie console):

```
tx = oracle.submitState(blockHeader, proof)
oracle.getState()
```
