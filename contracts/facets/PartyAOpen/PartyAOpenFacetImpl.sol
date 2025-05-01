// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibUserData } from "../../libraries/LibUserData.sol";
import { LibParty } from "../../libraries/LibParty.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { StateControlStorage } from "../../storages/StateControlStorage.sol";
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";
import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { OpenIntent, IntentStatus } from "../../types/IntentTypes.sol";
import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";
import { ExerciseFee, TradingFee, TradeSide, TradeAgreements, MarginType } from "../../types/BaseTypes.sol";

import { IPriceOracle } from "../../interfaces/IPriceOracle.sol";
import { PartyAOpenFacetErrors } from "./PartyAOpenFacetErrors.sol";

library PartyAOpenFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibParty for address;

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
		AppStorage.Layout storage appLayout = AppStorage.layout();
		FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();

		Symbol memory symbol = SymbolStorage.layout().symbols[tradeAgreements.symbolId];

		// validate sender
		if (appLayout.partyBConfigs[sender].isActive) revert PartyAOpenFacetErrors.SenderIsPartyB(sender);
		if (StateControlStorage.layout().suspendedAddresses[sender]) revert CommonErrors.SuspendedAddress(sender);
		// validate partyB whitelist
		for (uint8 i = 0; i < partyBsWhiteList.length; i++) {
			if (partyBsWhiteList[i] == msg.sender) revert PartyAOpenFacetErrors.PartyAInPartyBWhitelist(msg.sender);
		}
		// validate trade agreements
		if (!symbol.isValid) revert CommonErrors.InvalidSymbol(tradeAgreements.symbolId);
		if (tradeAgreements.expirationTimestamp < block.timestamp)
			revert PartyAOpenFacetErrors.LowExpirationTimestamp(tradeAgreements.expirationTimestamp, block.timestamp);
		if (tradeAgreements.exerciseFee.cap > 1e18) revert PartyAOpenFacetErrors.HighExerciseFeeCap(tradeAgreements.exerciseFee.cap, 1e18);
		if (tradeAgreements.tradeSide == TradeSide.SELL && tradeAgreements.marginType == MarginType.ISOLATED)
			revert PartyAOpenFacetErrors.ShortTradeInIsolatedMode();
		// validate deadline
		if (deadline < block.timestamp) revert CommonErrors.LowDeadline(deadline, block.timestamp);
		// validate affiliate
		if (!(feeLayout.affiliateStatus[affiliate] || affiliate == address(0))) revert PartyAOpenFacetErrors.InvalidAffiliate(affiliate);
		//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
		if (CounterPartyRelationsStorage.layout().boundPartyB[sender] != address(0)) {
			if (!(partyBsWhiteList.length == 1 && partyBsWhiteList[0] == CounterPartyRelationsStorage.layout().boundPartyB[sender]))
				revert PartyAOpenFacetErrors.UserBoundToAnotherPartyB(
					sender,
					CounterPartyRelationsStorage.layout().boundPartyB[sender],
					partyBsWhiteList
				);
		}

		if (tradeAgreements.marginType == MarginType.CROSS) {
			if (partyBsWhiteList.length != 1) revert PartyAOpenFacetErrors.OnlyOnePartyBIsAllowedInCrossMode();
			sender.requireSolventPartyA(partyBsWhiteList[0], symbol.collateral);
		}

		intentId = ++OpenIntentStorage.layout().lastOpenIntentId;
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
			tradingFee: TradingFee({
				feeToken: feeToken,
				tokenPrice: IPriceOracle(appLayout.priceOracleAddress).getPrice(feeToken),
				platformFee: symbol.tradingFee,
				affiliateFee: feeLayout.affiliateFees[affiliate][tradeAgreements.symbolId]
			}),
			affiliate: affiliate,
			userData: LibUserData.addCounter(userData, 0)
		});

		intent.save();
		intent.handleFeesAndPremium(true);
	}

	function cancelOpenIntent(address sender, uint256 intentId) internal returns (IntentStatus finalStatus) {
		OpenIntent storage intent = OpenIntentStorage.layout().openIntents[intentId];

		if (!(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.LOCKED)) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(IntentStatus.PENDING);
			requiredStatuses[1] = uint8(IntentStatus.LOCKED);

			revert CommonErrors.InvalidState("intent", uint8(intent.status), requiredStatuses);
		}

		if (intent.partyA != sender) revert CommonErrors.UnauthorizedSender(sender, intent.partyA);

		if (block.timestamp > intent.deadline) {
			intent.expire();
		} else if (intent.status == IntentStatus.PENDING) {
			intent.status = IntentStatus.CANCELED;
			intent.handleFeesAndPremium(false);
			intent.remove(false);
		} else {
			// LOCKED
			intent.status = IntentStatus.CANCEL_PENDING;
		}
		intent.statusModifyTimestamp = block.timestamp;
		return intent.status;
	}
}
