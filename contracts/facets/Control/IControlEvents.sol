// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { PartyBConfig } from "../../storages/AppStorage.sol";
import { OptionType } from "../../storages/SymbolStorage.sol";

interface IControlEvents {
	event CollateralWhitelisted(address indexed collateral);
	event CollateralRemovedFromWhitelist(address indexed collateral);
	event MaxCloseOrdersLengthUpdated(uint256 max);
	event MaxTradePerPartyAUpdated(uint256 max);
	event BalanceLimitPerUserUpdated(uint256 limit);
	event PartyADeallocateCooldownUpdated(uint256 cooldown);
	event PartyBDeallocateCooldownUpdated(uint256 cooldown);
	event ForceCancelOpenIntentTimeoutUpdated(uint256 timeout);
	event ForceCancelCloseIntentTimeoutUpdated(uint256 timeout);
	event DefaultFeeCollectorUpdated(address indexed collector);
	event GlobalPaused();
	event DepositPaused();
	event WithdrawPaused();
	event PartyBActionsPaused();
	event PartyAActionsPaused();
	event LiquidatingPaused();
	event GlobalUnpaused();
	event DepositUnpaused();
	event WithdrawUnpaused();
	event PartyBActionsUnpaused();
	event PartyAActionsUnpaused();
	event LiquidatingUnpaused();
	event EmergencyModeActivated();
	event EmergencyModeDeactivated();
	event PartyBEmergencyStatusActivated(address indexed partyB);
	event PartyBEmergencyStatusDeactivated(address indexed partyB);
	event AffiliateStatusUpdated(address indexed affiliate, bool status);
	event AffiliateFeeCollectorUpdated(address indexed affiliate, address indexed feeCollector);
	event RoleUpdated(address indexed account, bytes32 indexed role, bool granted);
	event PartyBConfigUpdated(address indexed partyB, PartyBConfig config);
	event SettlementPriceSigValidTimeUpdated(uint256 time);
	event LiquidationSigValidTimeUpdated(uint256 time);
	event LiquidationDetailUpdated(address indexed partyB, address indexed collateral);
	event SymbolPriceUpdated(address indexed partyB, uint256 indexed symbolId);
	event RoleGranted(bytes32 indexed role, address indexed user);
	event RoleRevoked(bytes32 indexed role, address indexed user);
	event PartyBReleaseIntervalUpdated(address indexed partyB, uint256 interval);
	event MaxConnectedPartyBsUpdated(uint256 max);
	event UnbindingCooldownUpdated(uint256 cooldown);
	event AddressSuspended(address indexed user, bool status);
	event WithdrawalSuspended(uint256 indexed withdrawId, bool status);
	event DeactiveInstantActionModeCooldownUpdated(uint256 cooldown);
	event InstantActionsModeUpdated(address indexed user, bool status);
	event InstantActionsModeDeactivateTimeUpdated(address indexed user, uint256 time);
	event OracleAdded(uint256 indexed oracleId, string name, address contractAddress);
	event SymbolAdded(uint256 indexed symbolId, string name, OptionType optionType, uint256 oracleId, address collateral, bool isStableCoin, uint256 tradingFee, uint256 symbolType);
	event PriceOracleAddressUpdated(address indexed oracle);
}
