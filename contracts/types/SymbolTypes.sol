// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

enum OptionType {
	PUT,
	CALL
}

struct Oracle {
	uint256 id;
	string name;
	address contractAddress;
}

struct Symbol {
	uint256 symbolId;
	bool isValid;
	string name;
	OptionType optionType;
	uint256 oracleId;
	address collateral;
	uint256 tradingFee;
	uint256 symbolType;
}
