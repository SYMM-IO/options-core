// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../../libraries/LibParty.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { LibUserData } from "../../libraries/LibUserData.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { StateControlStorage } from "../../storages/StateControlStorage.sol";
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";

import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { OpenIntent, IntentStatus } from "../../types/IntentTypes.sol";
import { TradeAgreements, TradeSide, MarginType } from "../../types/BaseTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { PartyBOpenFacetErrors } from "./PartyBOpenFacetErrors.sol";

library PartyBOpenFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibTradeOps for Trade;
	using LibParty for address;

	function lockOpenIntent(address sender, uint256 intentId) internal {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol storage symbol = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId];

		if (StateControlStorage.layout().suspendedAddresses[sender]) revert CommonErrors.SuspendedAddress(sender);

		if (StateControlStorage.layout().partyBEmergencyStatus[sender]) revert PartyBOpenFacetErrors.PartyBInEmergencyMode(sender);

		if (intent.partyA == sender) revert PartyBOpenFacetErrors.UserOnBothSides(sender);

		if (intentId > intentLayout.lastOpenIntentId) revert PartyBOpenFacetErrors.InvalidIntentId(intentId, intentLayout.lastOpenIntentId);

		if (intent.status != IntentStatus.PENDING) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		if (block.timestamp > intent.deadline) revert PartyBOpenFacetErrors.IntentExpired(intentId, block.timestamp, intent.deadline);

		if (!symbol.isValid) revert CommonErrors.InvalidSymbol(intent.tradeAgreements.symbolId);

		if (block.timestamp > intent.tradeAgreements.expirationTimestamp)
			revert PartyBOpenFacetErrors.ExpirationTimestampPassed(intentId, block.timestamp, intent.tradeAgreements.expirationTimestamp);

		if (appLayout.partyBConfigs[sender].oracleId != symbol.oracleId)
			revert PartyBOpenFacetErrors.OracleNotMatched(sender, appLayout.partyBConfigs[sender].oracleId, symbol.oracleId);

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

		if (!isValidPartyB) revert PartyBOpenFacetErrors.NotWhitelistedPartyB(sender, intent.partyBsWhiteList);

		if (appLayout.partyBConfigs[sender].symbolType != symbol.symbolType)
			revert PartyBOpenFacetErrors.MismatchedSymbolType(sender, appLayout.partyBConfigs[sender].symbolType, symbol.symbolType);

		sender.requireSolventPartyB(intent.partyA, symbol.collateral, MarginType.ISOLATED);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.LOCKED;
		intent.partyB = sender;
		intent.saveForPartyB();
	}

	function unlockOpenIntent(address sender, uint256 intentId) internal returns (IntentStatus) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];

		if (intent.partyB != sender) revert CommonErrors.UnauthorizedSender(sender, intent.partyB);

		if (intent.status != IntentStatus.LOCKED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.LOCKED);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		sender.requireSolventPartyB(intent.partyA, SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral, MarginType.ISOLATED);

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
		OpenIntent storage intent = OpenIntentStorage.layout().openIntents[intentId];

		if (intent.status != IntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		if (intent.partyB != sender) revert CommonErrors.UnauthorizedSender(sender, intent.partyB);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.handleFeesAndPremium(false);
		intent.remove(false);
	}

	function fillOpenIntent(
		address sender,
		MarginType partyBMarginType,
		uint256 intentId,
		uint256 quantity,
		uint256 price
	) internal returns (uint256 tradeId, uint256 newIntentId) {
		FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId];

		if (sender != intent.partyB) revert CommonErrors.UnauthorizedSender(sender, intent.partyB);

		if (StateControlStorage.layout().suspendedAddresses[intent.partyA]) revert CommonErrors.SuspendedAddress(intent.partyA);

		if (StateControlStorage.layout().suspendedAddresses[intent.partyB]) revert CommonErrors.SuspendedAddress(intent.partyB);

		if (StateControlStorage.layout().partyBEmergencyStatus[intent.partyB]) revert PartyBOpenFacetErrors.PartyBInEmergencyMode(intent.partyB);

		if (StateControlStorage.layout().emergencyMode) revert PartyBOpenFacetErrors.SystemInEmergencyMode();

		if (!symbol.isValid) revert CommonErrors.InvalidSymbol(intent.tradeAgreements.symbolId);

		if (intent.status != IntentStatus.LOCKED && intent.status != IntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(IntentStatus.LOCKED);
			requiredStatuses[1] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		if (intent.tradeAgreements.marginType == MarginType.CROSS && partyBMarginType != MarginType.CROSS) revert();

		intent.partyB.requireSolventPartyB(intent.partyA, symbol.collateral, partyBMarginType);
		if (intent.tradeAgreements.marginType == MarginType.CROSS) {
			intent.partyA.requireSolventPartyA(intent.partyB, symbol.collateral);
		}

		if (block.timestamp > intent.deadline) revert PartyBOpenFacetErrors.IntentExpired(intentId, block.timestamp, intent.deadline);

		if (block.timestamp > intent.tradeAgreements.expirationTimestamp)
			revert PartyBOpenFacetErrors.ExpirationTimestampPassed(intentId, block.timestamp, intent.tradeAgreements.expirationTimestamp);

		if (intent.tradeAgreements.quantity < quantity || quantity == 0)
			revert CommonErrors.InvalidAmount(
				"quantity",
				quantity,
				quantity == 0 ? 2 : 1, // 2 for equality check (not equal to 0), 1 for less than check
				intent.tradeAgreements.quantity
			);

		if (
			(intent.tradeAgreements.tradeSide == TradeSide.BUY && price > intent.price) ||
			(intent.tradeAgreements.tradeSide == TradeSide.SELL && price < intent.price)
		) revert PartyBOpenFacetErrors.InvalidOpenPrice(price, intent.price);

		address affiliateFeeCollector = feeLayout.affiliateFeeCollector[intent.affiliate] == address(0)
			? feeLayout.defaultFeeCollector
			: feeLayout.affiliateFeeCollector[intent.affiliate];

		address feeToken = intent.tradingFee.feeToken;

		accountLayout.balances[feeLayout.defaultFeeCollector][feeToken].setup(feeLayout.defaultFeeCollector, feeToken);
		accountLayout.balances[feeLayout.defaultFeeCollector][feeToken].instantIsolatedAdd(intent.getTradingFee(), IncreaseBalanceReason.FEE);

		accountLayout.balances[affiliateFeeCollector][feeToken].setup(affiliateFeeCollector, feeToken);
		accountLayout.balances[affiliateFeeCollector][feeToken].instantIsolatedAdd(intent.getAffiliateFee(), IncreaseBalanceReason.FEE);

		tradeId = ++TradeStorage.layout().lastTradeId;
		Trade memory trade = Trade({
			id: tradeId,
			openIntentId: intentId,
			tradeAgreements: TradeAgreements({
				symbolId: intent.tradeAgreements.symbolId,
				quantity: quantity,
				strikePrice: intent.tradeAgreements.strikePrice,
				expirationTimestamp: intent.tradeAgreements.expirationTimestamp,
				mm: (intent.tradeAgreements.mm * quantity) / intent.tradeAgreements.quantity,
				tradeSide: intent.tradeAgreements.tradeSide,
				marginType: intent.tradeAgreements.marginType,
				exerciseFee: intent.tradeAgreements.exerciseFee
			}),
			partyA: intent.partyA,
			partyB: intent.partyB,
			activeCloseIntentIds: new uint256[](0),
			settledPrice: 0,
			openedPrice: price,
			closedAmountBeforeExpiration: 0,
			closePendingAmount: 0,
			avgClosedPriceBeforeExpiration: 0,
			status: TradeStatus.OPENED,
			partyBMarginType: partyBMarginType,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp
		});

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
					mm: intent.tradeAgreements.mm - trade.tradeAgreements.mm,
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
				newIntent.handleFeesAndPremium(false);
			}

			intent.tradeAgreements.quantity = quantity;
		}

		intent.tradeId = tradeId;
		intent.status = IntentStatus.FILLED;
		intent.statusModifyTimestamp = block.timestamp;

		intent.remove(false);

		trade.save();
		accountLayout.balances[trade.partyB][symbol.collateral].setup(trade.partyB, symbol.collateral);

		if (intent.tradeAgreements.tradeSide == TradeSide.BUY) {
			if (intent.tradeAgreements.marginType == MarginType.CROSS) {
				accountLayout.balances[trade.partyA][symbol.collateral].crossUnlock(trade.partyB, intent.getPremium());
			} else {
				accountLayout.balances[trade.partyA][symbol.collateral].isolatedUnlock(intent.getPremium());
			}
			accountLayout.balances[trade.partyA][symbol.collateral].subForCounterParty(
				trade.partyB,
				trade.getPremium(),
				intent.tradeAgreements.marginType,
				DecreaseBalanceReason.PREMIUM
			);
		} else {
			if (intent.tradeAgreements.marginType == MarginType.CROSS) {
				accountLayout.balances[trade.partyA][symbol.collateral].crossUnlock(trade.partyB, trade.tradeAgreements.mm);
				accountLayout.balances[trade.partyA][symbol.collateral].increaseMM(trade.partyB, trade.tradeAgreements.mm);
			}
			accountLayout.balances[trade.partyB][symbol.collateral].subForCounterParty(
				trade.partyA,
				trade.getPremium(),
				partyBMarginType,
				DecreaseBalanceReason.PREMIUM
			);
			accountLayout.balances[trade.partyA][symbol.collateral].scheduledAdd(
				trade.partyB,
				trade.getPremium(),
				MarginType.CROSS,
				IncreaseBalanceReason.PREMIUM
			);
		}
	}
}
