// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibDecimals } from "../utils/LibDecimals.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";
import { LibParty } from "../models/LibParty.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { BridgeStorage } from "../../storages/BridgeStorage.sol";

import { BridgeTransaction, BridgeTransactionStatus } from "../../types/BridgeTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { BalanceErrors } from "../../errors/BalanceErrors.sol";

library LibBridge {
	using SafeERC20 for IERC20;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function transferToBridge(
		address sender,
		address collateral,
		uint256 amount,
		address bridge,
		address receiver
	) internal returns (uint256 currentId) {
		BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();

		if (!bridgeLayout.bridges[bridge]) revert BalanceErrors.BridgeNotWhitelisted(bridge);
		if (bridge == sender) revert BalanceErrors.SelfBridgeNotAllowed(bridge);
		if (receiver == address(0)) revert ValidationErrors.ZeroAddress("receiver");

		ScheduledReleaseBalance storage balance = sender.balanceOf(collateral);
		balance.syncAll();

		if (balance.isolatedBalance - balance.isolatedLockedBalance < amount)
			revert BalanceErrors.InsufficientBalance(sender, collateral, amount, balance.isolatedBalance);

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

		balance.isolatedSub(LibDecimals.normalizeAmount(collateral, amount), DecreaseBalanceReason.BRIDGE);

		bridgeLayout.bridgeTransactions[currentId] = bridgeTransaction;
	}

	function withdrawReceivedBridgeValues(uint256[] memory transactionIds) internal {
		BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();

		uint256 totalAmount = 0;
		if (transactionIds.length == 0) revert ValidationErrors.EmptyList();

		address collateral = bridgeLayout.bridgeTransactions[transactionIds[0]].collateral;
		for (uint256 i = transactionIds.length; i != 0; i--) {
			uint256 txId = transactionIds[i - 1];
			if (txId > bridgeLayout.lastBridgeTransactionId) revert BalanceErrors.TransactionIdNotFound(txId);

			BridgeTransaction storage bridgeTransaction = bridgeLayout.bridgeTransactions[txId];

			if (collateral != bridgeTransaction.collateral) revert BalanceErrors.MismatchedCollateral(collateral, bridgeTransaction.collateral);

			ValidationErrors.requireStatus("BridgeTransactionStatus", uint8(bridgeTransaction.status), uint8(BridgeTransactionStatus.RECEIVED));

			if (block.timestamp < AppStorage.layout().partyADeallocateCooldown + bridgeTransaction.timestamp)
				revert ValidationErrors.CooldownNotOver(
					"withdraw",
					block.timestamp,
					AppStorage.layout().partyADeallocateCooldown + bridgeTransaction.timestamp
				);

			if (bridgeTransaction.bridge != msg.sender) revert ValidationErrors.UnauthorizedSender(msg.sender, bridgeTransaction.bridge);

			totalAmount += bridgeTransaction.amount;
			bridgeTransaction.status = BridgeTransactionStatus.WITHDRAWN;
		}

		IERC20(collateral).safeTransfer(msg.sender, totalAmount);
	}

	function suspendBridgeTransaction(uint256 transactionId) internal {
		BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();
		BridgeTransaction storage bridgeTransaction = bridgeLayout.bridgeTransactions[transactionId];

		if (transactionId > bridgeLayout.lastBridgeTransactionId) revert BalanceErrors.TransactionIdNotFound(transactionId);

		ValidationErrors.requireStatus("BridgeTransactionStatus", uint8(bridgeTransaction.status), uint8(BridgeTransactionStatus.RECEIVED));

		bridgeTransaction.status = BridgeTransactionStatus.SUSPENDED;
	}

	function restoreBridgeTransaction(uint256 transactionId, uint256 validAmount) internal {
		BridgeStorage.Layout storage bridgeLayout = BridgeStorage.layout();
		BridgeTransaction storage bridgeTransaction = bridgeLayout.bridgeTransactions[transactionId];

		ValidationErrors.requireStatus("BridgeTransactionStatus", uint8(bridgeTransaction.status), uint8(BridgeTransactionStatus.SUSPENDED));

		if (bridgeLayout.invalidBridgedAmountsPool == address(0)) revert ValidationErrors.ZeroAddress("invalidBridgedAmountsPool");

		if (validAmount > bridgeTransaction.amount) revert BalanceErrors.ValidAmountExceedsOriginal(validAmount, bridgeTransaction.amount);

		ScheduledReleaseBalance storage balance = bridgeLayout.invalidBridgedAmountsPool.balanceOf(bridgeTransaction.collateral);

		balance.setup(bridgeLayout.invalidBridgedAmountsPool, bridgeTransaction.collateral);
		balance.instantIsolatedAdd(
			LibDecimals.normalizeAmount(bridgeTransaction.collateral, bridgeTransaction.amount - validAmount),
			IncreaseBalanceReason.BRIDGE
		);
		bridgeTransaction.status = BridgeTransactionStatus.RECEIVED;
		bridgeTransaction.amount = validAmount;
	}
}
