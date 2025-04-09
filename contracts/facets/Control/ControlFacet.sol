// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../../libraries/LibAccessibility.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage, PartyBConfig } from "../../storages/AppStorage.sol";
import { SymbolStorage, Symbol, Oracle, OptionType } from "../../storages/SymbolStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Ownable } from "../../utils/Ownable.sol";
import { IControlEvents } from "./IControlEvents.sol";
import { IControlFacet } from "./IControlFacet.sol";
import { ControlFacetErrors } from "./ControlFacetErrors.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ControlFacet is Accessibility, Ownable, IControlFacet {
	using EnumerableSet for EnumerableSet.AddressSet;

	function setAdmin(address _admin) external onlyOwner {
		if (_admin == address(0)) revert CommonErrors.ZeroAddress("admin");
		AppStorage.layout().hasRole[_admin][LibAccessibility.DEFAULT_ADMIN_ROLE] = true;
		emit RoleGranted(LibAccessibility.DEFAULT_ADMIN_ROLE, _admin);
	}

	function grantRole(address _user, bytes32 _role) external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		if (_user == address(0)) revert CommonErrors.ZeroAddress("user");
		AppStorage.Layout storage appStorageLayout = AppStorage.layout();
		if (!appStorageLayout.hasRole[_user][_role]) {
			appStorageLayout.hasRole[_user][_role] = true;
			appStorageLayout.roleMembers[_role].add(_user);
			emit RoleGranted(_role, _user);
		}
	}

	function revokeRole(address _user, bytes32 _role) external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		if (_user == address(0)) revert CommonErrors.ZeroAddress("user");
		AppStorage.Layout storage appStorageLayout = AppStorage.layout();
		if (appStorageLayout.hasRole[_user][_role]) {
			appStorageLayout.hasRole[_user][_role] = false;
			appStorageLayout.roleMembers[_role].remove(_user);
			emit RoleRevoked(_role, _user);
		}
	}

	function whiteListCollateral(address _collateral) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_collateral == address(0)) revert CommonErrors.ZeroAddress("collateral");
		AppStorage.layout().whiteListedCollateral[_collateral] = true;
		emit CollateralWhitelisted(_collateral);
	}

	function removeFromWhiteListCollateral(address _collateral) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().whiteListedCollateral[_collateral] = false;
		emit CollateralRemovedFromWhitelist(_collateral);
	}

	function setMaxCloseOrdersLength(uint256 _max) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().maxCloseOrdersLength = _max;
		emit MaxCloseOrdersLengthUpdated(_max);
	}

	function setMaxTradePerPartyA(uint256 _max) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().maxTradePerPartyA = _max;
		emit MaxTradePerPartyAUpdated(_max);
	}

	function setBalanceLimitPerUser(uint256 _limit) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().balanceLimitPerUser = _limit;
		emit BalanceLimitPerUserUpdated(_limit);
	}

	function setPartyADeallocateCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().partyADeallocateCooldown = _cooldown;
		emit PartyADeallocateCooldownUpdated(_cooldown);
	}

	function setPartyBDeallocateCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().partyBDeallocateCooldown = _cooldown;
		emit PartyBDeallocateCooldownUpdated(_cooldown);
	}

	function setForceCancelOpenIntentTimeout(uint256 _timeout) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().forceCancelOpenIntentTimeout = _timeout;
		emit ForceCancelOpenIntentTimeoutUpdated(_timeout);
	}

	function setForceCancelCloseIntentTimeout(uint256 _timeout) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().forceCancelCloseIntentTimeout = _timeout;
		emit ForceCancelCloseIntentTimeoutUpdated(_timeout);
	}

	function setDefaultFeeCollector(address _collector) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_collector == address(0)) revert CommonErrors.ZeroAddress("collector");
		AppStorage.layout().defaultFeeCollector = _collector;
		emit DefaultFeeCollectorUpdated(_collector);
	}

	function setAffiliateStatus(address _affiliate, bool _status) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().affiliateStatus[_affiliate] = _status;
		emit AffiliateStatusUpdated(_affiliate, _status);
	}

	function setAffiliateFeeCollector(address _affiliate, address _collector) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_collector == address(0)) revert CommonErrors.ZeroAddress("collector");
		AppStorage.layout().affiliateFeeCollector[_affiliate] = _collector;
		emit AffiliateFeeCollectorUpdated(_affiliate, _collector);
	}

	function setPartyBConfig(address _partyB, PartyBConfig calldata _config) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().partyBConfigs[_partyB] = _config;
		emit PartyBConfigUpdated(_partyB, _config);
	}

	function setSettlementPriceSigValidTime(uint256 _time) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().settlementPriceSigValidTime = _time;
		emit SettlementPriceSigValidTimeUpdated(_time);
	}

	function setLiquidationSigValidTime(uint256 _time) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().liquidationSigValidTime = _time;
		emit LiquidationSigValidTimeUpdated(_time);
	}

	// pause
	function pauseGlobal() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		AppStorage.layout().globalPaused = true;
		emit GlobalPaused();
	}

	function pauseDeposit() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		AppStorage.layout().depositingPaused = true;
		emit DepositPaused();
	}

	function pauseWithdraw() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		AppStorage.layout().withdrawingPaused = true;
		emit WithdrawPaused();
	}

	function pausePartyBActions() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		AppStorage.layout().partyBActionsPaused = true;
		emit PartyBActionsPaused();
	}

	function pausePartyAActions() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		AppStorage.layout().partyAActionsPaused = true;
		emit PartyAActionsPaused();
	}

	function pauseLiquidating() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		AppStorage.layout().liquidatingPaused = true;
		emit LiquidatingPaused();
	}

	// unpause
	function unpauseGlobal() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		AppStorage.layout().globalPaused = false;
		emit GlobalUnpaused();
	}

	function unpauseDeposit() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		AppStorage.layout().depositingPaused = false;
		emit DepositUnpaused();
	}

	function unpauseWithdraw() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		AppStorage.layout().withdrawingPaused = false;
		emit WithdrawUnpaused();
	}

	function unpausePartyBActions() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		AppStorage.layout().partyBActionsPaused = false;
		emit PartyBActionsUnpaused();
	}

	function unpausePartyAActions() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		AppStorage.layout().partyAActionsPaused = false;
		emit PartyAActionsUnpaused();
	}

	function unpauseLiquidating() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		AppStorage.layout().liquidatingPaused = false;
		emit LiquidatingUnpaused();
	}

	function activeEmergencyMode() external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		AppStorage.layout().emergencyMode = true;
		emit EmergencyModeActivated();
	}

	function deactiveEmergencyMode() external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		AppStorage.layout().emergencyMode = false;
		emit EmergencyModeDeactivated();
	}

	function activePartyBEmergencyStatus(address _partyB) external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		AppStorage.layout().partyBEmergencyStatus[_partyB] = true;
		emit PartyBEmergencyStatusActivated(_partyB);
	}

	function deactivePartyBEmergencyStatus(address _partyB) external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		AppStorage.layout().partyBEmergencyStatus[_partyB] = false;
		emit PartyBEmergencyStatusDeactivated(_partyB);
	}

	function setPartyBReleaseInterval(address _partyB, uint256 _interval) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().partyBReleaseIntervals[_partyB] = _interval;
		emit PartyBReleaseIntervalUpdated(_partyB, _interval);
	}

	function setMaxConnectedPartyBs(uint256 _max) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().maxConnectedPartyBs = _max;
		emit MaxConnectedPartyBsUpdated(_max);
	}

	function setUnbindingCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().unbindingCooldown = _cooldown;
		emit UnbindingCooldownUpdated(_cooldown);
	}

	function suspendAddress(address _user, bool _status) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().suspendedAddresses[_user] = _status;
		emit AddressSuspended(_user, _status);
	}

	function suspendWithdrawal(uint256 _withdrawId, bool _status) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().suspendedWithdrawal[_withdrawId] = _status;
		emit WithdrawalSuspended(_withdrawId, _status);
	}

	function setDeactiveInstantActionModeCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().deactiveInstantActionModeCooldown = _cooldown;
		emit DeactiveInstantActionModeCooldownUpdated(_cooldown);
	}

	function setInstantActionsMode(address _user, bool _status) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().instantActionsMode[_user] = _status;
		emit InstantActionsModeUpdated(_user, _status);
	}

	function setInstantActionsModeDeactivateTime(address _user, uint256 _time) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().instantActionsModeDeactivateTime[_user] = _time;
		emit InstantActionsModeDeactivateTimeUpdated(_user, _time);
	}

	function addOracle(string calldata _name, address _contractAddress) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_contractAddress == address(0)) revert CommonErrors.ZeroAddress("contractAddress");
		SymbolStorage.Layout storage s = SymbolStorage.layout();
		s.lastOracleId++;
		s.oracles[s.lastOracleId] = Oracle({ id: s.lastOracleId, name: _name, contractAddress: _contractAddress });
		emit OracleAdded(s.lastOracleId, _name, _contractAddress);
	}

	function addSymbol(
		string calldata _name,
		OptionType _optionType,
		uint256 _oracleId,
		address _collateral,
		uint256 _tradingFee,
		uint256 _symbolType
	) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_collateral == address(0)) revert CommonErrors.ZeroAddress("collateral");
		SymbolStorage.Layout storage s = SymbolStorage.layout();
		if (s.oracles[_oracleId].contractAddress == address(0) || s.lastOracleId < _oracleId)
			revert ControlFacetErrors.InvalidOracle(_oracleId, s.lastOracleId);

		s.lastSymbolId++;
		s.symbols[s.lastSymbolId] = Symbol({
			symbolId: s.lastSymbolId,
			isValid: true,
			name: _name,
			optionType: _optionType,
			oracleId: _oracleId,
			collateral: _collateral,
			tradingFee: _tradingFee,
			symbolType: _symbolType
		});
		s.lastSymbolId = s.lastSymbolId;
		emit SymbolAdded(s.lastSymbolId, _name, _optionType, _oracleId, _collateral, _tradingFee, _symbolType);
	}

	function setPriceOracleAddress(address _oracle) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().priceOracleAddress = _oracle;
		emit PriceOracleAddressUpdated(_oracle);
	}
}
