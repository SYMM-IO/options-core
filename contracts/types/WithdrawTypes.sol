// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SchnorrSign } from "./MuonTypes.sol";

struct Withdraw {
	uint256 id;
	uint256 amount;
	address collateral;
	address user;
	address to;
	uint256 timestamp;
	WithdrawStatus status;
}

struct UpnlSig {
	bytes reqId; // Unique identifier for the liquidation request
	uint256 timestamp; // Timestamp when the liquidation signature was created
	int256 partyAUpnl; // PartyA's unrealized profit and loss at the time
	int256 partyBUpnl; // PartyB's unrealized profit and loss at the time
	address collateral; // The address of collateral
	uint256 collateralPrice; // The price of collateral
	bytes gatewaySignature; // Signature from the gateway for verification
	SchnorrSign sigs; // Schnorr signature for additional verification
}

enum WithdrawStatus {
	INITIATED,
	CANCELED,
	COMPLETED
}
