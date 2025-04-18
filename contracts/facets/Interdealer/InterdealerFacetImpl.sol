// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../libraries/LibScheduledReleaseBalance.sol";
import { TransferIntentOps } from "../../libraries/LibTransferIntent.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { TransferIntent, IntentStorage, Trade, TransferIntentStatus } from "../../storages/IntentStorage.sol";

library InterdealerFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using TransferIntentOps for TransferIntent;

	function sendTransferIntent(
		uint256 tradeId,
		address[] memory partyBWhitelist,
		uint256 proposedPrice,
		uint256 deadline
	) internal returns (uint256 intentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		intentId = ++intentLayout.lastTransferIntentId;
		TransferIntent memory intent = TransferIntent({
			id: intentId,
			tradeId: tradeId,
			deadline: deadline,
			sender: msg.sender,
			whitelist: partyBWhitelist,
			receiver: address(0),
			proposedPrice: proposedPrice,
			status: TransferIntentStatus.PENDING
		});
		intentLayout.transferIntents[intentId] = intent;

		accountLayout.balances[intent.sender][intent.getSymbol().collateral].isolatedSub(intent.getPremium(), DecreaseBalanceReason.PREMIUM);
	}

	function cancelTransferIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		TransferIntent storage intent = intentLayout.transferIntents[intentId];

		if (intent.status == TransferIntentStatus.LOCKED) {
			intent.status = TransferIntentStatus.CANCEL_PENDING;
		} else if (intent.status == TransferIntentStatus.PENDING) {
			intent.status = TransferIntentStatus.CANCELED;
			address collateral = intent.getSymbol().collateral;
			accountLayout.balances[intent.sender][collateral].instantIsolatedAdd(intent.getPremium(), IncreaseBalanceReason.PREMIUM);
		} else {
			revert("InterdealerFacet: Invalid state");
		}
	}

	function lockTransferIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		TransferIntent storage intent = intentLayout.transferIntents[intentId];

		require(intent.status == TransferIntentStatus.PENDING, "InterdealerFacet: Invalid state");

		intent.status = TransferIntentStatus.LOCKED;
		intent.receiver = msg.sender;
	}

	function unlockTransferIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		TransferIntent storage intent = intentLayout.transferIntents[intentId];

		require(intent.status == TransferIntentStatus.LOCKED, "InterdealerFacet: Invalid state");
		require(intent.receiver == msg.sender, "InterdealerFacet: Intent is locked by another partyB");

		intent.status = TransferIntentStatus.PENDING;
		intent.receiver = address(0);
	}

	function acceptCancelTransferIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		TransferIntent storage intent = intentLayout.transferIntents[intentId];

		require(intent.status == TransferIntentStatus.CANCEL_PENDING, "InterdealerFacet: Invalid state");
		require(intent.receiver == msg.sender, "InterdealerFacet: Intent is locked by another partyB");

		address collateral = intent.getSymbol().collateral;
		accountLayout.balances[intent.sender][collateral].instantIsolatedAdd(intent.getPremium(), IncreaseBalanceReason.PREMIUM);

		intent.status = TransferIntentStatus.CANCELED;
	}

	function finalizeTransferIntent(uint256 intentId, uint256 fillPrice, bytes calldata clearingHouseSignature) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		TransferIntent storage intent = intentLayout.transferIntents[intentId];

		require(intent.status == TransferIntentStatus.LOCKED, "InterdealerFacet: Invalid state");
		require(intent.receiver == msg.sender, "InterdealerFacet: Intent is locked by another partyB");

		uint256 proposedPremium = intent.getPremium();
		uint256 filledPremium = intent.getPremiumWithPrice(fillPrice);

		address collateral = intent.getSymbol().collateral;
		accountLayout.balances[intent.receiver][collateral].instantIsolatedAdd(filledPremium, IncreaseBalanceReason.PREMIUM);
		if (proposedPremium - filledPremium > 0) {
			accountLayout.balances[intent.sender][collateral].instantIsolatedAdd(proposedPremium - filledPremium, IncreaseBalanceReason.PREMIUM);
		}

		intent.status = TransferIntentStatus.FINALIZED;

		Trade storage trade = intent.getTrade();
		trade.partyB = intent.receiver;
	}
}
