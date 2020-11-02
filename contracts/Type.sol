// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.4;

struct Context {
    MarginAccount takerAccount;
    MarginAccount makerAccount;
    int256 lpFee;
    int256 vaultFee;
    int256 operatorFee;
    int256 tradingPrice;
}

struct Settings {
    int256 minimalMargin;
    int256 initialMarginRate;
    int256 maintenanceMarginRate;
    int256 vaultFeeRate;
    int256 operatorFeeRate;
    int256 liquidatorPenaltyRate;
    int256 liquidationGasReserve;
    int256 fundPenaltyRate;
    int256 lpFee;
}

struct AMMSettings {
    int256 halfSpreadRate;
    int256 beta;
    int256 beta2;
    int256 lpFeeRate;
    int256 baseFundingRate;
    int256 targetLeverage;
}

struct MarginAccount {
    int256 cashBalance;
    int256 positionAmount;
    int256 entrySocialLoss;
    int256 entryFundingLoss;
}

struct LiquidationProviderAccount {
    int256 entryInsuranceFund;
}

struct State {
    bool emergency;
    bool shutdown;
    int256 markPrice; // slow
    int256 indexPrice; // fast
    int256 unitSocialLoss;
    int256 unitAccumulatedFundingLoss;
    int256 totalPositionAmount;
    int256 insuranceFund;
}

struct AccessControl {
    mapping (address => bytes32) privileges;
}

struct Perpetual {
    string symbol;
    address vault;
    address operator;
    address oracle;
    State state;
    AMMSettings ammSettings;
    Settings settings;
    MarginAccount ammAccount;
    mapping(address => MarginAccount) traderAccounts;
    mapping(address => LiquidationProviderAccount) lpAccounts;
    mapping(address => mapping(address => bytes32)) accessControls;
}