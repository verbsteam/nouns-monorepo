// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';

import { NounsDAOLogicSharedBaseTest } from '../helpers/NounsDAOLogicSharedBase.t.sol';
import { INounsDAOLogic } from '../../../contracts/interfaces/INounsDAOLogic.sol';
import { DeployUtilsV3 } from '../helpers/DeployUtilsV3.sol';
import { NounsDAOProxyV3 } from '../../../contracts/governance/NounsDAOProxyV3.sol';
import { NounsDAOTypes, NounsTokenLike } from '../../../contracts/governance/NounsDAOInterfaces.sol';

abstract contract NounsDAOLogic_GasSnapshot_propose is NounsDAOLogicSharedBaseTest {
    address immutable target = makeAddr('target');

    function setUp() public override {
        super.setUp();

        vm.startPrank(minter);
        nounsToken.mint();
        nounsToken.transferFrom(minter, proposer, 1);
        vm.roll(block.number + 1);
        vm.stopPrank();
    }

    function test_propose_shortDescription() public {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;
        string[] memory signatures = new string[](1);
        signatures[0] = '';
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = '';

        NounsTokenLike nouns = daoProxy.nouns();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = nouns.tokenOfOwnerByIndex(proposer, 0);

        vm.prank(proposer);
        daoProxy.propose(tokenIds, targets, values, signatures, calldatas, 'short description');
    }

    function test_propose_longDescription() public {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;
        string[] memory signatures = new string[](1);
        signatures[0] = '';
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = '';

        NounsTokenLike nouns = daoProxy.nouns();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = nouns.tokenOfOwnerByIndex(proposer, 0);

        vm.prank(proposer);
        daoProxy.propose(tokenIds, targets, values, signatures, calldatas, getLongDescription());
    }

    function getLongDescription() internal view returns (string memory) {
        return vm.readFile('./test/foundry/files/longProposalDescription.txt');
    }
}

abstract contract NounsDAOLogic_GasSnapshot_castVote is NounsDAOLogicSharedBaseTest {
    address immutable nouner = makeAddr('nouner');
    address immutable target = makeAddr('target');

    function setUp() public override {
        super.setUp();

        vm.startPrank(minter);
        nounsToken.mint();
        nounsToken.transferFrom(minter, proposer, 1);
        nounsToken.mint();
        nounsToken.transferFrom(minter, nouner, 2);
        vm.roll(block.number + 1);
        vm.stopPrank();

        givenProposal();
        vm.roll(block.number + daoProxy.votingDelay() + 1);
    }

    function givenProposal() internal {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;
        string[] memory signatures = new string[](1);
        signatures[0] = '';
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = '';

        NounsTokenLike nouns = daoProxy.nouns();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = nouns.tokenOfOwnerByIndex(proposer, 0);

        vm.prank(proposer);
        daoProxy.propose(tokenIds, targets, values, signatures, calldatas, 'short description');
    }

    function test_castVote_against() public {
        vote(nouner, 1, 0);
    }

    function test_castVoteWithReason() public {
        voteWithReason(nouner, 1, 0, "I don't like this proposal");
    }

    function test_castVote_lastMinuteFor() public {
        vm.roll(block.number + VOTING_PERIOD - LAST_MINUTE_BLOCKS);
        vote(nouner, 1, 1);
    }
}

abstract contract NounsDAOLogic_GasSnapshot_castVoteDuringObjectionPeriod is NounsDAOLogicSharedBaseTest {
    address immutable nouner = makeAddr('nouner');
    address immutable target = makeAddr('target');

    function setUp() public override {
        super.setUp();

        vm.startPrank(minter);
        nounsToken.mint();
        nounsToken.transferFrom(minter, proposer, 1);
        nounsToken.mint();
        nounsToken.transferFrom(minter, nouner, 2);
        vm.roll(block.number + 1);
        vm.stopPrank();

        givenProposal();
        vm.roll(block.number + daoProxy.votingDelay() + 1);

        // activate objection period
        vm.roll(block.number + VOTING_PERIOD - LAST_MINUTE_BLOCKS);
        vote(proposer, 1, 1);
        // enter objection period
        vm.roll(block.number + LAST_MINUTE_BLOCKS + 1);
    }

    function givenProposal() internal {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;
        string[] memory signatures = new string[](1);
        signatures[0] = '';
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = '';

        NounsTokenLike nouns = daoProxy.nouns();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = nouns.tokenOfOwnerByIndex(proposer, 0);

        vm.prank(proposer);
        daoProxy.propose(tokenIds, targets, values, signatures, calldatas, 'short description');
    }

    function test_castVote_duringObjectionPeriod_against() public {
        vote(nouner, 1, 0);
    }
}

contract NounsDAOLogic_GasSnapshot_V3_propose is DeployUtilsV3, NounsDAOLogic_GasSnapshot_propose {
    function deployDAOProxy(
        address timelock,
        address nounsToken,
        address vetoer
    ) internal override returns (INounsDAOLogic) {
        return _createDAOV3Proxy(timelock, nounsToken, vetoer);
    }
}

contract NounsDAOLogic_GasSnapshot_V3_vote is DeployUtilsV3, NounsDAOLogic_GasSnapshot_castVote {
    function deployDAOProxy(
        address timelock,
        address nounsToken,
        address vetoer
    ) internal override returns (INounsDAOLogic) {
        return _createDAOV3Proxy(timelock, nounsToken, vetoer);
    }

    function test_proposalsV3() public view {
        daoProxy.proposalsV3(1);
    }
}

contract NounsDAOLogic_GasSnapshot_V3_voteDuringObjectionPeriod is
    DeployUtilsV3,
    NounsDAOLogic_GasSnapshot_castVoteDuringObjectionPeriod
{
    function deployDAOProxy(
        address timelock,
        address nounsToken,
        address vetoer
    ) internal override returns (INounsDAOLogic) {
        return _createDAOV3Proxy(timelock, nounsToken, vetoer);
    }
}
