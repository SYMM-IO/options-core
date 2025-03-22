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
		TradeAgreements memory tradeAgreements,
		uint256 price,
		uint256 deadline,
		address feeToken,
		address affiliate,
		bytes memory userData
	) internal returns (uint256 intentId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		Symbol memory symbol = SymbolStorage.layout().symbols[tradeAgreements.symbolId];

		require(!accountLayout.suspendedAddresses[sender], "PartyAFacet: Sender is Suspended");
		require(symbol.isValid, "PartyAFacet: Symbol is not valid");
		require(deadline >= block.timestamp, "PartyAFacet: Low deadline");
		require(tradeAgreements.expirationTimestamp >= block.timestamp, "PartyAFacet: Low expiration timestamp");
		require(tradeAgreements.exerciseFee.cap <= 1e18, "PartyAFacet: High cap for exercise fee");
		require(appLayout.affiliateStatus[affiliate] || affiliate == address(0), "PartyAFacet: Invalid affiliate");

		if (accountLayout.boundPartyB[sender] != address(0)) {
			require(
				partyBsWhiteList.length == 1 && partyBsWhiteList[0] == accountLayout.boundPartyB[sender],
				"PartyAFacet: User is bound to another PartyB"
			);
		}

		intentId = ++IntentStorage.layout().lastOpenIntentId;
		OpenIntent memory intent = OpenIntent({
			id: intentId,
			tradeId: 0,
			tradeAgreements: tradeAgreements,
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
			userData: LibUserData.addCounter(userData, 0)
		});

		ScheduledReleaseBalance storage partyABalance = accountLayout.balances[sender][symbol.collateral];
		ScheduledReleaseBalance storage partyAFeeBalance = accountLayout.balances[sender][feeToken];

		if (partyBsWhiteList.length == 1) {
			require(
				uint256(partyABalance.partyBBalance(partyBsWhiteList[0])) >= intent.getPremium(),
				"PartyAFacet: insufficient available balance for premium"
			);
			require(
				uint256(partyAFeeBalance.partyBBalance(partyBsWhiteList[0])) >= intent.getTradingFee() + intent.getAffiliateFee(),
				"PartyAFacet: insufficient available balance for fee"
			);
		} else {
			require(uint256(partyABalance.available) >= intent.getPremium(), "PartyAFacet: insufficient available balance for premium");
			require(
				uint256(partyAFeeBalance.available) >= intent.getTradingFee() + intent.getAffiliateFee(),
				"PartyAFacet: insufficient available balance for fee"
			);
		}

		intent.save();
		intent.getFeesAndPremium();
	}

	function cancelOpenIntent(address sender, uint256 intentId) internal returns (IntentStatus finalStatus) {
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];

		require(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.LOCKED, "PartyAFacet: Invalid state");
		require(intent.partyA == sender, "PartyAFacet: Should be partyA of Intent");

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
