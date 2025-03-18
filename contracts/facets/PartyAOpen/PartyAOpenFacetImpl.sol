// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibIntent.sol";
import "../../libraries/LibOpenIntent.sol";
import "../../libraries/LibUserData.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";
import "../../interfaces/ITradeNFT.sol";

library PartyAOpenFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;

	function sendOpenIntent(
		address sender,
		address[] memory partyBsWhiteList,
		uint256 symbolId,
		uint256 price,
		uint256 quantity,
		uint256 strikePrice,
		uint256 expirationTimestamp,
		uint256 penalty,
		ExerciseFee memory exerciseFee,
		uint256 deadline,
		address feeToken,
		address affiliate,
		bytes memory userData
	) internal returns (uint256 intentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		Symbol memory symbol = SymbolStorage.layout().symbols[symbolId];

		require(symbol.isValid, "PartyAFacet: Symbol is not valid");
		require(deadline >= block.timestamp, "PartyAFacet: Low deadline");
		require(expirationTimestamp >= block.timestamp, "PartyAFacet: Low expiration timestamp");
		require(exerciseFee.cap <= 1e18, "PartyAFacet: High cap for exercise fee");
		require(!accountLayout.instantActionsMode[sender], "PartyAFacet: Instant action mode is activated");
		require(appLayout.affiliateStatus[affiliate] || affiliate == address(0), "PartyAFacet: Invalid affiliate");

		if (accountLayout.boundPartyB[sender] != address(0)) {
			require(
				partyBsWhiteList.length == 1 && partyBsWhiteList[0] == accountLayout.boundPartyB[sender],
				"PartyAFacet: User is bound to another PartyB"
			);
		}

		for (uint8 i = 0; i < partyBsWhiteList.length; i++) {
			require(partyBsWhiteList[i] != sender, "PartyAFacet: Sender isn't allowed in partyBWhiteList");
		}

		ScheduledReleaseBalance storage partyABalance = accountLayout.balances[sender][symbol.collateral];
		ScheduledReleaseBalance storage partyAFeeBalance = accountLayout.balances[sender][feeToken];

		if (partyBsWhiteList.length == 1) {
			require(
				uint256(partyABalance.partyBBalance(partyBsWhiteList[0])) >= (quantity * price) / 1e18,
				"PartyAFacet: insufficient available balance"
			);
			require(
				uint256(partyAFeeBalance.partyBBalance(partyBsWhiteList[0])) >= (quantity * price * symbol.tradingFee) / 1e36,
				"PartyAFacet: insufficient available balance for trading fee"
			);
		} else {
			require(uint256(partyABalance.available) >= (quantity * price) / 1e18, "PartyAFacet: insufficient available balance");
			require(
				uint256(partyAFeeBalance.available) >= (quantity * price * symbol.tradingFee) / 1e36,
				"PartyAFacet: insufficient available balance for trading fee"
			);
		}

		bytes memory userDataWithCounter = LibUserData.addCounter(userData, 0);

		intentId = ++intentLayout.lastOpenIntentId;
		OpenIntent memory intent = OpenIntent({
			id: intentId,
			tradeId: 0,
			partyBsWhiteList: partyBsWhiteList,
			symbolId: symbolId,
			price: price,
			quantity: quantity,
			strikePrice: strikePrice,
			expirationTimestamp: expirationTimestamp,
			penalty: penalty,
			exerciseFee: exerciseFee,
			partyA: sender,
			partyB: address(0),
			status: IntentStatus.PENDING,
			parentId: 0,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			deadline: deadline,
			tradingFee: TradingFee(feeToken, IPriceOracle(appLayout.priceOracleAddress).getPrice(feeToken), symbol.tradingFee),
			affiliate: affiliate,
			userData: userDataWithCounter
		});

		intent.save();

		uint256 tradingFee = intent.getTradingFee();
		uint256 affiliateFee = intent.getAffiliateFee();
		uint256 premium = intent.getPremium();

		// CHECK: These two can be moved to the first condition
		partyAFeeBalance.syncAll(block.timestamp);
		partyABalance.syncAll(block.timestamp);

		if (partyBsWhiteList.length == 1) {
			partyAFeeBalance.subForPartyB(partyBsWhiteList[0], tradingFee + affiliateFee);
			partyABalance.subForPartyB(partyBsWhiteList[0], premium);
		} else {
			partyAFeeBalance.sub(tradingFee + affiliateFee);
			partyABalance.sub(premium);
		}
	}

	function cancelOpenIntent(address sender, uint256 intentId) internal returns (IntentStatus finalStatus) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.symbolId];

		require(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.LOCKED, "PartyAFacet: Invalid state");
		require(intent.partyA == sender, "PartyAFacet: Should be partyA of Intent");
		require(!accountLayout.instantActionsMode[sender], "PartyAFacet: Instant action mode is activated");

		ScheduledReleaseBalance storage partyABalance = accountLayout.balances[intent.partyA][symbol.collateral];
		ScheduledReleaseBalance storage partyAFeeBalance = accountLayout.balances[intent.partyA][intent.tradingFee.feeToken];

		if (block.timestamp > intent.deadline) {
			LibIntent.expireOpenIntent(intentId);
		} else if (intent.status == IntentStatus.PENDING) {
			intent.status = IntentStatus.CANCELED;

			uint256 tradingFee = intent.getTradingFee();
			uint256 affiliateFee = intent.getAffiliateFee();

			if (intent.partyBsWhiteList.length == 1) {
				partyAFeeBalance.scheduledAdd(intent.partyBsWhiteList[0], tradingFee + affiliateFee, block.timestamp);
			} else {
				partyAFeeBalance.instantAdd(intent.tradingFee.feeToken, tradingFee + affiliateFee);
			}

			partyABalance.instantAdd(symbol.collateral, intent.getPremium());

			intent.remove(false);
		} else {
			// LOCKED
			intent.status = IntentStatus.CANCEL_PENDING;
		}
		intent.statusModifyTimestamp = block.timestamp;
		return intent.status;
	}
}
