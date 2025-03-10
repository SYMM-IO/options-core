// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibIntent.sol";
import "../../libraries/LibPartyB.sol";
import "../../libraries/LibMuon.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";

library InterdealerFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

	function sendTransferIntent(
		uint256 tradeId,
		address[] memory partyBWhitelist,
		uint256 proposedPrice,
		uint256 deadline
	) internal returns (uint256 intentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

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

		Trade storage trade = intentLayout.trades[intent.tradeId];
		Symbol storage symbol = symbolLayout.symbols[trade.symbolId];

		uint256 premium = proposedPrice * (trade.quantity - trade.closedAmountBeforeExpiration);
		accountLayout.balances[msg.sender][symbol.collateral].sub(premium);
	}

	function cancelTransferIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		TransferIntent storage intent = intentLayout.transferIntents[intentId];

		if (intent.status == TransferIntentStatus.LOCKED) {
			intent.status = TransferIntentStatus.CANCEL_PENDING;
		} else {
			intent.status = TransferIntentStatus.CANCELED;
		}
	}

	function lockTransferIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		TransferIntent storage intent = intentLayout.transferIntents[intentId];
		intent.status = TransferIntentStatus.LOCKED;
		intent.receiver = msg.sender;
	}

	function unlockTransferIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		TransferIntent storage intent = intentLayout.transferIntents[intentId];
		intent.status = TransferIntentStatus.LOCKED;
		intent.receiver = address(0);
	}

	function acceptCancelTransferIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		TransferIntent storage intent = intentLayout.transferIntents[intentId];
		intent.status = TransferIntentStatus.CANCELED;
	}

	function FinalizeTransferIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		TransferIntent storage intent = intentLayout.transferIntents[intentId];
		intent.status = TransferIntentStatus.FINALIZED;

	}
}
