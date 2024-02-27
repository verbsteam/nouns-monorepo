import { ethers, network } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  NounsDescriptor,
  NounsDescriptor__factory as NounsDescriptorFactory,
  NounsDescriptorV2,
  NounsDescriptorV2__factory as NounsDescriptorV2Factory,
  NounsToken,
  NounsToken__factory as NounsTokenFactory,
  NounsSeeder,
  NounsSeeder__factory as NounsSeederFactory,
  WETH,
  WETH__factory as WethFactory,
  NounsArt__factory as NounsArtFactory,
  SVGRenderer__factory as SVGRendererFactory,
  NounsDAOExecutor__factory as NounsDaoExecutorFactory,
  NounsDAOExecutor,
  Inflator__factory,
  NounsDAOLogicV4,
  NounsDAOLogicV4__factory as NounsDaoLogicFactory,
  NounsDAOProxyV3__factory as NounsDaoProxyV3Factory,
  NounsDAOForkEscrow__factory as NounsDAOForkEscrowFactory,
  INounsDAOLogic__factory,
  INounsDAOLogic,
  NounDelegationToken__factory,
} from '../typechain';
import ImageData from '../files/image-data-v1.json';
import ImageDataV2 from '../files/image-data-v2.json';
import { Block } from '@ethersproject/abstract-provider';
import { deflateRawSync } from 'zlib';
import { chunkArray } from '../utils';
import { MAX_QUORUM_VOTES_BPS, MIN_QUORUM_VOTES_BPS } from './constants';
import { DynamicQuorumParams } from './types';
import { BigNumber } from 'ethers';

export type TestSigners = {
  deployer: SignerWithAddress;
  account0: SignerWithAddress;
  account1: SignerWithAddress;
  account2: SignerWithAddress;
};

export const getSigners = async (): Promise<TestSigners> => {
  const [deployer, account0, account1, account2] = await ethers.getSigners();
  return {
    deployer,
    account0,
    account1,
    account2,
  };
};

export const deployNounsDescriptor = async (
  deployer?: SignerWithAddress,
): Promise<NounsDescriptor> => {
  const signer = deployer || (await getSigners()).deployer;
  const nftDescriptorLibraryFactory = await ethers.getContractFactory('NFTDescriptor', signer);
  const nftDescriptorLibrary = await nftDescriptorLibraryFactory.deploy();
  const nounsDescriptorFactory = new NounsDescriptorFactory(
    {
      'contracts/libs/NFTDescriptor.sol:NFTDescriptor': nftDescriptorLibrary.address,
    },
    signer,
  );

  return nounsDescriptorFactory.deploy();
};

export const deployNounsDescriptorV2 = async (
  deployer?: SignerWithAddress,
): Promise<NounsDescriptorV2> => {
  const signer = deployer || (await getSigners()).deployer;
  const nftDescriptorLibraryFactory = await ethers.getContractFactory('NFTDescriptorV2', signer);
  const nftDescriptorLibrary = await nftDescriptorLibraryFactory.deploy();
  const nounsDescriptorFactory = new NounsDescriptorV2Factory(
    {
      'contracts/libs/NFTDescriptorV2.sol:NFTDescriptorV2': nftDescriptorLibrary.address,
    },
    signer,
  );

  const renderer = await new SVGRendererFactory(signer).deploy();
  const descriptor = await nounsDescriptorFactory.deploy(
    ethers.constants.AddressZero,
    renderer.address,
  );

  const inflator = await new Inflator__factory(signer).deploy();

  const art = await new NounsArtFactory(signer).deploy(descriptor.address, inflator.address);
  await descriptor.setArt(art.address);

  return descriptor;
};

export const deployNounsSeeder = async (deployer?: SignerWithAddress): Promise<NounsSeeder> => {
  const factory = new NounsSeederFactory(deployer || (await getSigners()).deployer);

  return factory.deploy();
};

export const deployNounsToken = async (
  deployer?: SignerWithAddress,
  noundersDAO?: string,
  minter?: string,
  descriptor?: string,
  seeder?: string,
  proxyRegistryAddress?: string,
): Promise<NounsToken> => {
  const signer = deployer || (await getSigners()).deployer;
  const factory = new NounsTokenFactory(signer);

  return factory.deploy(
    noundersDAO || signer.address,
    minter || signer.address,
    descriptor || (await deployNounsDescriptorV2(signer)).address,
    seeder || (await deployNounsSeeder(signer)).address,
    proxyRegistryAddress || address(0),
  );
};

export const deployWeth = async (deployer?: SignerWithAddress): Promise<WETH> => {
  const factory = new WethFactory(deployer || (await getSigners()).deployer);

  return factory.deploy();
};

export const populateDescriptor = async (nounsDescriptor: NounsDescriptor): Promise<void> => {
  const { bgcolors, palette, images } = ImageData;
  const { bodies, accessories, heads, glasses } = images;

  // Split up head and accessory population due to high gas usage
  await Promise.all([
    nounsDescriptor.addManyBackgrounds(bgcolors),
    nounsDescriptor.addManyColorsToPalette(0, palette),
    nounsDescriptor.addManyBodies(bodies.map(({ data }) => data)),
    chunkArray(accessories, 10).map(chunk =>
      nounsDescriptor.addManyAccessories(chunk.map(({ data }) => data)),
    ),
    chunkArray(heads, 10).map(chunk => nounsDescriptor.addManyHeads(chunk.map(({ data }) => data))),
    nounsDescriptor.addManyGlasses(glasses.map(({ data }) => data)),
  ]);
};

export const populateDescriptorV2 = async (nounsDescriptor: NounsDescriptorV2): Promise<void> => {
  const { bgcolors, palette, images } = ImageDataV2;
  const { bodies, accessories, heads, glasses } = images;

  const {
    encodedCompressed: bodiesCompressed,
    originalLength: bodiesLength,
    itemCount: bodiesCount,
  } = dataToDescriptorInput(bodies.map(({ data }) => data));
  const {
    encodedCompressed: accessoriesCompressed,
    originalLength: accessoriesLength,
    itemCount: accessoriesCount,
  } = dataToDescriptorInput(accessories.map(({ data }) => data));
  const {
    encodedCompressed: headsCompressed,
    originalLength: headsLength,
    itemCount: headsCount,
  } = dataToDescriptorInput(heads.map(({ data }) => data));
  const {
    encodedCompressed: glassesCompressed,
    originalLength: glassesLength,
    itemCount: glassesCount,
  } = dataToDescriptorInput(glasses.map(({ data }) => data));

  await nounsDescriptor.addManyBackgrounds(bgcolors);
  await nounsDescriptor.setPalette(0, `0x000000${palette.join('')}`);
  await nounsDescriptor.addBodies(bodiesCompressed, bodiesLength, bodiesCount);
  await nounsDescriptor.addAccessories(accessoriesCompressed, accessoriesLength, accessoriesCount);
  await nounsDescriptor.addHeads(headsCompressed, headsLength, headsCount);
  await nounsDescriptor.addGlasses(glassesCompressed, glassesLength, glassesCount);
};

/**
 * Return a function used to mint `amount` Nouns on the provided `token`
 * @param token The Nouns ERC721 token
 * @param amount The number of Nouns to mint
 */
export const MintNouns = (
  token: NounsToken,
  burnNoundersTokens = true,
): ((amount: number) => Promise<void>) => {
  return async (amount: number): Promise<void> => {
    for (let i = 0; i < amount; i++) {
      await token.mint();
    }
    if (!burnNoundersTokens) return;

    await setTotalSupply(token, amount);
  };
};

/**
 * Mints or burns tokens to target a total supply. Due to Nounders' rewards tokens may be burned and tokenIds will not be sequential
 */
export const setTotalSupply = async (token: NounsToken, newTotalSupply: number): Promise<void> => {
  const totalSupply = (await token.totalSupply()).toNumber();

  if (totalSupply < newTotalSupply) {
    for (let i = 0; i < newTotalSupply - totalSupply; i++) {
      await token.mint();
    }
    // If Nounder's reward tokens were minted totalSupply will be more than expected, so run setTotalSupply again to burn extra tokens
    await setTotalSupply(token, newTotalSupply);
  }

  if (totalSupply > newTotalSupply) {
    for (let i = newTotalSupply; i < totalSupply; i++) {
      await token.burn(i);
    }
  }
};

// The following adapted from `https://github.com/compound-finance/compound-protocol/blob/master/tests/Utils/Ethereum.js`

const rpc = <T = unknown>({
  method,
  params,
}: {
  method: string;
  params?: unknown[];
}): Promise<T> => {
  return network.provider.send(method, params);
};

export const encodeParameters = (types: string[], values: unknown[]): string => {
  const abi = new ethers.utils.AbiCoder();
  return abi.encode(types, values);
};

export const blockByNumber = async (n: number | string): Promise<Block> => {
  return rpc({ method: 'eth_getBlockByNumber', params: [n, false] });
};

export const increaseTime = async (seconds: number): Promise<unknown> => {
  await rpc({ method: 'evm_increaseTime', params: [seconds] });
  return rpc({ method: 'evm_mine' });
};

export const freezeTime = async (seconds: number): Promise<unknown> => {
  await rpc({ method: 'evm_increaseTime', params: [-1 * seconds] });
  return rpc({ method: 'evm_mine' });
};

export const advanceBlocks = async (blocks: number): Promise<void> => {
  for (let i = 0; i < blocks; i++) {
    await mineBlock();
  }
};

export const blockNumber = async (parse = true): Promise<number> => {
  const result = await rpc<number>({ method: 'eth_blockNumber' });
  return parse ? parseInt(result.toString()) : result;
};

export const blockTimestamp = async (
  n: number | string,
  parse = true,
): Promise<number | string> => {
  const block = await blockByNumber(n);
  return parse ? parseInt(block.timestamp.toString()) : block.timestamp;
};

export const setNextBlockBaseFee = async (value: BigNumber): Promise<void> => {
  await network.provider.send('hardhat_setNextBlockBaseFeePerGas', [value.toHexString()]);
};

export const setNextBlockTimestamp = async (n: number, mine = true): Promise<void> => {
  await rpc({ method: 'evm_setNextBlockTimestamp', params: [n] });
  if (mine) await mineBlock();
};

export const minerStop = async (): Promise<void> => {
  await network.provider.send('evm_setAutomine', [false]);
  await network.provider.send('evm_setIntervalMining', [0]);
};

export const minerStart = async (): Promise<void> => {
  await network.provider.send('evm_setAutomine', [true]);
};

export const mineBlock = async (): Promise<void> => {
  await network.provider.send('evm_mine');
};

export const chainId = async (): Promise<number> => {
  return parseInt(await network.provider.send('eth_chainId'), 16);
};

export const address = (n: number): string => {
  return `0x${n.toString(16).padStart(40, '0')}`;
};

export const propStateToString = (stateInt: number): string => {
  const states: string[] = [
    'Pending',
    'Active',
    'Canceled',
    'Defeated',
    'Succeeded',
    'Queued',
    'Expired',
    'Executed',
    'Vetoed',
  ];
  return states[stateInt];
};

export const propose = async (
  gov: INounsDAOLogic,
  proposer: SignerWithAddress,
  stubPropUserAddress: string = address(0),
) => {
  const targets = [stubPropUserAddress];
  const values = ['0'];
  const signatures = ['getBalanceOf(address)'];
  const callDatas = [encodeParameters(['address'], [stubPropUserAddress])];

  const nounsAddress = await gov.nouns();
  const nouns = NounsTokenFactory.connect(nounsAddress, proposer);
  const tokenIds = [await nouns.tokenOfOwnerByIndex(proposer.address, 0)];

  await gov
    .connect(proposer)
    ['propose(uint256[],address[],uint256[],string[],bytes[],string)'](
      tokenIds,
      targets,
      values,
      signatures,
      callDatas,
      'do nothing',
    );
  return await gov.latestProposalIds(proposer.address);
};

function dataToDescriptorInput(data: string[]): {
  encodedCompressed: string;
  originalLength: number;
  itemCount: number;
} {
  const abiEncoded = ethers.utils.defaultAbiCoder.encode(['bytes[]'], [data]);
  const encodedCompressed = `0x${deflateRawSync(
    Buffer.from(abiEncoded.substring(2), 'hex'),
  ).toString('hex')}`;

  const originalLength = abiEncoded.substring(2).length / 2;
  const itemCount = data.length;

  return {
    encodedCompressed,
    originalLength,
    itemCount,
  };
}

export const deployGovernorV3 = async (deployer: SignerWithAddress): Promise<NounsDAOLogicV4> => {
  const NounsDAOProposals = await (
    await ethers.getContractFactory('NounsDAOProposals', deployer)
  ).deploy();
  const NounsDAOAdmin = await (await ethers.getContractFactory('NounsDAOAdmin', deployer)).deploy();
  const NounsDAOFork = await (await ethers.getContractFactory('NounsDAOFork', deployer)).deploy();
  const NounsDAOVotes = await (await ethers.getContractFactory('NounsDAOVotes', deployer)).deploy();
  const NounsDAODynamicQuorum = await (
    await ethers.getContractFactory('NounsDAODynamicQuorum', deployer)
  ).deploy();
  const NounsDAODelegation = await (
    await ethers.getContractFactory('NounsDAODelegation', deployer)
  ).deploy();

  return await new NounsDaoLogicFactory(
    {
      'contracts/governance/NounsDAOAdmin.sol:NounsDAOAdmin': NounsDAOAdmin.address,
      'contracts/governance/NounsDAOProposals.sol:NounsDAOProposals': NounsDAOProposals.address,
      'contracts/governance/fork/NounsDAOFork.sol:NounsDAOFork': NounsDAOFork.address,
      'contracts/governance/NounsDAOVotes.sol:NounsDAOVotes': NounsDAOVotes.address,
      'contracts/governance/NounsDAODynamicQuorum.sol:NounsDAODynamicQuorum':
        NounsDAODynamicQuorum.address,
      'contracts/governance/NounsDAODelegation.sol:NounsDAODelegation': NounsDAODelegation.address,
    },
    deployer,
  ).deploy();
};

export const deployGovernorV3WithV3Proxy = async (
  deployer: SignerWithAddress,
  tokenAddress: string,
  timelockAddress?: string,
  forkDAODeployerAddress?: string,
  vetoerAddress?: string,
  votingPeriod?: number,
  votingDelay?: number,
  proposalThresholdBPs?: number,
  dynamicQuorumParams?: DynamicQuorumParams,
): Promise<INounsDAOLogic> => {
  const v3LogicContract = await deployGovernorV3(deployer);
  const predictedProxyAddress = ethers.utils.getContractAddress({
    from: deployer.address,
    nonce: (await deployer.getTransactionCount()) + 1,
  });

  const escrowAddress = (
    await new NounsDAOForkEscrowFactory(deployer).deploy(predictedProxyAddress, tokenAddress)
  ).address;

  const nftDescriptorLibraryFactory = await ethers.getContractFactory('NFTDescriptorV2', deployer);
  const nftDescriptorLibrary = await nftDescriptorLibraryFactory.deploy();
  const delegationTokenAddress = (
    await new NounDelegationToken__factory(
      {
        'contracts/libs/NFTDescriptorV2.sol:NFTDescriptorV2': nftDescriptorLibrary.address,
      },
      deployer,
    ).deploy(tokenAddress, 'E381CB')
  ).address;

  const proxy = await new NounsDaoProxyV3Factory(deployer).deploy(
    timelockAddress || deployer.address,
    tokenAddress,
    delegationTokenAddress,
    escrowAddress,
    forkDAODeployerAddress || deployer.address,
    vetoerAddress || deployer.address,
    deployer.address,
    v3LogicContract.address,
    {
      votingPeriod: votingPeriod || 7200,
      votingDelay: votingDelay || 1,
      proposalThresholdBPS: proposalThresholdBPs || 1,
      lastMinuteWindowInBlocks: 0,
      objectionPeriodDurationInBlocks: 0,
      proposalUpdatablePeriodInBlocks: 0,
    },
    dynamicQuorumParams || {
      minQuorumVotesBPS: MIN_QUORUM_VOTES_BPS,
      maxQuorumVotesBPS: MAX_QUORUM_VOTES_BPS,
      quorumCoefficient: 0,
    },
  );

  return INounsDAOLogic__factory.connect(proxy.address, deployer);
};
