// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

enum LiquidationStatus {
	FLAGGED,
	IN_PROGRESS,
	CANCELLED
}

enum LiquidationSide {
	PARTY_A,
	PARTY_B
}

struct LiquidationDetail {
	LiquidationStatus status;
	int256 upnl;
	uint256 flagTimestamp;
	uint256 liquidationTimestamp;
	address flagger;
	address collateral;
	uint256 collateralPrice;
	address partyA;
	address partyB;
	LiquidationSide side;
}