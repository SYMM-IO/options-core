// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/AccountStorage.sol";

library LibAccount {
    /**
     * @notice Calculates the available balance for liquidation for Party B.
     * @param upnl The unrealized profit and loss.
     * @param balance The balance of Party B.
     * @param partyB The address of Party B.
     * @return The available balance for liquidation for Party B.
     */
    function partyBAvailableBalanceForLiquidation(
        int256 upnl,
        uint256 balance,
        address partyB
    ) internal view returns (int256) {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        // int256 freeBalance = int256(balance) - int256(accountLayout.lockedBalances[partyA].cva + accountLayout.lockedBalances[partyA].lf);
        return int256(balance) + upnl;
    }
}
