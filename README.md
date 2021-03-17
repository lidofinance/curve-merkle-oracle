# Trustless state oracle for ETH/stETH Curve pool

A trustless oracle for the ETH/stETH Curve pool balances using Merkle Patricia proofs
of Ethereum state.


## Sending oracle transaction

Use the following command to generate a proof correnspoding to the block `latest - 15`:

```
python offchain/generate_steth_price_proof.py \
  --rpc <RPC endpoint of a geth node> \
  --keyfile <path to a JSON file containing an encrypted private key> \
  --gas-price <tx gas price in wei> \
  --contract <oracle contract address>
```

Skip `--keyfile` and `--gas-price` flags to print the proof without sending a tx.


## Reading the reported balances

Use `oracle.getState()` function that returns a `(timestamp, etherBalance, stethBalance)` tuple
corresponding to the most fresh data, where `timestamp` is the one of the block the proof was
generated for.
