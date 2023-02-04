const main = async () => {
  const ferc20Factory = await hre.ethers.getContractFactory("FErc20Immutable");

  const ferc20 = await ferc20Factory.deploy(
    // underlyng address
    "0xD87Ba7A50B2E7E660f678A895E4B72E7CB4CCd9C", //for usdc
    //filtrollerAddress
    "0xddE41e7aF3E6b3Ef46A70025d0d859166270AC49",
    //interestRateModel_
    "0xFaeA25414c74E8d3804A4cAdbBd4aDd99FB95d05",
    //initialExchangeRateMantissa_
    "200000000000000000000000000",
    //name_
    "Filend USD Coin",
    //symbol_
    "fUSDC",
    //decinmals
    8,
    //admin_
    "0x659CE0FC2499E1Fa14d30F5CD88aD058ba490e39"
  );

  await ferc20.deployed();
  console.log("fUSDC Contract deployed to:", ferc20.address);
};

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log(error);
    process.exit(1);
    E;
  }
};

runMain();
