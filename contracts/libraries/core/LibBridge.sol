// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { CommonErrors } from "../utils/CommonErrors.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { BridgeStorage } from "../../storages/BridgeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { BridgeTransaction, BridgeTransactionStatus } from "../../types/BridgeTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BridgeFacetErrors } from "../../facets/Bridge/BridgeFacetErrors.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

library LibBridge {
	using SafeERC20 for IERC20;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

	function transferToBridge(address sender, address collateral, uint256 amount, address bridge, address receiver) internal returns (uint256 currentId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();
 
		if (!bridgeLayout.bridges[bridge]) revert BridgeFacetErrors.InvalidBridge(bridge);
		if (bridge == sender) revert BridgeFacetErrors.SameBridgeAndSender(bridge);
		if (receiver == address(0)) revert CommonErrors.ZeroAddress("receiver");

		accountLayout.balances[sender][collateral].syncAll();

		uint256 amountWith18Decimals = (amount * 1e18) / (10 ** IERC20Metadata(collateral).decimals());
		if (
			accountLayout.balances[sender][collateral].isolatedBalance - accountLayout.balances[sender][collateral].isolatedLockedBalance <
			amount
		) revert CommonErrors.InsufficientBalance(sender, collateral, amount, accountLayout.balances[sender][collateral].isolatedBalance);

		if (CounterPartyRelationsStorage.layout().instantActionsMode[sender]) revert Accessibility.InstantActionModeActive(sender);

		currentId = ++bridgeLayout.lastBridgeTransactionId;
		BridgeTransaction memory bridgeTransaction = BridgeTransaction({
			id: currentId,
			amount: amount,
			collateral: collateral,
			sender: sender,
			receiver: receiver,
			bridge: bridge,
			timestamp: block.timestamp,
			status: BridgeTransactionStatus.RECEIVED
		});
		accountLayout.balances[sender][collateral].isolatedSub(amountWith18Decimals, DecreaseBalanceReason.BRIDGE);
		bridgeLayout.bridgeTransactions[currentId] = bridgeTransaction;
		bridgeLayout.bridgeTransactionIds[bridge].push(currentId);
	}

	function withdrawReceivedBridgeValues(uint256[] memory transactionIds) internal {
		BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();

		uint256 totalAmount = 0;
		if (transactionIds.length == 0) revert CommonErrors.EmptyList();

		address collateral = bridgeLayout.bridgeTransactions[transactionIds[0]].collateral;
		for (uint256 i = transactionIds.length; i != 0; i--) {
			if (transactionIds[i - 1] > bridgeLayout.lastBridgeTransactionId)
				revert BridgeFacetErrors.InvalidBridgeTransactionId(transactionIds[i - 1]);

			BridgeTransaction storage bridgeTransaction = bridgeLayout.bridgeTransactions[transactionIds[i - 1]];

			if (collateral != bridgeTransaction.collateral)
				revert BridgeFacetErrors.BridgeCollateralMismatch(collateral, bridgeTransaction.collateral);

			CommonErrors.requireStatus("BridgeTransactionStatus", uint8(bridgeTransaction.status), uint8(BridgeTransactionStatus.RECEIVED));

			if (block.timestamp < AppStorage.layout().partyADeallocateCooldown + bridgeTransaction.timestamp)
				revert CommonErrors.CooldownNotOver(
					"withdraw",
					block.timestamp,
					AppStorage.layout().partyADeallocateCooldown + bridgeTransaction.timestamp
				);

			if (bridgeTransaction.bridge != msg.sender) revert CommonErrors.UnauthorizedSender(msg.sender, bridgeTransaction.bridge);

			totalAmount += bridgeTransaction.amount;
			bridgeTransaction.status = BridgeTransactionStatus.WITHDRAWN;
		}

		IERC20(collateral).safeTransfer(msg.sender, totalAmount);
	}

	function suspendBridgeTransaction(uint256 transactionId) internal {
		BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();
		BridgeTransaction storage bridgeTransaction = bridgeLayout.bridgeTransactions[transactionId];

		if (transactionId > bridgeLayout.lastBridgeTransactionId) revert BridgeFacetErrors.InvalidBridgeTransactionId(transactionId);

		CommonErrors.requireStatus("BridgeTransactionStatus", uint8(bridgeTransaction.status), uint8(BridgeTransactionStatus.RECEIVED));

		bridgeTransaction.status = BridgeTransactionStatus.SUSPENDED;
	}

	function restoreBridgeTransaction(uint256 transactionId, uint256 validAmount) internal {
		BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		BridgeTransaction storage bridgeTransaction = bridgeLayout.bridgeTransactions[transactionId];

		CommonErrors.requireStatus("BridgeTransactionStatus", uint8(bridgeTransaction.status), uint8(BridgeTransactionStatus.SUSPENDED));

		if (bridgeLayout.invalidBridgedAmountsPool == address(0)) revert CommonErrors.ZeroAddress("invalidBridgedAmountsPool");

		if (validAmount > bridgeTransaction.amount) revert BridgeFacetErrors.HighValidAmount(validAmount, bridgeTransaction.amount);

		accountLayout.balances[bridgeLayout.invalidBridgedAmountsPool][bridgeTransaction.collateral].setup(
			bridgeLayout.invalidBridgedAmountsPool,
			bridgeTransaction.collateral
		);
		accountLayout.balances[bridgeLayout.invalidBridgedAmountsPool][bridgeTransaction.collateral].instantIsolatedAdd(
			((bridgeTransaction.amount - validAmount) * (10 ** 18)) / (10 ** IERC20Metadata(bridgeTransaction.collateral).decimals()), //TODO: 1.
			IncreaseBalanceReason.BRIDGE
		);
		bridgeTransaction.status = BridgeTransactionStatus.RECEIVED;
		bridgeTransaction.amount = validAmount;
	}
}
