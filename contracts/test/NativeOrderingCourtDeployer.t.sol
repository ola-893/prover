// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { CovenantBook } from "../src/CovenantBook.sol";
import { NativeOrderingCourtDeployer } from "../src/NativeOrderingCourtDeployer.sol";
import { OrderingCourt } from "../src/OrderingCourt.sol";
import { PerformanceBureau } from "../src/PerformanceBureau.sol";
import { TestBase } from "./TestBase.sol";

contract NativeOrderingCourtDeployerTest is TestBase {
    function test_ProductionDeploymentPinsBothCreditcoinPrecompiles() public {
        PerformanceBureau bureau = new PerformanceBureau();
        NativeOrderingCourtDeployer deployer = new NativeOrderingCourtDeployer(bureau);
        CovenantBook book = deployer.COVENANT_BOOK();
        OrderingCourt court = deployer.ORDERING_COURT();

        assertEq(address(court), deployer.PREDICTED_COURT());
        assertEq(address(court.VERIFIER()), deployer.NATIVE_QUERY_VERIFIER());
        assertEq(address(book.CHAIN_INFO()), deployer.NATIVE_CHAIN_INFO());
        assertEq(address(court.COVENANT_BOOK()), address(book));
        assertEq(address(court.PERFORMANCE_BUREAU()), address(bureau));
        assertEq(book.NO_SANDWICH_COURT(), address(court));
        assertEq(book.FIFO_COURT(), address(court));
    }
}
