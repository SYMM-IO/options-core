// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

import "../../storages/AccountStorage.sol";
import "../../storages/IntentStorage.sol";

contract ViewFacet/* is IViewFacet */{
    /**
	 * @notice Returns the balance for a specified user and collateral type.
	 * @param user The address of the user.
     * @param collateral The address of the collateral type.
	 * @return The balance of the user.
	 */
	function balanceOf(address user, address collateral) external view returns (uint256) {
		return AccountStorage.layout().balances[user][collateral];
	}

    /**
	 * @notice Returns various values related to Party A.
	 * @param partyA The address of Party A.
	 // TODO 1, return liquidationStatus The liquidation status of Party A.
	 * @return suspendedAddresses returns a true/false representing whether the given address is suspended or not.
	 * @return balance The balance of Party A.
	 * @return lockedBalance The locked balance of Party A and specific collateral.
	 * @return withdrawIds The list of withdrawIds of Party A.
	 * @return openIntentsOf The list of openIntents of Party A.
	 * @return tradesOf The list of trades of Party A.
	 */
	function partyAStats(
		address partyA,
		address collateral
	)
		external
		view
		returns (bool, uint256, uint256, uint256[] memory, uint256[] memory, uint256[] memory)
	{
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		// MAStorage.Layout storage maLayout = MAStorage.layout();  #TODO 1: consider adding this after liquidation dev.
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		return (
			// maLayout.liquidationStatus[partyA], #TODO 1
			accountLayout.suspendedAddresses[partyA],
			accountLayout.balances[partyA][collateral],
			accountLayout.lockedBalances[partyA][collateral],
			accountLayout.withdrawIds[partyA],
			//TODO 2: consider adding AppStorage:partyAReimbursement after it's used 
			intentLayout.openIntentsOf[partyA],
			intentLayout.tradesOf[partyA]
			// intentLayout.closeIntentIdsOf TODO 3: consider adding this if it's necessary
		);
	}
}