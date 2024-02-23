// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";

contract DSCEngineTest is Test {
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STRATING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;

    address public USER = makeAddr("user");

    DeployDSC deployDSC;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    address[] tokenAddresses;
    address[] priceFeedAddress;

    function setUp() external {
        deployDSC = new DeployDSC();
        (dsc, dscEngine, config) = deployDSC.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STRATING_ERC20_BALANCE);
    }

    ///////////////////////////
    // Constructor Tests   ////
    ///////////////////////////
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddress.push(ethUsdPriceFeed);
        priceFeedAddress.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAddressMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddress, address(dsc));
    }

    /////////////////////
    // Price Tests   ////
    /////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 exceptedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(exceptedWeth, actualWeth);
    }

    /////////////////////////////////
    // depositCollateral Tests   ////
    /////////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testRevertsIfUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", USER, STRATING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(randToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedDepositedCollateral = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedCollateral, AMOUNT_COLLATERAL);
    }

    function testRevertsIfDepositCollateralAndMintDscBreaksHealthFactor() public {
        uint256 overageMintDscAmount = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(overageMintDscAmount, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, overageMintDscAmount);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    /////////////////////
    // mintDsc Tests  ///
    /////////////////////
    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintFails() public {
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddress = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddress, address(mockDsc));
        mockDsc.transferOwnership(address(mockDscEngine));
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testRevertsIfMintDscBreaksHealthFactor() public depositedCollateral {
        uint256 overageMintDscAmount = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(overageMintDscAmount, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL));
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.mintDsc(overageMintDscAmount);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        dscEngine.mintDsc(AMOUNT_TO_MINT);

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    /////////////////////
    // burnDsc Tests  ///
    /////////////////////
    function testRevertsIfBurnAmountIsZero() public depositedCollateralAndMintDsc {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
    }

    function testCanBurnAmountThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_TO_MINT);
        dscEngine.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }
}
