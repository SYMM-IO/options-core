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
	/// @notice Any party can fill the existing open intent on behalf of partyB if it has the suitable signature from the partyB
	/// @param signedFillOpenIntent The pure data of signature that partyB wants to fill the open order
	/// @param partyBSignature The signature of partyB
	function instantFillOpenIntent(
		SignedFillIntentById calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		InstantActionsFacetImpl.instantFillOpenIntent(signedFillOpenIntent, partyBSignature);
		OpenIntent storage intent = IntentStorage.layout().openIntents[signedFillOpenIntent.intentId];
		emit FillOpenIntent(intent.id, intent.tradeId, intent.partyA, intent.partyB, signedFillOpenIntent.quantity, signedFillOpenIntent.price);
	}

	/// @notice Any party can close a trade on behalf of partyB if it has the suitable signature from the partyB
	/// @param signedFillCloseIntent The pure data of signature that partyB wants to fill the close order
	/// @param partyBSignature The signature of partyB
	function instantFillCloseIntent(
		SignedFillIntentById calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		InstantActionsFacetImpl.instantFillCloseIntent(signedFillCloseIntent, partyBSignature);
		CloseIntent storage intent = IntentStorage.layout().closeIntents[signedFillCloseIntent.intentId];
		Trade storage trade = IntentStorage.layout().trades[intent.tradeId];
		emit FillCloseIntent(intent.id, trade.id, trade.partyA, trade.partyB, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}

	/// @notice Any party can lock an open intent on behalf of partyB if it has the suitable signature from the partyB
	/// @param signedLockIntent The pure data of intent that is going to be locked
	/// @param partyBSignature The signature of partyB
	function instantLock(
		SignedSimpleActionIntent calldata signedLockIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		InstantActionsFacetImpl.instantLock(signedLockIntent, partyBSignature);
		OpenIntent storage intent = IntentStorage.layout().openIntents[signedLockIntent.intentId];
		emit LockOpenIntent(intent.partyB, signedLockIntent.intentId);
	}

	/// @notice Any party can unlock an open intent on behalf of partyB if it has the suitable signature from the partyB
	/// @param signedUnlockIntent The pure data of intent that is going to be unlocked
	/// @param partyBSignature The signature of partyB
	function instantUnlock(
		SignedSimpleActionIntent calldata signedUnlockIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		IntentStatus res = InstantActionsFacetImpl.instantUnlock(signedUnlockIntent, partyBSignature);
		if (res == IntentStatus.EXPIRED) {
			emit ExpireOpenIntent(signedUnlockIntent.intentId);
		} else if (res == IntentStatus.PENDING) {
			emit UnlockOpenIntent(signedUnlockIntent.signer, signedUnlockIntent.intentId);
		}
	}

	/// @notice Any party can fill an open intent on behalf of partyB if it has the suitable signature from the partyB and partyA
	/// @param signedOpenIntent The pure data of intent that partyA wants to broadcast
	/// @param partyASignature The signature of partyA
	/// @param signedFillOpenIntent The pure data of signature that partyB wants to fill the open order
	/// @param partyBSignature The signature of partyB
	function instantCreateAndFillOpenIntent(
		SignedOpenIntent calldata signedOpenIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		uint256 intentId = InstantActionsFacetImpl.instantCreateAndFillOpenIntent(
			signedOpenIntent,
			partyASignature,
			signedFillOpenIntent,
			partyBSignature
		);
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
			intent.penalty,
			intent.exerciseFee,
			intent.tradingFee,
			intent.deadline
		);
		emit FillOpenIntent(intent.id, intent.tradeId, intent.partyA, intent.partyB, signedFillOpenIntent.quantity, signedFillOpenIntent.price);
	}

	/// @notice Any party can close a trade on behalf of partyB if it has the suitable signature from the partyB and partyA
	/// @param signedCloseIntent The pure data of close intent that partyA wants to broadcast
	/// @param partyASignature The signature of partyA
	/// @param signedFillCloseIntent The pure data of signature that partyB wants to fill the close order
	/// @param partyBSignature The signature of partyB
	function instantCreateAndFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		uint256 intentId = InstantActionsFacetImpl.instantCreateAndFillCloseIntent(
			signedCloseIntent,
			partyASignature,
			signedFillCloseIntent,
			partyBSignature
		);
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

	/// @notice Any party can cancel an open intent on behalf of parties if it has the suitable signature from the partyB and partyA
	/// @param signedCancelOpenIntent The pure data of open intent that partyA wants to cancel
	/// @param partyASignature The signature of partyA
	/// @param signedAcceptCancelOpenIntent The pure data of signature that partyB wants to accept the cancel open intent
	/// @param partyBSignature The signature of partyB
	function instantCancelOpenIntent(
		SignedSimpleActionIntent calldata signedCancelOpenIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
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

	/// @notice Any party can cancel a close intent on behalf of parties if it has the suitable signature from the partyB and partyA
	/// @param signedCancelCloseIntent The pure data of close intent that partyA wants to cancel
	/// @param partyASignature The signature of partyA
	/// @param signedAcceptCancelCloseIntent The pure data of signature that partyB wants to accept the cancel close intent
	/// @param partyBSignature The signature of partyB
	function instantCancelCloseIntent(
		SignedSimpleActionIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
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
