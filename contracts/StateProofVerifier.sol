// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import {RLPReader} from "skozin/Solidity-RLP@2.0.4/contracts/RLPReader.sol";
import {MerklePatriciaProofVerifier} from "./MerklePatriciaProofVerifier.sol";


library StateProofVerifier {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    uint256 constant HEADER_STATE_ROOT_INDEX = 3;
    uint256 constant HEADER_NUMBER_INDEX = 8;
    uint256 constant HEADER_TIMESTAMP_INDEX = 11;

    struct BlockHeader {
        bytes32 hash;
        bytes32 stateRootHash;
        uint256 number;
        uint256 timestamp;
    }

    struct Account {
        bool exists;
        uint256 nonce;
        uint256 balance;
        bytes32 storageRoot;
        bytes32 codeHash;
    }

    struct SlotValue {
        bool exists;
        uint256 value;
    }


    function verifyStateProof(
        bytes32 _addressHash, // keccak256(abi.encodePacked(address))
        bytes32[] memory _slotHashes, // keccak256(abi.encodePacked(uint256(slotIndex)))
        bytes memory _blockHeaderRlpBytes, // RLP([parentHash, sha3Uncles, miner, ...])
        bytes memory _proofRlpBytes // RLP([accountProof, [slotProofs...]])
    )
        internal pure returns (
            BlockHeader memory blockHeader,
            Account memory account,
            SlotValue[] memory slots
        )
    {
        blockHeader = parseBlockHeader(_blockHeaderRlpBytes);

        RLPReader.RLPItem[] memory proofs = _proofRlpBytes.toRlpItem().toList();
        require(proofs.length == 2);

        account = extractAccountFromProof(
            _addressHash,
            blockHeader.stateRootHash,
            proofs[0].toList()
        );

        slots = new SlotValue[](_slotHashes.length);

        if (!account.exists || _slotHashes.length == 0) {
            return (blockHeader, account, slots);
        }

        RLPReader.RLPItem[] memory slotProofs = proofs[1].toList();
        require(slotProofs.length == _slotHashes.length);

        for (uint256 i = 0; i < _slotHashes.length; ++i) {
            RLPReader.RLPItem[] memory slotProof = slotProofs[i].toList();
            slots[i] = extractSlotValueFromProof(_slotHashes[i], account.storageRoot, slotProof);
        }

        return (blockHeader, account, slots);
    }


    function verifyBlockHeader(bytes memory _headerRlpBytes)
        internal view returns (BlockHeader memory)
    {
        BlockHeader memory header = parseBlockHeader(_headerRlpBytes);
        // ensure that the block is actually in the blockchain
        require(header.hash == blockhash(header.number), "blockhash mismatch");
        return header;
    }


    function parseBlockHeader(bytes memory _headerRlpBytes)
        internal pure returns (BlockHeader memory)
    {
        BlockHeader memory result;
        RLPReader.RLPItem[] memory headerFields = _headerRlpBytes.toRlpItem().toList();

        result.stateRootHash = bytes32(headerFields[HEADER_STATE_ROOT_INDEX].toUint());
        result.number = headerFields[HEADER_NUMBER_INDEX].toUint();
        result.timestamp = headerFields[HEADER_TIMESTAMP_INDEX].toUint();
        result.hash = keccak256(_headerRlpBytes);

        return result;
    }


    function extractAccountFromProof(
        bytes32 _addressHash, // keccak256(abi.encodePacked(address))
        bytes32 _stateRootHash,
        RLPReader.RLPItem[] memory _proof
    )
        internal pure returns (Account memory)
    {
        bytes memory acctRlpBytes = MerklePatriciaProofVerifier.extractProofValue(
            _stateRootHash,
            abi.encodePacked(_addressHash),
            _proof
        );

        Account memory account;

        if (acctRlpBytes.length == 0) {
            return account;
        }

        RLPReader.RLPItem[] memory acctFields = acctRlpBytes.toRlpItem().toList();
        require(acctFields.length == 4);

        account.exists = true;
        account.nonce = acctFields[0].toUint();
        account.balance = acctFields[1].toUint();
        account.storageRoot = bytes32(acctFields[2].toUint());
        account.codeHash = bytes32(acctFields[3].toUint());

        return account;
    }


    function extractSlotValueFromProof(
        bytes32 _slotHash,
        bytes32 _storageRootHash,
        RLPReader.RLPItem[] memory _proof
    )
        internal pure returns (SlotValue memory)
    {
        bytes memory valueRlpBytes = MerklePatriciaProofVerifier.extractProofValue(
            _storageRootHash,
            abi.encodePacked(_slotHash),
            _proof
        );

        SlotValue memory value;

        if (valueRlpBytes.length != 0) {
            value.exists = true;
            value.value = valueRlpBytes.toRlpItem().toUint();
        }

        return value;
    }

}
