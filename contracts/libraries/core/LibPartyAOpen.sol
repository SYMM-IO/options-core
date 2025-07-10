// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibUserData } from "../utils/LibUserData.sol";
import { LibParty } from "../models/LibParty.sol";
import { LibOpenIntentOps } from "../models/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { StateControlStorage } from "../../storages/StateControlStorage.sol";
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";
import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { OpenIntent, OpenIntentStatus } from "../../types/IntentTypes.sol";
import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";
import { ExerciseFee, TradingFee, TradeSide, TradeAgreements, MarginType } from "../../types/BaseTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { IntentErrors } from "../../errors/IntentErrors.sol";
import { PartyRelationsErrors } from "../../errors/PartyRelationsErrors.sol";
import { SystemErrors } from "../../errors/SystemErrors.sol";

import { IPriceOracle } from "../../interfaces/IPriceOracle.sol";

library LibPartyAOpen {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibParty for address;

	function sendOpenIntent(
		address sender,
		address[] calldata partyBsWhiteList,
		TradeAgreements memory tradeAgreements,
		uint256 price,
		uint256 deadline,
		address feeToken,
		address affiliate,
		bytes calldata userData
	) internal returns (uint256 intentId) {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();

		Symbol memory symbol = SymbolStorage.layout().symbols[tradeAgreements.symbolId];

		// validate sender
		if (sender.isPartyB()) revert IntentErrors.PartyBSender();
		if (StateControlStorage.layout().suspendedAddresses[sender]) revert SystemErrors.UserSuspended(sender);
		// validate partyB whitelist
		for (uint8 i = 0; i < partyBsWhiteList.length; i++) {
			if (partyBsWhiteList[i] == msg.sender) revert IntentErrors.InvalidWhitelistEntry(msg.sender);
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
		if (CounterPartyRelationsStorage.layout().boundPartyB[sender] != address(0)) {
			if (!(partyBsWhiteList.length == 1 && partyBsWhiteList[0] == CounterPartyRelationsStorage.layout().boundPartyB[sender]))
				revert PartyRelationsErrors.BoundedToAnotherPartyB(sender, CounterPartyRelationsStorage.layout().boundPartyB[sender]);
		}

		if (tradeAgreements.marginType == MarginType.CROSS) {
			if (partyBsWhiteList.length != 1) revert IntentErrors.MultiplePartyBNotAllowed();
			sender.requireSolvent(partyBsWhiteList[0], symbol.collateral, tradeAgreements.marginType);
			partyBsWhiteList[0].requireSolvent(sender, symbol.collateral, tradeAgreements.marginType);
		} else if (tradeAgreements.marginType == MarginType.ISOLATED && partyBsWhiteList.length == 1) {
			partyBsWhiteList[0].requireSolvent(address(0), symbol.collateral, tradeAgreements.marginType);
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
			tradingFee: TradingFee({
				feeToken: feeToken,
				tokenPriceInCollateral: IPriceOracle(appLayout.priceOracleAddress).getPrice(
					feeToken,
					SymbolStorage.layout().symbols[tradeAgreements.symbolId].collateral
				),
				platformFee: symbol.tradingFee,
				affiliateFee: feeLayout.affiliateFees[affiliate][tradeAgreements.symbolId]
			}),
			affiliate: affiliate,
			userData: LibUserData.addCounter(userData, 0)
		});

		intent.save();
		intent.handleFeesAndPremium(true);
	}

	function cancelOpenIntent(address sender, uint256 intentId) internal returns (OpenIntentStatus finalStatus) {
		OpenIntent storage intent = OpenIntentStorage.layout().openIntents[intentId];

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
			intent.handleFeesAndPremium(false);
			intent.remove(false);
		} else {
			// LOCKED
			intent.status = OpenIntentStatus.CANCEL_PENDING;
		}
		intent.statusModifyTimestamp = block.timestamp;
		return intent.status;
	}
}
