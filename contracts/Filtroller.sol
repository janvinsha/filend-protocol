// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./FToken.sol";
import "./libraries/ErrorReporter.sol";
import "./libraries/Exponential.sol";
import "./PriceOracle.sol";
import "./libraries/FiltrollerInterface.sol";
import "./libraries/FiltrollerStorage.sol";
import "./Unitroller.sol";
import "./Governance/Fil.sol";

/**
 * @title Filend's Filtroller Contract
 * @author Filend
 */


 contract Filtroller is FiltrollerV3Storage, FiltrollerInterface, FiltrollerErrorReporter, Exponential {
    /// @notice Emitted when an admin supports a market
    event MarketListed(FToken fToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(FToken fToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(FToken fToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(FToken fToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint oldLiquidationIncentiveMantissa, uint newLiquidationIncentiveMantissa);

    /// @notice Emitted when maxAssets is changed by admin
    event NewMaxAssets(uint oldMaxAssets, uint newMaxAssets);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(FToken fToken, string action, bool pauseState);

    /// @notice Emitted when market filed status is changed
    event MarketFiled(FToken fToken, bool isFiled);

    /// @notice Emitted when FIL rate is changed
    event NewFilRate(uint oldFilRate, uint newFilRate);

    /// @notice Emitted when a new FIL speed is calculated for a market
    event FilSpeedUpdated(FToken indexed fToken, uint newSpeed);

    /// @notice Emitted when FIL is distributed to a supplier
    event DistributedSupplierFil(FToken indexed fToken, address indexed supplier, uint filDelta, uint filSupplyIndex);

    /// @notice Emitted when FIL is distributed to a borrower
    event DistributedBorrowerFil(FToken indexed fToken, address indexed borrower, uint filDelta, uint filBorrowIndex);

    /// @notice The threshold above which the flywheel transfers FIL, in wei
    uint public constant filClaimThreshold = 0.001e18;

    /// @notice The initial Fil index for a market
    uint224 public constant filInitialIndex = 1e36;

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    // liquidationIncentiveMantissa must be no less than this value
    uint internal constant liquidationIncentiveMinMantissa = 1.0e18; // 1.0

    // liquidationIncentiveMantissa must be no greater than this value
    uint internal constant liquidationIncentiveMaxMantissa = 1.5e18; // 1.5

    constructor() public {
        admin = msg.sender;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (FToken[] memory) {
        FToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param fToken The fToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, FToken fToken) external view returns (bool) {
        return markets[address(fToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param fTokens The list of addresses of the fToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(address[] memory fTokens) override public returns (uint[] memory) {
        uint len = fTokens.length;

        uint[] memory results = new uint[](len);
        for (uint i = 0; i < len; i++) {
            FToken fToken = FToken(fTokens[i]);

            results[i] = uint(addToMarketInternal(fToken, msg.sender));
        }

        return results;
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param fToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(FToken fToken, address borrower) internal returns (Error) {
        Market storage marketToJoin = markets[address(fToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return Error.NO_ERROR;
        }

        if (accountAssets[borrower].length >= maxAssets)  {
            // no space, cannot join
            return Error.TOO_MANY_ASSETS;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(fToken);

        emit MarketEntered(fToken, borrower);

        return Error.NO_ERROR;
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing neccessary collateral for an outstanding borrow.
     * @param fTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    function exitMarket(address fTokenAddress) override external returns (uint) {
        FToken fToken = FToken(fTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the fToken */
        (uint oErr, uint tokensHeld, uint amountOwed, ) = fToken.getAccountSnapshot(msg.sender);
        require(oErr == 0, "exitMarket: getAccountSnapshot failed"); // semi-opaque error code

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            return fail(Error.NONZERO_BORROW_BALANCE, FailureInfo.EXIT_MARKET_BALANCE_OWED);
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint allowed = redeemAllowedInternal(fTokenAddress, msg.sender, tokensHeld);
        if (allowed != 0) {
            return failOpaque(Error.REJECTION, FailureInfo.EXIT_MARKET_REJECTION, allowed);
        }

        Market storage marketToExit = markets[address(fToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return uint(Error.NO_ERROR);
        }

        /* Set fToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete fToken from the account’s list of assets */
        // load into memory for faster iteration
        FToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == fToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        FToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(fToken, msg.sender);

        return uint(Error.NO_ERROR);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param fToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(address fToken, address minter, uint mintAmount) override external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[fToken], "mint is paused");

        // Shh - currently unused
        minter;
        mintAmount;

        if (!markets[fToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        updateFilSupplyIndex(fToken);
        distributeSupplierFil(fToken, minter, false);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param fToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(address fToken, address minter, uint actualMintAmount, uint mintTokens) override external {
        // Shh - currently unused
        fToken;
        minter;
        actualMintAmount;
        mintTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param fToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of fTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowed(address fToken, address redeemer, uint redeemTokens) override external returns (uint) {
        uint allowed = redeemAllowedInternal(fToken, redeemer, redeemTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateFilSupplyIndex(fToken);
        distributeSupplierFil(fToken, redeemer, false);

        return uint(Error.NO_ERROR);
    }

    function redeemAllowedInternal(address fToken, address redeemer, uint redeemTokens) internal view returns (uint) {
        if (!markets[fToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[fToken].accountMembership[redeemer]) {
            return uint(Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, FToken(fToken), redeemTokens, 0);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param fToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(address fToken, address redeemer, uint redeemAmount, uint redeemTokens) override external {
        // Shh - currently unused
        fToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param fToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function borrowAllowed(address fToken, address borrower, uint borrowAmount) override external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[fToken], "borrow is paused");

        if (!markets[fToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (!markets[fToken].accountMembership[borrower]) {
            // only fTokens may call borrowAllowed if borrower not in market
            require(msg.sender == fToken, "sender must be fToken");

            // attempt to add borrower to the market
            Error err = addToMarketInternal(FToken(msg.sender), borrower);
            if (err != Error.NO_ERROR) {
                return uint(err);
            }

            // it should be impossible to break the important invariant
            assert(markets[fToken].accountMembership[borrower]);
        }

        if (oracle.getUnderlyingPrice(FToken(fToken)) == 0) {
            return uint(Error.PRICE_ERROR);
        }

        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, FToken(fToken), 0, borrowAmount);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({mantissa: FToken(fToken).borrowIndex()});
        updateFilBorrowIndex(fToken, borrowIndex);
        distributeBorrowerFil(fToken, borrower, borrowIndex, false);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param fToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(address fToken, address borrower, uint borrowAmount) override external {
        // Shh - currently unused
        fToken;
        borrower;
        borrowAmount;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param fToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function repayBorrowAllowed(
        address fToken,
        address payer,
        address borrower,
        uint repayAmount) override external returns (uint) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;

        if (!markets[fToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({mantissa: FToken(fToken).borrowIndex()});
        updateFilBorrowIndex(fToken, borrowIndex);
        distributeBorrowerFil(fToken, borrower, borrowIndex, false);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param fToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address fToken,
        address payer,
        address borrower,
        uint actualRepayAmount,
        uint borrowerIndex) override external {
        // Shh - currently unused
        fToken;
        payer;
        borrower;
        actualRepayAmount;
        borrowerIndex;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param fTokenBorrowed Asset which was borrowed by the borrower
     * @param fTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address fTokenBorrowed,
        address fTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) override external returns (uint) {
        // Shh - currently unused
        liquidator;

        if (!markets[fTokenBorrowed].isListed || !markets[fTokenCollateral].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        (Error err, , uint shortfall) = getAccountLiquidityInternal(borrower);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall == 0) {
            return uint(Error.INSUFFICIENT_SHORTFALL);
        }

        /* The liquidator may not repay more than what is allowed by the closeFactor */
        uint borrowBalance = FToken(fTokenBorrowed).borrowBalanceStored(borrower);
        (MathError mathErr, uint maxClose) = mulScalarTruncate(Exp({mantissa: closeFactorMantissa}), borrowBalance);
        if (mathErr != MathError.NO_ERROR) {
            return uint(Error.MATH_ERROR);
        }
        if (repayAmount > maxClose) {
            return uint(Error.TOO_MUCH_REPAY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param fTokenBorrowed Asset which was borrowed by the borrower
     * @param fTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function liquidateBorrowVerify(
        address fTokenBorrowed,
        address fTokenCollateral,
        address liquidator,
        address borrower,
        uint actualRepayAmount,
        uint seizeTokens) override external {
        // Shh - currently unused
        fTokenBorrowed;
        fTokenCollateral;
        liquidator;
        borrower;
        actualRepayAmount;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param fTokenCollateral Asset which was used as collateral and will be seized
     * @param fTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address fTokenCollateral,
        address fTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) override external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (!markets[fTokenCollateral].isListed || !markets[fTokenBorrowed].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (FToken(fTokenCollateral).filtroller() != FToken(fTokenBorrowed).filtroller()) {
            return uint(Error.FILTROLLER_MISMATCH);
        }

        // Keep the flywheel moving
        updateFilSupplyIndex(fTokenCollateral);
        distributeSupplierFil(fTokenCollateral, borrower, false);
        distributeSupplierFil(fTokenCollateral, liquidator, false);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param fTokenCollateral Asset which was used as collateral and will be seized
     * @param fTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address fTokenCollateral,
        address fTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) override external {
        // Shh - currently unused
        fTokenCollateral;
        fTokenBorrowed;
        liquidator;
        borrower;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param fToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of fTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function transferAllowed(address fToken, address src, address dst, uint transferTokens) override external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint allowed = redeemAllowedInternal(fToken, src, transferTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateFilSupplyIndex(fToken);
        distributeSupplierFil(fToken, src, false);
        distributeSupplierFil(fToken, dst, false);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param fToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of fTokens to transfer
     */
    function transferVerify(address fToken, address src, address dst, uint transferTokens) override external {
        // Shh - currently unused
        fToken;
        src;
        dst;
        transferTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `fTokenBalance` is the number of fTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint fTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code (semi-opaque),
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account) public view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, FToken(address(0)), 0, 0);

        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code,
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account) internal view returns (Error, uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, FToken(address(0)), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param fTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code (semi-opaque),
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address fTokenModify,
        uint redeemTokens,
        uint borrowAmount) public view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, FToken(fTokenModify), redeemTokens, borrowAmount);
        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param fTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral fToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        FToken fTokenModify,
        uint redeemTokens,
        uint borrowAmount) internal view returns (Error, uint, uint) {

        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;
        MathError mErr;

        // For each asset the account is in
        FToken[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            FToken asset = assets[i];

            // Read the balances and exchange rate from the fToken
            (oErr, vars.fTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account);
            if (oErr != 0) { // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (Error.SNAPSHOT_ERROR, 0, 0);
            }
            vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0);
            }
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            (mErr, vars.tokensToDenom) = mulExp3(vars.collateralFactor, vars.exchangeRate, vars.oraclePrice);
            if (mErr != MathError.NO_ERROR) {
                return (Error.MATH_ERROR, 0, 0);
            }

            // sumCollateral += tokensToDenom * fTokenBalance
            (mErr, vars.sumCollateral) = mulScalarTruncateAddUInt(vars.tokensToDenom, vars.fTokenBalance, vars.sumCollateral);
            if (mErr != MathError.NO_ERROR) {
                return (Error.MATH_ERROR, 0, 0);
            }

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);
            if (mErr != MathError.NO_ERROR) {
                return (Error.MATH_ERROR, 0, 0);
            }

            // Calculate effects of interacting with fTokenModify
            if (asset == fTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);
                if (mErr != MathError.NO_ERROR) {
                    return (Error.MATH_ERROR, 0, 0);
                }

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
                if (mErr != MathError.NO_ERROR) {
                    return (Error.MATH_ERROR, 0, 0);
                }
            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in fToken.liquidateBorrowFresh)
     * @param fTokenBorrowed The address of the borrowed fToken
     * @param fTokenCollateral The address of the collateral fToken
     * @param actualRepayAmount The amount of fTokenBorrowed underlying to convert into fTokenCollateral tokens
     * @return (errorCode, number of fTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(address fTokenBorrowed, address fTokenCollateral, uint actualRepayAmount) override external view returns (uint, uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = oracle.getUnderlyingPrice(FToken(fTokenBorrowed));
        uint priceCollateralMantissa = oracle.getUnderlyingPrice(FToken(fTokenCollateral));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = FToken(fTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;
        MathError mathErr;

        (mathErr, numerator) = mulExp(liquidationIncentiveMantissa, priceBorrowedMantissa);
        if (mathErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0);
        }

        (mathErr, denominator) = mulExp(priceCollateralMantissa, exchangeRateMantissa);
        if (mathErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0);
        }

        (mathErr, ratio) = divExp(numerator, denominator);
        if (mathErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0);
        }

        (mathErr, seizeTokens) = mulScalarTruncate(ratio, actualRepayAmount);
        if (mathErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0);
        }

        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /*** Admin Functions ***/

    /**
      * @notice Sets a new price oracle for the filtroller
      * @dev Admin function to set a new price oracle
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _setPriceOracle(PriceOracle newOracle) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK);
        }

        // Track the old oracle for the filtroller
        PriceOracle oldOracle = oracle;

        // Set filtroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets the closeFactor used when liquidating borrows
      * @dev Admin function to set closeFactor
      * @param newCloseFactorMantissa New close factor, scaled by 1e18
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_CLOSE_FACTOR_OWNER_CHECK);
        }

        Exp memory newCloseFactorExp = Exp({mantissa: newCloseFactorMantissa});
        Exp memory lowLimit = Exp({mantissa: closeFactorMinMantissa});
        if (lessThanOrEqualExp(newCloseFactorExp, lowLimit)) {
            return fail(Error.INVALID_CLOSE_FACTOR, FailureInfo.SET_CLOSE_FACTOR_VALIDATION);
        }

        Exp memory highLimit = Exp({mantissa: closeFactorMaxMantissa});
        if (lessThanExp(highLimit, newCloseFactorExp)) {
            return fail(Error.INVALID_CLOSE_FACTOR, FailureInfo.SET_CLOSE_FACTOR_VALIDATION);
        }

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets the collateralFactor for a market
      * @dev Admin function to set per-market collateralFactor
      * @param fToken The market to set the factor on
      * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setCollateralFactor(FToken fToken, uint newCollateralFactorMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK);
        }

        // Verify market is listed
        Market storage market = markets[address(fToken)];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        // If collateral factor != 0, fail if price == 0
        if (newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(fToken) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(fToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets maxAssets which controls how many markets can be entered
      * @dev Admin function to set maxAssets
      * @param newMaxAssets New max assets
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setMaxAssets(uint newMaxAssets) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_MAX_ASSETS_OWNER_CHECK);
        }

        uint oldMaxAssets = maxAssets;
        maxAssets = newMaxAssets;
        emit NewMaxAssets(oldMaxAssets, newMaxAssets);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets liquidationIncentive
      * @dev Admin function to set liquidationIncentive
      * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);
        }

        // Check de-scaled min <= newLiquidationIncentive <= max
        Exp memory newLiquidationIncentive = Exp({mantissa: newLiquidationIncentiveMantissa});
        Exp memory minLiquidationIncentive = Exp({mantissa: liquidationIncentiveMinMantissa});
        if (lessThanExp(newLiquidationIncentive, minLiquidationIncentive)) {
            return fail(Error.INVALID_LIQUIDATION_INCENTIVE, FailureInfo.SET_LIQUIDATION_INCENTIVE_VALIDATION);
        }

        Exp memory maxLiquidationIncentive = Exp({mantissa: liquidationIncentiveMaxMantissa});
        if (lessThanExp(maxLiquidationIncentive, newLiquidationIncentive)) {
            return fail(Error.INVALID_LIQUIDATION_INCENTIVE, FailureInfo.SET_LIQUIDATION_INCENTIVE_VALIDATION);
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Add the market to the markets mapping and set it as listed
      * @dev Admin function to set isListed and add support for the market
      * @param fToken The address of the market (token) to list
      * @return uint 0=success, otherwise a failure. (See enum Error for details)
      */
    function _supportMarket(FToken fToken) external returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        if (markets[address(fToken)].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        fToken.isFToken(); // Sanity check to make sure its really a FToken

        Market storage newMarket = markets[address(fToken)];
        newMarket.isListed = true;
        newMarket.isFiled = false;
        newMarket.collateralFactorMantissa = 0;
        _addMarketInternal(address(fToken));

        emit MarketListed(fToken);

        return uint(Error.NO_ERROR);
    }

    function _addMarketInternal(address fToken) internal {
        for (uint i = 0; i < allMarkets.length; i ++) {
            require(allMarkets[i] != FToken(fToken), "market already added");
        }
        allMarkets.push(FToken(fToken));
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) public returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK);
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint(Error.NO_ERROR);
    }

    function _setMintPaused(FToken fToken, bool state) public returns (bool) {
        require(markets[address(fToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(fToken)] = state;
        emit ActionPaused(fToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(FToken fToken, bool state) public returns (bool) {
        require(markets[address(fToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(fToken)] = state;
        emit ActionPaused(fToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _become(Unitroller unitroller, uint filRate_, address[] memory filMarketsToAdd, address[] memory otherMarketsToAdd) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");

        Filtroller(address(unitroller))._becomeG3(filRate_, filMarketsToAdd, otherMarketsToAdd);
    }

    function _becomeG3(uint filRate_, address[] memory filMarketsToAdd, address[] memory otherMarketsToAdd) public {
        require(msg.sender == filtrollerImplementation, "only brains can become itself");

        for (uint i = 0; i < filMarketsToAdd.length; i++) {
            _addMarketInternal(address(filMarketsToAdd[i]));
        }

        for (uint i = 0; i < otherMarketsToAdd.length; i++) {
            _addMarketInternal(address(otherMarketsToAdd[i]));
        }

        _setFilRate(filRate_);
        _addFilMarkets(filMarketsToAdd);
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == filtrollerImplementation;
    }

    /*** Fil Distribution ***/

    /**
     * @notice Recalculate and update FIL speeds for all FIL markets
     */
    function refreshFilSpeeds() public {
        FToken[] memory allMarkets_ = allMarkets;

        for (uint i = 0; i < allMarkets_.length; i++) {
            FToken fToken = allMarkets_[i];
            Exp memory borrowIndex = Exp({mantissa: fToken.borrowIndex()});
            updateFilSupplyIndex(address(fToken));
            updateFilBorrowIndex(address(fToken), borrowIndex);
        }

        Exp memory totalUtility = Exp({mantissa: 0});
        Exp[] memory utilities = new Exp[](allMarkets_.length);
        for (uint i = 0; i < allMarkets_.length; i++) {
            FToken fToken = allMarkets_[i];
            if (markets[address(fToken)].isFiled) {
                Exp memory assetPrice = Exp({mantissa: oracle.getUnderlyingPrice(fToken)});
                Exp memory interestPerBlock = mul_(Exp({mantissa: fToken.borrowRatePerBlock()}), fToken.totalBorrows());
                Exp memory utility = mul_(interestPerBlock, assetPrice);
                utilities[i] = utility;
                totalUtility = add_(totalUtility, utility);
            }
        }

        for (uint i = 0; i < allMarkets_.length; i++) {
            FToken fToken = allMarkets[i];
            uint newSpeed = totalUtility.mantissa > 0 ? mul_(filRate, div_(utilities[i], totalUtility)) : 0;
            filSpeeds[address(fToken)] = newSpeed;
            emit FilSpeedUpdated(fToken, newSpeed);
        }
    }

    /**
     * @notice Accrue FIL to the market by updating the supply index
     * @param fToken The market whose supply index to update
     */
    function updateFilSupplyIndex(address fToken) internal {
        FilMarketState storage supplyState = filSupplyState[fToken];
        uint supplySpeed = filSpeeds[fToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, uint(supplyState.block));
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint supplyTokens = FToken(fToken).totalSupply();
            uint filAccrued = mul_(deltaBlocks, supplySpeed);
            Double memory ratio = supplyTokens > 0 ? fraction(filAccrued, supplyTokens) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: supplyState.index}), ratio);
            filSupplyState[fToken] = FilMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                block: safe32(blockNumber, "block number exceeds 32 bits")
            });
        } else if (deltaBlocks > 0) {
            supplyState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    /**
     * @notice Accrue FIL to the market by updating the borrow index
     * @param fToken The market whose borrow index to update
     */
    function updateFilBorrowIndex(address fToken, Exp memory marketBorrowIndex) internal {
        FilMarketState storage borrowState = filBorrowState[fToken];
        uint borrowSpeed = filSpeeds[fToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, uint(borrowState.block));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint borrowAmount = div_(FToken(fToken).totalBorrows(), marketBorrowIndex);
            uint filAccrued = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = borrowAmount > 0 ? fraction(filAccrued, borrowAmount) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: borrowState.index}), ratio);
            filBorrowState[fToken] = FilMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                block: safe32(blockNumber, "block number exceeds 32 bits")
            });
        } else if (deltaBlocks > 0) {
            borrowState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    /**
     * @notice Calculate FIL accrued by a supplier and possibly transfer it to them
     * @param fToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute FIL to
     */
    function distributeSupplierFil(address fToken, address supplier, bool distributeAll) internal {
        FilMarketState storage supplyState = filSupplyState[fToken];
        Double memory supplyIndex = Double({mantissa: supplyState.index});
        Double memory supplierIndex = Double({mantissa: filSupplierIndex[fToken][supplier]});
        filSupplierIndex[fToken][supplier] = supplyIndex.mantissa;

        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
            supplierIndex.mantissa = filInitialIndex;
        }

        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);
        uint supplierTokens = FToken(fToken).balanceOf(supplier);
        uint supplierDelta = mul_(supplierTokens, deltaIndex);
        uint supplierAccrued = add_(filAccrued[supplier], supplierDelta);
        filAccrued[supplier] = transferFil(supplier, supplierAccrued, distributeAll ? 0 : filClaimThreshold);
        emit DistributedSupplierFil(FToken(fToken), supplier, supplierDelta, supplyIndex.mantissa);
    }

    /**
     * @notice Calculate FIL accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param fToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute FIL to
     */
    function distributeBorrowerFil(address fToken, address borrower, Exp memory marketBorrowIndex, bool distributeAll) internal {
        FilMarketState storage borrowState = filBorrowState[fToken];
        Double memory borrowIndex = Double({mantissa: borrowState.index});
        Double memory borrowerIndex = Double({mantissa: filBorrowerIndex[fToken][borrower]});
        filBorrowerIndex[fToken][borrower] = borrowIndex.mantissa;

        if (borrowerIndex.mantissa > 0) {
            Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);
            uint borrowerAmount = div_(FToken(fToken).borrowBalanceStored(borrower), marketBorrowIndex);
            uint borrowerDelta = mul_(borrowerAmount, deltaIndex);
            uint borrowerAccrued = add_(filAccrued[borrower], borrowerDelta);
            filAccrued[borrower] = transferFil(borrower, borrowerAccrued, distributeAll ? 0 : filClaimThreshold);
            emit DistributedBorrowerFil(FToken(fToken), borrower, borrowerDelta, borrowIndex.mantissa);
        }
    }

    /**
     * @notice Transfer FIL to the user, if they are above the threshold
     * @dev Note: If there is not enough FIL, we do not perform the transfer all.
     * @param user The address of the user to transfer FIL to
     * @param userAccrued The amount of FIL to (possibly) transfer
     * @return The amount of FIL which was NOT transferred to the user
     */
    function transferFil(address user, uint userAccrued, uint threshold) internal returns (uint) {
        if (userAccrued >= threshold && userAccrued > 0) {
            Fil fil = Fil(getFilAddress());
            uint filRemaining = fil.balanceOf(address(this));
            if (userAccrued <= filRemaining) {
                fil.transfer(user, userAccrued);
                return 0;
            }
        }
        return userAccrued;
    }

    /**
     * @notice Claim all the fil accrued by holder in all markets
     * @param holder The address to claim FIL for
     */
    function claimFil(address holder) public {
        return claimFil(holder, allMarkets);
    }

    /**
     * @notice Claim all the fil accrued by holder in the specified markets
     * @param holder The address to claim FIL for
     * @param fTokens The list of markets to claim FIL in
     */
    function claimFil(address holder, FToken[] memory fTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimFil(holders, fTokens, true, true);
    }

    /**
     * @notice Claim all fil accrued by the holders
     * @param holders The addresses to claim FIL for
     * @param fTokens The list of markets to claim FIL in
     * @param borrowers Whether or not to claim FIL earned by borrowing
     * @param suppliers Whether or not to claim FIL earned by supplying
     */
    function claimFil(address[] memory holders, FToken[] memory fTokens, bool borrowers, bool suppliers) public {
        for (uint i = 0; i < fTokens.length; i++) {
            FToken fToken = fTokens[i];
            require(markets[address(fToken)].isListed, "market must be listed");
            if (borrowers == true) {
                Exp memory borrowIndex = Exp({mantissa: fToken.borrowIndex()});
                updateFilBorrowIndex(address(fToken), borrowIndex);
                for (uint j = 0; j < holders.length; j++) {
                    distributeBorrowerFil(address(fToken), holders[j], borrowIndex, true);
                }
            }
            if (suppliers == true) {
                updateFilSupplyIndex(address(fToken));
                for (uint j = 0; j < holders.length; j++) {
                    distributeSupplierFil(address(fToken), holders[j], true);
                }
            }
        }
    }

    /*** Fil Distribution Admin ***/

    /**
     * @notice Set the amount of FIL distributed per block
     * @param filRate_ The amount of FIL wei per block to distribute
     */
    function _setFilRate(uint filRate_) public {
        require(adminOrInitializing(), "only admin can change fil rate");

        uint oldRate = filRate;
        filRate = filRate_;
        emit NewFilRate(oldRate, filRate_);

        refreshFilSpeeds();
    }

    /**
     * @notice Add markets to filMarkets, allowing them to earn FIL in the flywheel
     * @param fTokens The addresses of the markets to add
     */
    function _addFilMarkets(address[] memory fTokens) public {
        require(adminOrInitializing(), "only admin can add fil market");

        for (uint i = 0; i < fTokens.length; i++) {
            _addFilMarketInternal(fTokens[i]);
        }

        refreshFilSpeeds();
    }

    function _addFilMarketInternal(address fToken) internal {
        Market storage market = markets[fToken];
        require(market.isListed == true, "fil market is not listed");
        require(market.isFiled == false, "fil market already added");

        market.isFiled = true;
        emit MarketFiled(FToken(fToken), true);

        if (filSupplyState[fToken].index == 0 && filSupplyState[fToken].block == 0) {
            filSupplyState[fToken] = FilMarketState({
                index: filInitialIndex,
                block: safe32(getBlockNumber(), "block number exceeds 32 bits")
            });
        }

        if (filBorrowState[fToken].index == 0 && filBorrowState[fToken].block == 0) {
            filBorrowState[fToken] = FilMarketState({
                index: filInitialIndex,
                block: safe32(getBlockNumber(), "block number exceeds 32 bits")
            });
        }
    }

    /**
     * @notice Remove a market from filMarkets, preventing it from earning FIL in the flywheel
     * @param fToken The address of the market to drop
     */
    function _dropFilMarket(address fToken) public {
        require(msg.sender == admin, "only admin can drop fil market");

        Market storage market = markets[fToken];
        require(market.isFiled == true, "market is not a fil market");

        market.isFiled = false;
        emit MarketFiled(FToken(fToken), false);

        refreshFilSpeeds();
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (FToken[] memory) {
        return allMarkets;
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    /**
     * @notice Return the address of the FIL token
     * @return The address of FIL
     */
    function getFilAddress() public view returns (address) {
        return 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    }
}
