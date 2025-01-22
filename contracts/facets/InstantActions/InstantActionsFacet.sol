// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./InstantActionsFacetImpl.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./IInstantActionsFacet.sol";

contract InstantActionsFacet is Accessibility, Pausable, IInstantActionsFacet {
	function instantFillOpenIntent(
		SignedOpenIntent calldata signedOpenIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused {
		uint256 intentId = InstantActionsFacetImpl.instantFillOpenIntent(signedOpenIntent, partyASignature, signedFillOpenIntent, partyBSignature);
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];

		emit SendOpenIntent(
			intent.partyA,
			intent.id,
			intent.partyBsWhiteList,
			intent.symbolId,
			intent.price,
			intent.quantity,
			intent.strikePrice,
			intent.expirationTimestamp,
			intent.exerciseFee.rate,
			intent.exerciseFee.cap,
			intent.tradingFee,
			intent.deadline
		);
		emit FillOpenIntent(intent.id, intent.tradeId, intent.partyA, intent.partyB, signedFillOpenIntent.quantity, signedFillOpenIntent.price);
	}

	function instantFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused {
		uint256 intentId = InstantActionsFacetImpl.instantFillCloseIntent(signedCloseIntent, partyASignature, signedFillCloseIntent, partyBSignature);
		Trade storage trade = IntentStorage.layout().trades[signedCloseIntent.tradeId];
		// emit SendCloseIntent(
		// 	trade.partyA,
		// 	trade.partyB,
		// 	trade.id,
		// 	intentId,
		// 	signedFillCloseIntent.price,
		// 	signedFillCloseIntent.quantity,
		// 	signedCloseIntent.deadline,
		// 	IntentStatus.PENDING
		// );
		emit FillCloseIntent(intentId, trade.id, trade.partyA, trade.partyB, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}

	function instantCancelOpenIntent(
		SignedCancelIntent calldata signedCancelOpenIntent,
		bytes calldata partyASignature,
		SignedCancelIntent calldata signedAcceptCancelOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused {
		InstantActionsFacetImpl.instantCancelOpenIntent(signedCancelOpenIntent, partyASignature, signedAcceptCancelOpenIntent, partyBSignature);
	}

	function instantCancelCloseIntent(
		SignedCancelIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedCancelIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused {}
}
