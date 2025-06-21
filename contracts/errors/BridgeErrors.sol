// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library BridgeErrors {
	error BridgeNotWhitelisted(address bridge);
	error SelfBridgeNotAllowed(address bridge);
	error TransactionIdNotFound(uint256 transactionId);
	error MismatchedCollateral(address expectedCollateral, address transactionCollateral);
	error ValidAmountExceedsOriginal(uint256 givenValidAmount, uint256 bridgeAmount);
}
