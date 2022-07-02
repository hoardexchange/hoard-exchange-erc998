const { assert, expect } = require('chai');
const { ethers } = require("hardhat");

describe('ComposableTopDownERC20Enumerable', async () => {
    let ComposableTopDown,
        SampleERC20,
        SampleNFT;

    const expectedTokenId = 1;
    const firstChildTokenId = 1;
    const aliceBalance = 1;

    const bytesFirstToken = ethers.utils.hexZeroPad('0x1', 20);
    const zeroAddress = ethers.utils.hexZeroPad('0x0', 20);
    const ERC998_MAGIC_VALUE = '0xcd740db5';

    beforeEach(async () => {
        [
            alice,
            bob,
            owner,
            nonUsed,
        ] = await ethers.getSigners();
        aliceBytes32Address = ethers.utils.hexConcat([ERC998_MAGIC_VALUE, ethers.utils.hexZeroPad(alice.address, 28).toLowerCase()]);

        ComposableTopDown = await ethers.getContractFactory("ComposableTopDownERC20EnumerableDev");
        SampleERC20 = await ethers.getContractFactory("SampleERC20");
        SampleNFT = await ethers.getContractFactory("SampleNFT");

        composableTopDownInstance = await ComposableTopDown.deploy();
        await composableTopDownInstance.deployed();

        sampleERC20Instance = await SampleERC20.deploy('SampleERC20', 'S');
        await sampleERC20Instance.mint(alice.address, 1000);

        await composableTopDownInstance.safeMint(alice.address);
    });

    it('ERC165 - Should declare interfaces: ERC165, ERC721, IERC998ERC20TopDown, IERC998ERC20TopDownEnumerable', async () => {
        assert(await composableTopDownInstance.supportsInterface('0x01ffc9a7'), 'No interface declaration: ERC165');
        assert(await composableTopDownInstance.supportsInterface('0x80ac58cd'), 'No interface declaration: ERC721');
        assert(await composableTopDownInstance.supportsInterface('0x7294ffed'), 'No interface declaration: IERC998ERC20TopDown');
        assert(await composableTopDownInstance.supportsInterface('0xc5fd96cd'), 'No interface declaration: IERC998ERC20TopDownEnumerable');
    });

    it('Should add a contract after erc223 incoming transfer', async () => {
        // when:
        await sampleERC20Instance
            .connect(alice)['transfer(address,uint256,bytes)'](
                composableTopDownInstance.address,
                1,  // amount
                bytesFirstToken
            );

        // then:
        const totalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
        assert(totalERC20Contracts.eq(1), 'Invalid total erc20 contracts');

        const erc20ContractByIndex = await composableTopDownInstance.erc20ContractByIndex(expectedTokenId, 0);
        assert(erc20ContractByIndex === sampleERC20Instance.address, 'Invalid erc20 contract by index');
    });

    it('Should add a contract after getERC20 transfer', async () => {
        // when:
        await sampleERC20Instance.connect(alice).approve(composableTopDownInstance.address, 2);

        await composableTopDownInstance.connect(alice)
            .getERC20(
                alice.address,
                expectedTokenId,
                sampleERC20Instance.address,
                2);  // amount

        // then:
        const totalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
        assert(totalERC20Contracts.eq(1), 'Invalid total erc20 contracts');

        const erc20ContractByIndex = await composableTopDownInstance.erc20ContractByIndex(expectedTokenId, 0);
        assert(erc20ContractByIndex === sampleERC20Instance.address, 'Invalid erc20 contract by index');
    });

    it('Should remove a contract after erc223 transfer', async () => {
        // when:
        await sampleERC20Instance
            .connect(alice)['transfer(address,uint256,bytes)'](
                composableTopDownInstance.address,
                2,  // amount
                bytesFirstToken
            );

        await composableTopDownInstance
            .connect(alice)
            .transferERC223(
                expectedTokenId,
                bob.address,
                sampleERC20Instance.address,
                2,
                bytesFirstToken
            );

        // then:
        const totalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
        assert(totalERC20Contracts.eq(0), 'Invalid total erc20 contracts');
    });

    it('Should remove a contract after erc20 transfer', async () => {
        // when:
        await sampleERC20Instance.connect(alice).approve(composableTopDownInstance.address, 2);

        await composableTopDownInstance.connect(alice)
            .getERC20(
                alice.address,
                expectedTokenId,
                sampleERC20Instance.address,
                2);  // amount

        await composableTopDownInstance
            .connect(alice)
            .transferERC20(
                expectedTokenId,
                bob.address,
                sampleERC20Instance.address,
                2  // amount
            );

        // then:
        const totalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
        assert(totalERC20Contracts.eq(0), 'Invalid total erc20 contracts');
    });

    it('Multi Token tests - Should return proper totals after addition and removal', async () => {
        // given:
        const mintTokensAmount = 1000;
        const transferAmount = 500;
        const totalTokens = 5;
        const mintedPerNFT = 3;

        const [nfts, erc20s] = await setUpTestTokens(totalTokens, totalTokens);

        // when:

        // transfer erc20s
        for (let i = 0; i < erc20s.length; i++) {
            await erc20s[i].mint(alice.address, mintTokensAmount);
            await erc20s[i].connect(alice)['transfer(address,uint256,bytes)'](
                composableTopDownInstance.address,
                transferAmount,
                bytesFirstToken
            );

            const balance = await composableTopDownInstance.balanceOfERC20(expectedTokenId, erc20s[i].address);
            assert(balance.eq(transferAmount), `Invalid balanceOfERC20 on Token ${i}`);
        }

        const totalERC20TokensAdded = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
        assert(totalERC20TokensAdded.eq(totalTokens), 'Invalid Alice total ERC20 cotracts');

        // remove erc20s
        let tokenERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);

        for (let i = 0; i < tokenERC20Contracts; i++) {
            const tokenAddress = await composableTopDownInstance.erc20ContractByIndex(expectedTokenId, i);
            const balance = await composableTopDownInstance.balanceOfERC20(expectedTokenId, tokenAddress);

            await composableTopDownInstance.connect(alice).transferERC20(expectedTokenId, alice.address, tokenAddress, balance);
            const nextNumTotalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);

            assert(nextNumTotalERC20Contracts.eq(tokenERC20Contracts.sub(1)), `Expected ${tokenERC20Contracts - 1} tokenContracts but got ${nextNumTotalERC20Contracts}`);
            tokenERC20Contracts = nextNumTotalERC20Contracts;
        }
    });

    async function setUpTestTokens(nftCount, erc20Count) {
        let nfts = [];
        let erc20s = [];
        for (let i = 0; i < nftCount; i++) {
            nfts.push(await SampleNFT.deploy());
        }

        for (let i = 0; i < erc20Count; i++) {
            erc20s.push(await SampleERC20.deploy(i.toString(), i.toString()));
        }

        return [nfts, erc20s];
    }
});
