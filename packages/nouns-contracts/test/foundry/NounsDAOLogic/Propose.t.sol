// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { NounsDAOLogicBaseTest } from './NounsDAOLogicBaseTest.sol';
import { NounsTokenLike, NounsDAOEventsV3 } from '../../../contracts/governance/NounsDAOInterfaces.sol';
import { NounsDAOProposals } from '../../../contracts/governance/NounsDAOProposals.sol';

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
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 42, 'some signature', '');
        uint256 updatablePeriodEndBlock = block.number + dao.proposalUpdatablePeriodInBlocks();
        uint256 startBlock = updatablePeriodEndBlock + dao.votingDelay();
        uint256 endBlock = startBlock + dao.votingPeriod();
        bytes32 expectedTxsHash = NounsDAOProposals.hashProposal(txs);

        vm.expectEmit(true, true, true, true);
        emit NounsDAOEventsV3.ProposalCreated(
            1,
            proposer,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            startBlock,
            endBlock,
            'some description'
        );

        vm.expectEmit(true, true, true, true);
        emit NounsDAOEventsV3.ProposalCreatedWithRequirements(
            1,
            new address[](0),
            updatablePeriodEndBlock,
            1, // prop threshold
            0, // dao.minQuorumVotes()
            0, // clientId
            expectedTxsHash
        );

        NounsTokenLike nouns = dao.nouns();
        uint256[] memory tokenIds = new uint256[](10);
        for (uint i = 0; i < 10; i++) {
            tokenIds[i] = nouns.tokenOfOwnerByIndex(proposer, i);
        }

        vm.prank(proposer);
        dao.propose(tokenIds, txs.targets, txs.values, txs.signatures, txs.calldatas, 'some description');
    }
}
