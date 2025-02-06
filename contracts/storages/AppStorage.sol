// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../interfaces/IMuonOracle.sol";
struct SettlementState {
	int256 amount;
	bool pending;
}

struct LiquidationDetail {
	bytes liquidationId;
	LiquidationStatus status;
	int256 upnl;
	uint256 flagTimestamp;
	uint256 liquidationTimestamp;
	uint256 lossFactor;
	uint256 collateralPrice;
	address flagger;
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
	IMuonOracle.SchnorrSign sigs; // Schnorr signature for additional verification
}

struct SettlementPriceSig {
	bytes reqId;
	uint256 timestamp;
	uint256 symbolId;
	uint256 settlementPrice;
	uint256 settlementTimestamp;
	bytes gatewaySignature;
	IMuonOracle.SchnorrSign sigs;
}

struct Price {
	uint256 price;
	uint256 timestamp;
}

struct PartyBConfig {
	bool isActive;
	uint256 lossCoverage;
	uint256 oracleId;
}

enum LiquidationStatus {
	SOLVENT,
	FLAGGED,
	IN_PROGRESS
}

library AppStorage {
	bytes32 internal constant APP_STORAGE_SLOT = keccak256("diamond.standard.storage.app");

	struct Layout {
		mapping(address => bool) whiteListedCollateral;
		uint256 balanceLimitPerUser;
		uint256 maxCloseOrdersLength;
		uint256 maxTradePerPartyA;
		address priceOracleAddress;
		///////////////////////////////////
		bool globalPaused;
		bool depositingPaused;
		bool withdrawingPaused;
		bool partyBActionsPaused;
		bool partyAActionsPaused;
		bool liquidatingPaused;
		///////////////////////////////////
		bool emergencyMode;
		mapping(address => bool) partyBEmergencyStatus;
		uint256 partyADeallocateCooldown;
		uint256 partyBDeallocateCooldown;
		uint256 forceCancelOpenIntentTimeout;
		uint256 forceCancelCloseIntentTimeout;
		///////////////////////////////////
		address defaultFeeCollector;
		mapping(address => bool) affiliateStatus;
		mapping(address => address) affiliateFeeCollector;
		///////////////////////////////////
		mapping(address => mapping(bytes32 => bool)) hasRole;
		mapping(address => PartyBConfig) partyBConfigs;
		address[] partyBList;
		///////////////////////////////////
		uint256 settlementPriceSigValidTime;
		uint256 liquidationSigValidTime;
		///////////////////////////////////
		mapping(address => mapping(address => LiquidationDetail)) liquidationDetails; // partyBAddress => collateral => detail
		mapping(address => mapping(uint256 => Price)) symbolsPrices;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = APP_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
