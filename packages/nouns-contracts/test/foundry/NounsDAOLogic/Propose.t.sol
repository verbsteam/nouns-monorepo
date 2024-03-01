// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { NounsDAOLogicBaseTest } from './NounsDAOLogicBaseTest.sol';
import { NounsTokenLike } from '../../../contracts/governance/NounsDAOInterfaces.sol';

contract ProposeTest is NounsDAOLogicBaseTest {
    address proposer = makeAddr('proposer');

    function setUp() public override {
        super.setUp();

        vm.prank(address(dao.timelock()));
        dao._setProposalThresholdBPS(1_000);

        for (uint256 i = 0; i < 10; i++) {
            mintTo(proposer);
        }
    }

    function testEmits_ProposalCreated_and_ProposalCreatedWithRequirements() public {
        address[] memory targets = new address[](1);
        targets[0] = makeAddr('target');
        uint256[] memory values = new uint256[](1);
        values[0] = 42;
        string[] memory signatures = new string[](1);
        signatures[0] = 'some signature';
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = '';

        uint256 updatablePeriodEndBlock = block.number + dao.proposalUpdatablePeriodInBlocks();
        uint256 startBlock = updatablePeriodEndBlock + dao.votingDelay();
        uint256 endBlock = startBlock + dao.votingPeriod();

        vm.expectEmit(true, true, true, true);
        emit ProposalCreated(
            1,
            proposer,
            targets,
            values,
            signatures,
            calldatas,
            startBlock,
            endBlock,
            'some description'
        );

        vm.expectEmit(true, true, true, true);
        emit ProposalCreatedWithRequirements(
            1,
            new address[](0),
            updatablePeriodEndBlock,
            1, // prop threshold
            dao.minQuorumVotes(),
            0 // clientId
        );

        NounsTokenLike nouns = dao.nouns();
        uint256[] memory tokenIds = new uint256[](10);
        for (uint i = 0; i < 10; i++) {
            tokenIds[i] = nouns.tokenOfOwnerByIndex(proposer, i);
        }

        vm.prank(proposer);
        dao.propose(tokenIds, targets, values, signatures, calldatas, 'some description');
    }
}
