// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

library AppStorage {
    bytes32 internal constant APP_STORAGE_SLOT =
        keccak256("diamond.standard.storage.app");

    struct PartyBConfig {
        bool isActive;
        uint256 lossCoverage;
    }

    struct Layout {
        address collateral;
        uint256 balanceLimitPerUser;
        ///////////////////////////////////
        bool globalPaused;
        bool depositingPaused;
        bool withdrawingPaused;
        bool partyBActionsPaused;
        bool partyAActionsPaused;
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
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = APP_STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
