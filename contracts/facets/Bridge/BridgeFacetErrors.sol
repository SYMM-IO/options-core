// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library BridgeFacetErrors {
	// Bridge validation errors
	error InvalidBridge(address bridge);
	error SameBridgeAndSender(address bridge);

	// Transaction validation errors
	error InvalidBridgeTransactionId(uint256 transactionId);
	error BridgeCollateralMismatch(address expectedCollateral, address transactionCollateral);
	error HighValidAmount(uint256 givenValidAmount, uint256 bridgeAmount);
}
