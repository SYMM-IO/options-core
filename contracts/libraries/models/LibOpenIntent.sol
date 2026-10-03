// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";

import { TradeSide, MarginType, FeeStructure, FeeOp, TradeAgreements } from "../../types/BaseTypes.sol";
import { OpenIntent, OpenIntentEscrow, OpenIntentStatus } from "../../types/IntentTypes.sol";
import { ScheduledReleaseBalance, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { IntentErrors } from "../../errors/IntentErrors.sol";

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";

library LibOpenIntentOps {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function calculateFeeForQuantity(OpenIntent memory self, uint256 quantity, uint256 rate, uint256 price) internal pure returns (uint256) {
		return (quantity * price * rate) / (self.feeStructure.tokenPriceInCollateral * 1e18);
	}

	function calculateFee(OpenIntent memory self, uint256 rate, uint256 price) internal pure returns (uint256) {
		return calculateFeeForQuantity(self, self.tradeAgreements.quantity, rate, price);
	}

	function calculateOpenFeeAmountForQuantity(OpenIntent memory self, uint256 quantity, uint256 price) internal pure returns (uint256) {
		FeeStructure memory s = self.feeStructure;
		return
			calculateFeeForQuantity(self, quantity, s.platformFee.openFee, price) +
			calculateFeeForQuantity(self, quantity, s.affiliateFee.openFee, price) +
			calculateFeeForQuantity(self, quantity, s.solverFee.openFee, price);
	}

	function calculateOpenFeeAmount(OpenIntent memory self, uint256 price) internal pure returns (uint256) {
		return calculateOpenFeeAmountForQuantity(self, self.tradeAgreements.quantity, price);
	}

	function calculatePremium(OpenIntent memory self, uint256 price) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * price) / 1e18;
	}

	function getSymbol(OpenIntent memory self) internal view returns (Symbol memory) {
		return SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
	}

	function isDeferredPartyBSell(address[] memory partyBsWhiteList, TradeAgreements memory agreements) internal pure returns (bool) {
		return agreements.tradeSide == TradeSide.SELL && agreements.marginType == MarginType.CROSS && partyBsWhiteList.length == 0;
	}

	function isDeferredPartyBSellIntent(OpenIntent storage self) internal view returns (bool) {
		return
			self.tradeAgreements.tradeSide == TradeSide.SELL &&
			self.tradeAgreements.marginType == MarginType.CROSS &&
			self.partyBsWhiteList.length == 0;
	}

	function activeIntents(address owner, uint256 bucketId) internal view returns (uint256[] storage) {
		OpenIntentStorage.Layout storage layout = OpenIntentStorage.layout();
		if (bucketId == 0) return layout.activeOpenIntentsOf[owner];
		return layout.activeOpenIntentsOfBucket[owner][bucketId];
	}

	function register(OpenIntent memory self) internal {
		OpenIntentStorage.Layout storage layout = OpenIntentStorage.layout();
		layout.openIntents[self.id] = self;
		if (self.status == OpenIntentStatus.PENDING) {
			uint256[] storage intents = activeIntents(self.partyA, self.partyABucketId);
			intents.push(self.id);
			if (self.partyABucketId == 0) layout.activeOpenIntentsCount[self.partyA]++;
			else layout.activeOpenIntentsCountOfBucket[self.partyA][self.partyABucketId]++;
			layout.partyAOpenIntentsIndex[self.id] = intents.length - 1;
		}
	}

	function registerForPartyB(OpenIntent memory self) internal {
		OpenIntentStorage.Layout storage layout = OpenIntentStorage.layout();
		uint256[] storage intents = activeIntents(self.partyB, self.partyBBucketId);
		intents.push(self.id);
		layout.partyBOpenIntentsIndex[self.id] = intents.length - 1;
	}

	function unregister(OpenIntent memory self, bool fromPartyBOnly) internal {
		OpenIntentStorage.Layout storage layout = OpenIntentStorage.layout();
		if (!fromPartyBOnly) {
			uint256[] storage intents = activeIntents(self.partyA, self.partyABucketId);
			uint256 index = layout.partyAOpenIntentsIndex[self.id];
			uint256 lastIntentId = intents[intents.length - 1];
			intents[index] = lastIntentId;
			layout.partyAOpenIntentsIndex[lastIntentId] = index;
			intents.pop();
			if (self.partyABucketId == 0) layout.activeOpenIntentsCount[self.partyA]--;
			else layout.activeOpenIntentsCountOfBucket[self.partyA][self.partyABucketId]--;
			delete layout.partyAOpenIntentsIndex[self.id];
		}
		if (self.partyB != address(0)) {
			uint256[] storage intents = activeIntents(self.partyB, self.partyBBucketId);
			uint256 index = layout.partyBOpenIntentsIndex[self.id];
			uint256 lastIntentId = intents[intents.length - 1];
			intents[index] = lastIntentId;
			layout.partyBOpenIntentsIndex[lastIntentId] = index;
			intents.pop();
			delete layout.partyBOpenIntentsIndex[self.id];
		}
	}

	function expire(OpenIntent storage self) internal {
		if (block.timestamp <= self.deadline) revert IntentErrors.IntentNotExpired(self.id, block.timestamp, self.deadline);

		if (!(self.status == OpenIntentStatus.PENDING || self.status == OpenIntentStatus.CANCEL_PENDING || self.status == OpenIntentStatus.LOCKED)) {
			uint8[] memory requiredStatuses = new uint8[](3);
			requiredStatuses[0] = uint8(OpenIntentStatus.PENDING);
			requiredStatuses[1] = uint8(OpenIntentStatus.CANCEL_PENDING);
			requiredStatuses[2] = uint8(OpenIntentStatus.LOCKED);

			revert ValidationErrors.InvalidState("OpenIntentStatus", uint8(self.status), requiredStatuses);
		}

		self.status = OpenIntentStatus.EXPIRED;
		self.statusModifyTimestamp = block.timestamp;

		unlockForCancelOrExpire(self);
		unregister(self, false);
	}

	function lockDeferredSellEscrow(OpenIntent memory self) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();
		Symbol memory symbol = getSymbol(self);

		uint256 mm = self.tradeAgreements.mm;
		uint256 feeLockAmount = calculateOpenFeeAmount(self, self.price);

		self.partyA.balanceOf(self.partyABucketId, symbol.collateral).isolatedLock(mm);
		self.partyA.balanceOf(self.partyABucketId, self.feeStructure.feeToken).isolatedLock(feeLockAmount);

		openIntentLayout.openIntentEscrows[self.id] = OpenIntentEscrow({
			partyA: self.partyA,
			collateral: symbol.collateral,
			feeToken: self.feeStructure.feeToken,
			mm: mm,
			feeLockAmount: feeLockAmount,
			exists: true,
			consumed: false
		});

		emit IPartiesEvents.LockOpenIntentEscrow(self.id, self.partyA, symbol.collateral, mm, self.feeStructure.feeToken, feeLockAmount);
	}

	function releaseDeferredSellEscrow(uint256 intentId) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();
		OpenIntentEscrow storage escrow = openIntentLayout.openIntentEscrows[intentId];

		if (!escrow.exists) revert IntentErrors.MissingOpenIntentEscrow(intentId);
		if (escrow.consumed) revert IntentErrors.OpenIntentEscrowAlreadyConsumed(intentId);

		escrow.partyA.balanceOf(escrow.collateral).isolatedUnlock(escrow.mm);
		escrow.partyA.balanceOf(escrow.feeToken).isolatedUnlock(escrow.feeLockAmount);

		emit IPartiesEvents.ReleaseOpenIntentEscrow(intentId, escrow.partyA, escrow.collateral, escrow.mm, escrow.feeToken, escrow.feeLockAmount);

		delete openIntentLayout.openIntentEscrows[intentId];
	}

	function consumeDeferredSellEscrow(
		OpenIntent storage self,
		uint256 tradeId,
		address partyB,
		uint256 consumedMM,
		uint256 filledQuantity,
		uint256 fillPrice
	) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();
		OpenIntentEscrow storage escrow = openIntentLayout.openIntentEscrows[self.id];

		if (!escrow.exists) revert IntentErrors.MissingOpenIntentEscrow(self.id);
		if (escrow.consumed) revert IntentErrors.OpenIntentEscrowAlreadyConsumed(self.id);

		uint256 feeLockConsumed =
			filledQuantity == self.tradeAgreements.quantity
				? escrow.feeLockAmount
				: calculateOpenFeeAmountForQuantity(self, filledQuantity, self.price);
		uint256 actualFeeAmount = calculateOpenFeeAmountForQuantity(self, filledQuantity, fillPrice);

		escrow.partyA.balanceOf(escrow.collateral).isolatedUnlock(consumedMM);
		escrow.partyA.balanceOf(escrow.collateral).allocateBalance(partyB, consumedMM);

		escrow.partyA.balanceOf(escrow.feeToken).isolatedUnlock(feeLockConsumed);
		escrow.partyA.balanceOf(escrow.feeToken).allocateBalance(partyB, actualFeeAmount);

		escrow.mm -= consumedMM;
		escrow.feeLockAmount -= feeLockConsumed;
		emit IPartiesEvents.ConsumeOpenIntentEscrow(self.id, tradeId, partyB, consumedMM, actualFeeAmount);

		if (escrow.mm == 0 && escrow.feeLockAmount == 0) {
			escrow.consumed = true;
			delete openIntentLayout.openIntentEscrows[self.id];
		}
	}

	function moveDeferredSellEscrow(uint256 fromIntentId, OpenIntent memory toIntent) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();
		OpenIntentEscrow storage escrow = openIntentLayout.openIntentEscrows[fromIntentId];

		if (!escrow.exists) revert IntentErrors.MissingOpenIntentEscrow(fromIntentId);
		if (escrow.consumed) revert IntentErrors.OpenIntentEscrowAlreadyConsumed(fromIntentId);

		openIntentLayout.openIntentEscrows[toIntent.id] = OpenIntentEscrow({
			partyA: toIntent.partyA,
			collateral: escrow.collateral,
			feeToken: escrow.feeToken,
			mm: escrow.mm,
			feeLockAmount: escrow.feeLockAmount,
			exists: true,
			consumed: false
		});

		delete openIntentLayout.openIntentEscrows[fromIntentId];
	}

	function unlockForCancelOrExpire(OpenIntent storage self) internal {
		if (isDeferredPartyBSellIntent(self)) {
			releaseDeferredSellEscrow(self.id);
		} else {
			unlockFees(self);
			unlockPremiumIfBuy(self);
			unlockMMIfSell(self);
		}
	}

	function _lock(OpenIntent memory self, address collateral, uint256 amount) internal {
		ScheduledReleaseBalance storage partyABalance = self.partyA.balanceOf(self.partyABucketId, collateral);
		if (self.tradeAgreements.marginType == MarginType.ISOLATED) {
			partyABalance.isolatedLock(amount);
		} else {
			partyABalance.crossLock(self.partyBsWhiteList[0], self.partyBBucketId, amount);
		}
	}

	function _unlock(OpenIntent memory self, address collateral, uint256 amount) internal {
		ScheduledReleaseBalance storage partyABalance = self.partyA.balanceOf(self.partyABucketId, collateral);
		if (self.tradeAgreements.marginType == MarginType.ISOLATED) {
			partyABalance.isolatedUnlock(amount);
		} else {
			partyABalance.crossUnlock(self.partyBsWhiteList[0], self.partyBBucketId, amount);
		}
	}

	function lockPremiumIfBuy(OpenIntent memory self) internal {
		if (self.tradeAgreements.tradeSide == TradeSide.BUY) _lock(self, getSymbol(self).collateral, calculatePremium(self, self.price));
	}

	function unlockPremiumIfBuy(OpenIntent memory self) internal {
		if (self.tradeAgreements.tradeSide == TradeSide.BUY) _unlock(self, getSymbol(self).collateral, calculatePremium(self, self.price));
	}

	function lockMMIfSell(OpenIntent memory self) internal {
		if (self.tradeAgreements.tradeSide == TradeSide.SELL)
			self.partyA.balanceOf(self.partyABucketId, getSymbol(self).collateral).crossLock(
				self.partyBsWhiteList[0],
				self.partyBBucketId,
				self.tradeAgreements.mm
			);
	}

	function unlockMMIfSell(OpenIntent memory self) internal {
		if (self.tradeAgreements.tradeSide == TradeSide.SELL)
			self.partyA.balanceOf(self.partyABucketId, getSymbol(self).collateral).crossUnlock(
				self.partyBsWhiteList[0],
				self.partyBBucketId,
				self.tradeAgreements.mm
			);
	}

	function _handleFees(OpenIntent memory self, FeeOp op, uint256 price) private returns (uint256[3] memory fees) {
		FeeStructure memory s = self.feeStructure;
		bool isolated = self.tradeAgreements.marginType == MarginType.ISOLATED;
		bool singlePartyB = self.partyBsWhiteList.length == 1;
		address partyB = singlePartyB ? self.partyBsWhiteList[0] : self.partyB;
		if (!isolated && partyB == address(0)) revert ValidationErrors.ZeroAddress("partyB");
		fees = [
			calculateFee(self, s.platformFee.openFee, price),
			calculateFee(self, s.affiliateFee.openFee, price),
			calculateFee(self, s.solverFee.openFee, price)
		];

		if (op == FeeOp.Lock || op == FeeOp.Unlock) {
			for (uint8 i; i < 3; ++i) {
				if (op == FeeOp.Lock) _lock(self, s.feeToken, fees[i]);
				else _unlock(self, s.feeToken, fees[i]);
			}
			return fees;
		}

		ScheduledReleaseBalance storage bal = self.partyA.balanceOf(self.partyABucketId, s.feeToken);

		DecreaseBalanceReason[3] memory decReasons = [
			DecreaseBalanceReason.PLATFORM_FEE,
			DecreaseBalanceReason.AFFILIATE_FEE,
			DecreaseBalanceReason.SOLVER_FEE
		];

		for (uint8 i; i < 3; ++i) {
			if (op == FeeOp.Subtract) {
				if (isolated && !singlePartyB) {
					bal.isolatedSub(fees[i], decReasons[i]);
				} else {
					bal.subForCounterParty(partyB, self.partyBBucketId, fees[i], self.tradeAgreements.marginType, decReasons[i]);
				}
			}
		}
	}

	function getFeesFromUser(OpenIntent memory self, uint256 price) internal returns (uint256[3] memory fees) {
		fees = _handleFees(self, FeeOp.Subtract, price);
	}

	function lockFees(OpenIntent memory self) internal {
		_handleFees(self, FeeOp.Lock, self.price);
	}

	function unlockFees(OpenIntent memory self) internal {
		_handleFees(self, FeeOp.Unlock, self.price);
	}
}
