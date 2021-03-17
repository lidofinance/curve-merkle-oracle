# Trustless price oracle for ETH/stETH Curve pool

A trustless oracle for the ETH/stETH Curve pool using Merkle Patricia proofs of Ethereum state.
It provides the interface identical to the one of the actual Curve pool.

The oracle currently assumes that the pool's `fee` and `A` (amplification coefficient) values don't
change between the report and `get_dy` call.


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

* [`StableSwapStateOracle.sol`] is the contract that receives and verifies the report from the
  offchain code, and persists the verified state along with its timestamp.

* [`StableSwapPriceOracle.vy`] is the contract that provides the `det_dy` function, using the
  persisted state from `StableSwapStateOracle`.


[`StableSwapStateOracle.sol`]: ./contracts/StableSwapStateOracle.sol
[`StableSwapPriceOracle.vy`]: ./contracts/StableSwapPriceOracle.vy


## Deploying and using contracts

First, deploy `StableSwapStateOracle`. Then, deploy `StableSwapPriceOracle`, pointing it
to `StableSwapStateOracle` using the constructor param:

```python
# assuming eth-brownie console
state_oracle = StableSwapStateOracle.deploy({ 'from': deployer })
price_oracle = StableSwapPriceOracle.deploy(state_oracle, { 'from': deployer })
```

To send proofs to the state oracle, call `submitState` function:

```python
header_rlp_bytes = b"<header data>"
proofs_rlp_bytes = b"<proofs data>"

tx = state_oracle.submitState(header_rlp_bytes, proofs_rlp_bytes, { 'from': reporter })
```

The function is permissionless and, upon successful verification, will generate two events,
`NewSlotValues` and `NewBalances`, and update the `state` struct with the verified pool
balances. You can access the balances by calling `getState`:

```python
(timestamp, etherBalance, stethBalance) = state_oracle.getState()
```

To get stETH price, use the price oracle's `get_dy` function:

```python
eth_for_1_steth = price_oracle.get_dy(1, 0, 10**18)
```

The price oracle provides the following functions:

```python
def state_oracle() -> address: view
def data_timestamp() -> uint256: view

# Curve StableSwap interface
def get_dy(i: int128, j: int128, dx: uint256) -> uint256: view
def A() -> uint256: view
def A_precise() -> uint256: view
def balances(i: uint256) -> uint256: view
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
* Skip the `--gas-price` flag to use gas prive determined by the node.
* Skip the `--block` flag to generate a proof correnspoding to the block `latest - 15`.
