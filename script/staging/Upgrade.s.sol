// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.21;

import { ScriptTools } from "../../lib/dss-test/src/ScriptTools.sol";

import { IERC20 }   from "../../lib/forge-std/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../lib/forge-std/src/interfaces/IERC4626.sol";
import { console }  from "../../lib/forge-std/src/console.sol";
import { Script }   from "../../lib/forge-std/src/Script.sol";
import { stdJson }  from "../../lib/forge-std/src/StdJson.sol";

import { Base }      from "../../lib/spark-address-registry/src/Base.sol";
import { Ethereum }  from "../../lib/spark-address-registry/src/Ethereum.sol";

import { CCTPForwarder } from "../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";

import { ControllerInstance }                   from "../../deploy/ControllerInstance.sol";
import { ForeignControllerInit as ForeignInit } from "../../deploy/ForeignControllerInit.sol";
import { MainnetControllerInit as MainnetInit } from "../../deploy/MainnetControllerInit.sol";

import { ForeignController } from "../../src/ForeignController.sol";
import { MainnetController } from "../../src/MainnetController.sol";
import { makeAddressKey }    from "../../src/RateLimitHelpers.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

interface IAccessControlLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

}

contract UpgradeMainnetController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        vm.createSelectFork(getChain("mainnet").rpcUrl);

        console.log("Upgrading mainnet controller...");

        string memory fileSlug = "mainnet-staging";

        address newController = vm.envAddress("NEW_CONTROLLER");
        address oldController = vm.envAddress("OLD_CONTROLLER");

        string memory inputConfig = ScriptTools.readInput(fileSlug);

        ControllerInstance memory controllerInst = ControllerInstance({
            almProxy   : inputConfig.readAddress(".almProxy"),
            controller : newController,
            rateLimits : inputConfig.readAddress(".rateLimits")
        });

        address[] memory relayers = new address[](2);
        relayers[0] = inputConfig.readAddress(".relayer");
        relayers[1] = inputConfig.readAddress(".backstopRelayer");

        MainnetInit.ConfigAddressParams memory configAddresses = MainnetInit.ConfigAddressParams({
            freezer       : inputConfig.readAddress(".freezer"),
            relayers      : relayers,
            oldController : oldController
        });

        MainnetInit.CheckAddressParams memory checkAddresses = MainnetInit.CheckAddressParams({
            admin      : inputConfig.readAddress(".admin"),
            proxy      : inputConfig.readAddress(".almProxy"),
            rateLimits : inputConfig.readAddress(".rateLimits")
        });

        address baseAlmProxy = ScriptTools.readInput("base-staging").readAddress(".almProxy");

        vm.startBroadcast();
        MainnetInit.upgradeController(controllerInst, configAddresses, checkAddresses);
        vm.stopBroadcast();

        console.log("ALMProxy updated at         ", controllerInst.almProxy);
        console.log("RateLimits upgraded at      ", controllerInst.rateLimits);
        console.log("Controller upgraded at      ", newController);
        console.log("Old Controller deprecated at", oldController);
    }

    function _setMaxExchangeRate(address controller, address vault) internal {
        MainnetController(controller).setMaxExchangeRate(
            vault,
            1  * 10 ** IERC20(vault).decimals(),
            10 * 10 ** IERC20(IERC4626(vault).asset()).decimals()
        );
    }

    function _onboardCurvePool(
        address controller_,
        address rateLimits_,
        address pool,
        uint256 maxSlippage,
        uint256 swapMax,
        uint256 swapSlope,
        uint256 depositMax,
        uint256 depositSlope,
        uint256 withdrawMax,
        uint256 withdrawSlope
    )
        internal
    {
        MainnetController controller = MainnetController(controller_);
        RateLimits        rateLimits = RateLimits(rateLimits_);

        controller.setMaxSlippage(pool, maxSlippage);

        if (swapMax != 0) {
            rateLimits.setRateLimitData(
                makeAddressKey(controller.LIMIT_CURVE_SWAP(), pool),
                swapMax,
                swapSlope
            );
        }

        if (depositMax != 0) {
            rateLimits.setRateLimitData(
                makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(), pool),
                depositMax,
                depositSlope
            );
        }

        if (withdrawMax != 0) {
            rateLimits.setRateLimitData(
                makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), pool),
                withdrawMax,
                withdrawSlope
            );
        }
    }

}

contract UpgradeBaseController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        address newController = vm.envAddress("NEW_CONTROLLER");
        address oldController = vm.envAddress("OLD_CONTROLLER");

        vm.createSelectFork(getChain("base").rpcUrl);

        console.log(string(abi.encodePacked("Upgrading base controller...")));

        string memory inputConfig = ScriptTools.readInput("base-staging");

        ControllerInstance memory controllerInst = ControllerInstance({
            almProxy   : inputConfig.readAddress(".almProxy"),
            controller : newController,
            rateLimits : inputConfig.readAddress(".rateLimits")
        });

        address[] memory relayers = new address[](2);
        relayers[0] = inputConfig.readAddress(".relayer");
        relayers[1] = inputConfig.readAddress(".backstopRelayer");

        ForeignInit.ConfigAddressParams memory configAddresses = ForeignInit.ConfigAddressParams({
            freezer       : inputConfig.readAddress(".freezer"),
            relayers      : relayers,
            oldController : oldController
        });

        ForeignInit.CheckAddressParams memory checkAddresses = ForeignInit.CheckAddressParams({
            admin      : inputConfig.readAddress(".admin"),
            proxy      : inputConfig.readAddress(".almProxy"),
            rateLimits : inputConfig.readAddress(".rateLimits")
        });

        address mainnetAlmProxy = ScriptTools.readInput("mainnet-staging").readAddress(".almProxy");

        vm.startBroadcast();
        ForeignInit.upgradeController(controllerInst, configAddresses, checkAddresses);
        vm.stopBroadcast();

        console.log("ALMProxy updated at         ", controllerInst.almProxy);
        console.log("RateLimits upgraded at      ", controllerInst.rateLimits);
        console.log("Controller upgraded at      ", newController);
        console.log("Old controller deprecated at", oldController);
    }

}

contract TransferAdminRoles is Script {

    using stdJson     for string;
    using ScriptTools for string;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal constant STAGING_SAFE = 0xb52991d5d29f371f493910c36f5A849b3748Cc28;

    function run() external {
        vm.setEnv("FOUNDRY_ROOT_CHAINID",             "1");
        vm.setEnv("FOUNDRY_EXPORTS_OVERWRITE_LATEST", "true");

        _transferRoles("mainnet");
        _transferRoles("base");
    }

    function _transferRoles(string memory chainName) internal {
        vm.createSelectFork(getChain(chainName).rpcUrl);

        console.log(string(abi.encodePacked("Transferring ", chainName, " admin roles to SAFE...")));

        string memory fileSlug = string(abi.encodePacked(chainName, "-staging"));

        vm.startBroadcast();

        string memory inputConfig = ScriptTools.readInput(fileSlug);

        IAccessControlLike controller = IAccessControlLike(inputConfig.readAddress(".controller"));
        IAccessControlLike rateLimits = IAccessControlLike(inputConfig.readAddress(".rateLimits"));
        IAccessControlLike almProxy   = IAccessControlLike(inputConfig.readAddress(".almProxy"));

        address oldAdmin = inputConfig.readAddress(".admin");
        address newAdmin = STAGING_SAFE;

        controller.grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        rateLimits.grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        almProxy.grantRole(DEFAULT_ADMIN_ROLE, newAdmin);

        controller.revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        rateLimits.revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        almProxy.revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);

        vm.stopBroadcast();

        ScriptTools.exportContract(fileSlug, "admin", newAdmin);
    }

}
