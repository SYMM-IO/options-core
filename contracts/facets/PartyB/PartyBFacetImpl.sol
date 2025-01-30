// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibIntent.sol";
import "../../libraries/LibPartyB.sol";
import "../../libraries/LibMuon.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";
import "../../interfaces/ISignatureVerifier.sol";

library PartyBFacetImpl {
	function lockOpenIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol storage symbol = SymbolStorage.layout().symbols[intent.symbolId];

		require(intent.status == IntentStatus.PENDING, "PartyBFacet: Invalid state");
		require(block.timestamp <= intent.deadline, "PartyBFacet: Intent is expired");
		require(symbol.isValid, "PartyBFacet: Symbol is not valid");
		require(block.timestamp <= intent.expirationTimestamp, "PartyBFacet: Requested expiration has been passed");
		require(intentId <= intentLayout.lastOpenIntentId, "PartyBFacet: Invalid intentId");
		require(AppStorage.layout().partyBConfigs[msg.sender].oracleId == symbol.oracleId, "PartyBFacet: Oracle not matched");

		bool isValidPartyB;
		if (intent.partyBsWhiteList.length == 0) {
			require(msg.sender != intent.partyA, "PartyBFacet: PartyA can't be partyB too");
			isValidPartyB = true;
		} else {
			for (uint8 index = 0; index < intent.partyBsWhiteList.length; index++) {
				if (msg.sender == intent.partyBsWhiteList[index]) {
					isValidPartyB = true;
					break;
				}
			}
		}
		require(isValidPartyB, "PartyBFacet: Sender isn't whitelisted");
		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.LOCKED;
		intent.partyB = msg.sender;
		LibIntent.addToPartyBOpenIntents(intentId);
		intentLayout.openIntentsOf[intent.partyB].push(intent.id);
	}

	function unlockOpenIntent(uint256 intentId) internal returns (IntentStatus) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];

		require(intent.status == IntentStatus.LOCKED, "PartyBFacet: Invalid state");

		if (block.timestamp > intent.deadline) {
			LibIntent.expireOpenIntent(intentId);
			return IntentStatus.EXPIRED;
		} else {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = IntentStatus.PENDING;
			LibIntent.removeFromPartyBOpenIntents(intentId);
			intent.partyB = address(0);
			return IntentStatus.PENDING;
		}
	}

	function acceptCancelOpenIntent(uint256 intentId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.symbolId];
		require(intent.status == IntentStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		accountLayout.lockedBalances[intent.partyA][symbol.collateral] -= LibIntent.getPremiumOfOpenIntent(intentId);

		// send trading Fee back to partyA
		uint256 fee = LibIntent.getTradingFee(intentId);
		accountLayout.balances[intent.partyA][symbol.collateral] += fee;

		LibIntent.removeFromPartyAOpenIntents(intentId);
		LibIntent.removeFromPartyBOpenIntents(intentId);
	}

	function acceptCancelCloseIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		CloseIntent storage intent = intentLayout.closeIntents[intentId];

		require(intent.status == IntentStatus.CANCEL_PENDING, "LibIntent: Invalid state");

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		LibIntent.removeFromActiveCloseIntents(intentId);
	}

	function fillOpenIntent(uint256 intentId, uint256 quantity, uint256 price) internal returns (uint256 tradeId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];

		require(accountLayout.suspendedAddresses[intent.partyA] == false, "PartyBFacet: PartyA is suspended");
		require(!accountLayout.suspendedAddresses[msg.sender], "PartyBFacet: Sender is Suspended");
		require(!appLayout.partyBEmergencyStatus[intent.partyB], "PartyBFacet: PartyB is in emergency mode");
		require(!appLayout.emergencyMode, "PartyBFacet: System is in emergency mode");

		tradeId = LibPartyB.fillOpenIntent(intentId, quantity, price);
	}

	function fillCloseIntent(uint256 intentId, uint256 quantity, uint256 price) internal {
		LibPartyB.fillCloseIntent(intentId, quantity, price);
	}

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
			"PartyBFacet: Invalid PartyA signature"
		);
		require(!intentLayout.isSigUsed[openIntentHash], "SignatureVerifier: PartyA signature is already used");

		bytes32 fillOpenIntentHash = LibIntent.hashSignedFillOpenIntent(signedFillOpenIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signedFillOpenIntent.partyB, fillOpenIntentHash, partyBSignature),
			"PartyBFacet: Invalid PartyB signature"
		);
		require(!intentLayout.isSigUsed[fillOpenIntentHash], "SignatureVerifier: PartyB signature is already used");

		require(openIntentHash == signedFillOpenIntent.intentHash, "PartyBFacet: PartyB signature isn't related to the partyA signature");
		require(symbol.isValid, "PartyBFacet: Symbol is not valid");
		require(signedOpenIntent.deadline >= block.timestamp, "PartyBFacet: PartyA request is expired");
		require(signedFillOpenIntent.deadline >= block.timestamp, "PartyBFacet: PartyB request is expired");
		require(signedOpenIntent.expirationTimestamp >= block.timestamp, "PartyBFacet: Low expiration timestamp");
		require(signedOpenIntent.exerciseFee.cap <= 1e18, "PartyAFacet: High cap for exercise fee");
		require(signedOpenIntent.partyB == signedFillOpenIntent.partyB, "PartyBFacet: Invalid sig");
		require(signedOpenIntent.partyB != signedOpenIntent.partyA, "PartyBFacet: partyA cannot be same with partyB");
		require(appLayout.affiliateStatus[signedOpenIntent.affiliate] || signedOpenIntent.affiliate == address(0), "PartyBFacet: Invalid affiliate");
		require(appLayout.partyBConfigs[signedFillOpenIntent.partyB].oracleId == symbol.oracleId, "PartyBFacet: Unmatch oracle");
		require(accountLayout.suspendedAddresses[signedOpenIntent.partyA] == false, "PartyBFacet: PartyA is suspended");
		require(!accountLayout.suspendedAddresses[signedOpenIntent.partyB], "PartyBFacet: PartyB is Suspended");
		require(!appLayout.partyBEmergencyStatus[signedOpenIntent.partyB], "PartyBFacet: PartyB is in emergency mode");
		require(!appLayout.emergencyMode, "PartyBFacet: System is in emergency mode");
		require(
			appLayout.liquidationDetails[signedOpenIntent.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"PartyBFacet: PartyB is liquidated"
		);
		require(
			intentLayout.activeTradesOf[signedOpenIntent.partyA].length < appLayout.maxTradePerPartyA,
			"PartyBFacet: Too many active trades for partyA"
		);
		require(signedOpenIntent.quantity >= signedFillOpenIntent.quantity && signedFillOpenIntent.quantity > 0, "PartyBFacet: Invalid quantity");
		require(signedFillOpenIntent.price <= signedOpenIntent.price, "PartyBFacet: Opened price isn't valid");

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
			accountLayout.balances[signedOpenIntent.partyA][symbol.collateral] -= fee;
			address feeCollector = appLayout.affiliateFeeCollector[signedOpenIntent.affiliate] == address(0)
				? appLayout.defaultFeeCollector
				: appLayout.affiliateFeeCollector[signedOpenIntent.affiliate];
			accountLayout.balances[feeCollector][symbol.collateral] += fee;
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
		accountLayout.balances[trade.partyA][symbol.collateral] -= premium;
		accountLayout.balances[trade.partyB][symbol.collateral] += premium;
	}

	function instantFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		Trade storage trade = intentLayout.trades[signedCloseIntent.tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.symbolId];

		bytes32 closeIntentHash = LibIntent.hashSignedCloseIntent(signedCloseIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signedCloseIntent.partyA, closeIntentHash, partyASignature),
			"PartyBFacet: Invalid PartyA signature"
		);
		require(!intentLayout.isSigUsed[closeIntentHash], "SignatureVerifier: PartyA signature is already used");

		bytes32 fillCloseIntentHash = LibIntent.hashSignedFillCloseIntent(signedFillCloseIntent);
		require(
			ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signedFillCloseIntent.partyB, fillCloseIntentHash, partyBSignature),
			"PartyBFacet: Invalid PartyB signature"
		);
		require(!intentLayout.isSigUsed[fillCloseIntentHash], "SignatureVerifier: PartyB signature is already used");
		require(closeIntentHash == signedFillCloseIntent.intentHash, "PartyBFacet: PartyB signature isn't related to the partyA signature");
		require(signedCloseIntent.deadline >= block.timestamp, "PartyBFacet: PartyA request is expired");
		require(signedFillCloseIntent.deadline >= block.timestamp, "PartyBFacet: PartyB request is expired");
		require(trade.status == TradeStatus.OPENED, "PartyBFacet: Invalid state");
		require(LibIntent.getAvailableAmountToClose(trade.id) >= signedCloseIntent.quantity, "PartyBFacet: Invalid quantity");

		require(
			AppStorage.layout().liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"PartyBFacet: PartyB is liquidated"
		);
		require(
			signedFillCloseIntent.quantity > 0 && signedFillCloseIntent.quantity <= signedCloseIntent.quantity,
			"PartyBFacet: Invalid filled amount"
		);
		require(block.timestamp < trade.expirationTimestamp, "LibPartyB: Trade is expired");
		require(signedFillCloseIntent.price >= signedCloseIntent.price, "LibPartyB: Closed price isn't valid");

		intentLayout.isSigUsed[closeIntentHash] = true;
		intentLayout.isSigUsed[fillCloseIntentHash] = true;

		uint256 intentId = ++intentLayout.lastCloseIntentId;
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
		accountLayout.balances[trade.partyA][symbol.collateral] += pnl;
		accountLayout.balances[trade.partyB][symbol.collateral] -= pnl;

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

	function expireTrade(uint256 tradeId, SettlementPriceSig memory sig) internal {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.symbolId];
		LibMuon.verifySettlementPriceSig(sig);

		require(
			AppStorage.layout().liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"PartyBFacet: PartyB is liquidated"
		);
		require(sig.symbolId == trade.symbolId, "PartyBFacet: Invalid symbolId");
		require(trade.status == TradeStatus.OPENED, "PartyBFacet: Invalid trade state");
		require(block.timestamp > trade.expirationTimestamp, "PartyBFacet: Trade isn't expired");
		if (symbol.optionType == OptionType.PUT) {
			require(sig.settlementPrice >= trade.strikePrice, "PartyBFacet: Invalid price");
		} else {
			require(sig.settlementPrice <= trade.strikePrice, "PartyBFacet: Invalid price");
		}
		trade.settledPrice = sig.settlementPrice;

		LibIntent.closeTrade(tradeId, TradeStatus.EXPIRED, IntentStatus.CANCELED);
	}

	function exerciseTrade(uint256 tradeId, SettlementPriceSig memory sig) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.symbolId];
		LibMuon.verifySettlementPriceSig(sig);

		require(sig.symbolId == trade.symbolId, "PartyBFacet: Invalid symbolId");
		require(trade.status == TradeStatus.OPENED, "PartyBFacet: Invalid trade state");
		require(block.timestamp > trade.expirationTimestamp, "PartyBFacet: Trade isn't expired");
		require(
			AppStorage.layout().liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"PartyBFacet: PartyB is liquidated"
		);

		uint256 pnl;
		if (symbol.optionType == OptionType.PUT) {
			require(sig.settlementPrice < trade.strikePrice, "PartyBFacet: Invalid price");
			pnl = ((trade.quantity - trade.closedAmountBeforeExpiration) * (trade.strikePrice - sig.settlementPrice)) / 1e18;
		} else {
			require(sig.settlementPrice > trade.strikePrice, "PartyBFacet: Invalid price");
			pnl = ((trade.quantity - trade.closedAmountBeforeExpiration) * (sig.settlementPrice - trade.strikePrice)) / 1e18;
		}
		uint256 exerciseFee;
		{
			uint256 cap = (trade.exerciseFee.cap * pnl) / 1e18;
			uint256 fee = (trade.exerciseFee.rate * sig.settlementPrice * (trade.quantity - trade.closedAmountBeforeExpiration)) / 1e36;
			exerciseFee = cap < fee ? cap : fee;
		}
		uint256 amountToTransfer = pnl - exerciseFee;
		if (!symbol.isStableCoin) {
			amountToTransfer = (amountToTransfer * 1e18) / sig.settlementPrice;
		}

		accountLayout.balances[trade.partyA][symbol.collateral] += amountToTransfer;
		accountLayout.balances[trade.partyB][symbol.collateral] -= amountToTransfer;

		LibIntent.closeTrade(tradeId, TradeStatus.EXERCISED, IntentStatus.CANCELED);
	}
}
