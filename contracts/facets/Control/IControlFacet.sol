// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
pragma solidity >=0.8.19;

import { Symbol } from "../../types/SymbolTypes.sol";

import { PartyBConfig } from "../../storages/AppStorage.sol";
import { OptionType } from "../../types/SymbolTypes.sol";
import { IControlEvents } from "./IControlEvents.sol";

// Structs for view functions
struct SystemConfig {
	uint256 maxCloseOrdersLength;
	uint256 maxTradePerPartyA;
	uint256 partyADeallocateCooldown;
	uint256 partyBDeallocateCooldown;
	uint256 forceCancelOpenIntentTimeout;
	uint256 forceCancelCloseIntentTimeout;
	uint256 partyBExclusiveWindow;
	uint256 settlementPriceSigValidTime;
	address priceOracleAddress;
	address signatureVerifier;
	address tradeNftAddress;
}

struct PauseStates {
	bool globalPaused;
	bool depositingPaused;
	bool withdrawingPaused;
	bool internalTransferPaused;
	bool bridgePaused;
	bool bridgeWithdrawPaused;
	bool partyBActionsPaused;
	bool partyAActionsPaused;
	bool liquidatingPaused;
	bool thirdPartyActionsPaused;
	bool emergencyMode;
}

interface IControlFacet is IControlEvents {
	// Access Control
	function setAdmin(address _admin) external;
	function grantRole(address _user, bytes32 _role) external;
	function revokeRole(address _user, bytes32 _role) external;

	// Collateral Management
	function whiteListCollateral(address _collateral) external;
	function removeCollateralFromWhitelist(address _collateral) external;

	// System Parameters
	function setMaxCloseOrdersLength(uint256 _max) external;
	function setMaxTradePerPartyA(uint256 _max) external;
	function setBalanceLimitPerUser(address collateral, uint256 _limit) external;
	function setTimingParameters(
		uint256 _partyADeallocateCooldown,
		uint256 _partyBDeallocateCooldown,
		uint256 _forceCancelOpenTimeout,
		uint256 _forceCancelCloseTimeout,
		uint256 _settlementPriceSigValidTime,
		uint256 _partyBExclusiveWindow,
		uint256 _unbindingCooldown,
		uint256 _deactiveInstantActionModeCooldown
	) external;

	// Individual timing setters
	function setPartyADeallocateCooldown(uint256 _cooldown) external;
	function setPartyBDeallocateCooldown(uint256 _cooldown) external;
	function setForceCancelOpenIntentTimeout(uint256 _timeout) external;
	function setForceCancelCloseIntentTimeout(uint256 _timeout) external;
	function setSettlementPriceSigValidTime(uint256 _time) external;
	function setPartyBExclusiveWindow(uint256 _window) external;
	function setUnbindingCooldown(uint256 _cooldown) external;
	function setDeactiveInstantActionModeCooldown(uint256 _cooldown) external;
	
	// Release Interval Management
	function setPartyBReleaseInterval(address _partyB, uint256 _interval) external;
	function setDefaultReleaseInterval(uint256 _interval) external;
	function setMaxConnectedCounterParties(uint256 _max) external;

	// Fee Management
	function setDefaultFeeCollector(address _collector) external;
	function setAffiliateStatus(address _affiliate, bool _status) external;
	function setAffiliateFeesCollector(address _affiliate, address _collector) external;
	function setAffiliateFees(address _affiliate, uint256 _symbolId, uint256 fee) external;
	function batchSetAffiliateFees(address _affiliate, uint256[] calldata _symbolIds, uint256[] calldata _fees) external;

	// Party B Configuration
	function setPartyBConfig(address _partyB, PartyBConfig calldata _config) external;

	// Pause Management
	function pauseGlobal() external;
	function pauseDeposit() external;
	function pauseWithdraw() external;
	function pauseInternalTransfer() external;
	function pauseBridge() external;
	function pauseBridgeWithdraw() external;
	function pausePartyBActions() external;
	function pausePartyAActions() external;
	function pauseLiquidating() external;
	function pauseThirdPartyActions() external;

	// Unpause Management
	function unpauseGlobal() external;
	function unpauseDeposit() external;
	function unpauseWithdraw() external;
	function unpauseInternalTransfer() external;
	function unpauseBridge() external;
	function unpauseBridgeWithdraw() external;
	function unpausePartyBActions() external;
	function unpausePartyAActions() external;
	function unpauseLiquidating() external;
	function unpauseThirdPartyActions() external;

	// Emergency Controls
	function activeEmergencyMode() external;
	function deactiveEmergencyMode() external;
	function activePartyBEmergencyMode(address _partyB) external;
	function deactivePartyBEmergencyMode(address _partyB) external;

	// Suspension Controls
	function suspendAddress(address _user, bool _status) external;
	function suspendWithdrawal(uint256 _withdrawId, bool _status) external;
	function batchSuspendAddresses(address[] calldata users, bool[] calldata statuses) external;

	// Oracle & Symbol Management
	function addOracle(string calldata _name, address _contractAddress) external;
	function updateOracle(uint256 _oracleId, address _contractAddress) external;
	function addSymbol(
		string calldata _name,
		OptionType _optionType,
		uint256 _oracleId,
		address _collateral,
		uint256 _tradingFee,
		uint256 _symbolType
	) external;
	function addSymbols(Symbol[] memory symbols) external;
	function setSymbolTradingFee(uint256 _symbolId, uint256 _fee) external;
	function setSymbolValidationState(uint256 _symbolId, bool _state) external;
	function batchSetSymbolValidationState(uint256[] calldata symbolIds, bool[] calldata statuses) external;

	// Oracle & Signature Management
	function setPriceOracleAddress(address _oracle) external;
	function setSignatureVerifier(address _verifier) external;

	// Bridge Management
	function setBridgeValidationState(address _bridgeAddress, bool _state) external;
	function setInvalidBridgedAmountsPool(address _pool) external;

	// Instant Layer
	function setCallFromInstantLayer(bool _callFromInstantLayer) external;
}
