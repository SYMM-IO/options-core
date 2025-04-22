// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { StateControlStorage } from "../storages/StateControlStorage.sol";

abstract contract Pausable {
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

	modifier whenNotGlobalPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		_;
	}

	modifier whenNotBridgePaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		if (StateControlStorage.layout().bridgePaused) revert BridgePaused();
		_;
	}

	modifier whenNotBridgeWithdrawPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		if (StateControlStorage.layout().bridgeWithdrawPaused) revert BridgeWithdrawPaused();
		_;
	}

	modifier whenNotDepositingPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		if (StateControlStorage.layout().depositingPaused) revert DepositingPaused();
		_;
	}

	modifier whenNotInternalTransferPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		if (StateControlStorage.layout().internalTransferPaused) revert InternalTransferPaused();
		_;
	}

	modifier whenNotWithdrawingPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		if (StateControlStorage.layout().withdrawingPaused) revert WithdrawingPaused();
		_;
	}

	modifier whenNotPartyAActionsPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		if (StateControlStorage.layout().partyAActionsPaused) revert PartyAActionsPaused();
		_;
	}

	modifier whenNotPartyBActionsPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		if (StateControlStorage.layout().partyBActionsPaused) revert PartyBActionsPaused();
		_;
	}

	modifier whenNotThirdPartyActionsPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		if (StateControlStorage.layout().thirdPartyActionsPaused) revert ThirdPartyActionsPaused();
		_;
	}

	modifier whenNotLiquidationPaused() {
		if (StateControlStorage.layout().globalPaused) revert GlobalPaused();
		if (StateControlStorage.layout().liquidatingPaused) revert LiquidatingPaused();
		_;
	}
}
