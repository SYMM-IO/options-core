// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

struct PartyBConfig {
	bool isActive;
	uint256 lossCoverage;
	uint256 oracleId;
	uint256 symbolType;
}

library AppStorage {
	bytes32 internal constant APP_STORAGE_SLOT = keccak256("diamond.standard.storage.app");

	struct Layout {
		// System version
		uint16 version;
		/////////////////////////////////////////////////////////
		mapping(address => uint256) balanceLimitPerUser; // collateral => limit
		uint256 maxCloseOrdersLength;
		uint256 maxTradePerPartyA;
		address priceOracleAddress;
		mapping(address => bool) whiteListedCollateral;
		address tradeNftAddress;
		/////////////////////////////////////////////////////////
		mapping(bytes32 => bool) isSigUsed;
		address signatureVerifier;
		/////////////////////////////////////////////////////////
		uint256 partyADeallocateCooldown;
		uint256 partyBDeallocateCooldown;
		uint256 forceCancelOpenIntentTimeout;
		uint256 forceCancelCloseIntentTimeout;
		uint256 ownerExclusiveWindow;
		uint256 settlementPriceSigValidTime;
		/////////////////////////////////////////////////////////
		mapping(address => PartyBConfig) partyBConfigs;
		address[] partyBList;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = APP_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
