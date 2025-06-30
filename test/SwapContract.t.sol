// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Test, console} from "forge-std/Test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

contract SwapContract {
    // mainnet constants
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV3Factory public constant FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IQuoter public constant QUOTER = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant SXT = 0xE6Bfd33F52d82Ccb5b37E16D3dD81f9FFDAbB195;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address[4] public connectors;
    uint24[4] public fees;
    uint256 private constant DENOM = 1_000_000;
    uint256 private constant Q96 = 2 ** 96;
    uint256 private constant SLIPPAGE_BPS = 100; // 1%

    constructor() {
        connectors = [WETH, USDT, USDC, SXT];
        fees = [100, 500, 3_000, 10_000]; // 0.01%, 0.05%, 0.3%, 1%
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        uint256 balanceBefore = IERC20(tokenIn).balanceOf(address(this));

        SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);
        SafeERC20.safeIncreaseAllowance(IERC20(tokenIn), address(ROUTER), amountIn);

        (bytes memory bestPath, uint256 quote) = _findBestPath(tokenIn, tokenOut, amountIn);

        uint256 minOut = (quote * (10_000 - SLIPPAGE_BPS)) / 10_000;

        ISwapRouter.ExactInputParams memory p = ISwapRouter.ExactInputParams({
            path: bestPath,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });
        amountOut = ROUTER.exactInput(p);

        require(IERC20(tokenIn).balanceOf(address(this)) == balanceBefore, "balance should not change");
    }

    function _pool(address t0, address t1, uint24 fee) private view returns (address, uint24) {
        address pool = FACTORY.getPool(t0, t1, fee);
        return (pool, fee);
    }

    function _findBestPath(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        returns (bytes memory bestPath, uint256 bestOut)
    {
        unchecked {
            for (uint256 i; i < fees.length; ++i) {
                (address pool, uint24 fee) = _pool(tokenIn, tokenOut, fees[i]);
                if (pool == address(0)) continue;
                uint256 out = _quote(amountIn, pool, tokenIn, fee);
                if (out > bestOut) {
                    bestOut = out;
                    bestPath = abi.encodePacked(tokenIn, fee, tokenOut);
                }
            }

            for (uint256 c; c < connectors.length; ++c) {
                address mid = connectors[c];
                if (mid == tokenIn || mid == tokenOut) continue;

                for (uint256 f0; f0 < fees.length; ++f0) {
                    (address p01, uint24 fee01) = _pool(tokenIn, mid, fees[f0]);
                    if (p01 == address(0)) continue;

                    uint256 out01 = _quote(amountIn, p01, tokenIn, fee01);
                    if (out01 == 0) continue;

                    for (uint256 f1; f1 < fees.length; ++f1) {
                        (address p12, uint24 fee12) = _pool(mid, tokenOut, fees[f1]);
                        if (p12 == address(0)) continue;

                        uint256 out12 = _quote(out01, p12, mid, fee12);
                        if (out12 > bestOut) {
                            bestOut = out12;
                            bestPath = abi.encodePacked(tokenIn, fee01, mid, fee12, tokenOut);
                        }
                    }
                }
            }
        }
    }

    function _quote(uint256 amountIn, address pool, address tokenIn, uint24 fee)
        private
        view
        returns (uint256 amountOut)
    {
        // (uint160 sqrtP,,,,,,) = IUniswapV3Pool(pool).slot0();

        // uint256 px = uint256(sqrtP) * uint256(sqrtP); // Q192

        // if (tokenIn == IUniswapV3Pool(pool).token0()) {
        //     amountOut = Math.mulDiv(amountIn, px, Q96 * Q96);
        // } else {
        //     amountOut = Math.mulDiv(amountIn, Q96 * Q96, px);
        // }
        // amountOut = Math.mulDiv(amountOut, DENOM - fee, DENOM);

        amountOut = amountIn - uint256(fee);
    }
}

contract SwapContractTest is Test {
    SwapContract public swapContract;

    address _router;
    address _user;

    address _usdt;
    address _sxt;
    address _usdc;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 22790000); // mainnet fork for all tests here

        swapContract = new SwapContract();
        _sxt = swapContract.SXT();
        _usdt = swapContract.USDT();
        _usdc = swapContract.USDC();
        _router = address(swapContract.ROUTER());
        _user = address(0xF977814e90dA44bFA03b6295A0616a897441aceC); // binance exchange hot wallet

        console.log("SXT", IERC20(_sxt).balanceOf(_user));
        console.log("USDT", IERC20(_usdt).balanceOf(_user));
        console.log("USDC", IERC20(_usdc).balanceOf(_user));
    }

    // one hop swap
    // SXT -> USDT
    // gas: 246738
    function testSwap() public {
        address tokenIn = _sxt;
        address tokenOut = _usdt;
        uint256 tokenInAmount = 1_000 * 1e18;

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_user);

        vm.startPrank(_user);

        IERC20(tokenIn).approve(address(swapContract), tokenInAmount);
        uint256 amountOut = swapContract.swap(tokenIn, tokenOut, tokenInAmount);
        vm.stopPrank();

        console.log("amountOut", amountOut);
        console.log("SXT", IERC20(_sxt).balanceOf(_user));
        console.log("USDT", IERC20(_usdt).balanceOf(_user));
        console.log("USDC", IERC20(_usdc).balanceOf(_user));

        assertGt(amountOut, 0);
        assertGt(IERC20(tokenOut).balanceOf(_user), balanceBefore);
        assertEq(IERC20(tokenOut).balanceOf(_user), balanceBefore + amountOut);
    }

    // two hop swap
    // SXT -> USDT -> USDC
    // gas: 324241
    function testSwapTwoHop() public {
        uint256 tokenInAmount = 1_000 * 1e18;

        vm.startPrank(_user);
        address tokenIn = _sxt;
        address tokenOut = _usdc;

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(_user);

        IERC20(tokenIn).approve(address(swapContract), tokenInAmount);
        uint256 amountOut = swapContract.swap(tokenIn, tokenOut, tokenInAmount);
        vm.stopPrank();

        console.log("SXT", IERC20(_sxt).balanceOf(_user));
        console.log("USDT", IERC20(_usdt).balanceOf(_user));
        console.log("USDC", IERC20(_usdc).balanceOf(_user));

        assertGt(amountOut, 0);
        assertGt(IERC20(tokenOut).balanceOf(_user), balanceBefore);
    }
}
