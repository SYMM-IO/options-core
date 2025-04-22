// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SchnorrSign } from "./MuonTypes.sol";

struct LiquidationState {
	uint256 inProgressLiquidationId;
	LiquidationStatus status;
}

struct LiquidationDetail {
	bytes clearingHouseLiquidationId;
	int256 upnl;
	uint256 flagTimestamp;
	uint256 liquidationTimestamp;
	uint256 collateralPrice;
	address flagger;
	uint256 collectedCollateral;
	uint256 requiredCollateral;
}
struct LiquidationSig {
	bytes reqId; // Unique identifier for the liquidation request
	uint256 timestamp; // Timestamp when the liquidation signature was created
	bytes liquidationId; // Unique identifier for the liquidation event
	int256 upnl; // User's unrealized profit and loss at the time of insolvency
	address collateral; // The address of collateral
	uint256 collateralPrice; // The price of collateral
	uint256[] symbolIds; // List of symbol IDs involved in the liquidation
	uint256[] prices; // Corresponding prices of the symbols involved in the liquidation
	bytes gatewaySignature; // Signature from the gateway for verification
	SchnorrSign sigs; // Schnorr signature for additional verification
}

enum LiquidationStatus {
	SOLVENT,
	FLAGGED,
	IN_PROGRESS
}
