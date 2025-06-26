// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../../libraries/core/LibAccessibility.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/models/LibScheduledReleaseBalance.sol";

import { SymbolStorage } from "../../storages/SymbolStorage.sol";
import { AppStorage, PartyBConfig } from "../../storages/AppStorage.sol";
import { StateControlStorage } from "../../storages/StateControlStorage.sol";
import { AccessControlStorage } from "../../storages/AccessControlStorage.sol";
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";
import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";
import { BridgeStorage } from "../../storages/BridgeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";

import { Symbol, Oracle, OptionType } from "../../types/SymbolTypes.sol";
import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";

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
		appLayout.partyBExclusiveWindow = _partyBExclusiveWindow;

		counterPartyRelationsLayout.unbindingCooldown = _unbindingCooldown;
		counterPartyRelationsLayout.deactiveInstantActionModeCooldown = _deactiveInstantActionModeCooldown;

		emit PartyADeallocateCooldownUpdated(_partyADeallocateCooldown);
		emit PartyBDeallocateCooldownUpdated(_partyBDeallocateCooldown);
		emit ForceCancelOpenIntentTimeoutUpdated(_forceCancelOpenTimeout);
		emit ForceCancelCloseIntentTimeoutUpdated(_forceCancelCloseTimeout);
		emit SettlementPriceSigValidTimeUpdated(_settlementPriceSigValidTime);
		emit PartyBExclusiveWindowUpdated(_partyBExclusiveWindow);
		emit UnbindingCooldownUpdated(_unbindingCooldown);
		emit DeactiveInstantActionModeCooldownUpdated(_deactiveInstantActionModeCooldown);
	}

	// Individual setters remain for flexibility
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

	function setSettlementPriceSigValidTime(uint256 _time) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().settlementPriceSigValidTime = _time;
		emit SettlementPriceSigValidTimeUpdated(_time);
	}

	function setPartyBExclusiveWindow(uint256 _window) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AppStorage.layout().partyBExclusiveWindow = _window;
		emit PartyBExclusiveWindowUpdated(_window);
	}

	function setUnbindingCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		CounterPartyRelationsStorage.layout().unbindingCooldown = _cooldown;
		emit UnbindingCooldownUpdated(_cooldown);
	}

	function setDeactiveInstantActionModeCooldown(uint256 _cooldown) external onlyRole(LibAccessibility.SETTER_ROLE) {
		CounterPartyRelationsStorage.layout().deactiveInstantActionModeCooldown = _cooldown;
		emit DeactiveInstantActionModeCooldownUpdated(_cooldown);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          RELEASE INTERVAL MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	function setPartyBReleaseInterval(address _partyB, uint256 _interval) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		AccountStorage.layout().hasConfiguredInterval[_partyB] = true;
		AccountStorage.layout().releaseIntervals[_partyB] = _interval;
		emit PartyBReleaseIntervalUpdated(_partyB, _interval);
	}

	function setDefaultReleaseInterval(uint256 _interval) external onlyRole(LibAccessibility.SETTER_ROLE) {
		AccountStorage.layout().defaultReleaseInterval = _interval;
		emit DefaultReleaseIntervalUpdated(_interval);
	}

	function setMaxConnectedCounterParties(uint256 _max) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_max == 0) revert ValidationErrors.ZeroAmount();
		AccountStorage.layout().maxConnectedCounterParties = _max;
		emit MaxConnectedCounterPartiesUpdated(_max);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          FEE MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	function setDefaultFeeCollector(address _collector) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_collector == address(0)) revert ValidationErrors.ZeroAddress("collector");
		FeeManagementStorage.layout().defaultFeeCollector = _collector;
		emit DefaultFeeCollectorUpdated(_collector);
	}

	function setAffiliateStatus(address _affiliate, bool _status) external onlyRole(LibAccessibility.AFFILIATE_MANAGER_ROLE) {
		FeeManagementStorage.layout().affiliateStatus[_affiliate] = _status;
		emit AffiliateStatusUpdated(_affiliate, _status);
	}

	function setAffiliateFeesCollector(address _affiliate, address _collector) external onlyRole(LibAccessibility.AFFILIATE_MANAGER_ROLE) {
		if (_collector == address(0)) revert ValidationErrors.ZeroAddress("collector");
		FeeManagementStorage.layout().affiliateFeeCollector[_affiliate] = _collector;
		emit AffiliateFeesCollectorUpdated(_affiliate, _collector);
	}

	function setAffiliateFees(address _affiliate, uint256 _symbolId, uint256 fee) external {
		if (_affiliate == address(0)) revert ValidationErrors.ZeroAddress("affiliate");
		if (_affiliate != msg.sender && !LibAccessibility.hasRole(msg.sender, LibAccessibility.AFFILIATE_FEE_MANAGER_ROLE))
			revert ValidationErrors.UnauthorizedSender(msg.sender, _affiliate);

		FeeManagementStorage.layout().affiliateFees[_affiliate][_symbolId] = fee;
		emit AffiliateFeesUpdated(_affiliate, _symbolId, fee);
	}

	/**
	 * @notice Batch updates affiliate fees for multiple symbols
	 * @param _affiliate The affiliate address
	 * @param _symbolIds Array of symbol IDs
	 * @param _fees Array of fee amounts
	 */
	function batchSetAffiliateFees(
		address _affiliate,
		uint256[] calldata _symbolIds,
		uint256[] calldata _fees
	) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_affiliate == address(0)) revert ValidationErrors.ZeroAddress("affiliate");
		if (_affiliate != msg.sender && !LibAccessibility.hasRole(msg.sender, LibAccessibility.AFFILIATE_FEE_MANAGER_ROLE))
			revert ValidationErrors.UnauthorizedSender(msg.sender, _affiliate);
		if (_symbolIds.length != _fees.length) revert ValidationErrors.EmptyList();

		FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();
		for (uint256 i = 0; i < _symbolIds.length; i++) {
			feeLayout.affiliateFees[_affiliate][_symbolIds[i]] = _fees[i];
			emit AffiliateFeesUpdated(_affiliate, _symbolIds[i], _fees[i]);
		}
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          PARTY B CONFIGURATION
	// ═══════════════════════════════════════════════════════════════════════════

	function setPartyBConfig(address _partyB, PartyBConfig calldata _config) external onlyRole(LibAccessibility.PARTY_B_MANAGER_ROLE) {
		if (_partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		if (_config.isActive && _config.oracleId == 0) revert ValidationErrors.OracleNotFound(_config.oracleId);

		AppStorage.layout().partyBConfigs[_partyB] = _config;
		AccountStorage.layout().manualSync[_partyB] = true;
		emit PartyBConfigUpdated(_partyB, _config);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          PAUSE MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	// Pause functions
	function pauseGlobal() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().globalPaused = true;
		emit GlobalPaused();
	}

	function pauseDeposit() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().depositingPaused = true;
		emit DepositPaused();
	}

	function pauseWithdraw() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().withdrawingPaused = true;
		emit WithdrawPaused();
	}

	function pauseInternalTransfer() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().internalTransferPaused = true;
		emit InternalTransferPaused();
	}

	function pauseBridge() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().bridgePaused = true;
		emit BridgePaused();
	}

	function pauseBridgeWithdraw() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().bridgeWithdrawPaused = true;
		emit BridgeWithdrawPaused();
	}

	function pausePartyBActions() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().partyBActionsPaused = true;
		emit PartyBActionsPaused();
	}

	function pausePartyAActions() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().partyAActionsPaused = true;
		emit PartyAActionsPaused();
	}

	function pauseLiquidating() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().liquidatingPaused = true;
		emit LiquidatingPaused();
	}

	function pauseThirdPartyActions() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().thirdPartyActionsPaused = true;
		emit ThirdPartyActionsPaused();
	}

	// Unpause functions
	function unpauseGlobal() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().globalPaused = false;
		emit GlobalUnpaused();
	}

	function unpauseDeposit() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().depositingPaused = false;
		emit DepositUnpaused();
	}

	function unpauseWithdraw() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().withdrawingPaused = false;
		emit WithdrawUnpaused();
	}

	function unpauseInternalTransfer() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().internalTransferPaused = false;
		emit InternalTransferUnpaused();
	}

	function unpauseBridge() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().bridgePaused = false;
		emit BridgeUnpaused();
	}

	function unpauseBridgeWithdraw() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().bridgeWithdrawPaused = false;
		emit BridgeWithdrawUnpaused();
	}

	function unpausePartyBActions() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().partyBActionsPaused = false;
		emit PartyBActionsUnpaused();
	}

	function unpausePartyAActions() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().partyAActionsPaused = false;
		emit PartyAActionsUnpaused();
	}

	function unpauseLiquidating() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().liquidatingPaused = false;
		emit LiquidatingUnpaused();
	}

	function unpauseThirdPartyActions() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().thirdPartyActionsPaused = false;
		emit ThirdPartyActionsUnpaused();
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          EMERGENCY CONTROLS
	// ═══════════════════════════════════════════════════════════════════════════

	function activeEmergencyMode() external onlyRole(LibAccessibility.PAUSER_ROLE) {
		StateControlStorage.layout().emergencyMode = true;
		emit EmergencyModeActivated();
	}

	function deactiveEmergencyMode() external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		StateControlStorage.layout().emergencyMode = false;
		emit EmergencyModeDeactivated();
	}

	function activePartyBEmergencyMode(address _partyB) external onlyRole(LibAccessibility.PAUSER_ROLE) {
		if (_partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		StateControlStorage.layout().partyBEmergencyMode[_partyB] = true;
		emit PartyBEmergencyModeActivated(_partyB);
	}

	function deactivePartyBEmergencyMode(address _partyB) external onlyRole(LibAccessibility.UNPAUSER_ROLE) {
		if (_partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		StateControlStorage.layout().partyBEmergencyMode[_partyB] = false;
		emit PartyBEmergencyModeDeactivated(_partyB);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          SUSPENSION CONTROLS
	// ═══════════════════════════════════════════════════════════════════════════

	function suspendAddress(address _user, bool _status) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		if (_user == address(0)) revert ValidationErrors.ZeroAddress("user");
		StateControlStorage.layout().suspendedAddresses[_user] = _status;
		emit AddressSuspended(_user, _status);
	}

	function suspendWithdrawal(uint256 _withdrawId, bool _status) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		if (_withdrawId == 0) revert ValidationErrors.ZeroAmount();
		StateControlStorage.layout().suspendedWithdrawal[_withdrawId] = _status;
		emit WithdrawalSuspended(_withdrawId, _status);
	}

	/**
	 * @notice Batch suspend/unsuspend multiple addresses
	 * @param users Array of user addresses
	 * @param statuses Array of suspension statuses
	 */
	function batchSuspendAddresses(address[] calldata users, bool[] calldata statuses) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		if (users.length != statuses.length) revert ValidationErrors.EmptyList();

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
		if (_oracleId == 0 || _oracleId > s.lastOracleId) revert ValidationErrors.OracleNotFound(_oracleId);

		address oldAddress = s.oracles[_oracleId].contractAddress;
		s.oracles[_oracleId].contractAddress = _contractAddress;
		emit OracleUpdated(_oracleId, oldAddress, _contractAddress);
	}

	function setPriceOracleAddress(address _oracle) external onlyRole(LibAccessibility.ORACLE_MANAGER_ROLE) {
		if (_oracle == address(0)) revert ValidationErrors.ZeroAddress("oracle");
		AppStorage.layout().priceOracleAddress = _oracle;
		emit PriceOracleAddressUpdated(_oracle);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          SYMBOL MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

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
		if (s.oracles[_oracleId].contractAddress == address(0) || s.lastOracleId < _oracleId) revert ValidationErrors.OracleNotFound(_oracleId);

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

	function addSymbols(Symbol[] memory symbols) external onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		for (uint8 i = 0; i < symbols.length; i++) {
			Symbol memory s = symbols[i];
			addSymbol(s.name, s.optionType, s.oracleId, s.collateral, s.tradingFee, s.symbolType);
		}
	}

	function setSymbolTradingFee(uint256 _symbolId, uint256 _fee) external onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		SymbolStorage.Layout storage s = SymbolStorage.layout();
		if (s.lastSymbolId < _symbolId) revert ValidationErrors.InvalidSymbol(_symbolId);

		s.symbols[_symbolId].tradingFee = _fee;
		emit SymbolTradingFeeUpdated(_symbolId, s.symbols[_symbolId].tradingFee, _fee);
	}

	function setSymbolValidationState(uint256 _symbolId, bool _state) external onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		SymbolStorage.Layout storage s = SymbolStorage.layout();
		if (s.lastSymbolId < _symbolId) revert ValidationErrors.InvalidSymbol(_symbolId);

		s.symbols[_symbolId].isValid = _state;
		emit SymbolStateUpdated(_symbolId, _state);
	}

	/**
	 * @notice Batch updates symbol states
	 * @param symbolIds Array of symbol IDs
	 * @param states Array of validity states
	 */
	function batchSetSymbolValidationState(
		uint256[] calldata symbolIds,
		bool[] calldata states
	) external onlyRole(LibAccessibility.SYMBOL_MANAGER_ROLE) {
		if (symbolIds.length != states.length) revert ValidationErrors.EmptyList();

		SymbolStorage.Layout storage s = SymbolStorage.layout();
		for (uint256 i = 0; i < symbolIds.length; i++) {
			if (s.lastSymbolId < symbolIds[i]) revert ValidationErrors.InvalidSymbol(symbolIds[i]);
			s.symbols[symbolIds[i]].isValid = states[i];
			emit SymbolStateUpdated(symbolIds[i], states[i]);
		}
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          SIGNATURE MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	function setSignatureVerifier(address _verifier) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_verifier == address(0)) revert ValidationErrors.ZeroAddress("verifier");
		AppStorage.layout().signatureVerifier = _verifier;
		emit SignatureVerifierUpdated(_verifier);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          BRIDGE MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	function setBridgeValidationState(address _bridgeAddress, bool _state) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_bridgeAddress == address(0)) revert ValidationErrors.ZeroAddress("bridgeAddress");
		BridgeStorage.Layout storage s = BridgeStorage.layout();

		s.bridges[_bridgeAddress] = _state;
		emit SetBridgeValidationState(_bridgeAddress, _state);
	}

	function setInvalidBridgedAmountsPool(address _pool) external onlyRole(LibAccessibility.SETTER_ROLE) {
		if (_pool == address(0)) revert ValidationErrors.ZeroAddress("pool");
		BridgeStorage.Layout storage s = BridgeStorage.layout();

		s.invalidBridgedAmountsPool = _pool;
		emit SetInvalidBridgedAmountsPool(_pool);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//                          INSTANT LAYER MANAGEMENT
	// ═══════════════════════════════════════════════════════════════════════════

	function setCallFromInstantLayer(bool _callFromInstantLayer) external onlyRole(LibAccessibility.INSTANT_LAYER_ROLE) {
		AppStorage.layout().callFromInstantLayer = _callFromInstantLayer;
	}
}
