// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../libraries/models/LibParty.sol";

import { StateControlStorage } from "../storages/StateControlStorage.sol";

abstract contract Pausable {
	using LibParty for address;

	// Custom errors
	error GlobalPaused();
	error BridgePaused();
	error BridgeWithdrawPaused();
	error DepositingPaused();
	error InternalTransferPaused();
	error WithdrawingPaused();
	error PartyAActionsPaused();
	error PartyBActionsPaused();
	error ThirdPartyActionsPaused();
	error LiquidatingPaused();
	error EmergencyMode();

	modifier whenNotGlobalPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		_;
	}

	modifier whenNotBridgePaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert GlobalPaused();
		if (layout.bridgePaused) revert BridgePaused();
		_;
	}

	modifier whenNotBridgeWithdrawPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert GlobalPaused();
		if (layout.bridgeWithdrawPaused) revert BridgeWithdrawPaused();
		_;
	}

	modifier whenDepositingNotPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert GlobalPaused();
		if (layout.depositingPaused) revert DepositingPaused();
		_;
	}

	modifier whenNotInternalTransferPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert GlobalPaused();
		if (layout.internalTransferPaused) revert InternalTransferPaused();
		_;
	}

	modifier whenNotWithdrawingPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert GlobalPaused();
		if (layout.withdrawingPaused) revert WithdrawingPaused();
		_;
	}

	modifier whenPartyNotPaused(address user) {
		if (user.isPartyB()) {
			_whenNotPartyBActionsPaused();
		} else {
			_whenNotPartyAActionsPaused();
		}
		_;
	}

	function _whenNotPartyAActionsPaused() internal view {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert GlobalPaused();
		if (layout.partyAActionsPaused) revert PartyAActionsPaused();
	}

	function _whenNotPartyBActionsPaused() internal view {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert GlobalPaused();
		if (layout.partyBActionsPaused) revert PartyBActionsPaused();
		if (layout.emergencyMode) revert EmergencyMode();
	}

	modifier whenNotThirdPartyActionsPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert GlobalPaused();
		if (layout.thirdPartyActionsPaused) revert ThirdPartyActionsPaused();
		_;
	}

	modifier whenNotLiquidationPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert GlobalPaused();
		if (layout.liquidatingPaused) revert LiquidatingPaused();
		_;
	}
}
