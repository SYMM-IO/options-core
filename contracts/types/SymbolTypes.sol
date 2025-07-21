// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { Fee } from "./BaseTypes.sol";

enum OptionType {
	PUT,
	CALL
}

struct Oracle {
	uint256 id;
	address contractAddress;
	string name;
}

struct Symbol {
	uint256 symbolId;
	uint256 oracleId;
	uint256 symbolType;
	Fee platformFee;
	address collateral;
	string name;
	bool isValid;
	OptionType optionType;
}
