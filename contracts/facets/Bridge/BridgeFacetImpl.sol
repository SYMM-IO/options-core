// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/AccountStorage.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library BridgeFacetImpl {
	using SafeERC20 for IERC20;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

	function transferToBridge(address collateral, uint256 amount, address bridge, address receiver) internal returns (uint256 currentId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(accountLayout.bridges[bridge], "BridgeFacet: Invalid bridge");
		require(bridge != msg.sender, "BridgeFacet: Bridge and sender can't be the same");

		uint256 amountWith18Decimals = (amount * 1e18) / (10 ** IERC20Metadata(collateral).decimals());
		require(accountLayout.balances[msg.sender][collateral].available >= amount, "BridgeFacet: Insufficient balance");

		currentId = ++accountLayout.lastBridgeId;
		BridgeTransaction memory bridgeTransaction = BridgeTransaction({
			id: currentId,
			amount: amount,
			collateral: collateral,
			sender: msg.sender,
			receiver: receiver,
			bridge: bridge,
			timestamp: block.timestamp,
			status: BridgeTransactionStatus.RECEIVED
		});
		accountLayout.balances[collateral][msg.sender].sub(amountWith18Decimals);
		accountLayout.bridgeTransactions[currentId] = bridgeTransaction;
		accountLayout.bridgeTransactionIds[bridge].push(currentId);
	}

	function withdrawReceivedBridgeValues(uint256[] memory transactionIds) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		uint256 totalAmount = 0;
		require(transactionIds.length > 0, "BridgeFacet: Empty list");
		address collateral = accountLayout.bridgeTransactions[transactionIds[0]].collateral;
		for (uint256 i = transactionIds.length; i != 0; i--) {
			require(transactionIds[i - 1] <= accountLayout.lastBridgeId, "BridgeFacet: Invalid transactionId");
			BridgeTransaction storage bridgeTransaction = accountLayout.bridgeTransactions[transactionIds[i - 1]];
			require(collateral == bridgeTransaction.collateral, "BridgeFacet: Can't batch transactions with different collateral");
			require(bridgeTransaction.status == BridgeTransactionStatus.RECEIVED, "BridgeFacet: Already withdrawn");
			require(
				block.timestamp >= AppStorage.layout().partyADeallocateCooldown + bridgeTransaction.timestamp,
				"BridgeFacet: Cooldown hasn't reached"
			);
			require(bridgeTransaction.bridge == msg.sender, "BridgeFacet: Sender is not the transaction's bridge");

			totalAmount += bridgeTransaction.amount;
			bridgeTransaction.status = BridgeTransactionStatus.WITHDRAWN;
		}

		IERC20(collateral).safeTransfer(msg.sender, totalAmount);
	}

	function suspendBridgeTransaction(uint256 transactionId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		BridgeTransaction storage bridgeTransaction = accountLayout.bridgeTransactions[transactionId];

		require(transactionId <= accountLayout.lastBridgeId, "BridgeFacet: Invalid transactionId");
		require(bridgeTransaction.status == BridgeTransactionStatus.RECEIVED, "BridgeFacet: Invalid status");
		bridgeTransaction.status = BridgeTransactionStatus.SUSPENDED;
	}

	function restoreBridgeTransaction(uint256 transactionId, uint256 validAmount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		BridgeTransaction storage bridgeTransaction = accountLayout.bridgeTransactions[transactionId];

		require(bridgeTransaction.status == BridgeTransactionStatus.SUSPENDED, "BridgeFacet: Invalid status");
		require(accountLayout.invalidBridgedAmountsPool != address(0), "BridgeFacet: Zero address");
		require(validAmount <= bridgeTransaction.amount, "BridgeFacet: High valid amount");

		AccountStorage.layout().balances[bridgeTransaction.collateral][accountLayout.invalidBridgedAmountsPool].instantAdd(
			bridgeTransaction.collateral,
			((bridgeTransaction.amount - validAmount) * (10 ** 18)) / (10 ** IERC20Metadata(bridgeTransaction.collateral).decimals())
		);
		bridgeTransaction.status = BridgeTransactionStatus.RECEIVED;
		bridgeTransaction.amount = validAmount;
	}
}
