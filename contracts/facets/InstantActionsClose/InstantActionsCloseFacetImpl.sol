// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import { ISignatureVerifier } from "../../interfaces/ISignatureVerifier.sol";
import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { LibHash } from "../../libraries/LibHash.sol";
import {PartyBCloseFacetImpl} from "../PartyBClose/PartyBCloseFacetImpl.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage } from "../../storages/AppStorage.sol";
import { OpenIntent, CloseIntent, Trade, IntentStorage, IntentStatus, SignedFillIntentById, SignedSimpleActionIntent, SignedOpenIntent, SignedFillIntent, SignedCloseIntent } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { PartyAOpenFacetImpl } from "../PartyAOpen/PartyAOpenFacetImpl.sol";
import { PartyACloseFacetImpl } from "../PartyAClose/PartyACloseFacetImpl.sol";

library InstantActionsCloseFacetImpl {
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

	function instantFillCloseIntent(SignedFillIntentById calldata signedFillCloseIntent, bytes calldata partyBSignature) internal {
		bytes32 fillCloseIntentHash = LibHash.hashSignedFillCloseIntentById(signedFillCloseIntent);
		verifySignature(fillCloseIntentHash, partyBSignature, signedFillCloseIntent.partyB);

		PartyBCloseFacetImpl.fillCloseIntent(
			signedFillCloseIntent.partyB,
			signedFillCloseIntent.intentId,
			signedFillCloseIntent.quantity,
			signedFillCloseIntent.price
		);
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

		PartyBCloseFacetImpl.fillCloseIntent(signedFillCloseIntent.partyB, intentId, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}

	function instantCancelCloseIntent(
		SignedSimpleActionIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) internal returns (IntentStatus status) {
		bytes32 cancelIntentHash = LibHash.hashSignedCancelCloseIntent(signedCancelCloseIntent);
		verifySignature(cancelIntentHash, partyASignature, signedCancelCloseIntent.signer);

		status = PartyACloseFacetImpl.cancelCloseIntent(signedCancelCloseIntent.signer, signedCancelCloseIntent.intentId);

		if (status == IntentStatus.CANCEL_PENDING) {
			bytes32 acceptCancelIntentHash = LibHash.hashSignedAcceptCancelCloseIntent(signedAcceptCancelCloseIntent);
			verifySignature(acceptCancelIntentHash, partyBSignature, signedAcceptCancelCloseIntent.signer);

			PartyBCloseFacetImpl.acceptCancelCloseIntent(signedAcceptCancelCloseIntent.signer, signedAcceptCancelCloseIntent.intentId);
			status = IntentStatus.CANCELED;
		}
	}
}
