// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { LibUserData } from "../../libraries/LibUserData.sol";
import { LibPartyB } from "../../libraries/LibPartyB.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage, LiquidationStatus } from "../../storages/AppStorage.sol";
import { OpenIntent, Trade, IntentStorage, TradeAgreements, IntentStatus, TradeStatus } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";

library PartyBOpenFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibTradeOps for Trade;

	function lockOpenIntent(address sender, uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol storage symbol = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId];

		require(!AccountStorage.layout().suspendedAddresses[sender], "PartyBFacet: Sender is Suspended");
		require(!appLayout.partyBEmergencyStatus[sender], "PartyBFacet: Sender is in emergency mode");
		require(intent.partyA != sender, "PartyBFacet: User can't be on both sides");
		require(intentId <= intentLayout.lastOpenIntentId, "PartyBFacet: Invalid intentId");
		require(intent.status == IntentStatus.PENDING, "PartyBFacet: Invalid state");
		require(block.timestamp <= intent.deadline, "PartyBFacet: Intent is expired");
		require(symbol.isValid, "PartyBFacet: Symbol is not valid");
		require(block.timestamp <= intent.tradeAgreements.expirationTimestamp, "PartyBFacet: Requested expiration has been passed");
		require(appLayout.partyBConfigs[sender].oracleId == symbol.oracleId, "PartyBFacet: Oracle not matched");

		bool isValidPartyB;
		if (intent.partyBsWhiteList.length == 0) {
			isValidPartyB = true;
		} else {
			for (uint8 index = 0; index < intent.partyBsWhiteList.length; index++) {
				if (sender == intent.partyBsWhiteList[index]) {
					isValidPartyB = true;
					break;
				}
			}
		}
		require(isValidPartyB, "PartyBFacet: Sender isn't whitelisted");

		LibPartyB.requireNotLiquidatedPartyB(sender, symbol.collateral);
		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.LOCKED;
		intent.partyB = sender;
		intent.saveForPartyB();
	}

	function unlockOpenIntent(address sender, uint256 intentId) internal returns (IntentStatus) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];

		require(intent.partyB == sender, "PartyBFacet: Invalid sender");
		require(intent.status == IntentStatus.LOCKED, "PartyBFacet: Invalid state");
		LibPartyB.requireNotLiquidatedPartyB(sender, SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral);

		if (block.timestamp > intent.deadline) {
			intent.expire();
			return IntentStatus.EXPIRED;
		} else {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = IntentStatus.PENDING;
			intent.remove(true);
			intent.partyB = address(0); // should be after remove
			return IntentStatus.PENDING;
		}
	}

	function acceptCancelOpenIntent(address sender, uint256 intentId) internal {
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		require(intent.status == IntentStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		require(intent.partyB == sender, "PartyBFacet: Invalid sender");
		LibPartyB.requireNotLiquidatedPartyB(sender, SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.returnFeesAndPremium();
		intent.remove(false);
	}

	function fillOpenIntent(
		address sender,
		uint256 intentId,
		uint256 quantity,
		uint256 price
	) internal returns (uint256 tradeId, uint256 newIntentId) {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId];

		require(sender == intent.partyB, "PartyBFacet: Invalid sender");
		require(accountLayout.suspendedAddresses[intent.partyA] == false, "PartyBFacet: PartyA is suspended");
		require(!accountLayout.suspendedAddresses[intent.partyB], "PartyBFacet: Sender is Suspended");
		require(!appLayout.partyBEmergencyStatus[intent.partyB], "PartyBFacet: PartyB is in emergency mode");
		require(!appLayout.emergencyMode, "PartyBFacet: System is in emergency mode");
		require(symbol.isValid, "PartyBFacet: Symbol is not valid");
		require(appLayout.partyBConfigs[intent.partyB].symbolType == symbol.symbolType, "PartyBFacet: Mismatched symbol type");
		require(intent.status == IntentStatus.LOCKED || intent.status == IntentStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		LibPartyB.requireNotLiquidatedPartyB(intent.partyB, symbol.collateral);
		require(block.timestamp <= intent.deadline, "PartyBFacet: Intent is expired");
		require(block.timestamp <= intent.tradeAgreements.expirationTimestamp, "PartyBFacet: Requested expiration has been passed");
		require(intent.tradeAgreements.quantity >= quantity && quantity > 0, "PartyBFacet: Invalid quantity");
		require(price <= intent.price, "PartyBFacet: Opened price isn't valid");

		address feeCollector = appLayout.affiliateFeeCollector[intent.affiliate] == address(0)
			? appLayout.defaultFeeCollector
			: appLayout.affiliateFeeCollector[intent.affiliate];

		address feeToken = intent.tradingFee.feeToken;
		accountLayout.balances[appLayout.defaultFeeCollector][feeToken].instantAdd(feeToken, intent.getTradingFee());
		accountLayout.balances[feeCollector][feeToken].instantAdd(feeToken, intent.getAffiliateFee());

		tradeId = ++intentLayout.lastTradeId;
		Trade memory trade = Trade({
			id: tradeId,
			openIntentId: intentId,
			tradeAgreements: TradeAgreements({
				symbolId: intent.tradeAgreements.symbolId,
				quantity: quantity,
				strikePrice: intent.tradeAgreements.strikePrice,
				expirationTimestamp: intent.tradeAgreements.expirationTimestamp,
				penalty: (intent.tradeAgreements.penalty * quantity) / intent.tradeAgreements.quantity,
				tradeSide: intent.tradeAgreements.tradeSide,
				marginType: intent.tradeAgreements.marginType,
				exerciseFee: intent.tradeAgreements.exerciseFee
			}),
			partyA: intent.partyA,
			partyB: intent.partyB,
			activeCloseIntentIds: new uint256[](0),
			penaltyParticipants: new address[](1),
			settledPrice: 0,
			openedPrice: price,
			closedAmountBeforeExpiration: 0,
			closePendingAmount: 0,
			avgClosedPriceBeforeExpiration: 0,
			status: TradeStatus.OPENED,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp
		});

		trade.penaltyParticipants[0] = intent.partyB;
		intent.tradeId = tradeId;
		intent.status = IntentStatus.FILLED;
		intent.statusModifyTimestamp = block.timestamp;

		intent.remove(false);

		// partially fill
		if (intent.tradeAgreements.quantity > quantity) {
			newIntentId = ++intentLayout.lastOpenIntentId;
			IntentStatus newStatus;
			if (intent.status == IntentStatus.CANCEL_PENDING) {
				newStatus = IntentStatus.CANCELED;
			} else {
				newStatus = IntentStatus.PENDING;
			}

			OpenIntent memory newIntent = OpenIntent({
				id: newIntentId,
				tradeId: 0,
				tradeAgreements: TradeAgreements({
					symbolId: intent.tradeAgreements.symbolId,
					quantity: intent.tradeAgreements.quantity - quantity,
					strikePrice: intent.tradeAgreements.strikePrice,
					expirationTimestamp: intent.tradeAgreements.expirationTimestamp,
					penalty: intent.tradeAgreements.penalty - trade.tradeAgreements.penalty,
					tradeSide: intent.tradeAgreements.tradeSide,
					marginType: intent.tradeAgreements.marginType,
					exerciseFee: intent.tradeAgreements.exerciseFee
				}),
				price: intent.price,
				partyA: intent.partyA,
				partyB: address(0),
				partyBsWhiteList: intent.partyBsWhiteList,
				status: newStatus,
				parentId: intent.id,
				createTimestamp: block.timestamp,
				statusModifyTimestamp: block.timestamp,
				deadline: intent.deadline,
				tradingFee: intent.tradingFee,
				affiliate: intent.affiliate,
				userData: LibUserData.incrementCounter(intent.userData)
			});

			newIntent.save();

			if (newStatus == IntentStatus.CANCELED) {
				newIntent.returnFeesAndPremium();
			}
			intent.tradeAgreements.quantity = quantity;
		}
		trade.save();
		accountLayout.balances[trade.partyB][symbol.collateral].instantAdd(symbol.collateral, intent.getPremium());
	}
}
