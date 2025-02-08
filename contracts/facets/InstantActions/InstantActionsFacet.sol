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
	function instantLock(SignedSimpleActionIntent calldata signedLockIntent, bytes calldata partyBSignature) external whenNotPartyBActionsPaused {
		InstantActionsFacetImpl.instantLock(signedLockIntent, partyBSignature);
		OpenIntent storage intent = IntentStorage.layout().openIntents[signedLockIntent.intentId];
		emit LockOpenIntent(intent.partyB, signedLockIntent.intentId);
	}

	function instantUnlock(SignedSimpleActionIntent calldata signedUnlockIntent, bytes calldata partyBSignature) external whenNotPartyBActionsPaused {
		IntentStatus res = InstantActionsFacetImpl.instantUnlock(signedUnlockIntent, partyBSignature);
		if (res == IntentStatus.EXPIRED) {
			emit ExpireOpenIntent(signedUnlockIntent.intentId);
		} else if (res == IntentStatus.PENDING) {
			emit UnlockOpenIntent(signedUnlockIntent.signer, signedUnlockIntent.intentId);
		}
	}

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
			intent.exerciseFee,
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
		emit SendCloseIntent(
			trade.partyA,
			trade.partyB,
			trade.id,
			intentId,
			signedFillCloseIntent.price,
			signedFillCloseIntent.quantity,
			signedCloseIntent.deadline,
			IntentStatus.PENDING
		);
		emit FillCloseIntent(intentId, trade.id, trade.partyA, trade.partyB, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}

	function instantCancelOpenIntent(
		SignedSimpleActionIntent calldata signedCancelOpenIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused {
		IntentStatus result = InstantActionsFacetImpl.instantCancelOpenIntent(
			signedCancelOpenIntent,
			partyASignature,
			signedAcceptCancelOpenIntent,
			partyBSignature
		);
		OpenIntent memory intent = IntentStorage.layout().openIntents[signedCancelOpenIntent.intentId];
		if (result == IntentStatus.EXPIRED) {
			emit ExpireOpenIntent(intent.id);
		} else if (result == IntentStatus.CANCELED) {
			emit CancelOpenIntent(intent.partyA, intent.partyB, result, intent.id);
		}
	}

	function instantCancelCloseIntent(
		SignedSimpleActionIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		IntentStatus result = InstantActionsFacetImpl.instantCancelCloseIntent(
			signedCancelCloseIntent,
			partyASignature,
			signedAcceptCancelCloseIntent,
			partyBSignature
		);
		Trade memory trade = intentLayout.trades[intentLayout.closeIntents[signedCancelCloseIntent.intentId].tradeId];
		if (result == IntentStatus.EXPIRED) {
			emit ExpireCloseIntent(signedCancelCloseIntent.intentId);
		} else if (result == IntentStatus.CANCEL_PENDING) {
			emit CancelCloseIntent(trade.partyA, trade.partyB, signedCancelCloseIntent.intentId);
		}
	}
}
