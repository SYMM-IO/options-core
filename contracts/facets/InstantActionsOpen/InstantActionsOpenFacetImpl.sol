// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibHash } from "../../libraries/LibHash.sol";
import { LibSignature } from "../../libraries/LibSignature.sol";

import { IntentStatus } from "../../types/IntentTypes.sol";
import { TradeAgreements } from "../../types/BaseTypes.sol";
import { SignedFillIntentById, SignedSimpleActionIntent, SignedOpenIntent, SignedFillIntent } from "../../types/SignedIntentTypes.sol";

import { PartyBOpenFacetImpl } from "../PartyBOpen/PartyBOpenFacetImpl.sol";
import { PartyAOpenFacetImpl } from "../PartyAOpen/PartyAOpenFacetImpl.sol";

library InstantActionsOpenFacetImpl {
	function instantCreateAndFillOpenIntent(
		SignedOpenIntent calldata signedOpenIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) internal returns (uint256 intentId, uint256 tradeId, uint256 newIntentId) {
		bytes32 openIntentHash = LibHash.hashSignedOpenIntent(signedOpenIntent);
		LibSignature.verifySignature(openIntentHash, partyASignature, signedOpenIntent.partyA);

		bytes32 fillOpenIntentHash = LibHash.hashSignedFillOpenIntent(signedFillOpenIntent);
		LibSignature.verifySignature(fillOpenIntentHash, partyBSignature, signedFillOpenIntent.partyB);

		address[] memory partyBsWhitelist = new address[](1);
		partyBsWhitelist[0] = signedOpenIntent.partyB;

		intentId = PartyAOpenFacetImpl.sendOpenIntent(
			signedOpenIntent.partyA,
			partyBsWhitelist,
			TradeAgreements({
				symbolId: signedOpenIntent.symbolId,
				quantity: signedOpenIntent.quantity,
				strikePrice: signedOpenIntent.strikePrice,
				expirationTimestamp: signedOpenIntent.expirationTimestamp,
				mm: signedOpenIntent.mm,
				tradeSide: signedOpenIntent.tradeSide,
				marginType: signedOpenIntent.marginType,
				exerciseFee: signedOpenIntent.exerciseFee
			}),
			signedOpenIntent.price,
			signedOpenIntent.deadline,
			signedOpenIntent.feeToken,
			signedOpenIntent.affiliate,
			signedOpenIntent.userData
		);

		PartyBOpenFacetImpl.lockOpenIntent(signedFillOpenIntent.partyB, intentId);
		(tradeId, newIntentId) = PartyBOpenFacetImpl.fillOpenIntent(
			signedFillOpenIntent.partyB,
			intentId,
			signedFillOpenIntent.quantity,
			signedFillOpenIntent.price
		);
	}

	function instantCancelOpenIntent(
		SignedSimpleActionIntent calldata signedCancelOpenIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelOpenIntent,
		bytes calldata partyBSignature
	) internal returns (IntentStatus status) {
		bytes32 cancelIntentHash = LibHash.hashSignedCancelOpenIntent(signedCancelOpenIntent);
		LibSignature.verifySignature(cancelIntentHash, partyASignature, signedCancelOpenIntent.signer);

		status = PartyAOpenFacetImpl.cancelOpenIntent(signedCancelOpenIntent.signer, signedCancelOpenIntent.intentId);

		if (status == IntentStatus.CANCEL_PENDING) {
			bytes32 acceptCancelIntentHash = LibHash.hashSignedAcceptCancelOpenIntent(signedAcceptCancelOpenIntent);
			LibSignature.verifySignature(acceptCancelIntentHash, partyBSignature, signedAcceptCancelOpenIntent.signer);

			PartyBOpenFacetImpl.acceptCancelOpenIntent(signedAcceptCancelOpenIntent.signer, signedAcceptCancelOpenIntent.intentId);
			status = IntentStatus.CANCELED;
		}
	}
}
