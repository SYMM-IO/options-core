// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibBucket } from "./LibBucket.sol";
import { BucketErrors } from "../../errors/BucketErrors.sol";

import { LibUserData } from "../utils/LibUserData.sol";
import { LibParty } from "../models/LibParty.sol";
import { LibOpenIntentOps } from "../models/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";

import { OpenIntent, OpenIntentStatus } from "../../types/IntentTypes.sol";
import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";
import { TradeSide, TradeAgreements, MarginType, FeeStructure, Fee } from "../../types/BaseTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { IntentErrors } from "../../errors/IntentErrors.sol";
import { PartyRelationsErrors } from "../../errors/PartyRelationsErrors.sol";

import { IPriceOracle } from "../../interfaces/IPriceOracle.sol";

library LibPartyAOpen {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibParty for address;

	function sendOpenIntent(
		address sender,
		uint256 partyABucketId,
		address[] memory partyBsWhiteList,
		uint256 partyBBucketId,
		bool nativeIntent,
		TradeAgreements memory tradeAgreements,
		uint256 price,
		uint256 deadline,
		Fee memory solverFee,
		address feeToken,
		address affiliate,
		bytes calldata userData
	) internal returns (uint256 intentId) {
		LibBucket.requireInstantModeInactive(sender, partyABucketId);
		AppStorage.Layout storage appLayout = AppStorage.layout();
		FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();

		Symbol memory symbol = SymbolStorage.layout().symbols[tradeAgreements.symbolId];

		// validate sender
		if (sender.isPartyB()) revert IntentErrors.PartyBSender();
		LibBucket.requireNotSuspended(sender, partyABucketId);
		// validate partyB whitelist
		for (uint8 i = 0; i < partyBsWhiteList.length; i++) {
			if (partyBsWhiteList[i] == sender) revert IntentErrors.InvalidWhitelistEntry(sender);
		}
		if (nativeIntent) {
			if (partyBsWhiteList.length != 1 || partyBsWhiteList[0] == address(0)) revert BucketErrors.NativeCounterpartyRequired();
			if (tradeAgreements.marginType != MarginType.CROSS) revert BucketErrors.NativeCrossMarginRequired();
		}
		// validate trade agreements
		if (!symbol.isValid) revert ValidationErrors.InvalidSymbol(tradeAgreements.symbolId);
		if (tradeAgreements.expirationTimestamp < block.timestamp)
			revert IntentErrors.ExpirationTimestampPassed(tradeAgreements.expirationTimestamp, block.timestamp);
		if (tradeAgreements.exerciseFee.cap > 1e18) revert IntentErrors.InvalidExerciseFee(tradeAgreements.exerciseFee.cap, 1e18);
		if (tradeAgreements.tradeSide == TradeSide.SELL && tradeAgreements.marginType == MarginType.ISOLATED)
			revert IntentErrors.IsolatedModeSellNotAllowed();
		// validate deadline
		if (deadline < block.timestamp) revert ValidationErrors.LowDeadline(deadline, block.timestamp);
		// validate affiliate
		if (!(feeLayout.affiliateStatus[affiliate] || affiliate == address(0))) revert IntentErrors.InvalidAffiliate(affiliate);
		//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
		bool deferredSell = LibOpenIntentOps.isDeferredPartyBSell(partyBsWhiteList, tradeAgreements);
		address boundPartyB = LibBucket.boundPartyB(sender, partyABucketId);
		if (boundPartyB != address(0)) {
			if (deferredSell) revert IntentErrors.DeferredSellNotAllowedForBoundPartyA(sender, boundPartyB);
			if (
				!(partyBsWhiteList.length == 1 &&
					partyBsWhiteList[0] == boundPartyB &&
					partyBBucketId == LibBucket.boundPartyBBucketId(sender, partyABucketId))
			) revert PartyRelationsErrors.BoundedToAnotherPartyB(sender, boundPartyB);
		}

		if (tradeAgreements.marginType == MarginType.CROSS) {
			if (!deferredSell) {
				if (partyBsWhiteList.length != 1) revert IntentErrors.MultiplePartyBNotAllowed();
				sender.requireSolvent(partyABucketId, partyBsWhiteList[0], partyBBucketId, symbol.collateral, tradeAgreements.marginType);
				partyBsWhiteList[0].requireSolvent(partyBBucketId, sender, partyABucketId, symbol.collateral, tradeAgreements.marginType);
			}
		} else if (tradeAgreements.marginType == MarginType.ISOLATED && partyBsWhiteList.length == 1) {
			partyBsWhiteList[0].requireSolvent(partyBBucketId, address(0), 0, symbol.collateral, tradeAgreements.marginType);
		}

		if (tradeAgreements.quantity == 0) revert IntentErrors.InvalidOpenQuantity();

		intentId = ++OpenIntentStorage.layout().lastOpenIntentId;
		OpenIntent memory intent = OpenIntent({
			id: intentId,
			tradeId: 0,
			tradeAgreements: tradeAgreements,
			price: price,
			partyA: sender,
			partyB: address(0),
			partyBsWhiteList: partyBsWhiteList,
			status: OpenIntentStatus.PENDING,
			parentId: 0,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			deadline: deadline,
			feeStructure: FeeStructure({
				feeToken: feeToken,
				tokenPriceInCollateral: IPriceOracle(appLayout.priceOracleAddress).getPrice(
					feeToken,
					SymbolStorage.layout().symbols[tradeAgreements.symbolId].collateral
				),
				platformFee: symbol.platformFee,
				affiliateFee: feeLayout.affiliateFees[affiliate][tradeAgreements.symbolId],
				solverFee: solverFee
			}),
			affiliate: affiliate,
			userData: LibUserData.addCounter(userData, 0),
			partyABucketId: partyABucketId,
			partyBBucketId: partyBBucketId,
			relationshipId: nativeIntent ? LibBucket.bindIntentRelationship(intentId, sender, partyABucketId, partyBsWhiteList[0], partyBBucketId) : 0
		});

		intent.register();
		if (deferredSell) {
			intent.lockDeferredSellEscrow();
		} else {
			intent.lockFees();
			intent.lockPremiumIfBuy();
			intent.lockMMIfSell();
		}
		if (partyBsWhiteList.length == 1)
			LibBucket.requireNativeBacking(intentId, sender, partyABucketId, partyBsWhiteList[0], partyBBucketId, symbol.collateral, feeToken);
	}

	function cancelOpenIntent(address sender, uint256 intentId) internal returns (OpenIntentStatus finalStatus) {
		OpenIntent storage intent = OpenIntentStorage.layout().openIntents[intentId];
		LibBucket.requireInstantModeInactive(sender, intent.partyABucketId);

		if (!(intent.status == OpenIntentStatus.PENDING || intent.status == OpenIntentStatus.LOCKED)) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(OpenIntentStatus.PENDING);
			requiredStatuses[1] = uint8(OpenIntentStatus.LOCKED);

			revert ValidationErrors.InvalidState("OpenIntentStatus", uint8(intent.status), requiredStatuses);
		}

		if (intent.partyA != sender) revert ValidationErrors.UnauthorizedSender(sender, intent.partyA);
		if (block.timestamp > intent.deadline) {
			intent.expire();
		} else if (intent.status == OpenIntentStatus.PENDING) {
			intent.status = OpenIntentStatus.CANCELED;
			intent.unlockForCancelOrExpire();
			intent.unregister(false);
		} else {
			// LOCKED
			intent.status = OpenIntentStatus.CANCEL_PENDING;
		}
		intent.statusModifyTimestamp = block.timestamp;
		return intent.status;
	}
}
