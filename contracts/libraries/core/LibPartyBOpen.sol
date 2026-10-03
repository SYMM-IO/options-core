// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibBucket } from "./LibBucket.sol";
import { LibOpenIntentFunding } from "./LibOpenIntentFunding.sol";

import { LibParty } from "../models/LibParty.sol";
import { LibTradeOps } from "../models/LibTrade.sol";
import { LibUserData } from "../utils/LibUserData.sol";
import { LibOpenIntentOps } from "../models/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { StateControlStorage } from "../../storages/StateControlStorage.sol";

import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { OpenIntent, OpenIntentStatus } from "../../types/IntentTypes.sol";
import { TradeSide, MarginType } from "../../types/BaseTypes.sol";
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

		LibBucket.validateIntentRelationship(intentId, intent.partyA, intent.partyABucketId, sender, intent.partyBBucketId);

		// Check if either party is suspended
		LibBucket.requireNotSuspended(intent.partyA, intent.partyABucketId);
		LibBucket.requireNotSuspended(sender, intent.partyBBucketId);

		// Check Party B emergency modes
		LibBucket.requirePartyBNotEmergency(sender, intent.partyBBucketId);
		if (stateControlLayout.partyBsEmergencyMode) revert SystemErrors.PartyBsInEmergencyMode();

		// Validate intent exists
		if (intentId > intentLayout.lastOpenIntentId) revert IntentErrors.IntentNotFound(intentId);

		// Intent must be in PENDING status to be locked
		ValidationErrors.requireStatus("OpenIntentStatus", uint8(intent.status), uint8(OpenIntentStatus.PENDING));

		// Validate the trading symbol
		if (!symbol.isValid) revert ValidationErrors.InvalidSymbol(intent.tradeAgreements.symbolId);

		// Check if the trade agreement has expired
		if (block.timestamp >= intent.tradeAgreements.expirationTimestamp)
			revert IntentErrors.ExpirationTimestampPassed(block.timestamp, intent.tradeAgreements.expirationTimestamp);

		// Check if intent has expired
		if (block.timestamp > intent.deadline) revert IntentErrors.IntentExpired(intentId, block.timestamp, intent.deadline);

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

		if (intent.isDeferredPartyBSellIntent()) {
			if (!intentLayout.openIntentEscrows[intentId].exists) revert IntentErrors.MissingOpenIntentEscrow(intentId);
			if (intentLayout.openIntentEscrows[intentId].consumed) revert IntentErrors.OpenIntentEscrowAlreadyConsumed(intentId);
		}

		// Verify Party B is not in liquidation process
		sender.requireSolvent(intent.partyBBucketId, intent.partyA, intent.partyABucketId, symbol.collateral, intent.tradeAgreements.marginType);
		LibBucket.requireNativeBacking(
			intentId,
			intent.partyA,
			intent.partyABucketId,
			sender,
			intent.partyBBucketId,
			symbol.collateral,
			intent.feeStructure.feeToken
		);

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
		sender.requireSolvent(
			intent.partyBBucketId,
			intent.partyA,
			intent.partyABucketId,
			SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral,
			intent.relationshipId != 0 ? MarginType.CROSS : MarginType.ISOLATED
		);

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
		intent.unlockForCancelOrExpire();
		intent.unregister(false);
	}

	function fillOpenIntent(
		address sender,
		uint256 intentId,
		uint256 quantity,
		uint256 price
	) internal returns (uint256 tradeId, uint256 newIntentId) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		StateControlStorage.Layout storage stateControlLayout = StateControlStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId];
		MarginType marginType = intent.tradeAgreements.marginType;

		/* ---------------------------------------- CHECKS ---------------------------------------- */

		// Verify Party B is the one filling the intent
		if (sender != intent.partyB) revert ValidationErrors.UnauthorizedSender(sender, intent.partyB);

		LibBucket.validateIntentRelationship(intentId, intent.partyA, intent.partyABucketId, sender, intent.partyBBucketId);

		// System state checks
		LibBucket.requireNotSuspended(intent.partyA, intent.partyABucketId);
		LibBucket.requireNotSuspended(intent.partyB, intent.partyBBucketId);
		LibBucket.requirePartyBNotEmergency(intent.partyB, intent.partyBBucketId);
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
			intent.partyA.requireSolvent(
				intent.partyABucketId,
				intent.partyB,
				intent.partyBBucketId,
				symbol.collateral,
				intent.tradeAgreements.marginType
			);
		intent.partyB.requireSolvent(
			intent.partyBBucketId,
			intent.partyA,
			intent.partyABucketId,
			symbol.collateral,
			intent.tradeAgreements.marginType
		);

		// Time validations
		if (block.timestamp >= intent.tradeAgreements.expirationTimestamp)
			revert IntentErrors.ExpirationTimestampPassed(block.timestamp, intent.tradeAgreements.expirationTimestamp);
		if (block.timestamp > intent.deadline) revert IntentErrors.IntentExpired(intentId, block.timestamp, intent.deadline);

		// Quantity validations
		if (quantity == 0) revert ValidationErrors.ZeroAmount();
		if (intent.tradeAgreements.quantity < quantity) revert IntentErrors.InvalidFillAmount(quantity, intent.tradeAgreements.quantity);

		// Price validation (must be favorable to Party A)
		if (
			(intent.tradeAgreements.tradeSide == TradeSide.BUY && price > intent.price) ||
			(intent.tradeAgreements.tradeSide == TradeSide.SELL && price < intent.price)
		) revert IntentErrors.InvalidOpenPrice(price, intent.price);

		bool deferredSell = intent.isDeferredPartyBSellIntent();

		/* ---------------------------------------- UPDATE ---------------------------------------- */

		tradeId = ++TradeStorage.layout().lastTradeId;
		Trade memory trade;
		trade.id = tradeId;
		trade.openIntentId = intentId;
		trade.tradeAgreements = intent.tradeAgreements;
		trade.tradeAgreements.quantity = quantity;
		trade.tradeAgreements.mm = (intent.tradeAgreements.mm * quantity) / intent.tradeAgreements.quantity;
		trade.partyA = intent.partyA;
		trade.partyB = intent.partyB;
		trade.partyABucketId = intent.partyABucketId;
		trade.partyBBucketId = intent.partyBBucketId;
		trade.relationshipId = LibBucket.bindTradeRelationship(tradeId, intentId);
		trade.activeCloseIntentIds = new uint256[](0);
		trade.openedPrice = price;
		trade.status = TradeStatus.OPENED;
		trade.createTimestamp = block.timestamp;
		trade.statusModifyTimestamp = block.timestamp;
		trade.feeStructure = intent.feeStructure;
		trade.affiliate = intent.affiliate;

		if (deferredSell) {
			intent.consumeDeferredSellEscrow(tradeId, intent.partyB, trade.tradeAgreements.mm, quantity, price);
		} else {
			intent.unlockFees();
			intent.unlockPremiumIfBuy();
			intent.unlockMMIfSell();
		}

		/* ---------------------------------------- PARTIAL FILL ---------------------------------------- */

		// If this is a partial fill, create a new intent for the remaining quantity
		if (intent.tradeAgreements.quantity > quantity) newIntentId = _createResidual(intent, quantity, trade.tradeAgreements.mm, deferredSell);

		/* ---------------------------------------- BALANCES ---------------------------------------- */

		LibOpenIntentFunding.collectFees(intentId, price);

		// Update intent status to filled
		intent.tradeId = tradeId;
		intent.status = OpenIntentStatus.FILLED;
		intent.statusModifyTimestamp = block.timestamp;

		intent.unregister(false);

		trade.register();

		// Get balance references for both parties
		ScheduledReleaseBalance storage partyABalance = trade.partyA.balanceOf(trade.partyABucketId, symbol.collateral);
		ScheduledReleaseBalance storage partyBBalance = trade.partyB.balanceOf(trade.partyBBucketId, symbol.collateral);

		partyBBalance.setup(trade.partyB, trade.partyBBucketId, symbol.collateral);

		// Handle premium and maintenance margin based on trade side
		if (intent.tradeAgreements.tradeSide == TradeSide.BUY) {
			// Party A is buying: Party A pays premium to Party B
			partyABalance.subForCounterParty(trade.partyB, trade.partyBBucketId, trade.calculatePremium(), marginType, DecreaseBalanceReason.PREMIUM);
		} else {
			// Party A is selling: Party B pays premium to Party A, Party A should have maintenance margin
			partyABalance.increaseMM(trade.partyB, trade.partyBBucketId, trade.tradeAgreements.mm);
			partyBBalance.subForCounterParty(trade.partyA, trade.partyABucketId, trade.calculatePremium(), marginType, DecreaseBalanceReason.PREMIUM);
			partyABalance.scheduledAdd(trade.partyB, trade.partyBBucketId, trade.calculatePremium(), marginType, IncreaseBalanceReason.PREMIUM);
		}
		LibBucket.requireNativeBacking(
			intentId,
			trade.partyA,
			trade.partyABucketId,
			trade.partyB,
			trade.partyBBucketId,
			symbol.collateral,
			trade.feeStructure.feeToken
		);
		LibBucket.requireNativeBacking(
			intentId,
			trade.partyB,
			trade.partyBBucketId,
			trade.partyA,
			trade.partyABucketId,
			symbol.collateral,
			trade.feeStructure.feeToken
		);

		/* ---------------------------------------- NONCE ---------------------------------------- */

		if (marginType == MarginType.CROSS) {
			LibBucket.incrementNonce(trade.partyA, trade.partyABucketId, trade.partyB, trade.partyBBucketId);
			LibBucket.incrementNonce(trade.partyB, trade.partyBBucketId, trade.partyA, trade.partyABucketId);
		}
	}

	function _createResidual(OpenIntent storage intent, uint256 quantity, uint256 filledMM, bool deferredSell) private returns (uint256 newIntentId) {
		newIntentId = ++OpenIntentStorage.layout().lastOpenIntentId;
		OpenIntentStatus newStatus;

		// Determine new intent status based on current intent status
		if (intent.status == OpenIntentStatus.CANCEL_PENDING) {
			newStatus = OpenIntentStatus.CANCELED;
		} else {
			newStatus = OpenIntentStatus.PENDING;
		}

		// Create new intent for remaining quantity
		OpenIntent memory newIntent = intent;
		newIntent.id = newIntentId;
		newIntent.tradeId = 0;
		newIntent.tradeAgreements.quantity = intent.tradeAgreements.quantity - quantity;
		newIntent.tradeAgreements.mm = intent.tradeAgreements.mm - filledMM;
		newIntent.relationshipId = LibBucket.inheritIntentRelationship(intent.id, newIntentId);
		newIntent.partyB = address(0);
		newIntent.status = newStatus;
		newIntent.parentId = intent.id;
		newIntent.createTimestamp = block.timestamp;
		newIntent.statusModifyTimestamp = block.timestamp;
		newIntent.userData = LibUserData.incrementCounter(intent.userData);

		newIntent.register();
		if (deferredSell) {
			if (newStatus == OpenIntentStatus.CANCELED) {
				LibOpenIntentOps.releaseDeferredSellEscrow(intent.id);
			} else {
				LibOpenIntentOps.moveDeferredSellEscrow(intent.id, newIntent);
			}
		} else if (newStatus != OpenIntentStatus.CANCELED || !LibBucket.isNativeIntent(newIntentId)) {
			newIntent.lockFees();
			newIntent.lockPremiumIfBuy();
			newIntent.lockMMIfSell();
		}

		// Update original intent quantity to filled amount
		intent.tradeAgreements.quantity = quantity;
	}
}
