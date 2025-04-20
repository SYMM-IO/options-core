// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { LibUserData } from "../../libraries/LibUserData.sol";
import { LibPartyB } from "../../libraries/LibPartyB.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage, LiquidationStatus } from "../../storages/AppStorage.sol";
import { OpenIntent, Trade, IntentStorage, TradeAgreements, IntentStatus, TradeStatus } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { PartyBOpenFacetErrors } from "./PartyBOpenFacetErrors.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";

library PartyBOpenFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibTradeOps for Trade;
	using LibPartyB for address;

	function lockOpenIntent(address sender, uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol storage symbol = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId];

		if (AccountStorage.layout().suspendedAddresses[sender]) revert CommonErrors.SuspendedAddress(sender);

		if (appLayout.partyBEmergencyStatus[sender]) revert PartyBOpenFacetErrors.PartyBInEmergencyMode(sender);

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

		sender.requireSolvent(symbol.collateral);
		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.LOCKED;
		intent.partyB = sender;
		intent.saveForPartyB();
	}

	function unlockOpenIntent(address sender, uint256 intentId) internal returns (IntentStatus) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];

		if (intent.partyB != sender) revert CommonErrors.UnauthorizedSender(sender, intent.partyB);

		if (intent.status != IntentStatus.LOCKED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.LOCKED);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		sender.requireSolvent(SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral);

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

		if (intent.status != IntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		if (intent.partyB != sender) revert CommonErrors.UnauthorizedSender(sender, intent.partyB);

		sender.requireSolvent(SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.handleFeesAndPremium(false);
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

		if (sender != intent.partyB) revert CommonErrors.UnauthorizedSender(sender, intent.partyB);

		if (accountLayout.suspendedAddresses[intent.partyA]) revert CommonErrors.SuspendedAddress(intent.partyA);

		if (accountLayout.suspendedAddresses[intent.partyB]) revert CommonErrors.SuspendedAddress(intent.partyB);

		if (appLayout.partyBEmergencyStatus[intent.partyB]) revert PartyBOpenFacetErrors.PartyBInEmergencyMode(intent.partyB);

		if (appLayout.emergencyMode) revert PartyBOpenFacetErrors.SystemInEmergencyMode();

		if (!symbol.isValid) revert CommonErrors.InvalidSymbol(intent.tradeAgreements.symbolId);

		if (appLayout.partyBConfigs[intent.partyB].symbolType != symbol.symbolType)
			revert PartyBOpenFacetErrors.MismatchedSymbolType(intent.partyB, appLayout.partyBConfigs[intent.partyB].symbolType, symbol.symbolType);

		if (intent.status != IntentStatus.LOCKED && intent.status != IntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(IntentStatus.LOCKED);
			requiredStatuses[1] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		intent.partyB.requireSolvent(symbol.collateral);

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

		if (price > intent.price) revert PartyBOpenFacetErrors.InvalidOpenPrice(price, intent.price);

		address feeCollector = appLayout.affiliateFeeCollector[intent.affiliate] == address(0)
			? appLayout.defaultFeeCollector
			: appLayout.affiliateFeeCollector[intent.affiliate];

		address feeToken = intent.tradingFee.feeToken;

		accountLayout.balances[appLayout.defaultFeeCollector][feeToken].setup(appLayout.defaultFeeCollector, feeToken);
		accountLayout.balances[appLayout.defaultFeeCollector][feeToken].instantIsolatedAdd(intent.getTradingFee(), IncreaseBalanceReason.FEE);

		accountLayout.balances[feeCollector][feeToken].setup(feeCollector, feeToken);
		accountLayout.balances[feeCollector][feeToken].instantIsolatedAdd(intent.getAffiliateFee(), IncreaseBalanceReason.FEE);

		tradeId = ++intentLayout.lastTradeId;
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
		// pay back the extra locked premium
		accountLayout.balances[trade.partyA][symbol.collateral].instantIsolatedAdd(
			intent.getPremium() - trade.getPremium(),
			IncreaseBalanceReason.FEE
		);
	}
}
