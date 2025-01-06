// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Pausable.sol";
import "../../utils/Accessibility.sol";
import "./ILiquidationFacet.sol";
import "./LiquidationFacetImpl.sol";
import "../../storages/AccountStorage.sol";

contract LiquidationFacet is Pausable, Accessibility, ILiquidationFacet {
    /**
     * @notice Liquidates Party B based on the provided signature.
     * @param partyB The address of Party B to be liquidated.
     * @param liquidationSig The Muon signature.
     */
    function liquidate(
        address partyB,
        LiquidationSig memory liquidationSig
    )
        external
        whenNotLiquidationPaused
        onlyRole(LibAccessibility.LIQUIDATOR_ROLE)
    {
        LiquidationFacetImpl.liquidate(partyB, liquidationSig);
        // emit Liquidate(
        //     msg.sender,
        //     partyB,
        //     AccountStorage.layout().balances[partyB],
        //     liquidationSig.upnl,
        //     liquidationSig.liquidationId
        // );
    }

    /**
     * @notice Sets the prices of symbols at the time of liquidation.
     * @dev The Muon signature here should be the same as the one that got partyB liquidated.
     * @param partyB The address of Party B associated with the liquidation.
     * @param liquidationSig The Muon signature containing symbol IDs and their corresponding prices.
     */
    function setSymbolsPrice(
        address partyB,
        LiquidationSig memory liquidationSig
    )
        external
        whenNotLiquidationPaused
        onlyRole(LibAccessibility.LIQUIDATOR_ROLE)
    {
        LiquidationFacetImpl.setSymbolsPrice(partyB, liquidationSig);
        emit SetSymbolsPrices(
            msg.sender,
            partyB,
            liquidationSig.symbolIds,
            liquidationSig.prices,
            liquidationSig.liquidationId
        );
    }

    /**
     * @notice Cancels open intents of Party B.
     * @param partyB The address of Party B whose open intents will be canceled.
     * @param openIntentIds An array of open intent IDs representing the Intents to be canceled.
     */
    function liquidateOpenIntents(
        address partyB,
        uint256[] memory openIntentIds
    )
        external
        whenNotLiquidationPaused
        onlyRole(LibAccessibility.LIQUIDATOR_ROLE)
    {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        uint256[] memory pendingIntents = intentLayout.activeOpenIntentsOf[
            partyB
        ];
        (
            uint256[] memory liquidatedAmounts,
            bytes memory liquidationId
        ) = LiquidationFacetImpl.liquidateOpenIntents(partyB, openIntentIds);
        emit LiquidateOpenIntents(
            msg.sender,
            partyB,
            pendingIntents,
            liquidatedAmounts,
            liquidationId
        );
    }

    /**
     * @notice Liquidates trades of Party B.
     * @param partyB The address of Party B whose trades will be liquidated.
     * @param tradeIds An array of trade IDs representing the Trades to be liquidated.
     */
    function liquidateTrades(
        address partyB,
        uint256[] memory tradeIds
    )
        external
        whenNotLiquidationPaused
        onlyRole(LibAccessibility.LIQUIDATOR_ROLE)
    {
        (
            uint256[] memory liquidatedAmounts,
            bytes memory liquidationId
        ) = LiquidationFacetImpl.liquidateTrades(partyB, tradeIds);
        emit LiquidateTrades(
            msg.sender,
            partyB,
            tradeIds,
            liquidatedAmounts,
            liquidationId
        );
    }

    /**
     * @notice Settles liquidation for Party B with specified Party As.
     * @param partyB The address of Party B to settle liquidation for.
     * @param partyAs An array of addresses representing Party As involved in the settlement.
     */
    function settleLiquidation(
        address partyB,
        address[] memory partyAs
    ) external whenNotLiquidationPaused {
        (
            int256[] memory settleAmounts,
            bytes memory liquidationId
        ) = LiquidationFacetImpl.settleLiquidation(partyB, partyAs);
        emit SettleLiquidation(partyB, partyAs, settleAmounts, liquidationId);
        // if (AppStorage.layout().liquidationStatus[partyB] == false) {
        //     emit FullyLiquidated(partyB, liquidationId);
        // }
    }
}
