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
	int256 upnl;
	uint256 flagTimestamp;
	uint256 liquidationTimestamp;
	uint256 collateralPrice;
	address flagger;
	address collateral;
	address partyA;
	address partyB;
	LiquidationSide side;
	LiquidationStatus status;
}