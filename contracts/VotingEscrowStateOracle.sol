// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import {RLPReader} from "./RLPReader.sol";
import {StateProofVerifier as Verifier} from "./StateProofVerifier.sol";

interface AnyCallProxy {
    function context() external view returns(address, uint256);
}

contract VotingEscrowStateOracle {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

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
    /// Hash of the voting escrow contract address
    bytes32 constant VOTING_ESCROW_HASH = keccak256(abi.encodePacked(VOTING_ESCROW));

    /// `VotingEscrow.epoch()` storage slot hash
    bytes32 constant EPOCH_HASH = keccak256(abi.encode(3));

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

    /// Migrated `VotingEscrow` storage variables
    uint256 public epoch;
    Point[100000000000000000000000000000] public point_history;
    mapping(address => uint256) public user_point_epoch;
    mapping(address => Point[1000000000]) public user_point_history;

    mapping(uint256 => int128) public slope_changes;
    mapping(address => LockedBalance) public locked;

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

    function balanceOf(address _user) external view returns(uint256) {
        return balanceOf(_user, block.timestamp);
    }

    function balanceOf(address _user, uint256 _timestamp) public view returns(uint256) {
        uint256 _epoch = user_point_epoch[_user];
        if (_epoch == 0) {
            return 0;
        }
        Point memory last_point = user_point_history[_user][_epoch];
        last_point.bias -= last_point.slope * abi.decode(abi.encode(_timestamp - last_point.ts), (int128));
        if (last_point.bias < 0) {
            return 0;
        }
        return abi.decode(abi.encode(last_point.bias), (uint256));
    }

    function totalSupply() external view returns(uint256) {
        return totalSupply(block.timestamp);
    }

    function totalSupply(uint256 _timestamp) public view returns(uint256) {
        Point memory last_point = point_history[epoch];
        uint256 t_i = (last_point.ts / WEEK) * WEEK;  // value in the past
        for (uint256 i = 0; i < 255; i++) {
            t_i += WEEK;  // + week
            int128 d_slope = 0;
            if (t_i > _timestamp) {
                t_i = _timestamp;
            } else {
                d_slope = slope_changes[t_i];
                if (d_slope == 0) {
                    break;
                }
            }
            last_point.bias -= last_point.slope * abi.decode(abi.encode(t_i - last_point.ts), (int128));
            if (t_i == _timestamp) {
                break;
            }
            last_point.slope += d_slope;
            last_point.ts = t_i;
        }

        if (last_point.bias < 0) {
            return 0;
        }
        return abi.decode(abi.encode(last_point.bias), (uint256));
    }

    function submit_state(address _user, bytes memory _block_header_rlp, bytes memory _proof_rlp) external {
        // verify block header
        Verifier.BlockHeader memory block_header = Verifier.parseBlockHeader(_block_header_rlp);
        require(block_header.hash != bytes32(0)); // dev: invalid blockhash
        require(block_header.hash == _eth_blockhash[block_header.number]); // dev: blockhash mismatch

        // convert _proof_rlp into a list of `RLPItem`s
        RLPReader.RLPItem[] memory proofs = _proof_rlp.toRlpItem().toList();
        require(proofs.length == 21); // dev: invalid number of proofs

        // 0th proof is the account proof for Voting Escrow contract
        Verifier.Account memory ve_account = Verifier.extractAccountFromProof(
            VOTING_ESCROW_HASH, // position of the account is the hash of its address
            block_header.stateRootHash,
            proofs[0].toList()
        );
        require(ve_account.exists); // dev: Voting Escrow account does not exist

        // 1st proof is the `VotingEscrow.epoch()` storage slot proof
        Verifier.SlotValue memory slot_epoch = Verifier.extractSlotValueFromProof(
            EPOCH_HASH,
            ve_account.storageRoot,
            proofs[1].toList()
        );
        require(slot_epoch.exists);

        // 2-5th proof are the `VotingEscrow.point_history(uint256)` slots
        // this is a struct where bias and slope are int128, the position is determined based
        // on the value of `epoch`
        Verifier.SlotValue[4] memory slot_point_history;
        for (uint256 i = 0; i < 4; i++) {
            slot_point_history[i] = Verifier.extractSlotValueFromProof(
                keccak256(abi.encode(uint256(keccak256(abi.encode(uint256(keccak256(abi.encode(4))) + slot_epoch.value))) + i)),
                ve_account.storageRoot,
                proofs[2 + i].toList()
            );
            require(slot_point_history[i].exists); // dev: slot does not exist
        }

        // 6th proof is the `VotingEscrow.user_point_epoch(address)` slot proof
        Verifier.SlotValue memory slot_user_point_epoch = Verifier.extractSlotValueFromProof(
            keccak256(abi.encode(keccak256(abi.encode(6, _user)))),
            ve_account.storageRoot,
            proofs[6].toList()
        );
        require(slot_user_point_epoch.exists); // dev: slot does not exist

        // 7-10th proof are for `VotingEscrow.user_point_history` slots
        // similar to `point_history` this is a struct
        Verifier.SlotValue[4] memory slot_user_point_history;
        for (uint256 i = 0; i < 4; i++) {
            slot_user_point_history[i] = Verifier.extractSlotValueFromProof(
                keccak256(abi.encode(uint256(keccak256(abi.encode(uint256(keccak256(abi.encode(keccak256(abi.encode(5, _user))))) + slot_user_point_epoch.value))) + i)),
                ve_account.storageRoot,
                proofs[7 + i].toList()
            );
            require(slot_user_point_history[i].exists); // dev: slot does not exist
        }

        // 11-12th proof are for `VotingEscrow.locked()` this is a struct with 2 members
        Verifier.SlotValue[2] memory slot_locked;
        for (uint256 i = 0; i < 2; i++) {
            slot_locked[i] = Verifier.extractSlotValueFromProof(
                keccak256(abi.encode(uint256(keccak256(abi.encode(keccak256(abi.encode(2, _user))))) + i)),
                ve_account.storageRoot,
                proofs[11 + i].toList()
            );
            require(slot_locked[i].exists); // dev: slot does not exist
        }

        // Remaining proofs are for 2 months worth of slope changes
        // starting from the week beginning the last global point
        Verifier.SlotValue[8] memory slot_slope_changes;
        for (uint256 i = 0; i < 8; i++) {
            slot_slope_changes[i] = Verifier.extractSlotValueFromProof(
                keccak256(abi.encode(keccak256(abi.encode(7, (slot_point_history[2].value / WEEK) * WEEK + WEEK * i)))),
                ve_account.storageRoot,
                proofs[13 + i].toList()
            );
            require(slot_slope_changes[i].exists); // dev: slot does not exist
        }

        {
            /// incrememt the epoch storage var only if fresh
            /// also update slope changes too
            if (slot_epoch.value > epoch) {
                epoch = slot_epoch.value;

                uint256 start_time = (slot_point_history[2].value / WEEK) * WEEK;
                for (uint256 i = 0; i < 8; i++) {
                    slope_changes[start_time + WEEK * i] = abi.decode(abi.encode(slot_slope_changes[i].value), (int128));
                }
            }
            /// always set the point_history structs
            point_history[slot_epoch.value] = Point(
                abi.decode(abi.encode(slot_point_history[0].value), (int128)), // bias
                abi.decode(abi.encode(slot_point_history[1].value), (int128)), // slope
                slot_point_history[2].value, // ts
                slot_point_history[3].value // blk
            );

            // update the user point epoch and locked balance if it is newer
            if (slot_user_point_epoch.value > user_point_epoch[_user]) {
                user_point_epoch[_user] = slot_user_point_epoch.value;

                locked[_user] = LockedBalance(
                    abi.decode(abi.encode(slot_locked[0].value), (int128)),
                    slot_locked[1].value
                );
            }
            /// always set the point_history structs
            user_point_history[_user][slot_user_point_epoch.value] = Point(
                abi.decode(abi.encode(slot_user_point_history[0].value), (int128)), // bias
                abi.decode(abi.encode(slot_user_point_history[1].value), (int128)), // slope
                slot_user_point_history[2].value, // ts
                slot_user_point_history[3].value // blk
            );
        }
    }

    /**
      * @notice Get the Ethereum blockhash for block number `_eth_block_number`
      * @dev Reverts if the blockhash is unavailable, value in storage is `bytes32(0)`
      * @param _eth_block_number The block number to query the blockhash of
      * @return eth_blockhash The blockhash of `_eth_block_number`
      */
    function get_eth_blockhash(uint256 _eth_block_number) external view returns(bytes32 eth_blockhash) {
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
