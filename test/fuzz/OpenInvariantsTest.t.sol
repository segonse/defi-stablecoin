// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Handler} from "./Handler.t.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployDSC;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() external {
        deployDSC = new DeployDSC();
        (dsc, dscEngine, config) = deployDSC.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value:", wethValue);
        console.log("wbtc value:", wbtcValue);
        console.log("total supply:", totalSupply);
        console.log("Times mint called:", handler.timesMintCalled());
        assert(wethValue + wbtcValue >= totalSupply);
    }
}
