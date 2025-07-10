// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library StateControlStorage {
	bytes32 internal constant STATE_CONTROL_STORAGE_SLOT = keccak256("diamond.standard.storage.stateControl");

	struct Layout {
		bool globalPaused;
		bool depositingPaused;
		bool withdrawingPaused;
		bool partyBActionsPaused;
		bool partyAActionsPaused;
		bool liquidatingPaused;
		bool thirdPartyActionsPaused;
		bool internalTransferPaused;
		bool externalTransferPaused;
		bool expressWithdrawPaused;
		bool instantLayerPaused;
		///////////////////////////////////
		bool partyBsEmergencyMode;
		mapping(address => bool) partyBEmergencyMode;
		///////////////////////////////////
		mapping(address => bool) suspendedAddresses;
		mapping(uint256 => bool) suspendedWithdrawal;
	}

	function layout() internal pure returns (Layout storage l) {
		bytes32 slot = STATE_CONTROL_STORAGE_SLOT;
		assembly {
			l.slot := slot
		}
	}
}
