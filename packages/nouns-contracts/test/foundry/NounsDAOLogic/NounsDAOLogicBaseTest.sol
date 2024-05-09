// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { DeployUtilsV3 } from '../helpers/DeployUtilsV3.sol';
import { SigUtils, ERC1271Stub } from '../helpers/SigUtils.sol';
import { ProxyRegistryMock } from '../helpers/ProxyRegistryMock.sol';
import { NounsDAOProposals } from '../../../contracts/governance/NounsDAOProposals.sol';
import { NounsDAOProxyV3 } from '../../../contracts/governance/NounsDAOProxyV3.sol';
import { NounsDAOTypes, NounsTokenLike, NounsDAOEventsV3 } from '../../../contracts/governance/NounsDAOInterfaces.sol';
import { NounsToken } from '../../../contracts/NounsToken.sol';
import { NounsSeeder } from '../../../contracts/NounsSeeder.sol';
import { IProxyRegistry } from '../../../contracts/external/opensea/IProxyRegistry.sol';
import { NounsDAOExecutorV2 } from '../../../contracts/governance/NounsDAOExecutorV2.sol';
import { NounsDAOForkEscrow } from '../../../contracts/governance/fork/NounsDAOForkEscrow.sol';
import { INounsDAOLogic } from '../../../contracts/interfaces/INounsDAOLogic.sol';
import { DelegationHelpers } from '../helpers/DelegationHelpers.sol';
import { LibSort } from '../lib/LibSort.sol';

abstract contract NounsDAOLogicBaseTest is Test, DeployUtilsV3, SigUtils {
    using DelegationHelpers for address;

    NounsToken nounsToken;
    INounsDAOLogic dao;
    NounsDAOExecutorV2 timelock;

    address noundersDAO = makeAddr('nounders');
    address minter;
    address vetoer = makeAddr('vetoer');
    uint32 lastMinuteWindowInBlocks = 10;
    uint32 objectionPeriodDurationInBlocks = 10;
    uint32 proposalUpdatablePeriodInBlocks = 10;
    address forkEscrow;

    function setUp() public virtual {
        dao = _deployDAOV3();
        nounsToken = NounsToken(address(dao.nouns()));
        minter = nounsToken.minter();
        timelock = NounsDAOExecutorV2(payable(address(dao.timelock())));
        forkEscrow = address(dao.forkEscrow());
    }

    function vote(address voter_, uint256 proposalId_, uint8 support, string memory reason) internal {
        vm.startPrank(voter_);
        dao.castRefundableVoteWithReason(voter_.allVotesOf(dao), proposalId_, support, reason);
        vm.stopPrank();
    }

    function vote(address voter_, uint256 proposalId_, uint8 support, string memory reason, uint32 clientId) internal {
        vm.startPrank(voter_);
        dao.castRefundableVoteWithReason(voter_.allVotesOf(dao), proposalId_, support, reason, clientId);
        vm.stopPrank();
    }

    function mintTo(address to) internal returns (uint256 tokenID) {
        vm.startPrank(minter);
        tokenID = nounsToken.mint();
        nounsToken.transferFrom(minter, to, tokenID);
        vm.stopPrank();
        vm.roll(block.number + 1);
    }

    function propose(
        address proposer,
        NounsDAOProposals.ProposalTxs memory txs,
        string memory description
    ) internal returns (uint256 proposalId) {
        return propose(proposer, txs, description, 0);
    }

    function propose(
        address proposer,
        NounsDAOProposals.ProposalTxs memory txs,
        string memory description,
        uint32 clientId
    ) internal returns (uint256 proposalId) {
        NounsTokenLike nouns = dao.nouns();
        uint256 balance = nouns.balanceOf(proposer);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; ++i) {
            tokenIds[i] = nouns.tokenOfOwnerByIndex(proposer, i);
        }
        LibSort.insertionSort(tokenIds);

        return propose(proposer, tokenIds, txs, description, clientId);
    }

    function propose(
        address proposer,
        uint256[] memory tokenIds,
        NounsDAOProposals.ProposalTxs memory txs,
        string memory description,
        uint32 clientId
    ) internal returns (uint256 proposalId) {
        vm.prank(proposer);
        proposalId = dao.propose(
            tokenIds,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            description,
            clientId
        );
    }

    function propose(
        address proposer,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        string memory description
    ) internal returns (uint256 proposalId) {
        return propose(proposer, target, value, signature, data, description, 0);
    }

    function propose(
        address proposer,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        string memory description,
        uint32 clientId
    ) internal returns (uint256 proposalId) {
        NounsTokenLike nouns = dao.nouns();
        uint256 balance = nouns.balanceOf(proposer);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; ++i) {
            tokenIds[i] = nouns.tokenOfOwnerByIndex(proposer, i);
        }
        LibSort.insertionSort(tokenIds);

        return propose(proposer, tokenIds, target, value, signature, data, description, clientId);
    }

    function propose(
        address proposer,
        uint256[] memory tokenIds,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        string memory description,
        uint32 clientId
    ) internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        string[] memory signatures = new string[](1);
        signatures[0] = signature;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        vm.prank(proposer);
        proposalId = dao.propose(tokenIds, targets, values, signatures, calldatas, description, clientId);
    }

    function updateProposal(
        address proposer,
        uint256 proposalId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        string memory description
    ) internal {
        updateProposal(proposer, proposalId, target, value, signature, data, description, '');
    }

    function updateProposal(
        address proposer,
        uint256 proposalId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        string memory description,
        string memory updateMessage
    ) internal {
        vm.prank(proposer);
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        string[] memory signatures = new string[](1);
        signatures[0] = signature;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;
        dao.updateProposal(proposalId, targets, values, signatures, calldatas, description, updateMessage);
    }

    function updateProposalTransactions(
        address proposer,
        uint256 proposalId,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        string memory updateMessage
    ) internal {
        vm.prank(proposer);
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        string[] memory signatures = new string[](1);
        signatures[0] = signature;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;
        dao.updateProposalTransactions(proposalId, targets, values, signatures, calldatas, updateMessage);
    }

    function proposeBySigs(
        address proposer,
        address signer,
        uint256 signerPK,
        NounsDAOProposals.ProposalTxs memory txs,
        string memory description,
        uint256 expirationTimestamp
    ) internal returns (uint256 proposalId) {
        address[] memory signers = new address[](1);
        signers[0] = signer;
        uint256[] memory signerPKs = new uint256[](1);
        signerPKs[0] = signerPK;
        uint256[] memory expirationTimestamps = new uint256[](1);
        expirationTimestamps[0] = expirationTimestamp;

        return proposeBySigs(proposer, signers, signerPKs, expirationTimestamps, txs, description);
    }

    function proposeBySigs(
        address proposer,
        address[] memory signers,
        uint256[] memory signerPKs,
        uint256[] memory expirationTimestamps,
        NounsDAOProposals.ProposalTxs memory txs,
        string memory description
    ) internal returns (uint256 proposalId) {
        NounsDAOTypes.ProposerSignature[] memory sigs = new NounsDAOTypes.ProposerSignature[](signers.length);
        for (uint256 i = 0; i < signers.length; ++i) {
            sigs[i] = NounsDAOTypes.ProposerSignature(
                signProposal(proposer, signerPKs[i], txs, description, expirationTimestamps[i], address(dao)),
                signers[i],
                expirationTimestamps[i],
                signers[i].allVotesOf(dao)
            );
        }

        vm.startPrank(proposer);
        proposalId = dao.proposeBySigs(
            proposer.allVotesOf(dao),
            sigs,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            description
        );
        vm.stopPrank();
    }

    function updateProposalBySigs(
        uint256 proposalId,
        address proposer,
        address[] memory signers,
        uint256[] memory signerPKs,
        uint256[] memory expirationTimestamps,
        NounsDAOProposals.ProposalTxs memory txs,
        string memory description
    ) internal {
        NounsDAOTypes.ProposerSignature[] memory sigs = new NounsDAOTypes.ProposerSignature[](signers.length);
        for (uint256 i = 0; i < signers.length; ++i) {
            sigs[i] = NounsDAOTypes.ProposerSignature(
                signProposal(proposer, signerPKs[i], txs, description, expirationTimestamps[i], address(dao)),
                signers[i],
                expirationTimestamps[i],
                signers[i].allVotesOf(dao)
            );
        }

        vm.prank(proposer);
        dao.updateProposalBySigs(
            proposalId,
            sigs,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            description,
            ''
        );
    }

    function makeTxs(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) internal pure returns (NounsDAOProposals.ProposalTxs memory) {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        string[] memory signatures = new string[](1);
        signatures[0] = signature;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;
        return NounsDAOProposals.ProposalTxs(targets, values, signatures, calldatas);
    }

    struct ExpectNewPropEventsTemp {
        uint256 expectedStartBlock;
        uint256 expectedEndBlock;
        bytes32 txsHash;
    }

    function expectNewPropEvents(
        NounsDAOProposals.ProposalTxs memory txs,
        address expectedProposer,
        uint256 expectedPropId,
        uint256 expectedPropThreshold,
        uint256 expectedMinQuorumVotes,
        address[] memory expectedSigners
    ) internal {
        ExpectNewPropEventsTemp memory temp;
        temp.expectedStartBlock = block.number + proposalUpdatablePeriodInBlocks + VOTING_DELAY;
        temp.expectedEndBlock = temp.expectedStartBlock + VOTING_PERIOD;
        temp.txsHash = NounsDAOProposals.hashProposal(txs);

        vm.expectEmit(true, true, true, true);
        emit NounsDAOEventsV3.ProposalCreated(
            expectedPropId,
            expectedProposer,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            temp.expectedStartBlock,
            temp.expectedEndBlock,
            'description'
        );

        vm.expectEmit(true, true, true, true);
        emit NounsDAOEventsV3.ProposalCreatedWithRequirements(
            expectedPropId,
            expectedSigners,
            block.number + proposalUpdatablePeriodInBlocks,
            expectedPropThreshold,
            expectedMinQuorumVotes,
            0, // clientId
            temp.txsHash
        );
    }
}
