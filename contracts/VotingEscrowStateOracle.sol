// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

interface AnyCallProxy {
    function context() external view returns(address, uint256);
}

contract VotingEscrowOracle {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
    }

    /// Address of the voting escrow contract on Ethereum
    address constant VOTING_ESCROW = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    /// Hash of the block header for the Ethereum genesis block
    bytes32 constant GENESIS_BLOCKHASH = 0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3;
    /// Week in seconds
    uint256 constant WEEK = 1 weeks;

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
      * @notice Generate the arguments required for the `eth_getProofs` RPC call
      * @param _user The account the storage proof will be generated for
      * @param _global_epoch The value returned from `VotingEscrow.epoch()`
      * @param _user_epoch The value returned from `VotingEscrow.user_point_epoch(address)`
      * @param _last_point_ts The timestamp of the last global point returned from `VotingEscrow.point_history(uint256)`
      */
    function generate_eth_get_proof_params(
        address _user,
        uint256 _global_epoch,
        uint256 _user_epoch,
        uint256 _last_point_ts
    ) external view returns(address account, uint256[20] memory positions){
        account = VOTING_ESCROW;

        // `VotingEscrow.epoch()`
        positions[0] = 3;

        // `VotingEscrow.point_history(uint256)`
        uint256 point_history_pos = uint256(keccak256(abi.encode(uint256(keccak256(abi.encode(4))) + _global_epoch)));
        positions[1] = point_history_pos; // bias
        positions[2] = point_history_pos + 1; // slope
        positions[3] = point_history_pos + 2; // ts
        positions[4] = point_history_pos + 3; // blk

        // `VotingEscrow.user_point_epoch(address)`
        positions[5] = uint256(keccak256(abi.encode(6, _user)));

        // `VotingEscrow.user_point_history(address,uint256)`
        uint256 user_point_history_pos = uint256(keccak256(abi.encode(uint256(keccak256(abi.encode(keccak256(abi.encode(5, _user))))) + _user_epoch)));
        positions[6] = user_point_history_pos; // bias
        positions[7] = user_point_history_pos + 1; // bias
        positions[8] = user_point_history_pos + 2; // bias
        positions[9] = user_point_history_pos + 3; // bias

        // `VotingEscrow.locked(address)`
        uint256 locked_pos = uint256(keccak256(abi.encode(keccak256(abi.encode(2, _user)))));
        positions[10] = locked_pos;
        positions[11] = locked_pos + 1;

        // `VotingEscrow.slope_changes(uint256)`
        uint256 start_time = (_last_point_ts / WEEK) * WEEK;
        positions[12] = uint256(keccak256(abi.encode(7, start_time)));
        positions[13] = uint256(keccak256(abi.encode(7, start_time + WEEK)));
        positions[14] = uint256(keccak256(abi.encode(7, start_time + WEEK * 2)));
        positions[15] = uint256(keccak256(abi.encode(7, start_time + WEEK * 3)));
        positions[16] = uint256(keccak256(abi.encode(7, start_time + WEEK * 4)));
        positions[17] = uint256(keccak256(abi.encode(7, start_time + WEEK * 5)));
        positions[18] = uint256(keccak256(abi.encode(7, start_time + WEEK * 6)));
        positions[19] = uint256(keccak256(abi.encode(7, start_time + WEEK * 7)));
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
