// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/IntentStorage.sol";
import "../../utils/Pausable.sol";
import "./IForceActionsFacet.sol";
import "./ForceActionsFacetImpl.sol";

contract ForceActionsFacet is Pausable, IForceActionsFacet {
    /**
     * @notice Forces the cancellation of the specified open intent when partyB is not responsive for a certian amount of time(forceCancelOpenIntentTimeout).
     * @param intentId The ID of the open intent to be canceled.
     */
    function forceCancelOpenIntent(
        uint256 intentId
    ) external whenNotPartyAActionsPaused {
        ForceActionsFacetImpl.forceCancelOpenIntent(intentId);
        emit ForceCancelOpenIntent(intentId);
    }

    /**
     * @notice Forces the cancellation of the close intent associated with the specified intent when partyB is not responsive for a certain amount of time(forceCancelCloseIntentTimeout).
     * @param intentId The ID of the close intent to be canceled.
     */
    function forceCancelCloseIntent(
        uint256 intentId
    ) external whenNotPartyAActionsPaused {
        ForceActionsFacetImpl.forceCancelCloseIntent(intentId);
        emit ForceCancelCloseIntent(intentId);
    }
}
