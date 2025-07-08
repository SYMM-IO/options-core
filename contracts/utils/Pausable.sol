// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../libraries/models/LibParty.sol";

import { StateControlStorage } from "../storages/StateControlStorage.sol";

import { SystemErrors } from "../errors/SystemErrors.sol";

abstract contract Pausable {
	using LibParty for address;

	modifier whenNotGlobalPaused() {
		if (StateControlStorage.layout().globalPaused) revert SystemErrors.GlobalPaused();
		_;
	}

	modifier whenNotExpressWithdrawPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert SystemErrors.GlobalPaused();
		if (layout.expressWithdrawPaused) revert SystemErrors.ExpressWithdrawPaused();
		_;
	}

	modifier whenDepositingNotPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert SystemErrors.GlobalPaused();
		if (layout.depositingPaused) revert SystemErrors.DepositingPaused();
		_;
	}

	modifier whenInternalTransferNotPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert SystemErrors.GlobalPaused();
		if (layout.internalTransferPaused) revert SystemErrors.InternalTransferPaused();
		_;
	}

	modifier whenNotExternalTransferPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert SystemErrors.GlobalPaused();
		if (layout.externalTransferPaused) revert SystemErrors.ExternalTransferPaused();
		_;
	}

	modifier whenWithdrawingNotPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert SystemErrors.GlobalPaused();
		if (layout.withdrawingPaused) revert SystemErrors.WithdrawingPaused();
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

		if (layout.globalPaused) revert SystemErrors.GlobalPaused();
		if (layout.partyAActionsPaused) revert SystemErrors.PartyAActionsPaused();
	}

	function _whenNotPartyBActionsPaused() internal view {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert SystemErrors.GlobalPaused();
		if (layout.partyBActionsPaused) revert SystemErrors.PartyBActionsPaused();
	}

	modifier whenNotThirdPartyActionsPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert SystemErrors.GlobalPaused();
		if (layout.thirdPartyActionsPaused) revert SystemErrors.ThirdPartyActionsPaused();
		_;
	}

	modifier whenNotLiquidationPaused() {
		StateControlStorage.Layout storage layout = StateControlStorage.layout();

		if (layout.globalPaused) revert SystemErrors.GlobalPaused();
		if (layout.liquidatingPaused) revert SystemErrors.LiquidatingPaused();
		_;
	}
}
