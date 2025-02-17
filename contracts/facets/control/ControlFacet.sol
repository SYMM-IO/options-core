// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../utils/Ownable.sol";
import "../../utils/Accessibility.sol";
import "../../storages/SymbolStorage.sol";
import "../../storages/AppStorage.sol";
import "../../libraries/LibDiamond.sol";
import "./IControlFacet.sol";

contract ControlFacet is Accessibility, Ownable, IControlFacet {
	function setAdmin(address _admin) external onlyOwner {
		require(_admin != address(0), "ControlFacet: Zero address");
		AppStorage.layout().hasRole[_admin][LibAccessibility.DEFAULT_ADMIN_ROLE] = true;
		emit RoleGranted(LibAccessibility.DEFAULT_ADMIN_ROLE, _admin);
	}

	function grantRole(address _user, bytes32 _role) external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		require(_user != address(0), "ControlFacet: Zero address");
		AppStorage.layout().hasRole[_user][_role] = true;
		emit RoleGranted(_role, _user);
	}

	function revokeRole(address _user, bytes32 _role) external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		AppStorage.layout().hasRole[_user][_role] = false;
		emit RoleRevoked(_role, _user);
	}

	function whiteListCollateral(address _collateral) external onlyRole(LibAccessibility.SETTER_ROLE) {
		require(_collateral != address(0), "ControlFacet: zero address");
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
		require(_collector != address(0), "ControlFacet: zero address");
		AppStorage.layout().defaultFeeCollector = _collector;
		emit DefaultFeeCollectorUpdated(_collector);
	}

	function setAffiliateStatus(address _affiliate, bool _status) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().affiliateStatus[_affiliate] = _status;
		emit AffiliateStatusUpdated(_affiliate, _status);
	}

	function setAffiliateFeeCollector(address _affiliate, address _collector) external onlyRole(LibAccessibility.SETTER_ROLE) {
		require(_collector != address(0), "ControlFacet: zero address");
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
		AppStorage.layout().depositingPaused = true;
		emit GlobalPaused();
	}

	function pauseDeposit() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		AppStorage.layout().globalPaused = true;
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
		AppStorage.layout().depositingPaused = false;
		emit GlobalUnpaused();
	}

	function unpauseDeposit() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		AppStorage.layout().globalPaused = false;
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
}
