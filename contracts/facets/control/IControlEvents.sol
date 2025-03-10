// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/AppStorage.sol";
import "../../storages/SymbolStorage.sol";

interface IControlEvents {
	/// @notice Emitted when a collateral is whitelisted
	event CollateralWhitelisted(address indexed collateral);
	/// @notice Emitted when a collateral is removed from whitelist
	event CollateralRemovedFromWhitelist(address indexed collateral);
	/// @notice Emitted when max close orders length is updated
	event MaxCloseOrdersLengthUpdated(uint256 max);
	/// @notice Emitted when max trades per partyA is updated
	event MaxTradePerPartyAUpdated(uint256 max);
	/// @notice Emitted when balance limit per user is updated
	event BalanceLimitPerUserUpdated(uint256 limit);
	/// @notice Emitted when partyA deallocate cooldown is updated
	event PartyADeallocateCooldownUpdated(uint256 cooldown);
	/// @notice Emitted when partyB deallocate cooldown is updated
	event PartyBDeallocateCooldownUpdated(uint256 cooldown);
	/// @notice Emitted when force cancel open intent timeout is updated
	event ForceCancelOpenIntentTimeoutUpdated(uint256 timeout);
	/// @notice Emitted when force cancel close intent timeout is updated
	event ForceCancelCloseIntentTimeoutUpdated(uint256 timeout);
	/// @notice Emitted when default fee collector is updated
	event DefaultFeeCollectorUpdated(address indexed collector);
	/// @notice Emitted when the global pause is activated
	event GlobalPaused();
	/// @notice Emitted when the deposit pause is activated
	event DepositPaused();
	/// @notice Emitted when the withdraw pause is activated
	event WithdrawPaused();
	/// @notice Emitted when partyB actions are paused
	event PartyBActionsPaused();
	/// @notice Emitted when partyA actions are paused
	event PartyAActionsPaused();
	/// @notice Emitted when liquidating is paused
	event LiquidatingPaused();
	/// @notice Emitted when the global pause is deactivated
	event GlobalUnpaused();
	/// @notice Emitted when the deposit pause is deactivated
	event DepositUnpaused();
	/// @notice Emitted when the withdraw pause is deactivated
	event WithdrawUnpaused();
	/// @notice Emitted when partyB actions are unpaused
	event PartyBActionsUnpaused();
	/// @notice Emitted when partyA actions are unpaused
	event PartyAActionsUnpaused();
	/// @notice Emitted when liquidating is unpaused
	event LiquidatingUnpaused();
	/// @notice Emitted when emergency mode is activated
	event EmergencyModeActivated();
	/// @notice Emitted when emergency mode is deactivated
	event EmergencyModeDeactivated();
	/// @notice Emitted when a partyB is set to emergency status
	event PartyBEmergencyStatusActivated(address indexed partyB);
	/// @notice Emitted when a partyB emergency status is deactivated
	event PartyBEmergencyStatusDeactivated(address indexed partyB);
	/// @notice Emitted when an affiliate status is updated
	event AffiliateStatusUpdated(address indexed affiliate, bool status);
	/// @notice Emitted when an affiliate fee collector is updated
	event AffiliateFeeCollectorUpdated(address indexed affiliate, address indexed feeCollector);
	/// @notice Emitted when a role is assigned or revoked
	event RoleUpdated(address indexed account, bytes32 indexed role, bool granted);
	/// @notice Emitted when a PartyB configuration is updated
	event PartyBConfigUpdated(address indexed partyB, PartyBConfig config);
	/// @notice Emitted when the settlement price signature validity time is updated
	event SettlementPriceSigValidTimeUpdated(uint256 time);
	/// @notice Emitted when the liquidation signature validity time is updated
	event LiquidationSigValidTimeUpdated(uint256 time);
	/// @notice Emitted when a liquidation detail is updated
	event LiquidationDetailUpdated(address indexed partyB, address indexed collateral);
	/// @notice Emitted when a symbol price is updated
	event SymbolPriceUpdated(address indexed partyB, uint256 indexed symbolId);
	/// @notice Emitted when a role is granted
	event RoleGranted(bytes32 indexed role, address indexed user);
	/// @notice Emitted when a role is revoked
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
    event SymbolAdded(uint256 indexed symbolId, string name, OptionType optionType, address collateral);
	event PriceOracleAddressUpdated(address indexed oracle);
}
