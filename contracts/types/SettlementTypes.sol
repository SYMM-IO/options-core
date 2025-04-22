// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SchnorrSign } from "./MuonTypes.sol";

struct SettlementState {
	int256 amount;
	bool pending;
}

struct SettlementPriceSig {
	bytes reqId;
	uint256 timestamp;
	uint256 symbolId;
	uint256 settlementPrice;
	uint256 settlementTimestamp;
	uint256 collateralPrice;
	bytes gatewaySignature;
	SchnorrSign sigs;
}
