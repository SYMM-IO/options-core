// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

struct PublicKey {
	uint256 x;
	uint8 parity;
}

struct MuonConfig {
	uint256 muonAppId;
	PublicKey muonPublicKey;
	address validGateway;
}

enum OptionType {
	PUT,
	CALL
}

struct Oracle {
	uint256 id;
	string name;
	MuonConfig muonConfig;
}

struct Symbol {
	uint256 symbolId;
	bool isValid;
	string name;
	OptionType optionType;
	uint256 oracleId;
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
