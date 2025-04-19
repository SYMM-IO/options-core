// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPriceOracle } from "../../interfaces/IPriceOracle.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance, MarginType } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibUserData } from "../../libraries/LibUserData.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage } from "../../storages/AppStorage.sol";
import { OpenIntent, ExerciseFee, IntentStorage, TradingFee, TradeSide, IntentStatus, TradeAgreements } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { PartyAOpenFacetErrors } from "./PartyAOpenFacetErrors.sol";

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

		if (appLayout.partyBConfigs[sender].isActive) revert PartyAOpenFacetErrors.SenderIsPartyB(sender);

		if (accountLayout.suspendedAddresses[sender]) revert CommonErrors.SuspendedAddress(sender);

		if (!symbol.isValid) revert CommonErrors.InvalidSymbol(tradeAgreements.symbolId);

		if (deadline < block.timestamp) revert CommonErrors.LowDeadline(deadline, block.timestamp);

		if (tradeAgreements.expirationTimestamp < block.timestamp)
			revert PartyAOpenFacetErrors.LowExpirationTimestamp(tradeAgreements.expirationTimestamp, block.timestamp);

		if (tradeAgreements.exerciseFee.cap > 1e18) revert PartyAOpenFacetErrors.HighExerciseFeeCap(tradeAgreements.exerciseFee.cap, 1e18);

		if (!(appLayout.affiliateStatus[affiliate] || affiliate == address(0))) revert PartyAOpenFacetErrors.InvalidAffiliate(affiliate);

		if (accountLayout.boundPartyB[sender] != address(0)) {
			if (!(partyBsWhiteList.length == 1 && partyBsWhiteList[0] == accountLayout.boundPartyB[sender]))
				revert PartyAOpenFacetErrors.UserBoundToAnotherPartyB(sender, accountLayout.boundPartyB[sender], partyBsWhiteList);
		}
		if (tradeAgreements.tradeSide == TradeSide.SELL && tradeAgreements.marginType == MarginType.ISOLATED) {
			revert PartyAOpenFacetErrors.ShortTradeInIsolatedMode();
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
			tradingFee: TradingFee(
				feeToken,
				IPriceOracle(appLayout.priceOracleAddress).getPrice(feeToken),
				symbol.tradingFee,
				appLayout.affiliateFees[affiliate][tradeAgreements.symbolId]
			),
			affiliate: affiliate,
			userData: LibUserData.addCounter(userData, 0)
		});

		ScheduledReleaseBalance storage partyABalance = accountLayout.balances[sender][symbol.collateral];
		ScheduledReleaseBalance storage partyAFeeBalance = accountLayout.balances[sender][feeToken];

		// TODO: check if collateral and fee token is same
		if (partyBsWhiteList.length == 1) {
			if (tradeAgreements.marginType == MarginType.ISOLATED) {
				int256 b = partyABalance.counterPartyBalance(partyBsWhiteList[0], tradeAgreements.marginType);
				if (b < int256(intent.getPremium()))
					revert CommonErrors.InsufficientBalance(sender, symbol.collateral, intent.getPremium(), uint256(b));
				if (
					partyAFeeBalance.counterPartyBalance(partyBsWhiteList[0], tradeAgreements.marginType) <
					int256(intent.getTradingFee() + intent.getAffiliateFee())
				)
					revert CommonErrors.InsufficientBalance(
						sender,
						feeToken,
						intent.getTradingFee() + intent.getAffiliateFee(),
						uint256(partyAFeeBalance.counterPartyBalance(partyBsWhiteList[0], tradeAgreements.marginType))
					);
			}
		} else {
			if (uint256(partyABalance.isolatedBalance) < intent.getPremium())
				revert CommonErrors.InsufficientBalance(sender, symbol.collateral, intent.getPremium(), uint256(partyABalance.isolatedBalance));

			if (uint256(partyAFeeBalance.isolatedBalance) < intent.getTradingFee() + intent.getAffiliateFee())
				revert CommonErrors.InsufficientBalance(
					sender,
					feeToken,
					intent.getTradingFee() + intent.getAffiliateFee(),
					uint256(partyAFeeBalance.isolatedBalance)
				);
		}

		intent.save();
		intent.handleFeesAndPremium(true);
	}

	function cancelOpenIntent(address sender, uint256 intentId) internal returns (IntentStatus finalStatus) {
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];

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
