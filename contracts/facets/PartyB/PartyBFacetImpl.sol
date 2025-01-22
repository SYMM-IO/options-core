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
		require(AppStorage.layout().partyBConfigs[msg.sender].oracleId == symbol.oracleId, "PartyBFacet: Unmatch oracle");

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

	function instantOpenTradeWithSig(
		SignedOpenIntentRequest calldata req,
		bytes calldata signature,
		uint256 filledQuantity,
		uint256 filledPrice
	) internal returns (uint256 intentId, uint256 newIntentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		Symbol memory symbol = SymbolStorage.layout().symbols[req.symbolId];

		bytes32 hash = LibIntent.hashSignedOpenIntentRequest(req);
		bool isValid = ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(req.partyA, hash, signature);
		require(isValid, "PartyBFacet: Invalid PartyA signature");
		require(!intentLayout.isSigUsed[hash], "SignatureVerifier: Signature is already used");

		require(symbol.isValid, "PartyBFacet: Symbol is not valid");
		require(req.deadline >= block.timestamp, "PartyBFacet: Request expired");
		require(req.expirationTimestamp >= block.timestamp, "PartyBFacet: Low expiration timestamp");
		require(req.exerciseFee.cap <= 1e18, "PartyAFacet: High cap for exercise fee");
		require(req.partyB == msg.sender, "PartyBFacet: partyA cannot be in partyBWhiteList");
		require(req.partyB != req.partyA, "PartyBFacet: partyA cannot be same with partyB");
		require(appLayout.affiliateStatus[req.affiliate] || req.affiliate == address(0), "PartyBFacet: Invalid affiliate");
		require(appLayout.partyBConfigs[msg.sender].oracleId == symbol.oracleId, "PartyBFacet: Unmatch oracle");
		require(accountLayout.suspendedAddresses[req.partyA] == false, "PartyBFacet: PartyA is suspended");
		require(!accountLayout.suspendedAddresses[req.partyB], "PartyBFacet: PartyB is Suspended");
		require(!appLayout.partyBEmergencyStatus[req.partyB], "PartyBFacet: PartyB is in emergency mode");
		require(!appLayout.emergencyMode, "PartyBFacet: System is in emergency mode");
		require(appLayout.liquidationDetails[req.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT, "PartyBFacet: PartyB is liquidated");
		require(intentLayout.activeTradesOf[req.partyA].length < appLayout.maxTradePerPartyA, "PartyBFacet: Too many active trades for partyA");
		require(req.quantity >= filledQuantity && filledQuantity > 0, "PartyBFacet: Invalid quantity");
		require(filledPrice <= req.price, "PartyBFacet: Opened price isn't valid");

		intentLayout.isSigUsed[hash] = true;

		intentId = ++intentLayout.lastOpenIntentId;
		uint256 tradeId = ++intentLayout.lastTradeId;

		address[] memory partyBsWhitelist = new address[](1);
		partyBsWhitelist[0] = req.partyB;
		OpenIntent memory intent = OpenIntent({
			id: intentId,
			tradeId: tradeId,
			partyBsWhiteList: partyBsWhitelist,
			symbolId: req.symbolId,
			price: req.price,
			quantity: req.quantity,
			strikePrice: req.strikePrice,
			expirationTimestamp: req.expirationTimestamp,
			partyA: req.partyA,
			partyB: req.partyB,
			status: IntentStatus.FILLED,
			parentId: 0,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			deadline: req.deadline,
			tradingFee: symbol.tradingFee,
			affiliate: req.affiliate,
			exerciseFee: req.exerciseFee
		});

		intentLayout.openIntents[intentId] = intent;
		intentLayout.openIntentsOf[req.partyA].push(intent.id);
		intentLayout.openIntentsOf[req.partyB].push(intent.id);
		{
			uint256 fee = LibIntent.getTradingFee(intentId);
			accountLayout.balances[req.partyA][symbol.collateral] -= fee;
			address feeCollector = appLayout.affiliateFeeCollector[req.affiliate] == address(0)
				? appLayout.defaultFeeCollector
				: appLayout.affiliateFeeCollector[req.affiliate];
			accountLayout.balances[feeCollector][symbol.collateral] += (filledQuantity * intent.price * intent.tradingFee) / 1e36;
		}
		// filling
		Trade memory trade = Trade({
			id: tradeId,
			openIntentId: intentId,
			activeCloseIntentIds: new uint256[](0),
			symbolId: intent.symbolId,
			quantity: filledQuantity,
			strikePrice: intent.strikePrice,
			expirationTimestamp: intent.expirationTimestamp,
			settledPrice: 0,
			exerciseFee: intent.exerciseFee,
			partyA: intent.partyA,
			partyB: intent.partyB,
			openedPrice: filledPrice,
			closedAmountBeforeExpiration: 0,
			closePendingAmount: 0,
			avgClosedPriceBeforeExpiration: 0,
			status: TradeStatus.OPENED,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp
		});

		// partially fill
		if (intent.quantity > filledQuantity) {
			newIntentId = ++intentLayout.lastOpenIntentId;
			IntentStatus newStatus = IntentStatus.PENDING;

			OpenIntent memory q = OpenIntent({
				id: newIntentId,
				tradeId: 0,
				partyBsWhiteList: partyBsWhitelist,
				symbolId: intent.symbolId,
				price: intent.price,
				quantity: intent.quantity - filledQuantity,
				strikePrice: intent.strikePrice,
				expirationTimestamp: intent.expirationTimestamp,
				exerciseFee: intent.exerciseFee,
				partyA: intent.partyA,
				partyB: address(0),
				status: newStatus,
				parentId: intent.id,
				createTimestamp: block.timestamp,
				statusModifyTimestamp: block.timestamp,
				deadline: intent.deadline,
				tradingFee: intent.tradingFee,
				affiliate: intent.affiliate
			});

			intentLayout.openIntents[newIntentId] = q;
			intentLayout.openIntentsOf[intent.partyA].push(newIntentId);
			LibIntent.addToPartyAOpenIntents(newIntentId);

			OpenIntent storage newIntent = intentLayout.openIntents[newIntentId];

			// if (newStatus == IntentStatus.CANCELED) {
			// 	// send trading Fee back to partyA
			// 	uint256 fee = LibIntent.getTradingFee(newIntent.id);
			// 	accountLayout.balances[newIntent.partyA][symbol.collateral] += fee;
			// } else {
			accountLayout.lockedBalances[intent.partyA][symbol.collateral] += LibIntent.getPremiumOfOpenIntent(newIntent.id);
			// }
			intent.quantity = filledQuantity;
		}

		LibIntent.addToActiveTrades(tradeId);
		uint256 premium = LibIntent.getPremiumOfOpenIntent(intentId);
		accountLayout.balances[trade.partyA][symbol.collateral] -= premium;
		accountLayout.balances[trade.partyB][symbol.collateral] += premium;
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
