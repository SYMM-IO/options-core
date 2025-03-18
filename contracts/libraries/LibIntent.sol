// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../libraries/LibOpenIntent.sol";
import "../libraries/LibCloseIntent.sol";
import "../libraries/LibTrade.sol";
import "../storages/IntentStorage.sol";
import "../storages/AccountStorage.sol";
import "../storages/AppStorage.sol";
import "../storages/SymbolStorage.sol";
import "../interfaces/IPriceOracle.sol";

library LibIntent {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;

	function expireOpenIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.symbolId];

		require(block.timestamp > intent.deadline, "LibIntent: Intent isn't expired");
		require(
			intent.status == IntentStatus.PENDING || intent.status == IntentStatus.CANCEL_PENDING || intent.status == IntentStatus.LOCKED,
			"LibIntent: Invalid state"
		);

		ScheduledReleaseBalance storage partyABalance = accountLayout.balances[intent.partyA][symbol.collateral];
		ScheduledReleaseBalance storage partyAFeeBalance = accountLayout.balances[intent.partyA][intent.tradingFee.feeToken];

		intent.statusModifyTimestamp = block.timestamp;
		partyABalance.instantAdd(symbol.collateral, intent.getPremium());

		// send trading Fee back to partyA
		uint256 tradingFee = intent.getTradingFee();
		uint256 affiliateFee = intent.getAffiliateFee();

		if (intent.partyBsWhiteList.length == 1) {
			partyAFeeBalance.scheduledAdd(intent.partyBsWhiteList[0], tradingFee + affiliateFee, block.timestamp);
		} else {
			partyAFeeBalance.instantAdd(intent.tradingFee.feeToken, tradingFee + affiliateFee);
		}
		intent.remove(false);
		intent.status = IntentStatus.EXPIRED;
	}

	function expireCloseIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		CloseIntent storage intent = intentLayout.closeIntents[intentId];

		require(block.timestamp > intent.deadline, "LibIntent: Intent isn't expired");
		require(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.CANCEL_PENDING, "LibIntent: Invalid state");

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.EXPIRED;
		intent.remove();
	}
}
