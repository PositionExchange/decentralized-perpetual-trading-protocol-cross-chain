// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title Errors libraries
 * @author Position Exchange
 * @notice Defines the error messages emitted by the different contracts of the Position Exchange protocol
 * @dev Error messages prefix glossary:
 *  - VL = ValidationLogic
 *  - MATH = Math libraries
 *  - CT = Common errors between tokens (AToken, VariableDebtToken and StableDebtToken)
 *  - P = Pausable
 *  - A = Amm
 */
library Errors {
    //common errors

    //contract specific errors
    //    string public constant VL_INVALID_AMOUNT = '1'; // 'Amount must be greater than 0'
    string public constant VL_EMPTY_ADDRESS = "2";
    string public constant VL_INVALID_QUANTITY = "3"; // 'IQ'
    string public constant VL_INVALID_LEVERAGE = "4"; // 'IL'
    string public constant VL_INVALID_CLOSE_QUANTITY = "5"; // 'ICQ'
    string public constant VL_INVALID_CLAIM_FUND = "6"; // 'ICF'
    string public constant VL_NOT_ENOUGH_MARGIN_RATIO = "7"; // 'NEMR'
    string public constant VL_NO_POSITION_TO_REMOVE = "8"; // 'NPTR'
    string public constant VL_NO_POSITION_TO_ADD = "9"; // 'NPTA'
    string public constant VL_INVALID_QUANTITY_INTERNAL_CLOSE = "10"; // 'IQIC'
    string public constant VL_NOT_ENOUGH_LIQUIDITY = "11"; // 'NELQ'
    string public constant VL_INVALID_REMOVE_MARGIN = "12"; // 'IRM'
    string public constant VL_NOT_COUNTERPARTY = "13"; // 'IRM'
    string public constant VL_INVALID_INPUT = "14"; // 'IP'
    string public constant VL_SETTLE_FUNDING_TOO_EARLY = "15"; // 'SFTE'
    string public constant VL_LONG_PRICE_THAN_CURRENT_PRICE = "16"; // '!B'
    string public constant VL_SHORT_PRICE_LESS_CURRENT_PRICE = "17"; // '!S'
    string public constant VL_INVALID_SIZE = "18"; // ''
    string public constant VL_NOT_WHITELIST_MANAGER = "19"; // ''
    string public constant VL_INVALID_ORDER = "20"; // ''
    string public constant VL_ONLY_PENDING_ORDER = "21"; // ''
    string public constant VL_MUST_SAME_SIDE_SHORT = "22.1";
    string public constant VL_MUST_SAME_SIDE_LONG = "22.2";
    string public constant VL_MUST_SMALLER_REVERSE_QUANTITY = "23";
    string public constant VL_MUST_CLOSE_TO_INDEX_PRICE_SHORT = "24.1";
    string public constant VL_MUST_CLOSE_TO_INDEX_PRICE_LONG = "24.2";
    string public constant VL_MARKET_ORDER_MUST_CLOSE_TO_INDEX_PRICE = "25";
    string public constant VL_EXCEED_MAX_NOTIONAL = "26";
    string public constant VL_MUST_HAVE_POSITION = "27";
    string public constant VL_MUST_REACH_CONDITION = "28";
    string public constant VL_ONLY_POSITION_STRATEGY_ORDER = "29";
    string public constant VL_ONLY_POSITION_HOUSE = "30";
    string public constant VL_ONLY_VALIDATED_TRIGGERS = "31";
    string public constant VL_INVALID_CONDITION = "32";
    string public constant VL_MUST_BE_INTEGER = "33";

    string public constant V_TOKEN_NOT_WHITELISTED = "V-01";
    string public constant V_CALLER_NOT_WHITELISTED = "V-02";
    string public constant V_COLLATERAL_LESS_THAN_FEE = "V-03";
    string public constant V_MISSING_VAULT_UTILS = "V-04";
    string public constant V_MISSING_VAULT_PRICE_FEED = "V-05";
    string public constant V_MIN_BORROWING_RATE_NOT_REACHED = "V-06";
    string public constant V_MAX_BORROWING_RATE_EXCEEDED = "V-06";
    string public constant V_MAX_BORROWING_RATE_FACTOR_EXCEEDED = "V-07";
    string public constant V_DEPOSIT_AMOUNT_IS_ZERO = "V-08";
    string public constant V_WITHDRAW_AMOUNT_IS_ZERO = "V-09";
    string public constant V_USDP_AMOUNT_IS_ZERO = "V-10";
    string public constant V_REDEMPTION_AMOUNT_IS_ZERO = "V-11";
    string public constant V_SWAP_IS_NOT_SUPPORTED = "V-12";
    string public constant V_DUPLICATE_TOKENS = "V-13";
    string public constant V_INSUFFICIENT_BALANCE = "V-14";
    string public constant V_INSUFFICIENT_POOL_AMOUNT = "V-15";
    string public constant V_MAX_SHORTS_EXCEEDED = "V-16";
    string public constant V_ONLY_FUTURX_GATEWAY = "V-17";
    string public constant V_MAX_GAS_PRICE_EXCEEDED = "V-18";

    string public constant FGW_TOKEN_IS_NOT_ETH = "FGW-01";
    string public constant FGW_NOT_OWNER_OF_ORDER = "FGW-02";
    string public constant FGW_CALLER_NOT_WHITELISTED = "FGW-03";
    string public constant FGW_INDEX_TOKEN_IS_EMPTY = "FGW-04";
    string public constant FGW_COLLATERAL_TOKEN_IS_EMPTY = "FGW-05";
    string public constant FGW_INVALID_PATH_LENGTH = "FGW-06";

    string public constant FGWS_CALLER_NOT_WHITELISTED = "FGWS-01";
    string public constant FGWS_PENDING_COLLATERAL_MISMATCHED = "FGWS-02";
    string public constant FGWS_MISSING_ACCOUNT_01 = "FGWS-03";
    string public constant FGWS_MISSING_ACCOUNT_02 = "FGWS-04";
    string public constant FGWS_MISSING_ACCOUNT_03 = "FGWS-05";
    string public constant FGWS_MISSING_ACCOUNT_04 = "FGWS-06";

    string public constant FGWU_EXECUTION_FEE_MISMATCHED = "FGWU-40001";
    string public constant FGWU_INVALID_PATH_LENGTH = "FGWU-40002";
    string public constant FGWU_MIN_LEVERAGE_NOT_REACHED = "FGWU-40002";
    string public constant FGWU_VOUCHER_IS_INACTIVE = "FGWU-40002";
    string public constant FGWU_VOUCHER_IS_EXPIRED = "FGWU-40002";
    string public constant FGWU_VOUCHER_MINIMUM_TIME_NOT_MET = "FGWU-40002";
    string public constant FGWU_INSUFFICIENT_AMOUNT_01 = "FGWU-40002";
    string public constant FGWU_INSUFFICIENT_AMOUNT_02 = "FGWU-40002";
    string public constant FGWU_COLLATERAL_AND_INDEX_MISMATCHED = "FGWU-40002";
    string public constant FGWU_COLLATERAL_IS_NOT_WHITELISTED_01 = "FGWU-40002";
    string public constant FGWU_COLLATERAL_IS_NOT_WHITELISTED_02 = "FGWU-40002";
    string public constant FGWU_COLLATERAL_MUST_NOT_BE_STABLE = "FGWU-40002";
    string public constant FGWU_COLLATERAL_MUST_BE_STABLE = "FGWU-40002";
    string public constant FGWU_INDEX_TOKEN_MUST_NOT_BE_STABLE = "FGWU-40002";
    string public constant FGWU_INDEX_TOKEN_MUST_BE_SHORTABLE = "FGWU-40002";
    string public constant FGWU_INVALID_POSITION_COLLATERAL = "FGWU-40002";
    string public constant FGWU_INVALID_PENDING_COLLATERAL = "FGWU-40002";
    string public constant FGWU_MINIMUM_SIZE_NOT_REACHED = "FGWU-40002";
    string public constant FGWU_INVALID_STEP_BASE_SIZE = "FGWU-40002";
    string public constant FGWU_INSUFFICIENT_RESERVED_AMOUNT = "FGWU-50002";

    enum CollateralManagerErrors {
        NO_ERROR
    }
}
