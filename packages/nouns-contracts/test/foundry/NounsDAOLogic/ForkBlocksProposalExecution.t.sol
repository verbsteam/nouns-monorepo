// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { NounsDAOLogicBaseTest } from './NounsDAOLogicBaseTest.sol';
import { NounsDAOProposals } from '../../../contracts/governance/NounsDAOProposals.sol';

abstract contract ExecutableProposalState is NounsDAOLogicBaseTest {
    address user = makeAddr('user');
    uint256 proposalId;
    NounsDAOProposals.ProposalTxs proposalTxs;
    uint256[] tokenIds;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(minter);
        nounsToken.mint();
        nounsToken.transferFrom(minter, user, 1);
        vm.stopPrank();
        vm.roll(block.number + 1);
        tokenIds = [1];

        // prep an executable proposal
        proposalTxs = makeTxs(makeAddr('target'), 0, '', '');
        proposalId = propose(user, proposalTxs, '');

        vm.roll(block.number + dao.votingDelay() + dao.proposalUpdatablePeriodInBlocks() + 1);

        vm.prank(user);
        dao.castRefundableVote(tokenIds, proposalId, 1);

        vm.roll(block.number + dao.votingPeriod());
        dao.queue(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);

        vm.warp(block.timestamp + timelock.delay());
    }
}

contract ExecutableProposalStateTest is ExecutableProposalState {
    function test_executionWorksWhenNoActiveFork() public {
        dao.execute(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);
    }
}

abstract contract ExecutableProposalWithActiveForkState is ExecutableProposalState {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(user);
        tokenIds = [1];
        nounsToken.approve(address(dao), 1);
        dao.escrowToFork(tokenIds, new uint256[](0), '');
        vm.stopPrank();

        dao.executeFork();
    }
}

contract ExecutableProposalWithActiveForkStateTest is ExecutableProposalWithActiveForkState {
    function test_executionRevertsDuringFork() public {
        vm.expectRevert(NounsDAOProposals.CannotExecuteDuringForkingPeriod.selector);
        dao.execute(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);
    }

    function test_executionWorksAfterForkIsDone() public {
        vm.warp(dao.forkEndTimestamp() + 1);
        dao.execute(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);
    }
}
