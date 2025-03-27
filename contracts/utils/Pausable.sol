// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AppStorage } from "../storages/AppStorage.sol";

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
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		_;
	}

	modifier whenNotBridgePaused() {
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		if (AppStorage.layout().bridgePaused) revert BridgePaused();
		_;
	}

	modifier whenNotBridgeWithdrawPaused() {
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		if (AppStorage.layout().bridgeWithdrawPaused) revert BridgeWithdrawPaused();
		_;
	}

	modifier whenNotDepositingPaused() {
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		if (AppStorage.layout().depositingPaused) revert DepositingPaused();
		_;
	}

	modifier whenNotInternalTransferPaused() {
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		if (AppStorage.layout().internalTransferPaused) revert InternalTransferPaused();
		_;
	}

	modifier whenNotWithdrawingPaused() {
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		if (AppStorage.layout().withdrawingPaused) revert WithdrawingPaused();
		_;
	}

	modifier whenNotPartyAActionsPaused() {
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		if (AppStorage.layout().partyAActionsPaused) revert PartyAActionsPaused();
		_;
	}

	modifier whenNotPartyBActionsPaused() {
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		if (AppStorage.layout().partyBActionsPaused) revert PartyBActionsPaused();
		_;
	}

	modifier whenNotThirdPartyActionsPaused() {
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		if (AppStorage.layout().thirdPartyActionsPaused) revert ThirdPartyActionsPaused();
		_;
	}

	modifier whenNotLiquidationPaused() {
		if (AppStorage.layout().globalPaused) revert GlobalPaused();
		if (AppStorage.layout().liquidatingPaused) revert LiquidatingPaused();
		_;
	}
}
