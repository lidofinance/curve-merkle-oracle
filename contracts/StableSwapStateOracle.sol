// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "hamdiallam/Solidity-RLP@2.0.3/contracts/RLPReader.sol";
import {StateProofVerifier} from "./StateProofVerifier.sol";


contract StableSwapStateOracle {
    // Prevent reporitng data that is more fresh than this number of blocks ago
    uint256 constant public MIN_BLOCK_DELAY = 15;

    // Constants for offchain proof generation

    address constant public POOL_ADDRESS = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant public STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    // keccak256(abi.encodePacked(uint256(1)))
    bytes32 constant public POOL_ADMIN_BALANCES_0_POS = 0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6;

    // bytes32(uint256(POOL_ADMIN_BALANCES_0_POS) + 1)
    bytes32 constant public POOL_ADMIN_BALANCES_1_POS = 0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf7;

    // Constants for onchain proof verification

    // keccak256(abi.encodePacked(POOL_ADDRESS))
    bytes32 constant POOL_ADDRESS_HASH = 0xc70f76036d72b7bb865881e931082ea61bb4f13ec9faeb17f0591b18b6fafbd7;

    // keccak256(abi.encodePacked(STETH_ADDRESS))
    bytes32 constant STETH_ADDRESS_HASH = 0x6c958a912fe86c83262fbd4973f6bd042cef76551aaf679968f98665979c35e7;

    // keccak256(abi.encodePacked(POOL_ADMIN_BALANCES_0_POS))
    bytes32 constant POOL_ADMIN_BALANCES_0_HASH = 0xb5d9d894133a730aa651ef62d26b0ffa846233c74177a591a4a896adfda97d22;

    // keccak256(abi.encodePacked(POOL_ADMIN_BALANCES_1_POS)
    bytes32 constant POOL_ADMIN_BALANCES_1_HASH = 0xea7809e925a8989e20c901c4c1da82f0ba29b26797760d445a0ce4cf3c6fbd31;


    function getProofParams() external view returns (
        address poolAddress,
        address stethAddress,
        bytes32 poolAdminEtherBalancePos,
        bytes32 poolAdminCoinBalancePos
    ) {
        return (
            POOL_ADDRESS,
            STETH_ADDRESS,
            POOL_ADMIN_BALANCES_0_POS,
            POOL_ADMIN_BALANCES_1_POS
        );
    }


    struct StableSwapState {
        uint256 timestamp;
        uint256 etherBalance;
        uint256 coinBalance;
        uint256 adminEtherBalance;
        uint256 adminCoinBalance;
    }


    StableSwapState public state;


    function getState() external view returns (
        uint256 timestamp,
        uint256 etherBalance,
        uint256 coinBalance,
        uint256 adminEtherBalance,
        uint256 adminCoinBalance
    ) {
        return (
            state.timestamp,
            state.etherBalance,
            state.coinBalance,
            state.adminEtherBalance,
            state.adminCoinBalance
        );
    }


    function submitState(bytes memory _blockHeaderRlpBytes, bytes memory _proofRlpBytes) external {
        StateProofVerifier.BlockHeader memory blockHeader;
        StateProofVerifier.Account memory account;
        StateProofVerifier.SlotValue[] memory slots;

        bytes32[] memory slotHashes = new bytes32[](2);
        slotHashes[0] = POOL_ADMIN_BALANCES_0_HASH;
        slotHashes[1] = POOL_ADMIN_BALANCES_1_HASH;

        (blockHeader, account, slots) = StateProofVerifier.verifyStateProof(
          POOL_ADDRESS_HASH,
          slotHashes,
          _blockHeaderRlpBytes,
          _proofRlpBytes
        );

        // ensure that the block is actually in the blockchain
        require(blockHeader.hash == blockhash(blockHeader.number), "blockhash mismatch");

        uint256 currentBlock = block.number;

        // ensure block finality
        require(
            currentBlock > blockHeader.number &&
            currentBlock - blockHeader.number >= MIN_BLOCK_DELAY,
            "block too fresh"
        );

        require(account.exists, "account.exists");
        require(slots[0].exists, "slots[0].exists");
        require(slots[1].exists, "slots[1].exists");

        state = StableSwapState(
            blockHeader.timestamp,
            account.balance,
            0, // TODO: coinBalance
            slots[0].value,
            slots[1].value
        );
    }

}
