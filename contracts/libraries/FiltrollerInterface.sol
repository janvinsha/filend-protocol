// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

abstract contract FiltrollerInterface {
    /**
     * @notice Marker function used for light validation when updating the Filtroller of a market
     * @dev Implementations should simply return true.
     * @return true
     */
   bool public constant isFiltroller = true;

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata fTokens) virtual external returns (uint[] memory);
    function exitMarket(address fToken) virtual external returns (uint);

    /*** Policy Hooks ***/

    function mintAllowed(address fToken, address minter, uint mintAmount) virtual external returns (uint);
    function mintVerify(address fToken, address minter, uint mintAmount, uint mintTokens) virtual external;

    function redeemAllowed(address fToken, address redeemer, uint redeemTokens) virtual external returns (uint);
    function redeemVerify(address fToken, address redeemer, uint redeemAmount, uint redeemTokens) virtual external;

    function borrowAllowed(address fToken, address borrower, uint borrowAmount) virtual external returns (uint);
    function borrowVerify(address fToken, address borrower, uint borrowAmount) virtual external;

    function repayBorrowAllowed(
        address fToken,
        address payer,
        address borrower,
        uint repayAmount) virtual  external returns (uint);
    function repayBorrowVerify(
        address fToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex) virtual external;

    function liquidateBorrowAllowed(
        address fTokenBorrowed,
        address fTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) virtual external returns (uint);
    function liquidateBorrowVerify(
        address fTokenBorrowed,
        address fTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens) virtual external;

    function seizeAllowed(
        address fTokenCollateral,
        address fTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) virtual external returns (uint);
    function seizeVerify(
        address fTokenCollateral,
        address fTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) virtual external;

    function transferAllowed(address fToken, address src, address dst, uint transferTokens)virtual external returns (uint);
    function transferVerify(address fToken, address src, address dst, uint transferTokens) virtual external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address fTokenBorrowed,
        address fTokenCollateral,
        uint repayAmount) virtual external view returns (uint, uint);
}
