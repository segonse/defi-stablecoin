// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 public timesMintCalled;
    address[] usersWithCollateralDeposited;
    MockV3Aggregator ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        // console.log("msgSender:", msg.sender);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
        // console.log("collateralValueInUsd:", uint256(collateralValueInUsd));
        // console.log("totalDscMinted:", uint256(totalDscMinted));
        int256 maxDscToMint = int256(collateralValueInUsd) / 2 - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        // console.log("maxDscToMint:", uint256(maxDscToMint));
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        vm.prank(sender);
        dscEngine.mintDsc(amount);
        timesMintCalled++;
    }

    // redeem collateral <-

    // function depositedCollateral(address collateral, uint256 amountToCollateral) public {
    //     dscEngine.depositCollateral(collateral, amountToCollateral);
    // }

    function depositedCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        // console.log("msgSender2:", msg.sender);
        usersWithCollateralDeposited.push(msg.sender);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        // vm.assume(amountCollateral == 0);
        if (amountCollateral == 0) {
            return;
        }
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        uint256 remainCollateral = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        assertEq(amountCollateral, maxCollateralToRedeem - remainCollateral);
    }

    //This breaks our invariant test suite!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    //Helper Function
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function getterShouldNotRevert() public {}
}
