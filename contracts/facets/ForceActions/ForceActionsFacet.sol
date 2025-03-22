// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { Pausable } from "../../utils/Pausable.sol";
import { ForceActionsFacetEvents } from "./ForceActionsFacetEvents.sol";
import { ForceActionsFacetImpl } from "./ForceActionsFacetImpl.sol";
import { IForceActionsFacet } from "./IForceActionsFacet.sol";

/**
 * @title ForceActionsFacet
 * @notice Provides emergency resolution mechanisms for handling unresponsive counterparties
 * @dev Implements the IForceActionsFacet interface with pausability
 *      Force actions are safety measures to prevent trades from being locked indefinitely
 *      when counterparties become unresponsive or fail to act within required timeframes
 */
contract ForceActionsFacet is Pausable, IForceActionsFacet {
	/**
	 * @notice Forces the cancellation of an open intent when PartyB is unresponsive
	 * @dev Can only be executed after the forceCancelOpenIntentTimeout period has elapsed since locking
	 * @param intentId The unique identifier of the open intent to be forcibly canceled
	 */
	function forceCancelOpenIntent(uint256 intentId) external whenNotPartyAActionsPaused {
		ForceActionsFacetImpl.forceCancelOpenIntent(intentId);
		emit ForceCancelOpenIntent(intentId);
	}

	/**
	 * @notice Forces the cancellation of a close intent when PartyB is unresponsive
	 * @dev Can only be executed after the forceCancelCloseIntentTimeout period has elapsed since locking
	 *      This emergency mechanism prevents a trade from being locked in a pending close state indefinitely
	 * @param intentId The unique identifier of the close intent to be forcibly canceled
	 */
	function forceCancelCloseIntent(uint256 intentId) external whenNotPartyAActionsPaused {
		ForceActionsFacetImpl.forceCancelCloseIntent(intentId);
		emit ForceCancelCloseIntent(intentId);
	}

	/**
	 * @notice Forces the cancellation of an interdealer intent when the counterparty is unresponsive
	 * @param intentId The unique identifier of the interdealer intent to be forcibly canceled
	 */
	function forceCancelInterdealerIntent(uint256 intentId) external {
		// TODO: Implement interdealer intent forced cancellation
	}
}
