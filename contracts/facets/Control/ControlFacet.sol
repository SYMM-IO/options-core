// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../../libraries/models/LibParty.sol";
import { LibAccessibility } from "../../libraries/core/LibAccessibility.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/models/LibScheduledReleaseBalance.sol";

import { SymbolStorage } from "../../storages/SymbolStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage, PartyBConfig } from "../../storages/AppStorage.sol";
import { StateControlStorage } from "../../storages/StateControlStorage.sol";
import { AccessControlStorage } from "../../storages/AccessControlStorage.sol";
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";
import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";
import { Symbol, Oracle, OptionType } from "../../types/SymbolTypes.sol";
import { ExpressWithdrawProviderConfig } from "../../types/WithdrawTypes.sol";

import { SystemErrors } from "../../errors/SystemErrors.sol";
import { ValidationErrors } from "../../errors/ValidationErrors.sol";

import { Ownable } from "../../utils/Ownable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IControlFacet } from "./IControlFacet.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ControlFacet
 * @notice Administrative control facet for the Symmio protocol
 * @dev Manages system configuration, access control, and emergency operations
 */
contract ControlFacet is Accessibility, Ownable, IControlFacet {
	using EnumerableSet for EnumerableSet.AddressSet;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	// ═══════════════════════════════════════════════════════════════════════════
	//                              ACCESS CONTROL
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Sets the initial admin for the protocol
	 * @dev Can only be called by the contract owner
	 * @param _admin The address to be granted admin privileges
	 */
	function setAdmin(address _admin) external onlyOwner {
		if (_admin == address(0)) revert ValidationErrors.ZeroAddress("admin");
		AccessControlStorage.layout().hasRole[_admin][LibAccessibility.DEFAULT_ADMIN_ROLE] = true;
		emit RoleGranted(LibAccessibility.DEFAULT_ADMIN_ROLE, _admin);
	}

	/**
	 * @notice Grants a role to a user
	 * @dev Can only be called by DEFAULT_ADMIN_ROLE
	 * @param _user The address to grant the role to
	 * @param _role The role identifier to grant
	 */
	function grantRole(address _user, bytes32 _role) external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		if (_user == address(0)) revert ValidationErrors.ZeroAddress("user");
		AccessControlStorage.Layout storage layout = AccessControlStorage.layout();
		if (!layout.hasRole[_user][_role]) {
			layout.hasRole[_user][_role] = true;
			layout.roleMembers[_role].add(_user);
			emit RoleGranted(_role, _user);
		}
	}

	/**
	 * @notice Revokes a role from a user
	 * @dev Can only be called by DEFAULT_ADMIN_ROLE
	 * @param _user The address to revoke the role from
	 * @param _role The role identifier to revoke
	 */
	function revokeRole(address _user, bytes32 _role) external onlyRole(LibAccessibility.DEFAULT_ADMIN_ROLE) {
		if (_user == address(0)) revert ValidationErrors.ZeroAddress("user");
		AccessControlStorage.Layout storage layout = AccessControlStorage.layout();
		if (layout.hasRole[_user][_role]) {
			layout.hasRole[_user][_role] = false;
			layout.roleMembers[_role].remove(_user);
			emit RoleRevoked(_role, _user);
		}
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          COLLATERAL MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Adds a collateral token to the whitelist
	 * @param _collateral The address of the collateral token to whitelist
	 */
	function whiteListCollateral(address _collateral) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_collateral == address(0)) revert ValidationErrors.ZeroAddress("collateral");
		AppStorage.layout().whiteListedCollateral[_collateral] = true;
		emit CollateralWhitelisted(_collateral);
	}

	/**
	 * @notice Removes a collateral token from the whitelist
	 * @param _collateral The address of the collateral token to remove
	 */
	function removeCollateralFromWhitelist(address _collateral) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().whiteListedCollateral[_collateral] = false;
		emit CollateralRemovedFromWhitelist(_collateral);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          SYSTEM PARAMETERS
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Sets the maximum number of close orders allowed per trade
	 * @param _max The maximum number of close orders
	 */
	function setMaxCloseOrdersLength(uint256 _max) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_max == 0) revert ValidationErrors.ZeroAmount();
		AppStorage.layout().maxCloseOrdersLength = _max;
		emit MaxCloseOrdersLengthUpdated(_max);
	}

	/**
	 * @notice Sets the maximum number of trades allowed per PartyA
	 * @param _max The maximum number of trades
	 */
	function setMaxTradePerPartyA(uint256 _max) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_max == 0) revert ValidationErrors.ZeroAmount();
		AppStorage.layout().maxTradePerPartyA = _max;
		emit MaxTradePerPartyAUpdated(_max);
	}

	/**
	 * @notice Sets the balance limit per user for a specific collateral
	 * @param collateral The collateral token address
	 * @param _limit The balance limit amount
	 */
	function setBalanceLimitPerUser(address collateral, uint256 _limit) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (collateral == address(0)) revert ValidationErrors.ZeroAddress("collateral");
		AppStorage.layout().balanceLimitPerUser[collateral] = _limit;
		emit BalanceLimitPerUserUpdated(collateral, _limit);
	}

	/**
	 * @notice Sets all timing parameters in a single transaction
	 * @dev Reduces the number of transactions needed for initial setup
	 * @param _partyADeallocateCooldown Cooldown for PartyA deallocation
	 * @param _partyBDeallocateCooldown Cooldown for PartyB deallocation
	 * @param _forceCancelOpenTimeout Timeout for force canceling open intents
	 * @param _forceCancelCloseTimeout Timeout for force canceling close intents
	 * @param _settlementPriceSigValidTime Valid time for settlement price signatures
	 * @param _upnlSigValidTime Valid time for upnl signatures
	 * @param _partyBExclusiveWindow Exclusive window for PartyB actions
	 * @param _unbindingCooldown Cooldown for unbinding
	 * @param _deactiveInstantActionModeCooldown Cooldown for deactivating instant action mode
	 */
	function setTimingParameters(
		uint256 _partyADeallocateCooldown,
		uint256 _partyBDeallocateCooldown,
		uint256 _forceCancelOpenTimeout,
		uint256 _forceCancelCloseTimeout,
		uint256 _settlementPriceSigValidTime,
		uint256 _upnlSigValidTime,
		uint256 _partyBExclusiveWindow,
		uint256 _unbindingCooldown,
		uint256 _deactiveInstantActionModeCooldown
	) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		CounterPartyRelationsStorage.Layout storage counterPartyRelationsLayout = CounterPartyRelationsStorage.layout();

		appLayout.partyADeallocateCooldown = _partyADeallocateCooldown;
		appLayout.partyBDeallocateCooldown = _partyBDeallocateCooldown;
		appLayout.forceCancelOpenIntentTimeout = _forceCancelOpenTimeout;
		appLayout.forceCancelCloseIntentTimeout = _forceCancelCloseTimeout;
		appLayout.settlementPriceSigValidTime = _settlementPriceSigValidTime;
		appLayout.upnlSigValidTime = _upnlSigValidTime;
		appLayout.partyBExclusiveWindow = _partyBExclusiveWindow;

		counterPartyRelationsLayout.unbindingCooldown = _unbindingCooldown;
		counterPartyRelationsLayout.deactiveInstantActionModeCooldown = _deactiveInstantActionModeCooldown;

		emit PartyADeallocateCooldownUpdated(_partyADeallocateCooldown);
		emit PartyBDeallocateCooldownUpdated(_partyBDeallocateCooldown);
		emit ForceCancelOpenIntentTimeoutUpdated(_forceCancelOpenTimeout);
		emit ForceCancelCloseIntentTimeoutUpdated(_forceCancelCloseTimeout);
		emit SettlementPriceSigValidTimeUpdated(_settlementPriceSigValidTime);
		emit UpnlSigValidTimeUpdated(_upnlSigValidTime);
		emit PartyBExclusiveWindowUpdated(_partyBExclusiveWindow);
		emit UnbindingCooldownUpdated(_unbindingCooldown);
		emit DeactiveInstantActionModeCooldownUpdated(_deactiveInstantActionModeCooldown);
	}

	// Individual setters remain for flexibility

	/**
	 * @notice Sets the deallocate cooldown for PartyA
	 * @param _cooldown The deallocate cooldown
	 */
	function setPartyADeallocateCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().partyADeallocateCooldown = _cooldown;
		emit PartyADeallocateCooldownUpdated(_cooldown);
	}

	/**
	 * @notice Sets the deallocate cooldown for PartyB
	 * @param _cooldown The deallocate cooldown
	 */
	function setPartyBDeallocateCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().partyBDeallocateCooldown = _cooldown;
		emit PartyBDeallocateCooldownUpdated(_cooldown);
	}

	/**
	 * @notice Sets the force cancel open intent timeout
	 * @param _timeout The force cancel open intent timeout
	 */
	function setForceCancelOpenIntentTimeout(uint256 _timeout) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().forceCancelOpenIntentTimeout = _timeout;
		emit ForceCancelOpenIntentTimeoutUpdated(_timeout);
	}

	/**
	 * @notice Sets the force cancel close intent timeout
	 * @param _timeout The force cancel close intent timeout
	 */
	function setForceCancelCloseIntentTimeout(uint256 _timeout) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().forceCancelCloseIntentTimeout = _timeout;
		emit ForceCancelCloseIntentTimeoutUpdated(_timeout);
	}

	/**
	 * @notice Sets the settlement price signature valid time
	 * @param _time The settlement price signature valid time
	 */
	function setSettlementPriceSigValidTime(uint256 _time) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().settlementPriceSigValidTime = _time;
		emit SettlementPriceSigValidTimeUpdated(_time);
	}

	/**
	 * @notice Sets the upnl signature valid time
	 * @param _time The upnl signature valid time
	 */
	function setUpnlSigValidTime(uint256 _time) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().upnlSigValidTime = _time;
		emit UpnlSigValidTimeUpdated(_time);
	}

	/**
	 * @notice Sets the party B exclusive window
	 * @param _window The party B exclusive window
	 */
	function setPartyBExclusiveWindow(uint256 _window) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().partyBExclusiveWindow = _window;
		emit PartyBExclusiveWindowUpdated(_window);
	}

	/**
	 * @notice Sets the unbinding cooldown
	 * @param _cooldown The unbinding cooldown
	 */
	function setUnbindingCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		CounterPartyRelationsStorage.layout().unbindingCooldown = _cooldown;
		emit UnbindingCooldownUpdated(_cooldown);
	}

	/**
	 * @notice Sets the deactive instant action mode cooldown
	 * @param _cooldown The deactive instant action mode cooldown
	 */
	function setDeactiveInstantActionModeCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		CounterPartyRelationsStorage.layout().deactiveInstantActionModeCooldown = _cooldown;
		emit DeactiveInstantActionModeCooldownUpdated(_cooldown);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          RELEASE INTERVAL MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Sets the release interval for PartyB
	 * @param _partyB The PartyB address
	 * @param _interval The release interval
	 */
	function setPartyBReleaseInterval(address _partyB, uint256 _interval) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		AccountStorage.layout().hasConfiguredInterval[_partyB] = true;
		AccountStorage.layout().releaseIntervals[_partyB] = _interval;
		emit PartyBReleaseIntervalUpdated(_partyB, _interval);
	}

	/**
	 * @notice Sets the default release interval
	 * @param _interval The default release interval
	 */
	function setDefaultReleaseInterval(uint256 _interval) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().defaultReleaseInterval = _interval;
		emit DefaultReleaseIntervalUpdated(_interval);
	}

	/**
	 * @notice Sets the maximum number of connected counter parties
	 * @param _max The maximum number of connected counter parties
	 */
	function setMaxConnectedCounterParties(uint256 _max) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_max == 0) revert ValidationErrors.ZeroAmount();
		AccountStorage.layout().maxConnectedCounterParties = _max;
		emit MaxConnectedCounterPartiesUpdated(_max);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          FEE MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Sets the default fee collector
	 * @param _collector The default fee collector
	 */
	function setDefaultFeeCollector(address _collector) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_collector == address(0)) revert ValidationErrors.ZeroAddress("collector");
		FeeManagementStorage.layout().defaultFeeCollector = _collector;
		emit DefaultFeeCollectorUpdated(_collector);
	}

	/**
	 * @notice Sets the affiliate status
	 * @param _affiliate The affiliate address
	 * @param _status The affiliate status
	 */
	function setAffiliateStatus(address _affiliate, bool _status) external onlyRole(LibAccessibility.AFFILIATE_MANAGER_ROLE) {
		FeeManagementStorage.layout().affiliateStatus[_affiliate] = _status;
		emit AffiliateStatusUpdated(_affiliate, _status);
	}

	/**
	 * @notice Sets the affiliate fees collector
	 * @param _affiliate The affiliate address
	 * @param _collector The affiliate fees collector
	 */
	function setAffiliateFeesCollector(address _affiliate, address _collector) external onlyRole(LibAccessibility.AFFILIATE_MANAGER_ROLE) {
		if (_collector == address(0)) revert ValidationErrors.ZeroAddress("collector");
		FeeManagementStorage.layout().affiliateFeeCollector[_affiliate] = _collector;
		emit AffiliateFeesCollectorUpdated(_affiliate, _collector);
	}

	/**
	 * @notice Sets the affiliate fees for multiple symbols
	 * @param _affiliate The affiliate address
	 * @param _symbolIds Array of symbol IDs
	 * @param _fees Array of fee amounts
	 */
	function setAffiliateFees(
		address _affiliate,
		uint256[] calldata _symbolIds,
		uint256[] calldata _fees
	) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_affiliate == address(0)) revert ValidationErrors.ZeroAddress("affiliate");
		if (_affiliate != msg.sender && !LibAccessibility.hasRole(msg.sender, LibAccessibility.AFFILIATE_FEE_MANAGER_ROLE))
			revert ValidationErrors.UnauthorizedSender(msg.sender, _affiliate);
		if (_symbolIds.length != _fees.length) revert ValidationErrors.MismatchedLengths();

		FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();
		for (uint256 i = 0; i < _symbolIds.length; i++) {
			feeLayout.affiliateFees[_affiliate][_symbolIds[i]] = _fees[i];
			emit AffiliateFeesUpdated(_affiliate, _symbolIds[i], _fees[i]);
		}
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          PARTY B CONFIGURATION
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Sets the PartyB configuration
	 * @param _partyB The PartyB address
	 * @param _config The PartyB configuration
	 */
	function setPartyBConfig(address _partyB, PartyBConfig calldata _config) external onlyRole(LibAccessibility.PARTY_B_MANAGER_ROLE) {
		if (_partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		if (_config.isActive) verifyOracle(_config.oracleId);

		AppStorage.layout().partyBConfigs[_partyB] = _config;
		AccountStorage.layout().manualSync[_partyB] = true;
		emit PartyBConfigUpdated(_partyB, _config);
	}

	/**
	 * @notice Sets the supported symbol types for a PartyB in batch
	 * @param _partyB The PartyB address
	 * @param _symbolTypes Array of symbol types
	 * @param _statuses Array of statuses
	 */
	function setPartyBSupportedSymbolTypes(
		address _partyB,
		uint256[] calldata _symbolTypes,
		bool[] calldata _statuses
	) external onlyRole(LibAccessibility.PARTY_B_MANAGER_ROLE) {
		if (_partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		if (_symbolTypes.length != _statuses.length) revert ValidationErrors.MismatchedLengths();
		AppStorage.Layout storage appLayout = AppStorage.layout();
		for (uint256 i = 0; i < _symbolTypes.length; i++) {
			appLayout.partyBSupportedSymbolTypes[_partyB][_symbolTypes[i]] = _statuses[i];
			emit PartyBSupportedSymbolTypesUpdated(_partyB, _symbolTypes[i], _statuses[i]);
		}
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          PAUSE MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	// Pause functions

	/**
	 * @notice Pauses the global state
	 */
	function pauseGlobal() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().globalPaused = true;
		emit GlobalPaused();
	}

	/**
	 * @notice Pauses the deposit operations
	 */
	function pauseDeposit() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().depositingPaused = true;
		emit DepositPaused();
	}

	/**
	 * @notice Pauses the withdraw operations
	 */
	function pauseWithdraw() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().withdrawingPaused = true;
		emit WithdrawPaused();
	}

	/**
	 * @notice Pauses the express withdraw operations
	 */
	function pauseExpressWithdraw() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().expressWithdrawPaused = true;
		emit ExpressWithdrawPaused();
	}

	/**
	 * @notice Pauses the internal transfer operations
	 */
	function pauseInternalTransfer() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().internalTransferPaused = true;
		emit InternalTransferPaused();
	}

	/**
	 * @notice Pauses the external transfer operations
	 */
	function pauseExternalTransfer() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().externalTransferPaused = true;
		emit ExternalTransferPaused();
	}

	/**
	 * @notice Pauses the PartyB actions
	 */
	function pausePartyBActions() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().partyBActionsPaused = true;
		emit PartyBActionsPaused();
	}

	/**
	 * @notice Pauses the PartyA actions
	 */
	function pausePartyAActions() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().partyAActionsPaused = true;
		emit PartyAActionsPaused();
	}

	/**
	 * @notice Pauses the liquidating operations
	 */
	function pauseLiquidating() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().liquidatingPaused = true;
		emit LiquidatingPaused();
	}

	/**
	 * @notice Pauses the third party actions
	 */
	function pauseThirdPartyActions() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().thirdPartyActionsPaused = true;
		emit ThirdPartyActionsPaused();
	}

	/**
	 * @notice Pauses the instant layer
	 */
	function pauseInstantLayer() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().instantLayerPaused = true;
		emit InstantLayerPaused();
	}

	// Unpause functions

	/**
	 * @notice Unpauses the global state
	 */
	function unpauseGlobal() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().globalPaused = false;
		emit GlobalUnpaused();
	}

	/**
	 * @notice Unpauses the deposit operations
	 */
	function unpauseDeposit() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().depositingPaused = false;
		emit DepositUnpaused();
	}

	/**
	 * @notice Unpauses the withdraw operations
	 */
	function unpauseWithdraw() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().withdrawingPaused = false;
		emit WithdrawUnpaused();
	}

	/**
	 * @notice Unpauses the internal transfer operations
	 */
	function unpauseInternalTransfer() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().internalTransferPaused = false;
		emit InternalTransferUnpaused();
	}

	/**
	 * @notice Unpauses the external transfer operations
	 */
	function unpauseExternalTransfer() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().externalTransferPaused = false;
		emit ExternalTransferUnpaused();
	}

	/**
	 * @notice Unpauses the express withdraw operations
	 */
	function unpauseExpressWithdraw() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().expressWithdrawPaused = false;
		emit ExpressWithdrawUnpaused();
	}

	/**
	 * @notice Unpauses the PartyB actions
	 */
	function unpausePartyBActions() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().partyBActionsPaused = false;
		emit PartyBActionsUnpaused();
	}

	/**
	 * @notice Unpauses the PartyA actions
	 */
	function unpausePartyAActions() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().partyAActionsPaused = false;
		emit PartyAActionsUnpaused();
	}

	/**
	 * @notice Unpauses the liquidating operations
	 */
	function unpauseLiquidating() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().liquidatingPaused = false;
		emit LiquidatingUnpaused();
	}

	/**
	 * @notice Unpauses the third party actions
	 */
	function unpauseThirdPartyActions() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().thirdPartyActionsPaused = false;
		emit ThirdPartyActionsUnpaused();
	}

	/**
	 * @notice Unpauses the instant layer
	 */
	function unpauseInstantLayer() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().instantLayerPaused = false;
		emit InstantLayerUnpaused();
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          EMERGENCY CONTROLS
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Activates the PartyB emergency mode
	 */
	function activePartyBsEmergencyMode() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().partyBsEmergencyMode = true;
		emit PartyBsEmergencyModeActivated();
	}

	/**
	 * @notice Deactivates the PartyB emergency mode
	 */
	function deactivePartyBsEmergencyMode() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().partyBsEmergencyMode = false;
		emit PartyBsEmergencyModeDeactivated();
	}

	/**
	 * @notice Activates the PartyB emergency mode
	 * @param _partyB The PartyB address
	 */
	function activePartyBEmergencyMode(address _partyB) external onlyRole(LibAccessibility.PAUSER_ROLE) {
		if (_partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		StateControlStorage.layout().partyBEmergencyMode[_partyB] = true;
		emit PartyBEmergencyModeActivated(_partyB);
	}

	/**
	 * @notice Deactivates the PartyB emergency mode
	 * @param _partyB The PartyB address
	 */
	function deactivePartyBEmergencyMode(address _partyB) external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		if (_partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		StateControlStorage.layout().partyBEmergencyMode[_partyB] = false;
		emit PartyBEmergencyModeDeactivated(_partyB);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          SUSPENSION CONTROLS
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Suspends an address
	 * @param _user The user address
	 * @param _status The suspension status
	 */
	function suspendAddress(address _user, bool _status) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		if (_user == address(0)) revert ValidationErrors.ZeroAddress("user");
		StateControlStorage.layout().suspendedAddresses[_user] = _status;
		emit AddressSuspended(_user, _status);
	}

	/**
	 * @notice Suspends a withdrawal
	 * @param _withdrawId The withdrawal ID
	 * @param _status The suspension status
	 */
	function suspendWithdrawal(uint256 _withdrawId, bool _status) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		if (_withdrawId == 0) revert ValidationErrors.ZeroAmount();
		StateControlStorage.layout().suspendedWithdrawal[_withdrawId] = _status;
		emit WithdrawalSuspended(_withdrawId, _status);
	}

	/**
	 * @notice Suspend/unsuspend multiple addresses
	 * @param users Array of user addresses
	 * @param statuses Array of suspension statuses
	 */
	function suspendAddresses(address[] calldata users, bool[] calldata statuses) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		if (users.length != statuses.length) revert ValidationErrors.MismatchedLengths();

		StateControlStorage.Layout storage layout = StateControlStorage.layout();
		for (uint256 i = 0; i < users.length; i++) {
			if (users[i] == address(0)) revert ValidationErrors.ZeroAddress("user");
			layout.suspendedAddresses[users[i]] = statuses[i];
			emit AddressSuspended(users[i], statuses[i]);
		}
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                                  ORACLE
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Verifies if an oracle exists
	 * @param _oracleId The oracle ID
	 */
	function verifyOracle(uint256 _oracleId) internal view {
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();
		if (symbolLayout.oracles[_oracleId].contractAddress == address(0) || symbolLayout.lastOracleId < _oracleId)
			revert ValidationErrors.OracleNotFound(_oracleId);
	}

	/**
	 * @notice Adds an oracle
	 * @param _name The oracle name
	 * @param _contractAddress The oracle contract address
	 */
	function addOracle(string calldata _name, address _contractAddress) external onlyRole(LibAccessibility.ORACLE_MANAGER_ROLE) {
		if (_contractAddress == address(0)) revert ValidationErrors.ZeroAddress("contractAddress");
		if (bytes(_name).length == 0) revert ValidationErrors.EmptyField("name");

		SymbolStorage.Layout storage s = SymbolStorage.layout();
		s.lastOracleId++;
		s.oracles[s.lastOracleId] = Oracle({ id: s.lastOracleId, name: _name, contractAddress: _contractAddress });
		emit OracleAdded(s.lastOracleId, _name, _contractAddress);
	}

	/**
	 * @notice Updates an existing oracle's contract address
	 * @param _oracleId The oracle ID to update
	 * @param _contractAddress The new contract address
	 */
	function updateOracle(uint256 _oracleId, address _contractAddress) external onlyRole(LibAccessibility.ORACLE_MANAGER_ROLE) {
		if (_contractAddress == address(0)) revert ValidationErrors.ZeroAddress("contractAddress");

		SymbolStorage.Layout storage s = SymbolStorage.layout();
		verifyOracle(_oracleId);

		address oldAddress = s.oracles[_oracleId].contractAddress;
		s.oracles[_oracleId].contractAddress = _contractAddress;
		emit OracleUpdated(_oracleId, oldAddress, _contractAddress);
	}

	/**
	 * @notice Sets the price oracle address
	 * @param _oracle The price oracle address
	 */
	function setPriceOracleAddress(address _oracle) external onlyRole(LibAccessibility.ORACLE_MANAGER_ROLE) {
		if (_oracle == address(0)) revert ValidationErrors.ZeroAddress("oracle");
		AppStorage.layout().priceOracleAddress = _oracle;
		emit PriceOracleAddressUpdated(_oracle);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          SYMBOL MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Adds a symbol
	 * @param _name The symbol name
	 * @param _optionType The option type
	 * @param _oracleId The oracle ID
	 * @param _collateral The collateral address
	 * @param _tradingFee The trading fee
	 * @param _symbolType The symbol type
	 */
	function addSymbol(
		string memory _name,
		OptionType _optionType,
		uint256 _oracleId,
		address _collateral,
		uint256 _tradingFee,
		uint256 _symbolType
	) public onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		if (_collateral == address(0)) revert ValidationErrors.ZeroAddress("collateral");
		if (bytes(_name).length == 0) revert ValidationErrors.EmptyField("name");

		SymbolStorage.Layout storage s = SymbolStorage.layout();
		verifyOracle(_oracleId);

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
		emit SymbolAdded(s.lastSymbolId, _name, _optionType, _oracleId, _collateral, _tradingFee, _symbolType);
	}

	/**
	 * @notice Adds multiple symbols
	 * @param symbols Array of symbols
	 */
	function addSymbols(Symbol[] calldata symbols) external onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		for (uint8 i = 0; i < symbols.length; i++) {
			Symbol memory s = symbols[i];
			addSymbol(s.name, s.optionType, s.oracleId, s.collateral, s.tradingFee, s.symbolType);
		}
	}

	/**
	 * @notice Sets the trading fees for symbols
	 * @param _symbolIds Array of symbol IDs
	 * @param _fees Array of trading fees
	 */
	function setSymbolsTradingFees(uint256[] calldata _symbolIds, uint256[] calldata _fees) external onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		if (_symbolIds.length != _fees.length) revert ValidationErrors.MismatchedLengths();

		SymbolStorage.Layout storage s = SymbolStorage.layout();
		for (uint256 i = 0; i < _symbolIds.length; i++) {
			if (s.lastSymbolId < _symbolIds[i]) revert ValidationErrors.InvalidSymbol(_symbolIds[i]);
			uint256 oldFee = s.symbols[_symbolIds[i]].tradingFee;
			s.symbols[_symbolIds[i]].tradingFee = _fees[i];
			emit SymbolTradingFeeUpdated(_symbolIds[i], oldFee, _fees[i]);
		}
	}

	/**
	 * @notice Sets the validation states for symbols
	 * @param _symbolIds Array of symbol IDs
	 * @param _states Array of validation states
	 */
	function setSymbolsValidationState(
		uint256[] calldata _symbolIds,
		bool[] calldata _states
	) external onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		if (_symbolIds.length != _states.length) revert ValidationErrors.MismatchedLengths();

		SymbolStorage.Layout storage s = SymbolStorage.layout();
		for (uint256 i = 0; i < _symbolIds.length; i++) {
			if (s.lastSymbolId < _symbolIds[i]) revert ValidationErrors.InvalidSymbol(_symbolIds[i]);
			s.symbols[_symbolIds[i]].isValid = _states[i];
			emit SymbolStateUpdated(_symbolIds[i], _states[i]);
		}
	}

	/**
	 * @notice Sets the names for symbols
	 * @param _symbolIds Array of symbol IDs
	 * @param _names Array of new names
	 */
	function setSymbolsNames(uint256[] calldata _symbolIds, string[] calldata _names) external onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		if (_symbolIds.length != _names.length) revert ValidationErrors.MismatchedLengths();

		SymbolStorage.Layout storage s = SymbolStorage.layout();
		for (uint256 i = 0; i < _symbolIds.length; i++) {
			if (s.lastSymbolId < _symbolIds[i]) revert ValidationErrors.InvalidSymbol(_symbolIds[i]);
			if (bytes(_names[i]).length == 0) revert ValidationErrors.EmptyField("name");
			s.symbols[_symbolIds[i]].name = _names[i];
			emit SymbolNameUpdated(_symbolIds[i], _names[i]);
		}
	}

	/**
	 * @notice Sets the types for symbols
	 * @param _symbolIds Array of symbol IDs
	 * @param _types Array of types
	 */
	function setSymbolsTypes(uint256[] calldata _symbolIds, uint256[] calldata _types) external onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		if (_symbolIds.length != _types.length) revert ValidationErrors.MismatchedLengths();

		SymbolStorage.Layout storage s = SymbolStorage.layout();
		for (uint256 i = 0; i < _symbolIds.length; i++) {
			if (s.lastSymbolId < _symbolIds[i]) revert ValidationErrors.InvalidSymbol(_symbolIds[i]);
			s.symbols[_symbolIds[i]].symbolType = _types[i];
			emit SymbolTypeUpdated(_symbolIds[i], _types[i]);
		}
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          SIGNATURE MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Sets the signature verifier
	 * @param _verifier The signature verifier address
	 */
	function setSignatureVerifier(address _verifier) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_verifier == address(0)) revert ValidationErrors.ZeroAddress("verifier");
		AppStorage.layout().signatureVerifier = _verifier;
		emit SignatureVerifierUpdated(_verifier);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          WITHDRAW MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Sets the express withdraw provider config
	 * @param _provider The express withdraw provider address
	 * @param _collateral The collateral address of this provider config
	 * @param _config The express withdraw provider config
	 */
	function setExpressWithdrawProviderConfig(
		address _provider,
		address _collateral,
		ExpressWithdrawProviderConfig memory _config
	) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_provider == address(0)) revert ValidationErrors.ZeroAddress("provider");
		AccountStorage.layout().expressWithdrawProviderConfigs[_provider][_collateral] = _config;
		emit ExpressWithdrawProviderConfigUpdated(_provider, _config);
	}

	/**
	 * @notice Sets the invalid withdrawals amounts pool
	 * @param _pool The invalid withdrawals amounts pool address
	 */
	function setInvalidWithdrawalsAmountsPool(address _pool) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_pool == address(0)) revert ValidationErrors.ZeroAddress("pool");
		AccountStorage.layout().invalidWithdrawalsAmountsPool = _pool;
		emit InvalidWithdrawalsAmountsPoolUpdated(_pool);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          EXTERNAL TRANSFER TARGETS
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Sets the validation status for an external transfer target
	 * @param _target The target address
	 * @param _collateral The collateral address
	 * @param _status The validation status
	 */
	function setExternalTransferTargetValidationStatus(
		address _target,
		address _collateral,
		bool _status
	) external onlyRole(LibAccessibility.EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE) {
		if (_target == address(0)) revert ValidationErrors.ZeroAddress("target");
		if (_collateral == address(0)) revert ValidationErrors.ZeroAddress("collateral");

		AccountStorage.layout().externalTransferTargets[_target][_collateral] = _status;
		emit ExternalTransferTargetValidationStatusUpdated(_target, _collateral, _status);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          INSTANT LAYER MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Sets the call from instant layer
	 * @param _callFromInstantLayer The call from instant layer
	 */
	function setCallFromInstantLayer(bool _callFromInstantLayer) external onlyRole(LibAccessibility.INSTANT_LAYER_ROLE) {
		if (_callFromInstantLayer && StateControlStorage.layout().instantLayerPaused) revert SystemErrors.InstantLayerPaused();
		AppStorage.layout().callFromInstantLayer = _callFromInstantLayer;
	}
}
