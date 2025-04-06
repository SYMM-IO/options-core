export interface IConfig {
    configTitle: string;
    version: string;
    admin: string;
  
    roles: {
      grant: Array<{
        address: string;
        role: string;
      }>;
      revoke: Array<{
        address: string;
        role: string;
      }>;
    };
  
    collateral: {
      whiteList: string[];
      removeFromWhitelist: string[];
    };
  
    pause: {
      global: boolean;
    };
  
    deactiveInstantActionModeCooldown: number;
    unbindingCooldown: number;
    maxConnectedPartyBs: number;
    priceOracleAddress: string;
  
    partyB: Array<{
      address: string;
      isActive: boolean;
      lossCoverage: number;
      oracleId: number;
      symbolType: number;
    }>;
  
    oracles: Array<{
      name: string;
      address: string;
    }>;
  
    affiliates: Array<{
      address: string;
      status: boolean;
    }>;
  
    symbols: Array<{
      address: string;
      name: string;
      optionType: string;
      oracleId: string;
      isStableCoin: boolean;
      tradingFee: string;
      type: string;
    }>;
  }
  