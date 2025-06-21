// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../libraries/models/LibParty.sol";

import { StateControlStorage } from "../storages/StateControlStorage.sol";

import { PausableErrors } from "../errors/PausableErrors.sol";

abstract contract Pausable {
	using LibParty for address;

	modifier whenNotGlobalPaused() {
		if (StateControlStorage.layout().globalPaused) revert PausableErrors.GlobalPaused();
		_;
	}

	modifier whenNotBridgePaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert PausableErrors.GlobalPaused();
		if (layout.bridgePaused) revert PausableErrors.BridgePaused();
		_;
	}

	modifier whenNotBridgeWithdrawPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert PausableErrors.GlobalPaused();
		if (layout.bridgeWithdrawPaused) revert PausableErrors.BridgeWithdrawPaused();
		_;
	}

	modifier whenDepositingNotPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert PausableErrors.GlobalPaused();
		if (layout.depositingPaused) revert PausableErrors.DepositingPaused();
		_;
	}

	modifier whenNotInternalTransferPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert PausableErrors.GlobalPaused();
		if (layout.internalTransferPaused) revert PausableErrors.InternalTransferPaused();
		_;
	}

	modifier whenNotWithdrawingPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert PausableErrors.GlobalPaused();
		if (layout.withdrawingPaused) revert PausableErrors.WithdrawingPaused();
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

		if (layout.globalPaused) revert PausableErrors.GlobalPaused();
		if (layout.partyAActionsPaused) revert PausableErrors.PartyAActionsPaused();
	}

	function _whenNotPartyBActionsPaused() internal view {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert PausableErrors.GlobalPaused();
		if (layout.partyBActionsPaused) revert PausableErrors.PartyBActionsPaused();
		if (layout.emergencyMode) revert PausableErrors.EmergencyMode();
	}

	modifier whenNotThirdPartyActionsPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert PausableErrors.GlobalPaused();
		if (layout.thirdPartyActionsPaused) revert PausableErrors.ThirdPartyActionsPaused();
		_;
	}

	modifier whenNotLiquidationPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert PausableErrors.GlobalPaused();
		if (layout.liquidatingPaused) revert PausableErrors.LiquidatingPaused();
		_;
	}
}
