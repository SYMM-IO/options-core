// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { PartyBConfig } from "../../storages/AppStorage.sol";

import { OptionType } from "../../types/SymbolTypes.sol";

import { IControlEvents } from "./IControlEvents.sol";

interface IControlFacet is IControlEvents {
	function setAdmin(address _admin) external;

	function grantRole(address _user, bytes32 _role) external;

	function revokeRole(address _user, bytes32 _role) external;

	function whiteListCollateral(address _collateral) external;

	function removeFromWhiteListCollateral(address _collateral) external;

	function setMaxCloseOrdersLength(uint256 _max) external;

	function setMaxTradePerPartyA(uint256 _max) external;

	function setBalanceLimitPerUser(address collateral, uint256 _limit) external;

	function setPartyADeallocateCooldown(uint256 _cooldown) external;

	function setPartyBDeallocateCooldown(uint256 _cooldown) external;

	function setForceCancelOpenIntentTimeout(uint256 _timeout) external;

	function setForceCancelCloseIntentTimeout(uint256 _timeout) external;

	function setDefaultFeeCollector(address _collector) external;

	function setPartyBReleaseInterval(address _partyB, uint256 _interval) external;

	function setDefaultReleaseInterval(uint256 _interval) external;

	function pauseGlobal() external;

	function pauseDeposit() external;

	function pauseWithdraw() external;

	function pausePartyBActions() external;

	function pausePartyAActions() external;

	function pauseLiquidating() external;

	function unpauseGlobal() external;

	function unpauseDeposit() external;

	function unpauseWithdraw() external;

	function unpausePartyBActions() external;

	function unpausePartyAActions() external;

	function unpauseLiquidating() external;

	function activeEmergencyMode() external;

	function deactiveEmergencyMode() external;

	function activePartyBEmergencyStatus(address _partyB) external;

	function deactivePartyBEmergencyStatus(address _partyB) external;

	function setAffiliateStatus(address _affiliate, bool _status) external;

	function setAffiliateFeeCollector(address _affiliate, address _feeCollector) external;

	function setPartyBConfig(address _partyB, PartyBConfig calldata _config) external;

	function setSettlementPriceSigValidTime(uint256 _time) external;

	function addOracle(string calldata _name, address _contractAddress) external;

	function addSymbol(
		string calldata _name,
		OptionType _optionType,
		uint256 _oracleId,
		address _collateral,
		uint256 _tradingFee,
		uint256 _symbolType
	) external;

	function setMaxConnectedCounterParties(uint256 _max) external;

	function setManualSync(address user, bool isManual) external;
}
