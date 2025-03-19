// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPriceOracle } from "../../interfaces/IPriceOracle.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibUserData } from "../../libraries/LibUserData.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage } from "../../storages/AppStorage.sol";
import { OpenIntent, ExerciseFee, IntentStorage, TradingFee, TradeSide, MarginType, IntentStatus, TradeAgreements } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";

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
		TradeSide tradeSide,
		MarginType marginType,
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
			tradeAgreements: TradeAgreements({
				symbolId: symbolId,
				quantity: quantity,
				strikePrice: strikePrice,
				expirationTimestamp: expirationTimestamp,
				penalty: penalty,
				tradeSide: tradeSide,
				marginType: marginType,
				exerciseFee: exerciseFee
			}),
			price: price,
			partyA: sender,
			partyB: address(0),
			partyBsWhiteList: partyBsWhiteList,
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
		intent.getFeesAndPremiumFromUser();
	}

	function cancelOpenIntent(address sender, uint256 intentId) internal returns (IntentStatus finalStatus) {
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];

		require(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.LOCKED, "PartyAFacet: Invalid state");
		require(intent.partyA == sender, "PartyAFacet: Should be partyA of Intent");
		require(!AccountStorage.layout().instantActionsMode[sender], "PartyAFacet: Instant action mode is activated");

		if (block.timestamp > intent.deadline) {
			intent.expire();
		} else if (intent.status == IntentStatus.PENDING) {
			intent.status = IntentStatus.CANCELED;
			intent.returnFeesAndPremium();
			intent.remove(false);
		} else {
			// LOCKED
			intent.status = IntentStatus.CANCEL_PENDING;
		}
		intent.statusModifyTimestamp = block.timestamp;
		return intent.status;
	}
}
