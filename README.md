# Trustless price oracle for ETH/stETH Curve pool

A trustless oracle for the ETH/stETH Curve pool using Merkle Patricia proofs of Ethereum state.

The oracle currently assumes that the pool's `fee` and `A` (amplification coefficient) values don't
change between the time of proof generation and submission.


## Mechanics

The oracle works by generating and verifying Merkle Patricia proofs of the following Ethereum state:

* Curve stETH/ETH pool contract account and the following slots from its storage trie:
  * `admin_balances[0]`
  * `admin_balances[1]`

* stETH contract account and the following slots from its storage trie:
  * `shares[0xDC24316b9AE028F1497c275EB9192a3Ea0f67022]`
  * `keccak256("lido.StETH.totalShares")`
  * `keccak256("lido.Lido.beaconBalance")`
  * `keccak256("lido.Lido.bufferedEther")`
  * `keccak256("lido.Lido.depositedValidators")`
  * `keccak256("lido.Lido.beaconValidators")`


## Contracts

The repo contains two main contracts:

* [`StableSwapStateOracle.sol`] is the main oracle contract. It receives and verifies the report
  from the offchain code, and persists the verified state along with its timestamp.

* [`StableSwapPriceHelper.vy`] is a helper contract used by `StableSwapStateOracle.sol` and written
  in Vyper. It contains the code for calculating exchange price based on the pool state. The code
  is copied from the [actual pool contract] with minimal modifiactions.

[`StableSwapStateOracle.sol`]: ./contracts/StableSwapStateOracle.sol
[`StableSwapPriceHelper.vy`]: ./contracts/StableSwapPriceHelper.vy
[actual pool contract]: https://github.com/curvefi/curve-contract/blob/3fa3b6c/contracts/pools/steth/StableSwapSTETH.vy


## Deploying and using contracts

First, deploy `StableSwapPriceHelper`. Then, deploy `StableSwapStateOracle`, pointing it
to `StableSwapPriceHelper` using the constructor param:

```python
# assuming eth-brownie console

helper = StableSwapPriceHelper.deploy({ 'from': deployer })

price_update_threshold = 300 # 3%
price_update_threshold_admin = deployer

oracle = StableSwapStateOracle.deploy(
  helper,
  price_update_threshold_admin,
  price_update_threshold,
  { 'from': deployer }
)
```

To send proofs to the state oracle, call `submitState` function:

```python
header_rlp_bytes = '0x...'
proofs_rlp_bytes = '0x...'

tx = oracle.submitState(header_rlp_bytes, proofs_rlp_bytes, { 'from': reporter })
```

The function is permissionless and, upon successful verification, will generate two events,
`SlotValuesUpdated` and `PriceUpdated`, and update the oracle with the verified pool balances
and stETH price. You can access them by calling `getState` and `getPrice`:

```python
(timestamp, etherBalance, stethBalance, stethPrice) = oracle.getState()
stethPrice = oracle.getPrice()
print("stETH/ETH price:", stethPrice / 10**18)
```


## Sending oracle transaction

Use the following script to generate and submit a proof to the oracle contract:

```
python offchain/generate_steth_price_proof.py \
  --rpc <HTTP RPC endpoint of a geth full node> \
  --keyfile <path to a JSON file containing an encrypted private key> \
  --gas-price <tx gas price in wei> \
  --contract <state oracle contract address> \
  --block <block number>
```

Some flags are optional:

* Skip the `--keyfile` flag to print the proof without sending a tx.
* Skip the `--gas-price` flag to use gas price determined by the node.
* Skip the `--block` flag to generate a proof correnspoding to the block `latest - 15`.
