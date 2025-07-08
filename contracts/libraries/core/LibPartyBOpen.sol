// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { LibTradeOps } from "../models/LibTrade.sol";
import { LibUserData } from "../utils/LibUserData.sol";
import { LibOpenIntentOps } from "../models/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { StateControlStorage } from "../../storages/StateControlStorage.sol";
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";

import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { OpenIntent, OpenIntentStatus } from "../../types/IntentTypes.sol";
import { TradeAgreements, TradeSide, MarginType } from "../../types/BaseTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { IntentErrors } from "../../errors/IntentErrors.sol";
import { SystemErrors } from "../../errors/SystemErrors.sol";

library LibPartyBOpen {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibTradeOps for Trade;
	using LibParty for address;

	function lockOpenIntent(address sender, uint256 intentId) internal {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();
		StateControlStorage.Layout storage stateControlLayout = StateControlStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol storage symbol = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId];

		if (stateControlLayout.suspendedAddresses[intent.partyA]) revert SystemErrors.UserSuspended(intent.partyA);
		if (stateControlLayout.suspendedAddresses[sender]) revert SystemErrors.UserSuspended(sender);
		if (stateControlLayout.partyBEmergencyMode[sender]) revert SystemErrors.PartyBInEmergencyMode(sender);
		if (stateControlLayout.partyBsEmergencyMode) revert SystemErrors.PartyBsInEmergencyMode();

		if (intentId > intentLayout.lastOpenIntentId) revert IntentErrors.IntentNotFound(intentId);

		ValidationErrors.requireStatus("OpenIntentStatus", uint8(intent.status), uint8(OpenIntentStatus.PENDING));

		if (block.timestamp > intent.deadline) revert IntentErrors.IntentExpired(intentId, block.timestamp, intent.deadline);

		if (!symbol.isValid) revert ValidationErrors.InvalidSymbol(intent.tradeAgreements.symbolId);

		if (block.timestamp > intent.tradeAgreements.expirationTimestamp)
			revert IntentErrors.ExpirationTimestampPassed(block.timestamp, intent.tradeAgreements.expirationTimestamp);

		if (appLayout.partyBConfigs[sender].oracleId != symbol.oracleId)
			revert IntentErrors.OracleMismatch(sender, appLayout.partyBConfigs[sender].oracleId, symbol.oracleId);

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

		if (!isValidPartyB) revert IntentErrors.NotWhitelistedPartyB(sender, intent.partyBsWhiteList);

		if (appLayout.partyBConfigs[sender].symbolType != symbol.symbolType)
			revert IntentErrors.SymbolTypeMismatch(sender, appLayout.partyBConfigs[sender].symbolType, symbol.symbolType);

		sender.requireSolvent(intent.partyA, symbol.collateral, MarginType.ISOLATED);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = OpenIntentStatus.LOCKED;
		intent.partyB = sender;
		intent.saveForPartyB();
	}

	function unlockOpenIntent(address sender, uint256 intentId) internal returns (OpenIntentStatus) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];

		if (intent.partyB != sender) revert ValidationErrors.UnauthorizedSender(sender, intent.partyB);

		ValidationErrors.requireStatus("OpenIntentStatus", uint8(intent.status), uint8(OpenIntentStatus.LOCKED));

		sender.requireSolvent(intent.partyA, SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral, MarginType.ISOLATED);

		if (block.timestamp > intent.deadline) {
			intent.expire();
			return OpenIntentStatus.EXPIRED;
		} else {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = OpenIntentStatus.PENDING;
			intent.remove(true);
			intent.partyB = address(0); // should be after remove
			return OpenIntentStatus.PENDING;
		}
	}

	function acceptCancelOpenIntent(address sender, uint256 intentId) internal {
		OpenIntent storage intent = OpenIntentStorage.layout().openIntents[intentId];

		ValidationErrors.requireStatus("OpenIntentStatus", uint8(intent.status), uint8(OpenIntentStatus.CANCEL_PENDING));

		if (intent.partyB != sender) revert ValidationErrors.UnauthorizedSender(sender, intent.partyB);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = OpenIntentStatus.CANCELED;
		intent.handleFeesAndPremium(false);
		intent.remove(false);
	}

	function fillOpenIntent(
		address sender,
		uint256 intentId,
		uint256 quantity,
		uint256 price
	) internal returns (uint256 tradeId, uint256 newIntentId) {
		FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		StateControlStorage.Layout storage stateControlLayout = StateControlStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId];

		if (sender != intent.partyB) revert ValidationErrors.UnauthorizedSender(sender, intent.partyB);
		if (stateControlLayout.suspendedAddresses[intent.partyA]) revert SystemErrors.UserSuspended(intent.partyA);
		if (stateControlLayout.suspendedAddresses[intent.partyB]) revert SystemErrors.UserSuspended(intent.partyB);
		if (stateControlLayout.partyBEmergencyMode[intent.partyB]) revert SystemErrors.PartyBInEmergencyMode(intent.partyB);
		if (stateControlLayout.partyBsEmergencyMode) revert SystemErrors.PartyBsInEmergencyMode();
		if (!symbol.isValid) revert ValidationErrors.InvalidSymbol(intent.tradeAgreements.symbolId);
		if (intent.status != OpenIntentStatus.LOCKED && intent.status != OpenIntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(OpenIntentStatus.LOCKED);
			requiredStatuses[1] = uint8(OpenIntentStatus.CANCEL_PENDING);
			revert ValidationErrors.InvalidState("OpenIntentStatus", uint8(intent.status), requiredStatuses);
		}
		if (intent.tradeAgreements.marginType == MarginType.CROSS)
			intent.partyA.requireSolvent(intent.partyB, symbol.collateral, intent.tradeAgreements.marginType);
		intent.partyB.requireSolvent(intent.partyA, symbol.collateral, intent.tradeAgreements.marginType);
		if (block.timestamp > intent.deadline) revert IntentErrors.IntentExpired(intentId, block.timestamp, intent.deadline);
		if (block.timestamp > intent.tradeAgreements.expirationTimestamp)
			revert IntentErrors.ExpirationTimestampPassed(block.timestamp, intent.tradeAgreements.expirationTimestamp);
		if (quantity == 0) revert ValidationErrors.ZeroAmount();
		if (intent.tradeAgreements.quantity < quantity) revert IntentErrors.InvalidFillAmount(quantity, intent.tradeAgreements.quantity);
		if (
			(intent.tradeAgreements.tradeSide == TradeSide.BUY && price > intent.price) ||
			(intent.tradeAgreements.tradeSide == TradeSide.SELL && price < intent.price)
		) revert IntentErrors.InvalidOpenPrice(price, intent.price);

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
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp
		});

		// partially fill
		if (intent.tradeAgreements.quantity > quantity) {
			newIntentId = ++intentLayout.lastOpenIntentId;
			OpenIntentStatus newStatus;
			if (intent.status == OpenIntentStatus.CANCEL_PENDING) {
				newStatus = OpenIntentStatus.CANCELED;
			} else {
				newStatus = OpenIntentStatus.PENDING;
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

			if (newStatus == OpenIntentStatus.CANCELED) {
				newIntent.handleFeesAndPremium(false);
			}

			intent.tradeAgreements.quantity = quantity;
		}

		{
			address affiliateFeeCollector = feeLayout.affiliateFeeCollector[intent.affiliate] == address(0)
				? feeLayout.defaultFeeCollector
				: feeLayout.affiliateFeeCollector[intent.affiliate];
			address feeToken = intent.tradingFee.feeToken;

			ScheduledReleaseBalance storage defaultFeeCollectorBalance = feeLayout.defaultFeeCollector.balanceOf(feeToken);
			defaultFeeCollectorBalance.setup(feeLayout.defaultFeeCollector, feeToken);
			defaultFeeCollectorBalance.instantIsolatedAdd(intent.getTradingFee(), IncreaseBalanceReason.FEE);

			ScheduledReleaseBalance storage affiliateFeeCollectorBalance = affiliateFeeCollector.balanceOf(feeToken);
			affiliateFeeCollectorBalance.setup(affiliateFeeCollector, feeToken);
			affiliateFeeCollectorBalance.instantIsolatedAdd(intent.getAffiliateFee(), IncreaseBalanceReason.FEE);
		}

		intent.tradeId = tradeId;
		intent.status = OpenIntentStatus.FILLED;
		intent.statusModifyTimestamp = block.timestamp;

		intent.remove(false);

		trade.save();

		ScheduledReleaseBalance storage partyABalance = trade.partyA.balanceOf(symbol.collateral);
		ScheduledReleaseBalance storage partyBBalance = trade.partyB.balanceOf(symbol.collateral);

		partyBBalance.setup(trade.partyB, symbol.collateral);

		if (intent.tradeAgreements.tradeSide == TradeSide.BUY) {
			if (intent.tradeAgreements.marginType == MarginType.CROSS) {
				partyABalance.crossUnlock(trade.partyB, intent.getPremium());
			} else {
				partyABalance.isolatedUnlock(intent.getPremium());
			}
			partyABalance.subForCounterParty(trade.partyB, trade.getPremium(), intent.tradeAgreements.marginType, DecreaseBalanceReason.PREMIUM);
		} else {
			partyABalance.crossUnlock(trade.partyB, trade.tradeAgreements.mm);
			partyABalance.increaseMM(trade.partyB, trade.tradeAgreements.mm);
			partyBBalance.subForCounterParty(trade.partyA, trade.getPremium(), trade.tradeAgreements.marginType, DecreaseBalanceReason.PREMIUM);
			partyABalance.scheduledAdd(trade.partyB, trade.getPremium(), MarginType.CROSS, IncreaseBalanceReason.PREMIUM);
		}
		
		if (trade.tradeAgreements.marginType == MarginType.CROSS) {
			accountLayout.nonces[trade.partyA][trade.partyB] += 1;
			accountLayout.nonces[trade.partyB][trade.partyA] += 1;
		}
	}
}
