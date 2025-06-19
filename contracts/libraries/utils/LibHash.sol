// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SignedOpenIntent, SignedCloseIntent, SignedFillIntent, SignedFillIntentById, SignedSimpleActionIntent } from "../../types/SignedIntentTypes.sol";
import { SignedInternalTransfer, SignedWithdraw, SignedBridgeTransfer, SignedAllocate } from "../../types/SignedAccountTypes.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library LibHash {
	using ECDSA for bytes32;

	function hashSignedOpenIntent(SignedOpenIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioOpenIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		bytes memory encodedData = abi.encode(
			CHAIN_ID,
			addr,
			SIGN_PREFIX,
			req.partyA,
			req.partyB,
			req.price,
			abi.encode(req.symbolId, req.quantity, req.strikePrice, req.expirationTimestamp, req.mm, req.exerciseFee.rate, req.exerciseFee.cap),
			req.marginType,
			req.deadline,
			req.feeToken,
			req.affiliate,
			req.salt
		);

		return keccak256(encodedData).toEthSignedMessageHash();
	}

	function hashSignedCloseIntent(SignedCloseIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioCloseIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return
			keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.partyA, req.tradeId, req.price, req.quantity, req.deadline, req.salt))
				.toEthSignedMessageHash();
	}

	function hashSignedFillOpenIntent(SignedFillIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillOpenIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return
			keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.partyB, req.intentHash, req.price, req.quantity, req.deadline, req.salt))
				.toEthSignedMessageHash();
	}

	function hashSignedFillOpenIntentById(SignedFillIntentById calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillOpenIntentById_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return
			keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.partyB, req.intentId, req.price, req.quantity, req.deadline, req.salt))
				.toEthSignedMessageHash();
	}

	function hashSignedFillCloseIntent(SignedFillIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillCloseIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return
			keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.partyB, req.intentHash, req.price, req.quantity, req.deadline, req.salt))
				.toEthSignedMessageHash();
	}

	function hashSignedFillCloseIntentById(SignedFillIntentById calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillCloseIntentById_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return
			keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.partyB, req.intentId, req.price, req.quantity, req.deadline, req.salt))
				.toEthSignedMessageHash();
	}

	function hashSignedCancelOpenIntent(SignedSimpleActionIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioCancelOpenIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt)).toEthSignedMessageHash();
	}

	function hashSignedAcceptCancelOpenIntent(SignedSimpleActionIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioAcceptCancelOpenIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt)).toEthSignedMessageHash();
	}

	function hashSignedCancelCloseIntent(SignedSimpleActionIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioCancelCloseIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt)).toEthSignedMessageHash();
	}

	function hashSignedAcceptCancelCloseIntent(SignedSimpleActionIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioAcceptCancelCloseIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt)).toEthSignedMessageHash();
	}

	function hashSignedLockIntent(SignedSimpleActionIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioLockIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt)).toEthSignedMessageHash();
	}

	function hashSignedUnlockIntent(SignedSimpleActionIntent calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioUnlockIntent_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt)).toEthSignedMessageHash();
	}

	function hashInternalTransfer(SignedInternalTransfer calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SignedInternalTransfer_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return
			keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.sender, req.receiver, req.collateral, req.amount, req.deadline, req.salt))
				.toEthSignedMessageHash();
	}

	function hashWithdraw(SignedWithdraw calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SignedWithdraw_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return
			keccak256(
				abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.sender, req.receiver, req.collateral, req.amount, req.deadline, req.salt)
			).toEthSignedMessageHash();
	}

	function hashBridgeTransfer(SignedBridgeTransfer calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SignedBridgeTransfer_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return
			keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.sender, req.receiver, req.collateral, req.amount, req.deadline, req.salt))
				.toEthSignedMessageHash();
	}

	function hashSignedAllocate(SignedAllocate calldata req) internal view returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SignedAllocate_v1");
		uint256 CHAIN_ID = block.chainid;
		address addr = address(this);

		return
			keccak256(abi.encode(CHAIN_ID, addr, SIGN_PREFIX, req.signer, req.sender, req.counterParty, req.collateral, req.amount, req.deadline, req.salt))
				.toEthSignedMessageHash();
	}
}
