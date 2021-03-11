// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "hamdiallam/Solidity-RLP@2.0.3/contracts/RLPReader.sol";
import {StateProofVerifier} from "./StateProofVerifier.sol";


contract Oracle {
    bytes32 constant ADDRESS_HASH = keccak256(abi.encodePacked(address(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022)));

    bytes32 constant SLOT_0_HASH = keccak256(abi.encodePacked(uint256(0)));
    bytes32 constant SLOT_1_HASH = keccak256(abi.encodePacked(uint256(1)));
    bytes32 constant SLOT_2_HASH = keccak256(abi.encodePacked(uint256(2)));


    function submit(bytes memory _blockHeaderRlpBytes, bytes memory _proofRlpBytes)
        public pure returns (
            bytes32 blockHash,
            bool exists,
            uint256 nonce,
            uint256 balance,
            bytes32 storageRoot,
            bytes32 codeHash,
            uint256 slotValue0
        )
    {
        StateProofVerifier.BlockHeader memory blockHeader;
        StateProofVerifier.Account memory account;
        StateProofVerifier.SlotValue[] memory slots;

        bytes32[] memory slotHashes = new bytes32[](1);
        slotHashes[0] = SLOT_2_HASH;

        (blockHeader, account, slots) = StateProofVerifier.verifyStateProof(
          ADDRESS_HASH,
          slotHashes,
          _blockHeaderRlpBytes,
          _proofRlpBytes
        );

        blockHash = blockHeader.hash;
        exists = account.exists;
        nonce = account.nonce;
        balance = account.balance;
        storageRoot = account.storageRoot;
        codeHash = account.codeHash;

        slotValue0 = slots[0].value;
    }

}
