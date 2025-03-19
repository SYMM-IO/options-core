// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ISignatureVerifier } from "../../interfaces/ISignatureVerifier.sol";
import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { LibHash } from "../../libraries/LibHash.sol";
import { PartyBCloseFacetImpl } from "../PartyBClose/PartyBCloseFacetImpl.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { LibSignature } from "../../libraries/LibSignature.sol";
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

	function instantFillCloseIntent(SignedFillIntentById calldata signedFillCloseIntent, bytes calldata partyBSignature) internal {
		bytes32 fillCloseIntentHash = LibHash.hashSignedFillCloseIntentById(signedFillCloseIntent);
		LibSignature.verifySignature(fillCloseIntentHash, partyBSignature, signedFillCloseIntent.partyB);

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
		LibSignature.verifySignature(closeIntentHash, partyASignature, signedCloseIntent.partyA);

		bytes32 fillCloseIntentHash = LibHash.hashSignedFillCloseIntent(signedFillCloseIntent);
		LibSignature.verifySignature(fillCloseIntentHash, partyBSignature, signedFillCloseIntent.partyB);

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
		LibSignature.verifySignature(cancelIntentHash, partyASignature, signedCancelCloseIntent.signer);

		status = PartyACloseFacetImpl.cancelCloseIntent(signedCancelCloseIntent.signer, signedCancelCloseIntent.intentId);

		if (status == IntentStatus.CANCEL_PENDING) {
			bytes32 acceptCancelIntentHash = LibHash.hashSignedAcceptCancelCloseIntent(signedAcceptCancelCloseIntent);
			LibSignature.verifySignature(acceptCancelIntentHash, partyBSignature, signedAcceptCancelCloseIntent.signer);

			PartyBCloseFacetImpl.acceptCancelCloseIntent(signedAcceptCancelCloseIntent.signer, signedAcceptCancelCloseIntent.intentId);
			status = IntentStatus.CANCELED;
		}
	}
}
