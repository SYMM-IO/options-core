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

		/* ---------------------------------------- CHECKS ---------------------------------------- */

		// Check if either party is suspended
		if (stateControlLayout.suspendedAddresses[intent.partyA]) revert SystemErrors.UserSuspended(intent.partyA);
		if (stateControlLayout.suspendedAddresses[sender]) revert SystemErrors.UserSuspended(sender);

		// Check Party B emergency modes
		if (stateControlLayout.partyBEmergencyMode[sender]) revert SystemErrors.PartyBInEmergencyMode(sender);
		if (stateControlLayout.partyBsEmergencyMode) revert SystemErrors.PartyBsInEmergencyMode();

		// Validate intent exists
		if (intentId > intentLayout.lastOpenIntentId) revert IntentErrors.IntentNotFound(intentId);

		// Intent must be in PENDING status to be locked
		ValidationErrors.requireStatus("OpenIntentStatus", uint8(intent.status), uint8(OpenIntentStatus.PENDING));

		// Check if intent has expired
		if (block.timestamp > intent.deadline) revert IntentErrors.IntentExpired(intentId, block.timestamp, intent.deadline);

		// Validate the trading symbol
		if (!symbol.isValid) revert ValidationErrors.InvalidSymbol(intent.tradeAgreements.symbolId);

		// Check if the trade agreement has expired
		if (block.timestamp >= intent.tradeAgreements.expirationTimestamp)
			revert IntentErrors.ExpirationTimestampPassed(block.timestamp, intent.tradeAgreements.expirationTimestamp);

		// Verify Party B's oracle matches the symbol's oracle
		if (appLayout.partyBConfigs[sender].oracleId != symbol.oracleId)
			revert IntentErrors.OracleMismatch(sender, appLayout.partyBConfigs[sender].oracleId, symbol.oracleId);

		// Check if Party B is whitelisted (if whitelist exists)
		bool isValidPartyB;
		if (intent.partyBsWhiteList.length == 0) {
			// No whitelist means any Party B can lock
			isValidPartyB = true;
		} else {
			// Check if sender is in the whitelist
			for (uint8 index = 0; index < intent.partyBsWhiteList.length; index++) {
				if (sender == intent.partyBsWhiteList[index]) {
					isValidPartyB = true;
					break;
				}
			}
		}

		if (!isValidPartyB) revert IntentErrors.NotWhitelistedPartyB(sender, intent.partyBsWhiteList);

		// Verify Party B supports this symbol type
		if (!appLayout.partyBSupportedSymbolTypes[sender][symbol.symbolType]) revert IntentErrors.SymbolTypeNotSupported(sender, symbol.symbolType);

		// Verify Party B is not in liquidation process
		sender.requireSolvent(intent.partyA, symbol.collateral, MarginType.ISOLATED);

		/* ---------------------------------------- UPDATE ---------------------------------------- */

		// Update intent status and assign Party B
		intent.statusModifyTimestamp = block.timestamp;
		intent.status = OpenIntentStatus.LOCKED;
		intent.partyB = sender;
		intent.registerForPartyB();
	}

	function unlockOpenIntent(address sender, uint256 intentId) internal returns (OpenIntentStatus) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];

		/* ---------------------------------------- CHECKS ---------------------------------------- */

		// Only the Party B who locked it can unlock
		if (intent.partyB != sender) revert ValidationErrors.UnauthorizedSender(sender, intent.partyB);

		// Intent must be in LOCKED status
		ValidationErrors.requireStatus("OpenIntentStatus", uint8(intent.status), uint8(OpenIntentStatus.LOCKED));

		// Verify Party B is not in liquidation process
		sender.requireSolvent(intent.partyA, SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral, MarginType.ISOLATED);

		/* ---------------------------------------- UPDATE ---------------------------------------- */

		if (block.timestamp > intent.deadline) {
			// Intent has expired, mark it as expired
			intent.expire();
			return OpenIntentStatus.EXPIRED;
		} else {
			// Return to pending status for other Party Bs to lock
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = OpenIntentStatus.PENDING;
			intent.unregister(true);
			intent.partyB = address(0); // Clear Party B assignment (must be after remove)
			return OpenIntentStatus.PENDING;
		}
	}

	function acceptCancelOpenIntent(address sender, uint256 intentId) internal {
		OpenIntent storage intent = OpenIntentStorage.layout().openIntents[intentId];

		/* ---------------------------------------- CHECKS ---------------------------------------- */

		// Intent must be in CANCEL_PENDING status
		ValidationErrors.requireStatus("OpenIntentStatus", uint8(intent.status), uint8(OpenIntentStatus.CANCEL_PENDING));

		// Only the assigned Party B can accept cancellation
		if (intent.partyB != sender) revert ValidationErrors.UnauthorizedSender(sender, intent.partyB);

		/* ---------------------------------------- UPDATE ---------------------------------------- */

		// Update status to canceled
		intent.statusModifyTimestamp = block.timestamp;
		intent.status = OpenIntentStatus.CANCELED;

		// Release all locked funds and fees
		intent.unlockFees();
		intent.unlockPremiumIfBuy();
		intent.unlockMMIfSell();
		intent.unregister(false);
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
		MarginType marginType = intent.tradeAgreements.marginType;

		/* ---------------------------------------- CHECKS ---------------------------------------- */

		// Verify Party B is the one filling the intent
		if (sender != intent.partyB) revert ValidationErrors.UnauthorizedSender(sender, intent.partyB);

		// System state checks
		if (stateControlLayout.suspendedAddresses[intent.partyA]) revert SystemErrors.UserSuspended(intent.partyA);
		if (stateControlLayout.suspendedAddresses[intent.partyB]) revert SystemErrors.UserSuspended(intent.partyB);
		if (stateControlLayout.partyBEmergencyMode[intent.partyB]) revert SystemErrors.PartyBInEmergencyMode(intent.partyB);
		if (stateControlLayout.partyBsEmergencyMode) revert SystemErrors.PartyBsInEmergencyMode();

		// Symbol validation
		if (!symbol.isValid) revert ValidationErrors.InvalidSymbol(intent.tradeAgreements.symbolId);

		// Intent status validation (must be LOCKED or CANCEL_PENDING)
		if (intent.status != OpenIntentStatus.LOCKED && intent.status != OpenIntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(OpenIntentStatus.LOCKED);
			requiredStatuses[1] = uint8(OpenIntentStatus.CANCEL_PENDING);
			revert ValidationErrors.InvalidState("OpenIntentStatus", uint8(intent.status), requiredStatuses);
		}

		// Verify that both parties are not in liquidation process
		if (intent.tradeAgreements.marginType == MarginType.CROSS)
			intent.partyA.requireSolvent(intent.partyB, symbol.collateral, intent.tradeAgreements.marginType);
		intent.partyB.requireSolvent(intent.partyA, symbol.collateral, intent.tradeAgreements.marginType);

		// Time validations
		if (block.timestamp > intent.deadline) revert IntentErrors.IntentExpired(intentId, block.timestamp, intent.deadline);
		if (block.timestamp >= intent.tradeAgreements.expirationTimestamp)
			revert IntentErrors.ExpirationTimestampPassed(block.timestamp, intent.tradeAgreements.expirationTimestamp);

		// Quantity validations
		if (quantity == 0) revert ValidationErrors.ZeroAmount();
		if (intent.tradeAgreements.quantity < quantity) revert IntentErrors.InvalidFillAmount(quantity, intent.tradeAgreements.quantity);

		// Price validation (must be favorable to Party A)
		if (
			(intent.tradeAgreements.tradeSide == TradeSide.BUY && price > intent.price) ||
			(intent.tradeAgreements.tradeSide == TradeSide.SELL && price < intent.price)
		) revert IntentErrors.InvalidOpenPrice(price, intent.price);

		/* ---------------------------------------- UPDATE ---------------------------------------- */

		tradeId = ++TradeStorage.layout().lastTradeId;
		Trade memory trade = Trade({
			id: tradeId,
			openIntentId: intentId,
			tradeAgreements: TradeAgreements({
				symbolId: intent.tradeAgreements.symbolId,
				quantity: quantity,
				strikePrice: intent.tradeAgreements.strikePrice,
				expirationTimestamp: intent.tradeAgreements.expirationTimestamp,
				mm: (intent.tradeAgreements.mm * quantity) / intent.tradeAgreements.quantity, // Proportional maintenance margin
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
			statusModifyTimestamp: block.timestamp,
			feeStructure: intent.feeStructure,
			affiliate: intent.affiliate
		});

		intent.unlockFees();
		intent.unlockPremiumIfBuy();
		intent.unlockMMIfSell();

		/* ---------------------------------------- PARTIAL FILL ---------------------------------------- */

		// If this is a partial fill, create a new intent for the remaining quantity
		if (intent.tradeAgreements.quantity > quantity) {
			newIntentId = ++intentLayout.lastOpenIntentId;
			OpenIntentStatus newStatus;

			// Determine new intent status based on current intent status
			if (intent.status == OpenIntentStatus.CANCEL_PENDING) {
				newStatus = OpenIntentStatus.CANCELED;
			} else {
				newStatus = OpenIntentStatus.PENDING;
			}

			// Create new intent for remaining quantity
			OpenIntent memory newIntent = OpenIntent({
				id: newIntentId,
				tradeId: 0,
				tradeAgreements: TradeAgreements({
					symbolId: intent.tradeAgreements.symbolId,
					quantity: intent.tradeAgreements.quantity - quantity, // Remaining quantity
					strikePrice: intent.tradeAgreements.strikePrice,
					expirationTimestamp: intent.tradeAgreements.expirationTimestamp,
					mm: intent.tradeAgreements.mm - trade.tradeAgreements.mm, // Remaining maintenance margin
					tradeSide: intent.tradeAgreements.tradeSide,
					marginType: intent.tradeAgreements.marginType,
					exerciseFee: intent.tradeAgreements.exerciseFee
				}),
				price: intent.price,
				partyA: intent.partyA,
				partyB: address(0), // Reset Party B for new intent
				partyBsWhiteList: intent.partyBsWhiteList,
				status: newStatus,
				parentId: intent.id,
				createTimestamp: block.timestamp,
				statusModifyTimestamp: block.timestamp,
				deadline: intent.deadline,
				feeStructure: intent.feeStructure,
				affiliate: intent.affiliate,
				userData: LibUserData.incrementCounter(intent.userData)
			});

			newIntent.register();
			newIntent.lockFees();
			newIntent.lockPremiumIfBuy();
			newIntent.lockMMIfSell();

			// Update original intent quantity to filled amount
			intent.tradeAgreements.quantity = quantity;
		}

		/* ---------------------------------------- BALANCES ---------------------------------------- */

		uint256[3] memory fees = intent.getFeesFromUser();

		{
			address feeToken = intent.feeStructure.feeToken;

			// Determine affiliate fee collector (use default if none specified)
			address affiliateFeeCollector = feeLayout.affiliateFeeCollector[intent.affiliate] == address(0)
				? feeLayout.defaultFeeCollector
				: feeLayout.affiliateFeeCollector[intent.affiliate];

			// Pay platform fees
			ScheduledReleaseBalance storage defaultFeeCollectorBalance = feeLayout.defaultFeeCollector.balanceOf(feeToken);
			defaultFeeCollectorBalance.setup(feeLayout.defaultFeeCollector, feeToken);
			defaultFeeCollectorBalance.instantIsolatedAdd(fees[0], IncreaseBalanceReason.PLATFORM_FEE);

			// Pay affiliate fees
			ScheduledReleaseBalance storage affiliateFeeCollectorBalance = affiliateFeeCollector.balanceOf(feeToken);
			affiliateFeeCollectorBalance.setup(affiliateFeeCollector, feeToken);
			affiliateFeeCollectorBalance.instantIsolatedAdd(fees[1], IncreaseBalanceReason.AFFILIATE_FEE);

			// Pay solver fees
			ScheduledReleaseBalance storage solverFeeCollectorBalance = intent.partyB.balanceOf(feeToken);
			solverFeeCollectorBalance.setup(intent.partyB, feeToken);
			if (intent.tradeAgreements.marginType == MarginType.ISOLATED) {
				solverFeeCollectorBalance.instantIsolatedAdd(fees[2], IncreaseBalanceReason.SOLVER_FEE);
			} else {
				solverFeeCollectorBalance.scheduledAdd(intent.partyA, fees[2], MarginType.CROSS, IncreaseBalanceReason.SOLVER_FEE);
			}
		}

		// Update intent status to filled
		intent.tradeId = tradeId;
		intent.status = OpenIntentStatus.FILLED;
		intent.statusModifyTimestamp = block.timestamp;

		intent.unregister(false);

		trade.register();

		// Get balance references for both parties
		ScheduledReleaseBalance storage partyABalance = trade.partyA.balanceOf(symbol.collateral);
		ScheduledReleaseBalance storage partyBBalance = trade.partyB.balanceOf(symbol.collateral);

		partyBBalance.setup(trade.partyB, symbol.collateral);

		// Handle premium and maintenance margin based on trade side
		if (intent.tradeAgreements.tradeSide == TradeSide.BUY) {
			// Party A is buying: Party A pays premium to Party B
			partyABalance.subForCounterParty(trade.partyB, trade.calculatePremium(), marginType, DecreaseBalanceReason.PREMIUM);
		} else {
			// Party A is selling: Party B pays premium to Party A, Party A should have maintenance margin
			partyABalance.increaseMM(trade.partyB, trade.tradeAgreements.mm);
			partyBBalance.subForCounterParty(trade.partyA, trade.calculatePremium(), marginType, DecreaseBalanceReason.PREMIUM);
			partyABalance.scheduledAdd(trade.partyB, trade.calculatePremium(), marginType, IncreaseBalanceReason.PREMIUM);
		}

		/* ---------------------------------------- NONCE ---------------------------------------- */

		if (marginType == MarginType.CROSS) {
			accountLayout.nonces[trade.partyA][trade.partyB] += 1;
			accountLayout.nonces[trade.partyB][trade.partyA] += 1;
		}
	}
}
