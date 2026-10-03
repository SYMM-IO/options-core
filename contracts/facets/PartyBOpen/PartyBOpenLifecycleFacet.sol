// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { OpenIntentStatus } from "../../types/IntentTypes.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IPartyBOpenEvents } from "./IPartyBOpenEvents.sol";
import { LibPartyBOpen } from "../../libraries/core/LibPartyBOpen.sol";

/**
 * @title PartyBOpenFacet
 * @notice Manages PartyB's interactions with open intents submitted by PartyA users
 * @dev Implements the IPartyBOpenEvents interface with access control and pausability mechanisms
 */
contract PartyBOpenLifecycleFacet is Accessibility, Pausable, IPartyBOpenEvents {
	function lockOpenIntent(uint256 intentId) external whenPartyNotPaused(msg.sender) onlyPartyB(msg.sender) {
		LibPartyBOpen.lockOpenIntent(msg.sender, intentId);
		emit LockOpenIntent(intentId, msg.sender);
	}

	function unlockOpenIntent(uint256 intentId) external whenPartyNotPaused(msg.sender) {
		OpenIntentStatus finalStatus = LibPartyBOpen.unlockOpenIntent(msg.sender, intentId);
		if (finalStatus == OpenIntentStatus.EXPIRED) {
			emit ExpireOpenIntent(intentId);
		} else if (finalStatus == OpenIntentStatus.PENDING) {
			emit UnlockOpenIntent(intentId, msg.sender);
		}
	}

	function acceptCancelOpenIntent(uint256 intentId) external whenPartyNotPaused(msg.sender) {
		LibPartyBOpen.acceptCancelOpenIntent(msg.sender, intentId);
		emit AcceptCancelOpenIntent(intentId);
	}
}
