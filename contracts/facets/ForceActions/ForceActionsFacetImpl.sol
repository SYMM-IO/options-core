// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/IntentStorage.sol";
import "../../storages/AppStorage.sol";
import "../../libraries/LibIntent.sol";

library ForceActionsFacetImpl {
    function forceCancelOpenIntent(uint256 intentId) internal {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        AppStorage.Layout storage appLayout = AppStorage.layout();
        OpenIntent storage intent = IntentStorage.layout().openIntents[
            intentId
        ];

        require(
            intent.status == IntentStatus.CANCEL_PENDING,
            "PartyAFacet: Invalid state"
        );
        require(
            block.timestamp >
                intent.statusModifyTimestamp +
                    appLayout.forceCancelOpenIntentTimeout,
            "PartyAFacet: Cooldown not reached"
        );
        intent.statusModifyTimestamp = block.timestamp;
        intent.status = IntentStatus.CANCELED;
        accountLayout.lockedBalances[intent.partyA] -= LibIntent
            .getPremiumOfOpenIntent(intentId);

        // send trading Fee back to partyA
        uint256 fee = LibIntent.getTradingFee(intent.id);
        accountLayout.balances[intent.partyA] += fee;

        LibIntent.removeFromPartyAOpenIntents(intent.id);
        LibIntent.removeFromPartyBOpenIntents(intent.id);
    }

    function forceCancelCloseIntent(uint256 intentId) internal {
        AppStorage.Layout storage appLayout = AppStorage.layout();
        CloseIntent storage intent = IntentStorage.layout().closeIntents[
            intentId
        ];
        require(
            intent.status == IntentStatus.CANCEL_PENDING,
            "PartyAFacet: Invalid state"
        );
        require(
            block.timestamp >
                intent.statusModifyTimestamp +
                    appLayout.forceCancelCloseIntentTimeout,
            "PartyAFacet: Cooldown not reached"
        );

        intent.statusModifyTimestamp = block.timestamp;
        intent.status = IntentStatus.CANCELED;

        LibIntent.removeFromActiveCloseIntents(intentId);
    }
}
