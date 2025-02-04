// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibIntent.sol";
import "../../libraries/LibPartyB.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";
import "../../interfaces/ISignatureVerifier.sol";

library InstantActionsFacetImpl {
	using StagedReleaseBalanceOps for StagedReleaseBalance;

	function instantFillOpenIntent(
		SignedOpenIntent calldata signedOpenIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) internal returns (uint256 intentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		Symbol memory symbol = SymbolStorage.layout().symbols[signedOpenIntent.symbolId];

		bytes32 openIntentHash = LibIntent.hashSignedOpenIntent(signedOpenIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signedOpenIntent.partyA, openIntentHash, partyASignature),
			"InstantActionsFacet: Invalid PartyA signature"
		);
		require(!intentLayout.isSigUsed[openIntentHash], "InstantActionsFacet: PartyA signature is already used");

		bytes32 fillOpenIntentHash = LibIntent.hashSignedFillOpenIntent(signedFillOpenIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signedFillOpenIntent.partyB, fillOpenIntentHash, partyBSignature),
			"InstantActionsFacet: Invalid PartyB signature"
		);
		require(!intentLayout.isSigUsed[fillOpenIntentHash], "InstantActionsFacet: PartyB signature is already used");

		require(openIntentHash == signedFillOpenIntent.intentHash, "InstantActionsFacet: PartyB signature isn't related to the partyA signature");
		require(symbol.isValid, "InstantActionsFacet: Symbol is not valid");
		require(signedOpenIntent.deadline >= block.timestamp, "InstantActionsFacet: PartyA request is expired");
		require(signedFillOpenIntent.deadline >= block.timestamp, "InstantActionsFacet: PartyB request is expired");
		require(signedOpenIntent.expirationTimestamp >= block.timestamp, "InstantActionsFacet: Low expiration timestamp");
		require(signedOpenIntent.exerciseFee.cap <= 1e18, "InstantActionsFacet: High cap for exercise fee");
		require(signedOpenIntent.partyB == signedFillOpenIntent.partyB, "InstantActionsFacet: Invalid signature");
		require(signedOpenIntent.partyB != signedOpenIntent.partyA, "InstantActionsFacet: partyA cannot be the same as partyB");
		require(
			appLayout.affiliateStatus[signedOpenIntent.affiliate] || signedOpenIntent.affiliate == address(0),
			"InstantActionsFacet: Invalid affiliate"
		);
		require(appLayout.partyBConfigs[signedFillOpenIntent.partyB].oracleId == symbol.oracleId, "InstantActionsFacet: Mismatched oracle");
		require(accountLayout.suspendedAddresses[signedOpenIntent.partyA] == false, "InstantActionsFacet: PartyA is suspended");
		require(!accountLayout.suspendedAddresses[signedOpenIntent.partyB], "InstantActionsFacet: PartyB is Suspended");
		require(!appLayout.partyBEmergencyStatus[signedOpenIntent.partyB], "InstantActionsFacet: PartyB is in emergency mode");
		require(!appLayout.emergencyMode, "InstantActionsFacet: System is in emergency mode");
		require(
			appLayout.liquidationDetails[signedOpenIntent.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"InstantActionsFacet: PartyB is liquidated"
		);
		require(
			intentLayout.activeTradesOf[signedOpenIntent.partyA].length < appLayout.maxTradePerPartyA,
			"InstantActionsFacet: Too many active trades for partyA"
		);
		require(
			signedOpenIntent.quantity >= signedFillOpenIntent.quantity && signedFillOpenIntent.quantity > 0,
			"InstantActionsFacet: Invalid filled quantity"
		);
		require(signedFillOpenIntent.price <= signedOpenIntent.price, "InstantActionsFacet: Invalid filled price");

		if (accountLayout.boundPartyB[signedOpenIntent.partyA] != address(0)) {
			require(
				signedFillOpenIntent.partyB == accountLayout.boundPartyB[signedOpenIntent.partyA],
				"InstantActionsFacet: User is bound to another PartyB"
			);
		}

		intentLayout.isSigUsed[openIntentHash] = true;
		intentLayout.isSigUsed[fillOpenIntentHash] = true;

		intentId = ++intentLayout.lastOpenIntentId;
		uint256 tradeId = ++intentLayout.lastTradeId;

		address[] memory partyBsWhitelist = new address[](1);
		partyBsWhitelist[0] = signedOpenIntent.partyB;
		OpenIntent memory intent = OpenIntent({
			id: intentId,
			tradeId: tradeId,
			partyBsWhiteList: partyBsWhitelist,
			symbolId: signedOpenIntent.symbolId,
			price: signedOpenIntent.price,
			quantity: signedFillOpenIntent.quantity,
			strikePrice: signedOpenIntent.strikePrice,
			expirationTimestamp: signedOpenIntent.expirationTimestamp,
			partyA: signedOpenIntent.partyA,
			partyB: signedOpenIntent.partyB,
			status: IntentStatus.FILLED,
			parentId: 0,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			deadline: signedOpenIntent.deadline,
			tradingFee: symbol.tradingFee,
			affiliate: signedOpenIntent.affiliate,
			exerciseFee: signedOpenIntent.exerciseFee
		});

		intentLayout.openIntents[intentId] = intent;
		intentLayout.openIntentsOf[signedOpenIntent.partyA].push(intent.id);
		intentLayout.openIntentsOf[signedOpenIntent.partyB].push(intent.id);
		{
			uint256 fee = LibIntent.getTradingFee(intentId);
			accountLayout.balances[signedOpenIntent.partyA][symbol.collateral].syncAll(block.timestamp);
			accountLayout.balances[signedOpenIntent.partyA][symbol.collateral].subForPartyB(signedOpenIntent.partyB, fee);

			address feeCollector = appLayout.affiliateFeeCollector[signedOpenIntent.affiliate] == address(0)
				? appLayout.defaultFeeCollector
				: appLayout.affiliateFeeCollector[signedOpenIntent.affiliate];
			accountLayout.balances[feeCollector][symbol.collateral].instantAdd(fee);
		}
		// filling
		Trade memory trade = Trade({
			id: tradeId,
			openIntentId: intentId,
			activeCloseIntentIds: new uint256[](0),
			symbolId: intent.symbolId,
			quantity: signedFillOpenIntent.quantity,
			strikePrice: intent.strikePrice,
			expirationTimestamp: intent.expirationTimestamp,
			settledPrice: 0,
			exerciseFee: intent.exerciseFee,
			partyA: intent.partyA,
			partyB: intent.partyB,
			openedPrice: signedFillOpenIntent.price,
			closedAmountBeforeExpiration: 0,
			closePendingAmount: 0,
			avgClosedPriceBeforeExpiration: 0,
			status: TradeStatus.OPENED,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp
		});

		LibIntent.addToActiveTrades(tradeId);
		uint256 premium = LibIntent.getPremiumOfOpenIntent(intentId);
		accountLayout.balances[trade.partyA][symbol.collateral].syncAll(block.timestamp);
		accountLayout.balances[trade.partyA][symbol.collateral].subForPartyB(trade.partyB, premium);
		accountLayout.balances[trade.partyB][symbol.collateral].instantAdd(premium);
	}

	function instantFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) internal returns (uint256 intentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		Trade storage trade = intentLayout.trades[signedCloseIntent.tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.symbolId];

		bytes32 closeIntentHash = LibIntent.hashSignedCloseIntent(signedCloseIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signedCloseIntent.partyA, closeIntentHash, partyASignature),
			"InstantActionsFacet: Invalid PartyA signature"
		);
		require(!intentLayout.isSigUsed[closeIntentHash], "InstantActionsFacet: PartyA signature is already used");

		bytes32 fillCloseIntentHash = LibIntent.hashSignedFillCloseIntent(signedFillCloseIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signedFillCloseIntent.partyB, fillCloseIntentHash, partyBSignature),
			"InstantActionsFacet: Invalid PartyB signature"
		);
		require(!intentLayout.isSigUsed[fillCloseIntentHash], "InstantActionsFacet: PartyB signature is already used");
		require(closeIntentHash == signedFillCloseIntent.intentHash, "InstantActionsFacet: PartyB signature isn't related to the partyA signature");
		require(signedCloseIntent.deadline >= block.timestamp, "InstantActionsFacet: PartyA request is expired");
		require(signedFillCloseIntent.deadline >= block.timestamp, "InstantActionsFacet: PartyB request is expired");
		require(trade.status == TradeStatus.OPENED, "InstantActionsFacet: Invalid state");
		require(LibIntent.getAvailableAmountToClose(trade.id) >= signedCloseIntent.quantity, "InstantActionsFacet: Invalid quantity");

		require(
			AppStorage.layout().liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"InstantActionsFacet: PartyB is liquidated"
		);
		require(
			signedFillCloseIntent.quantity > 0 && signedFillCloseIntent.quantity <= signedCloseIntent.quantity,
			"InstantActionsFacet: Invalid filled quantity"
		);
		require(block.timestamp < trade.expirationTimestamp, "InstantActionsFacet: Trade is expired");
		require(signedFillCloseIntent.price >= signedCloseIntent.price, "InstantActionsFacet: Closed price isn't valid");

		intentLayout.isSigUsed[closeIntentHash] = true;
		intentLayout.isSigUsed[fillCloseIntentHash] = true;

		intentId = ++intentLayout.lastCloseIntentId;
		CloseIntent memory intent = CloseIntent({
			id: intentId,
			tradeId: trade.id,
			price: signedCloseIntent.price,
			quantity: signedFillCloseIntent.quantity,
			filledAmount: signedFillCloseIntent.quantity,
			status: IntentStatus.FILLED,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			deadline: signedCloseIntent.deadline
		});

		intentLayout.closeIntents[intentId] = intent;
		intentLayout.closeIntentIdsOf[trade.id].push(intentId);

		uint256 pnl = (signedFillCloseIntent.quantity * signedFillCloseIntent.price) / 1e18;
		accountLayout.balances[trade.partyA][symbol.collateral].add(trade.partyB, pnl, block.timestamp);
		accountLayout.balances[trade.partyB][symbol.collateral].sub(pnl);

		trade.avgClosedPriceBeforeExpiration =
			(trade.avgClosedPriceBeforeExpiration *
				trade.closedAmountBeforeExpiration +
				signedFillCloseIntent.quantity *
				signedFillCloseIntent.price) /
			(trade.closedAmountBeforeExpiration + signedFillCloseIntent.quantity);

		trade.closedAmountBeforeExpiration += signedFillCloseIntent.quantity;

		if (trade.quantity == trade.closedAmountBeforeExpiration) {
			trade.status = TradeStatus.CLOSED;
			trade.statusModifyTimestamp = block.timestamp;
			LibIntent.removeFromActiveTrades(trade.id);
		}
	}

	function instantCancelOpenIntent(
		SignedCancelIntent calldata signedCancelOpenIntent,
		bytes calldata partyASignature,
		SignedCancelIntent calldata signedAcceptCancelOpenIntent,
		bytes calldata partyBSignature
	) internal returns (IntentStatus result) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[signedCancelOpenIntent.intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.symbolId];

		bytes32 cancelIntentHash = LibIntent.hashSignedCancelOpenIntent(signedCancelOpenIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signedCancelOpenIntent.signer, cancelIntentHash, partyASignature),
			"InstantActionsFacet: Invalid PartyA signature"
		);
		require(!intentLayout.isSigUsed[cancelIntentHash], "InstantActionsFacet: PartyA signature is already used");
		intentLayout.isSigUsed[cancelIntentHash] = true;

		// ignore the partyB signature if the status is PENDING
		if (intent.status == IntentStatus.LOCKED) {
			bytes32 acceptCancelIntentHash = LibIntent.hashSignedAcceptCancelOpenIntent(signedAcceptCancelOpenIntent);
			require(
				ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(
					signedAcceptCancelOpenIntent.signer,
					acceptCancelIntentHash,
					partyBSignature
				),
				"InstantActionsFacet: Invalid PartyB signature"
			);
			require(!intentLayout.isSigUsed[acceptCancelIntentHash], "InstantActionsFacet: PartyB signature is already used");
			intentLayout.isSigUsed[acceptCancelIntentHash] = true;
			require(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.LOCKED, "InstantActionsFacet: Invalid state");
			require(intent.partyB == signedAcceptCancelOpenIntent.signer);
			require(signedCancelOpenIntent.intentId == signedAcceptCancelOpenIntent.intentId, "InstantActionsFacet: Signatures don't match");
			require(signedAcceptCancelOpenIntent.deadline >= block.timestamp, "InstantActionsFacet: PartyB request is expired");
			LibIntent.removeFromPartyBOpenIntents(intent.id);
		}
		require(signedCancelOpenIntent.deadline >= block.timestamp, "InstantActionsFacet: PartyA request is expired");
		require(intent.partyA == signedCancelOpenIntent.signer);

		if (block.timestamp > intent.deadline) {
			LibIntent.expireOpenIntent(intent.id);
			result = IntentStatus.EXPIRED;
		} else {
			intent.status = IntentStatus.CANCELED;
			uint256 fee = LibIntent.getTradingFee(intent.id);
			accountLayout.balances[intent.partyA][symbol.collateral].add(intent.partyB, fee, block.timestamp);

			accountLayout.lockedBalances[intent.partyA][symbol.collateral] -= LibIntent.getPremiumOfOpenIntent(intent.id);
			LibIntent.removeFromPartyAOpenIntents(intent.id);
			result = IntentStatus.CANCELED;
			intent.statusModifyTimestamp = block.timestamp;
		}
	}

	function instantCancelCloseIntent(
		SignedCancelIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedCancelIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) internal returns (IntentStatus result) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		CloseIntent storage intent = intentLayout.closeIntents[signedCancelCloseIntent.intentId];
		Trade storage trade = intentLayout.trades[intent.tradeId];

		bytes32 cancelIntentHash = LibIntent.hashSignedCancelCloseIntent(signedCancelCloseIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signedCancelCloseIntent.signer, cancelIntentHash, partyASignature),
			"InstantActionsFacet: Invalid PartyA signature"
		);
		require(!intentLayout.isSigUsed[cancelIntentHash], "InstantActionsFacet: PartyA signature is already used");
		bytes32 acceptCancelIntentHash = LibIntent.hashSignedAcceptCancelCloseIntent(signedAcceptCancelCloseIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(
				signedAcceptCancelCloseIntent.signer,
				acceptCancelIntentHash,
				partyBSignature
			),
			"InstantActionsFacet: Invalid PartyB signature"
		);
		require(!intentLayout.isSigUsed[acceptCancelIntentHash], "InstantActionsFacet: PartyB signature is already used");

		require(intent.status == IntentStatus.PENDING, "InstantActionsFacet: Invalid state");
		require(trade.partyB == signedAcceptCancelCloseIntent.signer);
		require(signedCancelCloseIntent.intentId == signedAcceptCancelCloseIntent.intentId, "InstantActionsFacet: Signatures don't match");
		require(signedAcceptCancelCloseIntent.deadline >= block.timestamp, "InstantActionsFacet: PartyB request is expired");
		require(signedCancelCloseIntent.deadline >= block.timestamp, "InstantActionsFacet: PartyA request is expired");
		require(trade.partyA == signedCancelCloseIntent.signer);

		intentLayout.isSigUsed[cancelIntentHash] = true;
		intentLayout.isSigUsed[acceptCancelIntentHash] = true;

		if (block.timestamp > intent.deadline) {
			LibIntent.expireCloseIntent(intent.id);
			result = IntentStatus.EXPIRED;
		} else {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = IntentStatus.CANCELED;
			LibIntent.removeFromActiveCloseIntents(intent.id);
			result = IntentStatus.CANCELED;
		}
	}
}
