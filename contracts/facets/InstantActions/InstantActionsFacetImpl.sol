// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import { ISignatureVerifier } from "../../interfaces/ISignatureVerifier.sol";
import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { LibHash } from "../../libraries/LibHash.sol";
import { LibIntent } from "../../libraries/LibIntent.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage } from "../../storages/AppStorage.sol";
import { OpenIntent, CloseIntent, Trade, IntentStorage, IntentStatus, SignedFillIntentById, SignedSimpleActionIntent, SignedOpenIntent, SignedFillIntent, SignedCloseIntent } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { PartyAOpenFacetImpl } from "../PartyAOpen/PartyAOpenFacetImpl.sol";
import { PartyACloseFacetImpl } from "../PartyAClose/PartyACloseFacetImpl.sol";
import { PartyBFacetImpl } from "../PartyB/PartyBFacetImpl.sol";

library InstantActionsFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;

	function verifySignature(bytes32 hashValue, bytes calldata signature, address signer) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signer, hashValue, signature),
			"InstantActionsFacet: Invalid signature"
		);
		require(!intentLayout.isSigUsed[hashValue], "InstantActionsFacet: Signature is already used");
		intentLayout.isSigUsed[hashValue] = true;
	}

	function instantFillOpenIntent(SignedFillIntentById calldata signedFillOpenIntent, bytes calldata partyBSignature) internal {
		bytes32 fillOpenIntentHash = LibHash.hashSignedFillOpenIntentById(signedFillOpenIntent);
		verifySignature(fillOpenIntentHash, partyBSignature, signedFillOpenIntent.partyB);

		PartyBFacetImpl.fillOpenIntent(
			signedFillOpenIntent.partyB,
			signedFillOpenIntent.intentId,
			signedFillOpenIntent.quantity,
			signedFillOpenIntent.price
		);
	}

	function instantFillCloseIntent(SignedFillIntentById calldata signedFillCloseIntent, bytes calldata partyBSignature) internal {
		bytes32 fillCloseIntentHash = LibHash.hashSignedFillCloseIntentById(signedFillCloseIntent);
		verifySignature(fillCloseIntentHash, partyBSignature, signedFillCloseIntent.partyB);

		PartyBFacetImpl.fillCloseIntent(
			signedFillCloseIntent.partyB,
			signedFillCloseIntent.intentId,
			signedFillCloseIntent.quantity,
			signedFillCloseIntent.price
		);
	}

	function instantLock(SignedSimpleActionIntent calldata signedLockIntent, bytes calldata partyBSignature) internal {
		bytes32 lockIntentHash = LibHash.hashSignedLockIntent(signedLockIntent);
		verifySignature(lockIntentHash, partyBSignature, signedLockIntent.signer);

		PartyBFacetImpl.lockOpenIntent(signedLockIntent.signer, signedLockIntent.intentId);
	}

	function instantUnlock(SignedSimpleActionIntent calldata signedUnlockIntent, bytes calldata partyBSignature) internal returns (IntentStatus) {
		bytes32 unlockIntentHash = LibHash.hashSignedUnlockIntent(signedUnlockIntent);
		verifySignature(unlockIntentHash, partyBSignature, signedUnlockIntent.signer);

		return PartyBFacetImpl.unlockOpenIntent(signedUnlockIntent.signer, signedUnlockIntent.intentId);
	}

	function instantCreateAndFillOpenIntent(
		SignedOpenIntent calldata signedOpenIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) internal returns (uint256 intentId) {
		bytes32 openIntentHash = LibHash.hashSignedOpenIntent(signedOpenIntent);
		verifySignature(openIntentHash, partyASignature, signedOpenIntent.partyA);

		bytes32 fillOpenIntentHash = LibHash.hashSignedFillOpenIntent(signedFillOpenIntent);
		verifySignature(fillOpenIntentHash, partyBSignature, signedFillOpenIntent.partyB);

		address[] memory partyBsWhitelist = new address[](1);
		partyBsWhitelist[0] = signedOpenIntent.partyB;

		intentId = PartyAOpenFacetImpl.sendOpenIntent(
			signedOpenIntent.partyA,
			partyBsWhitelist,
			signedOpenIntent.symbolId,
			signedOpenIntent.price,
			signedOpenIntent.quantity,
			signedOpenIntent.strikePrice,
			signedOpenIntent.expirationTimestamp,
			signedOpenIntent.penalty,
			signedOpenIntent.exerciseFee,
			signedOpenIntent.deadline,
			signedOpenIntent.feeToken,
			signedOpenIntent.affiliate,
			signedOpenIntent.userData
		);

		PartyBFacetImpl.lockOpenIntent(signedFillOpenIntent.partyB, intentId);

		PartyBFacetImpl.fillOpenIntent(signedFillOpenIntent.partyB, intentId, signedFillOpenIntent.quantity, signedFillOpenIntent.price);
	}

	function instantCreateAndFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) internal returns (uint256 intentId) {
		bytes32 closeIntentHash = LibHash.hashSignedCloseIntent(signedCloseIntent);
		verifySignature(closeIntentHash, partyASignature, signedCloseIntent.partyA);

		bytes32 fillCloseIntentHash = LibHash.hashSignedFillCloseIntent(signedFillCloseIntent);
		verifySignature(fillCloseIntentHash, partyBSignature, signedFillCloseIntent.partyB);

		intentId = PartyACloseFacetImpl.sendCloseIntent(
			signedCloseIntent.partyA,
			signedCloseIntent.tradeId,
			signedCloseIntent.price,
			signedCloseIntent.quantity,
			signedCloseIntent.deadline
		);

		PartyBFacetImpl.fillCloseIntent(signedFillCloseIntent.partyB, intentId, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}

	function instantCancelOpenIntent(
		SignedSimpleActionIntent calldata signedCancelOpenIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelOpenIntent,
		bytes calldata partyBSignature
	) internal returns (IntentStatus status) {
		bytes32 cancelIntentHash = LibHash.hashSignedCancelOpenIntent(signedCancelOpenIntent);
		verifySignature(cancelIntentHash, partyASignature, signedCancelOpenIntent.signer);

		status = PartyAOpenFacetImpl.cancelOpenIntent(signedCancelOpenIntent.signer, signedCancelOpenIntent.intentId);

		if (status == IntentStatus.CANCEL_PENDING) {
			bytes32 acceptCancelIntentHash = LibHash.hashSignedAcceptCancelOpenIntent(signedAcceptCancelOpenIntent);
			verifySignature(acceptCancelIntentHash, partyBSignature, signedAcceptCancelOpenIntent.signer);

			PartyBFacetImpl.acceptCancelOpenIntent(signedAcceptCancelOpenIntent.signer, signedAcceptCancelOpenIntent.intentId);
            status = IntentStatus.CANCELED;
		}
	}

	function instantCancelCloseIntent(
		SignedSimpleActionIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) internal returns (IntentStatus status){
		bytes32 cancelIntentHash = LibHash.hashSignedCancelCloseIntent(signedCancelCloseIntent);
		verifySignature(cancelIntentHash, partyASignature, signedCancelCloseIntent.signer);

		status = PartyACloseFacetImpl.cancelCloseIntent(signedCancelCloseIntent.signer, signedCancelCloseIntent.intentId);

        if (status == IntentStatus.CANCEL_PENDING){
            bytes32 acceptCancelIntentHash = LibHash.hashSignedAcceptCancelCloseIntent(signedAcceptCancelCloseIntent);
            verifySignature(acceptCancelIntentHash, partyBSignature, signedAcceptCancelCloseIntent.signer);
            
		    PartyBFacetImpl.acceptCancelCloseIntent(signedAcceptCancelCloseIntent.signer, signedAcceptCancelCloseIntent.intentId);
            status = IntentStatus.CANCELED;
        }
	}
}
