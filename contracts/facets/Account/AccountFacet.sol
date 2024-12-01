// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./IAccountFacet.sol";
import "./AccountFacetImpl.sol";
import "../../storages/AppStorage.sol";

contract AccountFacet is Accessibility, Pausable, IAccountFacet {
    /// @notice Allows either PartyA or PartyB to deposit collateral.
    /// @param amount The amount of collateral to be deposited, specified in collateral decimals.
    function deposit(
        uint256 amount
    ) external whenNotDepositingPaused notSuspended(msg.sender) {
        AccountFacetImpl.deposit(msg.sender, amount);
        emit Deposit(
            msg.sender,
            msg.sender,
            amount,
            AccountStorage.layout().balances[msg.sender]
        );
    }

    /// @notice Allows either Party A or Party B to deposit collateral on behalf of another user.
    /// @param user The recipient address for the deposit.
    /// @param amount The amount of collateral to be deposited, specified in collateral decimals.
    function depositFor(
        address user,
        uint256 amount
    )
        external
        whenNotDepositingPaused
        notSuspended(msg.sender)
        notSuspended(user)
    {
        AccountFacetImpl.deposit(user, amount);
        emit Deposit(
            msg.sender,
            user,
            amount,
            AccountStorage.layout().balances[user]
        );
    }

    /// @notice Allows Partys to distinct withdraw a specified amount of collateral.
    /// @param amount The precise amount of collateral to be withdrawn, specified in 18 decimals.
    /// @param to The address that the collateral transfers
    function withdraw(
        uint256 amount,
        address to
    )
        external
        whenNotWithdrawingPaused
        notSuspended(msg.sender)
        notSuspended(to)
    {
        AccountFacetImpl.withdraw(amount, to);
        emit InitWithdraw(
            msg.sender,
            to,
            amount,
            AccountStorage.layout().balances[msg.sender]
        );
    }

    /// @notice Allows Partys to claim a withdraw.
    /// @param id The Id of withdraw object
    function claimWithdraw(
        uint256 id
    ) external whenNotWithdrawingPaused notSuspendedWithdrawal(id) {
        AccountFacetImpl.claimWithdraw(id);
        emit ClaimWithdraw(id);
    }

    /// @notice Allows Partys to cancel a withdraw.
    /// @param id The Id of withdraw object
    function cancelWithdraw(
        uint256 id
    ) external whenNotWithdrawingPaused notSuspendedWithdrawal(id) {
        Withdraw storage withdrawObject = AccountStorage.layout().withdraws[id];
        AccountFacetImpl.cancelWithdraw(id);
        emit CancelWithdraw(
            id,
            AccountStorage.layout().balances[withdrawObject.user]
        );
    }
}
