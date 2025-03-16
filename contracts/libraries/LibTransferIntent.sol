// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";
import "../storages/SymbolStorage.sol";

library TransferIntentOps {
	function getPremium(TransferIntent memory self) internal view returns (uint256) {
		Trade memory trade = IntentStorage.layout().trades[self.tradeId];
		return self.proposedPrice * (trade.quantity - trade.closedAmountBeforeExpiration);
	}

	function getPremiumWithPrice(TransferIntent memory self, uint256 price) internal view returns (uint256) {
		Trade memory trade = IntentStorage.layout().trades[self.tradeId];
		return price * (trade.quantity - trade.closedAmountBeforeExpiration);
	}

	function getTrade(TransferIntent memory self) internal view returns (Trade storage) {
		return IntentStorage.layout().trades[self.tradeId];
	}

	function getSymbol(TransferIntent memory self) internal view returns (Symbol memory) {
		return SymbolStorage.layout().symbols[getTrade(self).symbolId];
	}
}
