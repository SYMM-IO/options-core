// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

interface IBridgeEvents {
	event TransferToBridge(
		address sender,
		address receiver,
		address collateral,
		uint256 amount,
		address bridgeAddress,
		uint256 transactionId,
		uint256 newBalance
	);
	event WithdrawReceivedBridgeValue(uint256 transactionId);
	event SuspendBridgeTransaction(uint256 transactionId);
	event RestoreBridgeTransaction(uint256 transactionId, uint256 validAmount);
	event WithdrawReceivedBridgeValues(uint256[] transactionIds);
}
