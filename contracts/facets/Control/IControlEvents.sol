// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { PartyBConfig } from "../../storages/AppStorage.sol";

import { OptionType } from "../../types/SymbolTypes.sol";

interface IControlEvents {
	event CollateralWhitelisted(address indexed collateral);
	event CollateralRemovedFromWhitelist(address indexed collateral);
	event MaxCloseOrdersLengthUpdated(uint256 max);
	event MaxTradePerPartyAUpdated(uint256 max);
	event BalanceLimitPerUserUpdated(address collateral, uint256 limit);
	event PartyADeallocateCooldownUpdated(uint256 cooldown);
	event PartyBDeallocateCooldownUpdated(uint256 cooldown);
	event ForceCancelOpenIntentTimeoutUpdated(uint256 timeout);
	event ForceCancelCloseIntentTimeoutUpdated(uint256 timeout);
	event DefaultFeeCollectorUpdated(address indexed collector);
	event GlobalPaused();
	event ThirdPartyActionsPaused();
	event DepositPaused();
	event WithdrawPaused();
	event PartyBActionsPaused();
	event PartyAActionsPaused();
	event LiquidatingPaused();
	event InstantLayerPaused();
	event GlobalUnpaused();
	event DepositUnpaused();
	event WithdrawUnpaused();
	event PartyBActionsUnpaused();
	event PartyAActionsUnpaused();
	event ThirdPartyActionsUnpaused();
	event LiquidatingUnpaused();
	event InstantLayerUnpaused();
	event EmergencyModeActivated();
	event EmergencyModeDeactivated();
	event PartyBEmergencyModeActivated(address indexed partyB);
	event PartyBEmergencyModeDeactivated(address indexed partyB);
	event AffiliateStatusUpdated(address indexed affiliate, bool status);
	event AffiliateFeesCollectorUpdated(address indexed affiliate, address indexed feeCollector);
	event AffiliateFeesUpdated(address indexed affiliate, uint256 indexed symbolId, uint256 fee);
	event RoleUpdated(address indexed account, bytes32 indexed role, bool granted);
	event PartyBConfigUpdated(address indexed partyB, PartyBConfig config);
	event SettlementPriceSigValidTimeUpdated(uint256 time);
	event UpnlSigValidTimeUpdated(uint256 time);
	event LiquidationDetailUpdated(address indexed partyB, address indexed collateral);
	event SymbolPriceUpdated(address indexed partyB, uint256 indexed symbolId);
	event RoleGranted(bytes32 indexed role, address indexed user);
	event RoleRevoked(bytes32 indexed role, address indexed user);
	event PartyBReleaseIntervalUpdated(address indexed partyB, uint256 interval);
	event DefaultReleaseIntervalUpdated(uint256 interval);
	event MaxConnectedCounterPartiesUpdated(uint256 max);
	event UnbindingCooldownUpdated(uint256 cooldown);
	event AddressSuspended(address indexed user, bool status);
	event WithdrawalSuspended(uint256 indexed withdrawId, bool status);
	event DeactiveInstantActionModeCooldownUpdated(uint256 cooldown);
	event OracleAdded(uint256 indexed oracleId, string name, address contractAddress);
	event SymbolAdded(
		uint256 indexed symbolId,
		string name,
		OptionType optionType,
		uint256 oracleId,
		address collateral,
		uint256 tradingFee,
		uint256 symbolType
	);
	event SymbolStateUpdated(uint256 indexed symbolId, bool status);
	event SymbolTradingFeeUpdated(uint256 indexed _symbolId, uint256 _oldFee, uint256 _fee);
	event PriceOracleAddressUpdated(address indexed oracle);
	event SetManualSync(address user, bool isManual);
	event SignatureVerifierUpdated(address indexed verifier);
	event SetExpressWithdrawProvider(address indexed _provider, bool _state);
	event SetInvalidExpressWithdrawsPool(address indexed _pool);
	event UserWindowUpdated(address indexed user, address indexed collateral, address indexed counterParty);
	event PartyBExclusiveWindowUpdated(uint256 window);
	event InternalTransferPaused();
	event InternalTransferUnpaused();
	event ExpressWithdrawPaused();
	event ExpressWithdrawUnpaused();
	event ExpressWithdrawCollectionPaused();
	event ExpressWithdrawCollectionUnpaused();
	event OracleUpdated(uint256 indexed oracleId, address oldAddress, address newAddress);
}
