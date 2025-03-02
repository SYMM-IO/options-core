// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

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
	bool isStableCoin; // true if the collateral is stablecoin and false if the collateral is same with the symbol underlying token
	uint256 tradingFee;
}

library SymbolStorage {
	bytes32 internal constant SYMBOL_STORAGE_SLOT = keccak256("diamond.standard.storage.symbol");

	struct Layout {
		mapping(uint256 => Oracle) oracles;
		uint256 lastOracleId;
		/////////////////////////////////////////
		mapping(uint256 => Symbol) symbols;
		uint256 lastSymbolId;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = SYMBOL_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
