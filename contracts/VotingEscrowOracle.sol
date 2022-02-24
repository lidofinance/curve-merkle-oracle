// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

interface AnyCallProxy {
    function context() external view returns(address, uint256);
}

contract VotingEscrowOracle {
    /// Hash of the block header for the Ethereum genesis block
    bytes32 constant GENESIS_BLOCKHASH = 0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3;

    /// Address of the AnyCallProxy for the chain this contract is deployed on
    address public immutable ANYCALL;

    /// Mapping of Ethereum block number to blockhash
    mapping(uint256 => bytes32) private _eth_blockhash;
    /// Last Ethereum block number which had its blockhash stored
    uint256 public last_eth_block_number;

    /// Owner of the contract with special privileges
    address public owner;
    /// Future owner of the contract
    address public future_owner;

    /// Log a blockhash update
    event SetBlockhash(uint256 _eth_block_number, bytes32 _eth_blockhash);
    /// Log a transfer of ownership
    event TransferOwnership(address _old_owner, address _new_owner);

    constructor(address _anycall) {
        _eth_blockhash[0] = GENESIS_BLOCKHASH;
        emit SetBlockhash(0, GENESIS_BLOCKHASH);

        owner = msg.sender;
        emit TransferOwnership(address(0), msg.sender);

        ANYCALL = _anycall;
    }

    /**
      * @notice Get the Ethereum blockhash for block number `_eth_block_number`
      * @dev Reverts if the blockhash is unavailable, value in storage is `bytes32(0)`
      * @param _eth_block_number The block number to query the blockhash of
      * @return eth_blockhash The blockhash of `_eth_block_number`
      */
    function get_eth_blockhash(uint256 _eth_block_number) public view returns(bytes32 eth_blockhash) {
        eth_blockhash = _eth_blockhash[_eth_block_number];
        require(eth_blockhash != bytes32(0)); // dev: blockhash unavailable
    }

    /**
      * @notice Set the Ethereum blockhash for `_eth_block_number` in storage
      * @param _eth_block_number The block number to set the blockhash of
      * @param __eth_blockhash The blockhash to set in storage
      */
    function set_eth_blockhash(uint256 _eth_block_number, bytes32 __eth_blockhash) external {
        // either a cross-chain call from `self` or `owner` is valid to set the blockhash
        if (msg.sender == ANYCALL) {
           (address sender, uint256 from_chain_id) = AnyCallProxy(msg.sender).context();
           require(sender == address(this) && from_chain_id == 1); // dev: only root self
        } else {
            require(msg.sender == owner); // dev: only owner
        }

        // set the blockhash in storage
        _eth_blockhash[_eth_block_number] = __eth_blockhash;
        emit SetBlockhash(_eth_block_number, __eth_blockhash);

        // update the last block number stored
        if (_eth_block_number > last_eth_block_number) {
            last_eth_block_number = _eth_block_number;
        }
    }

    /**
      * @notice Commit the future owner to storage for later transfer to
      * @param _future_owner The address of the future owner
      */
    function commit_transfer_ownership(address _future_owner) external {
        require(msg.sender == owner); // dev: only owner
        future_owner = _future_owner;
    }

    /**
      * @notice Accept the transfer of ownership
      * @dev Only callable by the future owner
      */
    function accept_transfer_ownership() external {
        require(msg.sender == future_owner); // dev: only future owner
        emit TransferOwnership(owner, msg.sender);
        owner = msg.sender;
    }
}
